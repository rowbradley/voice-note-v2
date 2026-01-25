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

    /// Whether recording is currently paused (derived from pauseStartTime)
    var isPaused: Bool { pauseStartTime != nil }

    /// Current input device name
    private(set) var currentInputDevice: String = "Microphone"

    /// Whether voice is currently detected
    private(set) var isVoiceDetected: Bool = false

    /// Audio format being used (needed by transcriber)
    private(set) var audioFormat: AVAudioFormat?

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.voicenote", category: "LiveAudio")
    private let audioSessionProvider: AudioSessionProvider
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var bufferContinuation: AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>.Continuation?

    /// Tracks pause duration to subtract from total recording time
    private var totalPausedDuration: TimeInterval = 0.0
    private var pauseStartTime: Date?

    /// Format when recording started - downstream consumers (file, transcription) expect this
    private var originalRecordingFormat: AVAudioFormat?

    /// Converts new hardware format → original format when route changes mid-recording
    /// Thread-safe: AudioFormatConverter is Sendable, safe to access from audio callback thread
    private var resamplingConverter: AudioFormatConverter?

    // Voice detection threshold (see AudioConstants for tuning guidance)
    private let voiceThreshold: Float = AudioConstants.voiceThreshold

    // UI update throttling to prevent MainActor crossing overhead
    // Frame rate read from AppSettings.shared.frameRateCFInterval (30 or 60fps)
    private var lastUIUpdate: CFAbsoluteTime = 0

    // Interruption handling (for background recording)
    private(set) var isInterrupted = false

    /// Debounce task for route change restarts
    private var routeRestartDebounceTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init(audioSessionProvider: AudioSessionProvider? = nil) {
        self.audioSessionProvider = audioSessionProvider ?? Self.createDefaultProvider()
        logger.debug("LiveAudioService initialized")
    }

    /// Creates the platform-appropriate audio session provider
    private static func createDefaultProvider() -> AudioSessionProvider {
        #if os(iOS)
        return iOSAudioSession()
        #elseif os(macOS)
        return macOSAudioSession()
        #endif
    }

    // Note: Timer cleanup happens in stopDurationTimer() called from stopRecording()/cancelRecording()
    // Continuation is finished in stopRecording()/cancelRecording()
    // When object is deallocated, references are dropped automatically

    // MARK: - Public Methods

    /// Start recording and return an async stream of audio buffers for transcription
    /// - Returns: AsyncStream of audio buffers with timestamps (needed by SpeechAnalyzer)
    func startRecording() async throws -> AsyncStream<(AVAudioPCMBuffer, AVAudioTime)> {
        logger.info("Starting live audio recording...")

        // Configure and activate audio session via platform provider
        try await audioSessionProvider.configure()
        try await audioSessionProvider.activate()

        // Update audio input device
        await updateAudioInputDevice()

        // Setup route change notifications via provider
        setupRouteChangeObserver()

        // Setup interruption monitoring for background recording (iOS only)
        setupInterruptionObserver()

        // Create audio engine
        let engine = AVAudioEngine()
        audioEngine = engine

        // Get input format from hardware - MUST use this for tap to avoid format mismatch
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Use the hardware's native format for both tap and file
        // SpeechAnalyzer can handle any reasonable format - bestAvailableAudioFormat is just a preference
        audioFormat = inputFormat
        // Lock in format for this recording session - file and transcription expect this throughout
        originalRecordingFormat = inputFormat
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
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat, block: makeTapCallback())

        // Start engine - finish continuation if this fails to prevent memory leak
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Cleanup continuation to prevent leak
            bufferContinuation?.finish()
            bufferContinuation = nil

            // Stop observers we added earlier
            audioSessionProvider.stopObservingRouteChanges()
            audioSessionProvider.stopObservingInterruptions()

            // Deactivate audio session
            try? audioSessionProvider.deactivate()

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

        // If paused when stop is called, account for that pause duration
        if isPaused, let pauseStart = pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
        }

        // Calculate duration before clearing state (already accounts for pauses)
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
        originalRecordingFormat = nil
        resamplingConverter = nil
        stopDurationTimer()

        // Reset recording state
        resetRecordingState()

        // Cancel any pending route restart debounce
        routeRestartDebounceTask?.cancel()
        routeRestartDebounceTask = nil

        // Stop route change and interruption observers
        audioSessionProvider.stopObservingRouteChanges()
        audioSessionProvider.stopObservingInterruptions()
        isInterrupted = false

        // Deactivate audio session
        try audioSessionProvider.deactivate()

        logger.debug("Live audio recording stopped. Duration: \(duration)s")

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
        originalRecordingFormat = nil
        resamplingConverter = nil
        stopDurationTimer()

        // Reset recording state
        resetRecordingState()

        // Cancel any pending route restart debounce
        routeRestartDebounceTask?.cancel()
        routeRestartDebounceTask = nil

        // Stop route change and interruption observers
        audioSessionProvider.stopObservingRouteChanges()
        audioSessionProvider.stopObservingInterruptions()
        isInterrupted = false

        // Deactivate audio session
        try? audioSessionProvider.deactivate()

        logger.debug("Live audio recording cancelled")
    }

    /// Resets observable recording state to initial values.
    /// Extracted to avoid duplication between stopRecording() and cancelRecording().
    private func resetRecordingState() {
        isRecording = false
        totalPausedDuration = 0.0
        pauseStartTime = nil  // This sets isPaused to false via computed property
        currentAudioLevel = 0.0
        currentDuration = 0.0
        isVoiceDetected = false
    }

    /// Pause recording - pauses AVAudioEngine and stops buffer streaming.
    /// Duration timer continues but pause time is tracked and subtracted.
    /// Only works with LiveAudioService (not AVAudioRecorder which has known bugs).
    /// - Throws: `LiveAudioError.noActiveRecording` if not recording or already paused
    func pauseRecording() throws {
        guard isRecording, !isPaused, let engine = audioEngine else {
            throw LiveAudioError.cannotPause
        }

        // Pause the audio engine - stops tap callbacks
        engine.pause()

        // Track pause start time (this sets isPaused to true via computed property)
        pauseStartTime = Date()

        // Zero out audio level while paused
        currentAudioLevel = 0.0
        isVoiceDetected = false

        logger.debug("Audio engine paused")
    }

    /// Resume recording after pause.
    /// Restarts AVAudioEngine and continues buffer streaming.
    /// - Throws: `LiveAudioError.cannotResume` if not paused, or engine start fails
    func resumeRecording() throws {
        guard isRecording, isPaused, let engine = audioEngine else {
            throw LiveAudioError.cannotResume
        }

        // Calculate pause duration and add to total
        if let pauseStart = pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
        }

        // Restart the audio engine (clears pauseStartTime after to handle throw)
        try engine.start()

        // Clear pause state (this sets isPaused to false via computed property)
        pauseStartTime = nil

        logger.debug("Audio engine resumed")
    }

    /// Pre-warm audio hardware at app launch to prevent first-recording failure.
    /// Apple docs: "Check the input node's input format for a nonzero sample rate
    /// and channel count to see if input is in an enabled state."
    func prewarmAudioSystem() async throws {
        logger.debug("Pre-warming audio system...")

        try await audioSessionProvider.configure()
        try await audioSessionProvider.activate()

        // Force hardware singleton creation
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)

        // Validate hardware is ready (per Apple docs)
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            logger.warning("Audio hardware not ready: \(format.sampleRate)Hz, \(format.channelCount) channels")
            try? audioSessionProvider.deactivate()
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

        let elapsed = Date().timeIntervalSince(startTime)
        var pauseAdjustment = totalPausedDuration

        // Add current pause duration if paused (pauseStartTime is non-nil when paused)
        if let pauseStart = pauseStartTime {
            pauseAdjustment += Date().timeIntervalSince(pauseStart)
        }

        return max(0, elapsed - pauseAdjustment)
    }

    private func createRecordingURL() throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "live_recording_\(UUID().uuidString).m4a"
        return documentsPath.appendingPathComponent(fileName)
    }

    private func startDurationTimer() {
        // Update duration every 0.5 seconds (2Hz) - duration display doesn't need sub-second precision
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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

    /// Creates tap callback closure for audio buffer processing.
    /// Shared between initial recording and engine restarts.
    ///
    /// Note: This callback runs on the audio thread, not MainActor.
    /// AVAudioFile.write(from:) is thread-safe. AudioFormatConverter is Sendable.
    /// os.Logger is thread-safe - no need to dispatch error logging to MainActor.
    private func makeTapCallback() -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { [weak self] buffer, time in
            guard let self = self else { return }

            // Resample if format changed after route switch
            // Converts new hardware format → original recording format
            let outputBuffer: AVAudioPCMBuffer
            if let converter = self.resamplingConverter {
                do {
                    outputBuffer = try converter.convert(buffer)
                } catch {
                    // os.Logger is thread-safe, no dispatch needed
                    self.logger.error("Resampling failed: \(error)")
                    return  // Drop this buffer rather than corrupt the file
                }
            } else {
                outputBuffer = buffer
            }

            // Write to file (single-writer from tap callback is safe;
            // concurrent writes would NOT be thread-safe)
            do {
                try self.audioFile?.write(from: outputBuffer)
            } catch {
                // os.Logger is thread-safe, no dispatch needed
                self.logger.error("Failed to write audio buffer: \(error)")
            }

            // Yield to stream for transcription
            // Note: AVAudioTime from original buffer is approximate after resampling
            // but AnalyzerInput uses simple initializer assuming contiguous audio
            self.bufferContinuation?.yield((outputBuffer, time))

            // Throttle UI updates based on frame rate setting
            let now = CFAbsoluteTimeGetCurrent()
            let interval = AppSettings.shared.frameRateCFInterval
            if now - self.lastUIUpdate >= interval {
                self.lastUIUpdate = now
                Task { @MainActor in
                    self.updateAudioLevel(from: outputBuffer)
                }
            }
        }
    }

    // MARK: - Audio Input Device Detection

    /// Update current input device from audio session provider.
    /// Called during recording and can be called in idle state to show device indicator.
    func updateAudioInputDevice() async {
        currentInputDevice = await audioSessionProvider.currentInputDevice
    }

    /// Whether the current input is an external device (headphones, Bluetooth, etc.)
    var isExternalInputConnected: Bool {
        get async {
            await audioSessionProvider.isExternalInputConnected
        }
    }

    // MARK: - Route Change Handling

    private func setupRouteChangeObserver() {
        audioSessionProvider.observeRouteChanges { [weak self] in
            Task { @MainActor in
                await self?.handleRouteChange()
            }
        }
    }

    private func handleRouteChange() async {
        let oldDevice = currentInputDevice
        await updateAudioInputDevice()

        // If recording is active and input device changed, restart engine to use new input
        // This handles: AirPods connecting/disconnecting, wired headset plugging in, etc.
        guard isRecording, currentInputDevice != oldDevice else {
            return
        }

        logger.info("Audio input changed during recording: \(oldDevice) → \(self.currentInputDevice). Scheduling restart...")

        // Debounce rapid route changes (e.g., user rapidly plugging/unplugging)
        routeRestartDebounceTask?.cancel()
        routeRestartDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            do {
                try await restartAudioEngineForNewInput()
                logger.info("Audio engine restarted successfully for new input")
            } catch {
                logger.error("Failed to restart audio engine: \(error)")
            }
        }
    }

    /// Restart the audio engine to pick up a new input device while preserving the recording session.
    ///
    /// IMPORTANT: We must create a NEW AVAudioEngine instance when the hardware changes.
    /// A stopped engine returns cached format data, not the current hardware format.
    /// Per Apple docs: "When the audio engine's I/O unit observes a change to the audio
    /// input or output hardware's channel count or sample rate, the audio engine stops,
    /// uninitializes itself."
    private func restartAudioEngineForNewInput() async throws {
        guard let oldEngine = audioEngine, bufferContinuation != nil else {
            throw LiveAudioError.noActiveRecording
        }

        // Stop current engine and remove tap
        oldEngine.inputNode.removeTap(onBus: 0)
        oldEngine.stop()

        // Structural safety: converter assignment requires tap callback not running
        precondition(!oldEngine.isRunning, "Engine must be stopped before restart")

        // Brief delay for iOS audio routing to settle after route change
        // Bluetooth HFP negotiation needs time to complete
        try await Task.sleep(for: .milliseconds(150))

        // Create a FRESH engine to get current hardware format
        // A stopped engine returns stale cached format, causing format mismatch crashes
        let newEngine = AVAudioEngine()
        let inputFormat = newEngine.inputNode.outputFormat(forBus: 0)

        // Validate hardware is ready
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            logger.error("New hardware format invalid: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
            throw LiveAudioError.audioSystemNotReady
        }

        logger.info("New hardware format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Update stored references
        audioEngine = newEngine
        audioFormat = inputFormat

        // Check if we need to resample to maintain file/stream consistency
        // Only check sample rate and channel count - these affect file/transcription compatibility
        // Other format differences (interleaving, alignment) don't require resampling
        // Thread safety: engine is stopped above, so tap callback is not running during this assignment
        if let originalFormat = originalRecordingFormat,
           (inputFormat.sampleRate != originalFormat.sampleRate ||
            inputFormat.channelCount != originalFormat.channelCount) {
            // Create converter: new hardware format → original recording format
            resamplingConverter = try AudioFormatConverter(from: inputFormat, to: originalFormat)
            logger.info("Created resampler: \(inputFormat.sampleRate)Hz → \(originalFormat.sampleRate)Hz")
        } else {
            // Formats match (or no original format), no resampling needed
            resamplingConverter = nil
        }

        // Install tap with correct format on new engine
        let bufferSize: AVAudioFrameCount = 1024
        newEngine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat, block: makeTapCallback())

        // Start new engine
        newEngine.prepare()
        try newEngine.start()
    }

    // MARK: - Interruption Handling (Background Recording)

    private func setupInterruptionObserver() {
        audioSessionProvider.observeInterruptions(
            began: { [weak self] in
                Task { @MainActor in
                    self?.isInterrupted = true
                    self?.logger.info("Audio interrupted")
                }
            },
            ended: { [weak self] shouldResume in
                Task { @MainActor in
                    guard let self = self else { return }
                    if shouldResume {
                        do {
                            try await self.audioSessionProvider.activate()
                            try self.audioEngine?.start()
                            self.isInterrupted = false
                            self.logger.info("Audio resumed after interruption")
                        } catch {
                            self.logger.error("Failed to resume audio: \(error)")
                        }
                    } else {
                        self.logger.info("Interruption ended but shouldResume=false")
                    }
                }
            }
        )
    }
}

// MARK: - Errors

enum LiveAudioError: LocalizedError {
    case noActiveRecording
    case audioSystemNotReady
    case cannotPause
    case cannotResume

    var errorDescription: String? {
        switch self {
        case .noActiveRecording:
            return "No active recording found"
        case .audioSystemNotReady:
            return "Audio hardware not ready"
        case .cannotPause:
            return "Cannot pause: not recording or already paused"
        case .cannotResume:
            return "Cannot resume: not paused or no active recording"
        }
    }
}
