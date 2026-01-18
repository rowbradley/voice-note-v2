import SwiftUI

/// Vertical audio level visualizer using TimelineView + Canvas.
///
/// Performance characteristics:
/// - TimelineView provides controlled update scheduling (30 or 60fps)
/// - Canvas uses immediate-mode drawing (no view diffing)
/// - drawingGroup() composites to Metal texture
///
/// Responds to Low Power Mode:
/// - Standard: 60fps, 20 bars
/// - Low Power: 30fps, 12 bars
struct AudioLevelVisualizer: View {
    /// Current audio level (0.0 to 1.0)
    let level: Float

    /// Whether recording is active (pauses animation when false)
    let isRecording: Bool

    /// Whether voice is currently detected (affects color)
    var isVoiceDetected: Bool = false

    /// App settings for frame rate and bar count
    @Environment(\.appSettings) private var appSettings

    /// Fixed bar spacing
    private let barSpacing: CGFloat = AudioConstants.LevelBar.barSpacing

    /// Fixed height for the visualizer
    private let maxBarHeight: CGFloat = 40

    var body: some View {
        // Read settings at render time so changes take effect immediately
        let interval = appSettings.frameRateInterval
        let barCount = appSettings.levelBarCount

        TimelineView(.animation(minimumInterval: interval, paused: !isRecording)) { _ in
            Canvas { context, size in
                drawBars(context: context, size: size, barCount: barCount)
            }
            .drawingGroup() // Composite to Metal for performance
        }
        .frame(height: maxBarHeight)
        .opacity(isRecording ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.25), value: isRecording)
    }

    /// Draws the audio level bars.
    /// - Parameters:
    ///   - context: Canvas graphics context
    ///   - size: Available drawing size
    ///   - barCount: Number of bars to draw
    private func drawBars(context: GraphicsContext, size: CGSize, barCount: Int) {
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = (size.width - totalSpacing) / CGFloat(barCount)
        let startX = (size.width - (CGFloat(barCount) * barWidth + totalSpacing)) / 2

        for index in 0..<barCount {
            let x = startX + CGFloat(index) * (barWidth + barSpacing)
            let height = barHeight(for: index, maxHeight: size.height, barCount: barCount)
            let y = size.height - height

            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
            context.fill(path, with: .color(barColor(for: index, barCount: barCount)))
        }
    }

    /// Calculates bar height based on current audio level.
    /// - Parameters:
    ///   - index: Bar index (0 = leftmost)
    ///   - maxHeight: Maximum bar height
    ///   - barCount: Total number of bars
    /// - Returns: Height for this bar
    private func barHeight(for index: Int, maxHeight: CGFloat, barCount: Int) -> CGFloat {
        let position = Float(index) / Float(barCount)
        let isActive = level > position
        return isActive ? maxHeight : maxHeight * 0.3
    }

    /// Determines bar color based on position and activity.
    /// - Parameters:
    ///   - index: Bar index (0 = leftmost)
    ///   - barCount: Total number of bars
    /// - Returns: Color for this bar
    private func barColor(for index: Int, barCount: Int) -> Color {
        let position = Float(index) / Float(barCount)
        let isActive = level > position

        if !isActive {
            return Color.gray.opacity(0.3)
        }

        // Color zones based on position
        if position > AudioConstants.LevelThreshold.high {
            return .red      // Very loud (80%+)
        } else if position > AudioConstants.LevelThreshold.medium {
            return .yellow   // Moderately loud (50-80%)
        } else {
            // Green when voice detected, blue otherwise
            return isVoiceDetected ? .green : .blue
        }
    }
}

// MARK: - Convenience Initializers

extension AudioLevelVisualizer {
    /// Initialize with just recording state (level defaults to 0)
    init(isRecording: Bool) {
        self.level = 0.0
        self.isRecording = isRecording
        self.isVoiceDetected = false
    }

    /// Initialize with single audio level (backward compatible API)
    init(audioLevel: Float, isRecording: Bool, isVoiceDetected: Bool = false) {
        self.level = audioLevel
        self.isRecording = isRecording
        self.isVoiceDetected = isVoiceDetected
    }
}

// MARK: - Previews

#Preview("Recording - Standard") {
    AudioLevelVisualizer(audioLevel: 0.6, isRecording: true, isVoiceDetected: true)
        .padding()
}

#Preview("Recording - Low Level") {
    AudioLevelVisualizer(audioLevel: 0.2, isRecording: true)
        .padding()
}

#Preview("Not Recording") {
    AudioLevelVisualizer(isRecording: false)
        .padding()
}

#Preview("High Level") {
    AudioLevelVisualizer(audioLevel: 0.9, isRecording: true)
        .padding()
}
