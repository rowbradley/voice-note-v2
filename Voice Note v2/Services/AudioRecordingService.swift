import AVFoundation
import Foundation
import Observation
import os.log

/// Legacy audio recording service using AVAudioRecorder.
///
/// ## Deprecation Notice
///
/// This service is deprecated as of iOS 26. Use `LiveAudioService` for new development.
///
/// This service remains available as a fallback for edge cases where live transcription
/// is unavailable:
/// - Speech recognition permissions denied
/// - Siri/Dictation disabled in Settings
/// - SpeechAnalyzer initialization failure
///
/// ## Technical Background
///
/// **AVAudioRecorder** (this service):
/// - Simple API for recording to file
/// - Cannot stream audio buffers in real-time
/// - No access to raw PCM data during recording
///
/// **AVAudioEngine** (LiveAudioService):
/// - Graph-based audio processing
/// - Real-time buffer access via installTap()
/// - Required for live transcription (streaming to SpeechAnalyzer)
///
/// Per Apple documentation: "For more advanced recording capabilities, like applying
/// signal processing to recorded audio, use AVAudioEngine instead."
///
/// - SeeAlso: `LiveAudioService` for the primary recording implementation
@available(iOS, deprecated: 26.0, message: "Use LiveAudioService for new development. This is fallback only.")
@MainActor
@Observable
final class AudioRecordingService {
    var currentAudioLevel: Float = 0.0
    var currentDuration: TimeInterval = 0.0
    var currentInputDevice: String = "Microphone"
    var isVoiceDetected: Bool = false
    
    private var audioRecorder: AVAudioRecorder?
    #if os(iOS)
    private var recordingSession: AVAudioSession = AVAudioSession.sharedInstance()
    #endif
    private var recordingStartTime: Date?
    private var levelTimer: Timer?
    private let logger = Logger(subsystem: "com.voicenote", category: "AudioRecording")
    
    // Voice detection threshold (see AudioConstants for tuning guidance)
    private let voiceThreshold: Float = AudioConstants.voiceThreshold

    // Note: Timer cleanup happens in stopLevelMonitoring() called from stopRecording()
    // When object is deallocated, Timer reference is dropped automatically

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }
    
    var currentRecordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    func startRecording() async throws {
        // Configure audio session
        try configureAudioSession()
        
        // Update audio input device
        updateAudioInputDevice()
        
        // Setup route change notifications
        setupAudioRouteChangeNotification()
        
        // Create recording URL
        let recordingURL = try createRecordingURL()
        
        // Configure recorder settings optimized for speech
        let settings = createRecordingSettings()
        
        // Create and configure recorder
        audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        
        // Start recording
        guard audioRecorder?.record() == true else {
            // Cleanup observer we added earlier to prevent leak
            NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
            try? recordingSession.setActive(false)
            throw AudioRecordingError.failedToStartRecording
        }

        recordingStartTime = Date()
        startLevelMonitoring()
    }
    
    func stopRecording() async throws -> (URL, TimeInterval) {
        guard let recorder = audioRecorder else {
            throw AudioRecordingError.noActiveRecording
        }

        // Calculate duration BEFORE clearing startTime
        let duration = currentRecordingDuration

        recorder.stop()
        let recordingURL = recorder.url

        // Wait for file to stabilize (AVAudioRecorder.stop() returns before file is fully flushed)
        // Poll file size until it stops changing for 200ms
        var lastSize: UInt64 = 0
        var stableCount = 0

        for _ in 0..<AudioConstants.FileStabilization.maxAttempts {
            try await Task.sleep(nanoseconds: AudioConstants.FileStabilization.pollInterval)

            let attributes = try FileManager.default.attributesOfItem(atPath: recordingURL.path)
            let currentSize = attributes[.size] as? UInt64 ?? 0

            if currentSize > 0 && currentSize == lastSize {
                stableCount += 1
                if stableCount >= AudioConstants.FileStabilization.stableThreshold { break }
            } else {
                stableCount = 0
            }
            lastSize = currentSize
        }

        logger.debug("Recording file stabilized at \(lastSize) bytes")

        // Cleanup
        stopLevelMonitoring()
        audioRecorder = nil
        recordingStartTime = nil

        // Remove route change notifications
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)

        // Deactivate audio session
        try recordingSession.setActive(false)

        return (recordingURL, duration)
    }
    
    private func configureAudioSession() throws {
        // Configure for optimal speech recording
        // .allowBluetoothHFP enables Bluetooth input - iOS routes automatically
        // NOTE: setPreferredInput() breaks AVAudioEngine tap callbacks, don't use it
        try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try recordingSession.setActive(true)

        logger.debug("Audio session configured")
    }
    
    private func createRecordingURL() throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "recording_\(UUID().uuidString).m4a"
        return documentsPath.appendingPathComponent(fileName)
    }
    
    private func createRecordingSettings() -> [String: Any] {
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]
    }
    
    private func startLevelMonitoring() {
        // 5Hz provides smooth UI feedback while minimizing power consumption
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevelsAndDuration()
            }
        }
    }
    
    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        currentAudioLevel = 0.0
        currentDuration = 0.0
    }
    
    private func updateLevelsAndDuration() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            currentAudioLevel = 0.0
            isVoiceDetected = false
            return
        }
        
        // Update audio levels
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        
        // Voice detection based on average power (more stable than peak)
        isVoiceDetected = averagePower > voiceThreshold
        
        // Convert dB to linear scale (0.0 to 1.0)
        // Use peak power for more responsive visualization
        // Typical speech: -40 to -10 dB, loud speech: -10 to 0 dB
        let clampedPower = max(-50.0, min(0.0, peakPower))
        let normalizedLevel = (clampedPower + 50.0) / 50.0
        
        currentAudioLevel = max(0.0, min(1.0, normalizedLevel))
        
        // Update duration
        currentDuration = currentRecordingDuration
    }
    
    // MARK: - Audio Input Device Detection
    
    private func updateAudioInputDevice() {
        let currentRoute = recordingSession.currentRoute
        if let input = currentRoute.inputs.first {
            currentInputDevice = getReadableDeviceName(for: input)
        }
    }
    
    private func getReadableDeviceName(for input: AVAudioSessionPortDescription) -> String {
        switch input.portType {
        case .builtInMic:
            return "Built-in Microphone"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            // For Bluetooth devices, use the device name if available
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
            // Use the port name if available, otherwise generic name
            return input.portName.isEmpty ? "External Microphone" : input.portName
        }
    }
    
    private func setupAudioRouteChangeNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: recordingSession
        )
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        Task { @MainActor in
            updateAudioInputDevice()
        }
    }
    
}

enum AudioRecordingError: LocalizedError {
    case failedToStartRecording
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .failedToStartRecording:
            return "Failed to start recording"
        case .noActiveRecording:
            return "No active recording found"
        }
    }
}
