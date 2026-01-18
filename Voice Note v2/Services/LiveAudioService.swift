import AVFoundation
import Foundation
import Observation
import os.log
import Speech

/// Audio capture service using AVAudioEngine for live transcription
/// Provides simultaneous buffer streaming and file recording
@MainActor
@Observable
final class LiveAudioService {
    // MARK: - Public State

    /// Current audio level (0.0 to 1.0) for UI visualization
    private(set) var currentAudioLevel: Float = 0.0

    /// Current recording duration in seconds
    private(set) var currentDuration: TimeInterval = 0.0

    /// Whether recording is currently active
    private(set) var isRecording: Bool = false

    /// Current input device name
    private(set) var currentInputDevice: String = "Microphone"

    /// Whether voice is currently detected
    private(set) var isVoiceDetected: Bool = false

    /// Audio format being used (needed by transcriber)
    private(set) var audioFormat: AVAudioFormat?

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.voicenote", category: "LiveAudio")
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var bufferContinuation: AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>.Continuation?

    // Voice detection threshold (see AudioConstants for tuning guidance)
    private let voiceThreshold: Float = AudioConstants.voiceThreshold

    // UI update throttling to prevent MainActor crossing overhead
    // Frame rate read from AppSettings.shared.frameRateCFInterval (30 or 60fps)
    private var lastUIUpdate: CFAbsoluteTime = 0

    // Interruption handling (for background recording)
    private var interruptionTask: Task<Void, Never>?
    private(set) var isInterrupted = false

    // MARK: - Lifecycle

    init() {
        logger.debug("LiveAudioService initialized")
    }

    // Note: Timer cleanup happens in stopDurationTimer() called from stopRecording()/cancelRecording()
    // Continuation is finished in stopRecording()/cancelRecording()
    // When object is deallocated, references are dropped automatically

    // MARK: - Public Methods

    /// Start recording and return an async stream of audio buffers for transcription
    /// - Returns: AsyncStream of audio buffers with timestamps (needed by SpeechAnalyzer)
    func startRecording() async throws -> AsyncStream<(AVAudioPCMBuffer, AVAudioTime)> {
        logger.info("Starting live audio recording...")

        // Configure audio session
        try await configureAudioSession()

        // Update audio input device
        updateAudioInputDevice()

        // Setup route change notifications
        setupAudioRouteChangeNotification()

        // Setup interruption monitoring for background recording
        startInterruptionMonitoring()

        // Create audio engine
        let engine = AVAudioEngine()
        audioEngine = engine

        // Get input format from hardware - MUST use this for tap to avoid format mismatch
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Use the hardware's native format for both tap and file
        // SpeechAnalyzer can handle any reasonable format - bestAvailableAudioFormat is just a preference
        audioFormat = inputFormat
        logger.debug("Recording format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Create output file
        let outputURL = try createRecordingURL()
        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: inputFormat.settings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )

        logger.debug("Recording to file: \(outputURL)")

        // Create async stream for buffer delivery (includes timestamp for SpeechAnalyzer)
        let (stream, continuation) = AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>.makeStream()
        bufferContinuation = continuation

        // Handle stream termination
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.logger.debug("Buffer stream terminated")
            }
        }

        // Install tap on input node - MUST use inputFormat to match hardware
        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Write to file
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                Task { @MainActor in
                    self.logger.error("Failed to write audio buffer: \(error)")
                }
            }

            // Yield to stream for transcription (include timestamp!)
            self.bufferContinuation?.yield((buffer, time))

            // Throttle UI updates based on Low Power Mode setting
            // Standard: 60fps, Low Power: 30fps
            // Buffers arrive at ~43/sec (1024 samples @ 44.1kHz)
            let now = CFAbsoluteTimeGetCurrent()
            let interval = AppSettings.shared.frameRateCFInterval
            if now - self.lastUIUpdate >= interval {
                self.lastUIUpdate = now
                Task { @MainActor in
                    self.updateAudioLevel(from: buffer)
                }
            }
        }

        // Start engine - finish continuation if this fails to prevent memory leak
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Cleanup continuation to prevent leak
            bufferContinuation?.finish()
            bufferContinuation = nil

            // Remove observer we added earlier
            NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
            stopInterruptionMonitoring()

            // Deactivate audio session
            try? AVAudioSession.sharedInstance().setActive(false)

            throw error
        }

        recordingStartTime = Date()
        isRecording = true
        startDurationTimer()

        logger.info("Live audio recording started")

        return stream
    }

    /// Stop recording and return the audio file URL and duration
    /// - Returns: Tuple of (audio file URL, duration in seconds)
    func stopRecording() async throws -> (URL, TimeInterval) {
        logger.info("Stopping live audio recording...")

        guard let engine = audioEngine else {
            throw LiveAudioError.noActiveRecording
        }

        // Calculate duration before clearing state
        let duration = currentRecordingDuration

        // Stop the engine and remove tap
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Wait for audio file to stabilize on disk (AVAudioEngine write may not be complete)
        // Without this, transcription may fail with "no speech detected" (error 1110)
        // because the file hasn't finished flushing to disk
        guard let audioFile = audioFile else {
            throw LiveAudioError.noActiveRecording
        }
        let fileURL = audioFile.url
        var lastSize: UInt64 = 0
        var stableCount = 0

        logger.debug("Waiting for audio file to stabilize...")
        for _ in 0..<AudioConstants.FileStabilization.maxAttempts {
            try await Task.sleep(nanoseconds: AudioConstants.FileStabilization.pollInterval)

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let currentSize = attributes[.size] as? UInt64 else {
                continue
            }

            if currentSize > 0 && currentSize == lastSize {
                stableCount += 1
                if stableCount >= AudioConstants.FileStabilization.stableThreshold {
                    logger.debug("Audio file stabilized at \(currentSize) bytes")
                    break
                }
            } else {
                stableCount = 0
            }
            lastSize = currentSize
        }

        // Finish the buffer stream
        bufferContinuation?.finish()
        bufferContinuation = nil

        // Cleanup
        self.audioFile = nil
        self.audioEngine = nil
        recordingStartTime = nil
        stopDurationTimer()

        // Reset state
        isRecording = false
        currentAudioLevel = 0.0
        currentDuration = 0.0
        isVoiceDetected = false

        // Remove route change notifications
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)

        // Stop interruption monitoring
        stopInterruptionMonitoring()
        isInterrupted = false

        // Deactivate audio session
        try AVAudioSession.sharedInstance().setActive(false)

        logger.info("Live audio recording stopped. Duration: \(duration)s, File: \(fileURL)")

        return (fileURL, duration)
    }

    /// Cancel recording without saving
    func cancelRecording() async {
        logger.info("Canceling live audio recording...")

        // Stop engine if running
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        // Finish stream
        bufferContinuation?.finish()
        bufferContinuation = nil

        // Delete file if created
        if let audioFile = audioFile {
            try? FileManager.default.removeItem(at: audioFile.url)
        }

        // Cleanup
        audioFile = nil
        audioEngine = nil
        recordingStartTime = nil
        stopDurationTimer()

        // Reset state
        isRecording = false
        currentAudioLevel = 0.0
        currentDuration = 0.0
        isVoiceDetected = false

        // Remove notifications
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)

        // Stop interruption monitoring
        stopInterruptionMonitoring()
        isInterrupted = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    /// Pre-warm audio hardware at app launch to prevent first-recording failure.
    /// Apple docs: "Check the input node's input format for a nonzero sample rate
    /// and channel count to see if input is in an enabled state."
    func prewarmAudioSystem() async throws {
        logger.debug("Pre-warming audio system...")

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        // Force hardware singleton creation
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)

        // Validate hardware is ready (per Apple docs)
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            logger.warning("Audio hardware not ready: \(format.sampleRate)Hz, \(format.channelCount) channels")
            try session.setActive(false)
            throw LiveAudioError.audioSystemNotReady
        }

        // Preallocate resources (Apple: "to responsively start audio")
        engine.prepare()
        engine.stop()

        // Leave session active — hardware stays warm for first recording
        logger.info("Audio system pre-warmed: \(format.sampleRate)Hz, \(format.channelCount) channels")
    }

    // MARK: - Private Methods

    private var currentRecordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    private func configureAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()

        // Configure for recording with playback capability
        // .allowBluetoothHFP enables Bluetooth input - iOS routes automatically
        // NOTE: setPreferredInput() breaks AVAudioEngine tap callbacks, don't use it
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        logger.debug("Audio session configured")
    }

    private func createRecordingURL() throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "live_recording_\(UUID().uuidString).m4a"
        return documentsPath.appendingPathComponent(fileName)
    }

    private func startDurationTimer() {
        // Update duration every 0.2 seconds
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentDuration = self?.currentRecordingDuration ?? 0
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataPointer = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return }

        // Calculate RMS (root mean square) for more stable level
        var sum: Float = 0.0
        var peak: Float = 0.0

        for i in 0..<frameLength {
            let sample = channelDataPointer[i]
            sum += sample * sample
            peak = max(peak, abs(sample))
        }

        let rms = sqrt(sum / Float(frameLength))

        // Convert to dB
        let rmsDb = 20 * log10(max(rms, 0.00001))
        let peakDb = 20 * log10(max(peak, 0.00001))

        // Voice detection based on RMS (more stable than peak)
        isVoiceDetected = rmsDb > voiceThreshold

        // Normalize to 0-1 range for UI
        // Typical speech: -40 to -10 dB, loud speech: -10 to 0 dB
        let clampedPower = max(-50.0, min(0.0, peakDb))
        let normalizedLevel = (clampedPower + 50.0) / 50.0

        currentAudioLevel = max(0.0, min(1.0, normalizedLevel))
    }

    // MARK: - Audio Input Device Detection

    private func updateAudioInputDevice() {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        if let input = currentRoute.inputs.first {
            currentInputDevice = getReadableDeviceName(for: input)
        }
    }

    private func getReadableDeviceName(for input: AVAudioSessionPortDescription) -> String {
        switch input.portType {
        case .builtInMic:
            return "Built-in Microphone"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            let deviceName = input.portName.isEmpty ? "Bluetooth" : input.portName
            return deviceName
        case .headsetMic:
            return "Wired Headset"
        case .airPlay:
            return "AirPlay Device"
        case .carAudio:
            return "Car Audio"
        case .usbAudio:
            return "USB Microphone"
        default:
            return input.portName.isEmpty ? "External Microphone" : input.portName
        }
    }

    private func setupAudioRouteChangeNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleRouteChange(notification: Notification) {
        Task { @MainActor in
            updateAudioInputDevice()
        }
    }

    // MARK: - Interruption Handling (Background Recording)

    private func startInterruptionMonitoring() {
        interruptionTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            )
            for await notification in notifications {
                await self?.handleInterruption(notification)
            }
        }
    }

    private func stopInterruptionMonitoring() {
        interruptionTask?.cancel()
        interruptionTask = nil
    }

    private func handleInterruption(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            isInterrupted = true
            // Log reason (iOS 14.5+)
            if let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt,
               let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
                switch reason {
                case .appWasSuspended:
                    logger.info("Audio interrupted - app was suspended")
                case .builtInMicMuted:
                    logger.info("Audio interrupted - mic muted (iPad)")
                case .routeDisconnected:
                    logger.info("Audio interrupted - route disconnected")
                default:
                    logger.info("Audio interrupted - another app took focus")
                }
            }

        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) {
                do {
                    // Must reactivate session before restarting engine
                    try AVAudioSession.sharedInstance().setActive(true)
                    try audioEngine?.start()
                    isInterrupted = false
                    logger.info("Audio resumed after interruption")
                } catch {
                    logger.error("Failed to resume audio: \(error)")
                }
            } else {
                logger.info("Interruption ended but shouldResume=false")
                // Recording stays paused - user must manually resume
            }

        @unknown default:
            break
        }
    }
}

// MARK: - Errors

enum LiveAudioError: LocalizedError {
    case noActiveRecording
    case audioSystemNotReady

    var errorDescription: String? {
        switch self {
        case .noActiveRecording:
            return "No active recording found"
        case .audioSystemNotReady:
            return "Audio hardware not ready"
        }
    }
}
