import AVFoundation
import Foundation
import os.log

@MainActor
class AudioRecordingService: ObservableObject {
    @Published var currentAudioLevel: Float = 0.0
    @Published var currentDuration: TimeInterval = 0.0
    @Published var currentInputDevice: String = "Microphone"
    @Published var isVoiceDetected: Bool = false
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession = AVAudioSession.sharedInstance()
    private var recordingStartTime: Date?
    private var levelTimer: Timer?
    private let logger = Logger(subsystem: "com.voicenote", category: "AudioRecording")
    
    // Voice detection thresholds (adjusted for better low-volume detection)
    private let voiceThreshold: Float = -40.0 // dB - more sensitive to quiet speech
    private let silenceThreshold: Float = -55.0 // dB - background noise level
    
    
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
        stopLevelMonitoring()
        
        let recordingURL = recorder.url
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
        try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        
        // Activate the session
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
        // Reduced frequency from 30Hz → 10Hz → 5Hz for optimal battery life
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
    
    deinit {
        // Ensure proper cleanup
        levelTimer?.invalidate()
        levelTimer = nil
        NotificationCenter.default.removeObserver(self)
        
        // Stop recording if still active
        if audioRecorder?.isRecording == true {
            audioRecorder?.stop()
        }
        audioRecorder = nil
        
        // Deactivate audio session
        try? recordingSession.setActive(false)
    }
}

enum AudioRecordingError: LocalizedError {
    case failedToStartRecording
    case noActiveRecording
    case audioSessionError(Error)
    
    var errorDescription: String? {
        switch self {
        case .failedToStartRecording:
            return "Failed to start recording"
        case .noActiveRecording:
            return "No active recording found"
        case .audioSessionError(let error):
            return "Audio session error: \(error.localizedDescription)"
        }
    }
}