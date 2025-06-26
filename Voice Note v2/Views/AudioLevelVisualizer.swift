import SwiftUI

struct AudioLevelVisualizer: View {
    let levels: [Float]  // Array of audio levels (0.0 to 1.0)
    let isRecording: Bool
    var isVoiceDetected: Bool = false
    
    private let barCount = 5
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 6
    private let maxBarHeight: CGFloat = 40
    private let baselineHeight: CGFloat = 6  // Uniform baseline for all bars
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(barColor(for: index))
                    .frame(width: barWidth, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.1), value: levels)
            }
        }
        .frame(height: maxBarHeight) // Fixed height for alignment
        .opacity(isRecording ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.25), value: isRecording)
    }
    
    
    private func barHeight(for index: Int) -> CGFloat {
        guard isRecording, index < levels.count else {
            return baselineHeight
        }
        
        let level = max(0.0, min(1.0, levels[index])) // Clamp level between 0-1
        let heightRange = maxBarHeight - baselineHeight
        return max(baselineHeight, baselineHeight + (CGFloat(level) * heightRange))
    }
    
    private func barColor(for index: Int) -> Color {
        if !isRecording {
            return .gray.opacity(0.3)
        }
        
        guard index < levels.count else {
            return .gray.opacity(0.3)
        }
        
        let level = levels[index]
        
        // Voice detection colors
        if isVoiceDetected {
            // Blue tint when voice is detected
            if level > 0.8 {
                return .red.opacity(0.9)      // Still red for peaking
            } else if level > 0.6 {
                return .blue.opacity(0.9)     // Blue for voice
            } else {
                return .blue.opacity(0.7)     // Lighter blue
            }
        } else {
            // Gray when no voice detected
            return .gray.opacity(0.5)
        }
    }
}

// MARK: - Convenience Initializers
extension AudioLevelVisualizer {
    init(isRecording: Bool) {
        self.isRecording = isRecording
        self.levels = Array(repeating: 0.0, count: 5)
    }
    
    init(audioLevel: Float, isRecording: Bool, isVoiceDetected: Bool = false) {
        self.isRecording = isRecording
        self.isVoiceDetected = isVoiceDetected
        
        // Optimize calculations - pre-compute multipliers for better performance
        if isRecording && audioLevel > 0 {
            // Generate varied levels based on single input for visual interest
            self.levels = [
                audioLevel,
                audioLevel * 0.8,
                audioLevel * 0.9,
                audioLevel * 0.7,
                audioLevel * 0.85
            ]
        } else {
            // Use static zero array when not recording to avoid unnecessary calculations
            self.levels = [0.0, 0.0, 0.0, 0.0, 0.0]
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Idle state
        AudioLevelVisualizer(isRecording: false)
        
        // Low recording
        AudioLevelVisualizer(audioLevel: 0.3, isRecording: true)
        
        // Medium recording
        AudioLevelVisualizer(audioLevel: 0.6, isRecording: true)
        
        // High recording
        AudioLevelVisualizer(audioLevel: 0.9, isRecording: true)
    }
    .padding()
}