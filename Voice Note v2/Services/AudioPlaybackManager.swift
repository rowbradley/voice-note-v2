import Foundation
import AVFoundation
import Combine
import os.log

@MainActor
class AudioPlaybackManager: ObservableObject {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var progress: Double = 0.0
    @Published var currentTime: TimeInterval = 0.0
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private(set) var duration: TimeInterval = 0.0
    private let logger = Logger(subsystem: "com.voicenote", category: "AudioPlayback")
    
    func setupAudio(url: URL) {
        do {
            // Configure audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Create audio player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            
            let audioDuration = audioPlayer?.duration ?? 0.0
            // Ensure duration is valid (not NaN or infinite)
            duration = audioDuration.isFinite ? audioDuration : 0.0
            isReady = true
            
            logger.info("Audio player ready. Duration: \(self.duration)s")
            
        } catch {
            logger.error("Failed to setup audio player: \(error)")
            isReady = false
        }
    }
    
    func startPlayback() {
        guard let player = audioPlayer, isReady else {
            logger.error("Cannot start playback - player not ready")
            return
        }
        
        player.play()
        isPlaying = true
        startTimer()
        
        logger.info("Started playback")
    }
    
    func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
        
        logger.info("Paused playback")
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0.0
        progress = 0.0
        stopTimer()
        
        logger.info("Stopped playback")
    }
    
    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        
        // Ensure progress is valid and duration is finite
        let safeProgress = progress.isFinite ? max(0, min(1, progress)) : 0
        let targetTime = duration * safeProgress
        
        if targetTime.isFinite {
            player.currentTime = min(max(targetTime, 0), duration)
        }
        updateProgress()
    }
    
    private func startTimer() {
        // Reduced frequency from 10Hz to 4Hz for better battery life
        // UI updates at 0.25s intervals are still smooth for playback progress
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
                self?.checkIfFinished()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateProgress() {
        guard let player = audioPlayer else { return }
        
        let playerCurrentTime = player.currentTime
        currentTime = playerCurrentTime.isFinite ? playerCurrentTime : 0.0
        
        // Calculate progress safely, ensuring no division by zero or NaN
        if duration > 0 && duration.isFinite && currentTime.isFinite {
            progress = currentTime / duration
        } else {
            progress = 0.0
        }
    }
    
    private func checkIfFinished() {
        guard let player = audioPlayer else { return }
        
        if !player.isPlaying && currentTime >= duration - 0.1 {
            // Playback finished
            isPlaying = false
            stopTimer()
            currentTime = 0.0
            progress = 0.0
            player.currentTime = 0
            
            logger.info("Playback finished")
        }
    }
    
    deinit {
        audioPlayer?.stop()
        timer?.invalidate()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// MARK: - Extensions for better control
extension AudioPlaybackManager {
    var isAtBeginning: Bool {
        currentTime < 1.0
    }
    
    var isAtEnd: Bool {
        currentTime >= duration - 1.0
    }
    
    func skipForward(seconds: TimeInterval = 15.0) {
        seek(to: currentTime + seconds)
    }
    
    func skipBackward(seconds: TimeInterval = 15.0) {
        seek(to: currentTime - seconds)
    }
}