import SwiftUI

struct RecordingTimer: View {
    let duration: TimeInterval
    let isRecording: Bool
    
    var body: some View {
        Text(formattedTime)
            .font(.system(.title2, design: .monospaced, weight: .medium))
            .foregroundColor(isRecording ? .primary : .secondary)
            .opacity(isRecording ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.3), value: isRecording)
    }
    
    private var formattedTime: String {
        // Ensure duration is finite and non-negative
        let safeDuration = duration.isFinite ? max(0, duration) : 0.0
        let minutes = Int(safeDuration) / 60
        let seconds = Int(safeDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Blinking Recording Indicator
struct RecordingIndicator: View {
    let isRecording: Bool
    @State private var isBlinking = false
    @State private var animationTask: Task<Void, Never>?
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .opacity(isRecording && isBlinking ? 0.3 : 1.0)
            
            Text("REC")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundColor(.red)
        }
        .opacity(isRecording ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
        .onAppear {
            if isRecording {
                startBlinking()
            }
        }
        .onDisappear {
            stopBlinking()
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startBlinking()
            } else {
                stopBlinking()
            }
        }
    }
    
    private func startBlinking() {
        stopBlinking() // Cancel any existing animation
        
        animationTask = Task {
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.8)) {
                    isBlinking.toggle()
                }
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            }
        }
    }
    
    private func stopBlinking() {
        animationTask?.cancel()
        animationTask = nil
        isBlinking = false
    }
}

// MARK: - Combined Recording Display
struct RecordingDisplay: View {
    let duration: TimeInterval
    let isRecording: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            RecordingIndicator(isRecording: isRecording)
            RecordingTimer(duration: duration, isRecording: isRecording)
        }
        .frame(maxWidth: .infinity) // Center the recording display
    }
}

#Preview {
    VStack(spacing: 30) {
        // Timer only - idle
        RecordingTimer(duration: 0, isRecording: false)
        
        // Timer only - recording
        RecordingTimer(duration: 65, isRecording: true)
        
        // Recording indicator - idle
        RecordingIndicator(isRecording: false)
        
        // Recording indicator - active
        RecordingIndicator(isRecording: true)
        
        // Combined display - idle
        RecordingDisplay(duration: 0, isRecording: false)
        
        // Combined display - recording
        RecordingDisplay(duration: 125, isRecording: true)
    }
    .padding()
}