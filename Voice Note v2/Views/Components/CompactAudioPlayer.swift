import SwiftUI
import AVFoundation

struct CompactAudioPlayer: View {
    @ObservedObject var playbackManager: AudioPlaybackManager
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    
    var audioURL: URL? = nil
    var fileSize: String? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            // Main player controls
            HStack(spacing: 12) {
                // Play/Pause button
                Button(action: togglePlayback) {
                    Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!playbackManager.isReady)
                
                // Time and scrubber
                VStack(spacing: 4) {
                    // Scrubber
                    Slider(
                        value: isDragging ? $dragValue : $playbackManager.progress,
                        in: 0...1,
                        onEditingChanged: handleScrubbing
                    )
                    .tint(.blue)
                    
                    // Time labels
                    HStack {
                        Text(formatTime(isDragging ? safeTimeCalculation(dragValue * playbackManager.duration) : playbackManager.currentTime))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(formatTime(playbackManager.duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                
                // Share button
                if let audioURL = audioURL {
                    ShareLink(item: audioURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                }
            }
            
            // Audio metadata
            HStack(spacing: 16) {
                if let fileSize = fileSize {
                    Label(fileSize, systemImage: "doc.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Label("M4A", systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func togglePlayback() {
        if playbackManager.isPlaying {
            playbackManager.pausePlayback()
        } else {
            playbackManager.startPlayback()
        }
    }
    
    private func handleScrubbing(isDragging: Bool) {
        self.isDragging = isDragging
        
        if !isDragging {
            // User finished dragging, seek to position
            playbackManager.seek(to: dragValue)
        } else {
            // User started dragging, pause if playing
            if playbackManager.isPlaying {
                playbackManager.pausePlayback()
            }
            dragValue = playbackManager.progress
        }
    }
    
    private func safeTimeCalculation(_ time: TimeInterval) -> TimeInterval {
        return time.isFinite ? time : 0.0
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        // Ensure time is finite and non-negative
        let safeTime = time.isFinite ? max(0, time) : 0.0
        let minutes = Int(safeTime) / 60
        let seconds = Int(safeTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview
#Preview {
    CompactAudioPlayer(playbackManager: AudioPlaybackManager())
        .padding()
}