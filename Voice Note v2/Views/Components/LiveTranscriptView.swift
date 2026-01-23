import SwiftUI

/// Live transcript display during recording
/// Shows volatile (in-progress) and finalized text with visual distinction
struct LiveTranscriptView: View {
    let transcript: String
    let isRecording: Bool
    let duration: TimeInterval

    @State private var scrollDebounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Transcript area with progressive scroll (old text fades at top)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        if transcript.isEmpty {
                            if isRecording {
                                // During recording, waiting for speech
                                recordingEmptyState
                            } else {
                                // Idle state (before recording)
                                idleEmptyState
                            }
                        } else {
                            // Transcript text
                            Text(transcript)
                                .font(.system(.title3, design: .rounded))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(Spacing.xs)
                        }

                        // Bottom anchor for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(Spacing.md)
                }
                .onChange(of: transcript) { _, _ in
                    // Debounce scroll to reduce animation overhead during rapid transcript updates
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: AudioConstants.Debounce.scroll)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Fade mask at top - old text fades out as it scrolls up
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)

                    Color.black  // Fully visible below gradient
                }
            )

            // Bottom bar with recording indicator and duration (only during recording)
            if isRecording {
                recordingStatusBar
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(isRecording ? Color.red : Color(.systemGray4),
                        lineWidth: isRecording ? 2 : 1)
                .phaseAnimator([false, true]) { content, phase in
                    content.opacity(
                        isRecording ? (phase ? 0.4 : 0.8) : 1.0
                    )
                } animation: { phase in
                    phase ? .easeInOut(duration: 1.0) : .easeOut(duration: 0.3)
                }
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var idleEmptyState: some View {
        VStack {
            Spacer()
            Text("Tap record to start transcribing.")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var recordingEmptyState: some View {
        VStack(spacing: Spacing.sm) {
            // No waveform icon - cleaner look
            Text("Listening...")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }

    @ViewBuilder
    private var recordingStatusBar: some View {
        HStack {
            // Recording indicator
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(phase ? 0.5 : 1.0)
                    } animation: { _ in .easeInOut(duration: 1.0) }

                Text("REC")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundColor(.red)
            }

            Spacer()

            // Duration
            Text(Formatters.duration(duration))
                .font(.system(.callout, design: .monospaced, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color(.systemGray6))
    }

}

/// Controls view displayed below the transcript during live recording
struct LiveRecordingControlsView: View {
    let audioLevel: Float
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: Spacing.sm) {
            // Audio level visualization
            AudioLevelBar(level: audioLevel)
                .frame(height: ComponentSize.minTouchTarget)

            Spacer()

            // Stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: ComponentSize.largeButton, height: ComponentSize.largeButton)
                        .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: ComponentSize.buttonIcon, height: ComponentSize.buttonIcon)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Text("Tap to stop")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
    }
}

/// Audio level visualization using a center-out symmetric dot matrix.
///
/// Visual behavior:
/// - 3 rows × 19 columns (11 in Low Power Mode)
/// - Fills from center outward horizontally as level increases
/// - Fills bottom-up vertically (bottom row = low, top row = loud)
/// - Color zones: green (center) → yellow (mid) → red (edges), or monochrome gray
///
/// Performance:
/// - TimelineView provides 30/60fps update scheduling
/// - Canvas uses immediate-mode drawing with Metal compositing
/// - `.drawingGroup()` enables GPU acceleration
struct AudioLevelBar: View {
    // MARK: - Constants

    private enum Constants {
        // Grid dimensions (~1.33x scale, pixel-aligned)
        static let rowCount = 3
        static let standardColumnCount = 19  // was 15 (odd for center symmetry)
        static let lowPowerColumnCount = 11  // was 9 (odd for center symmetry)
        static let dotDiameter: CGFloat = 8.0  // was 6.0 (pixel-aligned on all devices)
        static let dotSpacing: CGFloat = 4.0   // was 3.0 (pixel-aligned)
        static let rowSpacing: CGFloat = 4.0   // was 3.0 (pixel-aligned)

        // Row activation thresholds (level required to light each row)
        static let midRowThreshold: Float = 0.33
        static let topRowThreshold: Float = 0.66

        // Color zone boundaries (normalized distance from center)
        static let yellowZoneStart: Float = 0.5
        static let redZoneStart: Float = 0.8

        // Appearance
        static let inactiveOpacity: Double = 0.3
        static let monochromeOpacity: Double = 0.65  // slightly higher for better contrast
    }

    // MARK: - Properties

    /// Current audio level (0.0 to 1.0)
    let level: Float

    /// App settings for frame rate
    @Environment(AppSettings.self) private var appSettings

    @ViewBuilder
    var body: some View {
        if appSettings.showAudioVisualizer {
            let interval = appSettings.frameRateInterval
            let columnCount = appSettings.lowPowerMode
                ? Constants.lowPowerColumnCount
                : Constants.standardColumnCount

            TimelineView(.animation(minimumInterval: interval)) { _ in
                Canvas { context, size in
                    let totalHorizontalSpace = Constants.dotSpacing * CGFloat(columnCount - 1)
                    let totalVerticalSpace = Constants.rowSpacing * CGFloat(Constants.rowCount - 1)

                    // Calculate dot size to fit, capped at max diameter
                    let availableWidth = size.width - totalHorizontalSpace
                    let availableHeight = size.height - totalVerticalSpace
                    let dotSize = min(
                        availableWidth / CGFloat(columnCount),
                        availableHeight / CGFloat(Constants.rowCount),
                        Constants.dotDiameter
                    )

                    // Center the grid horizontally
                    let gridWidth = CGFloat(columnCount) * dotSize + totalHorizontalSpace
                    let startX = (size.width - gridWidth) / 2

                    // Center the grid vertically
                    let gridHeight = CGFloat(Constants.rowCount) * dotSize + totalVerticalSpace
                    let startY = (size.height - gridHeight) / 2

                    let activeRows = activeRowCount()

                    for row in 0..<Constants.rowCount {
                        for column in 0..<columnCount {
                            // Row 0 = bottom, row 2 = top
                            // Bottom rows light first, so check if row < activeRows
                            let rowActive = row < activeRows
                            let columnActive = isColumnActive(column: column, totalColumns: columnCount)
                            let isActive = rowActive && columnActive

                            let x = startX + CGFloat(column) * (dotSize + Constants.dotSpacing)
                            // Flip Y so row 0 is at bottom
                            let y = startY + CGFloat(Constants.rowCount - 1 - row) * (dotSize + Constants.rowSpacing)

                            let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                            let path = Path(ellipseIn: rect)

                            let color = dotColor(column: column, totalColumns: columnCount, isActive: isActive)
                            context.fill(path, with: .color(color))
                        }
                    }
                }
                .drawingGroup()
            }
        }
        // When disabled, renders nothing (no placeholder needed since parent handles layout)
    }

    // MARK: - Activation Logic

    /// Determines if a column should be lit based on center-out fill pattern.
    /// Center columns light first, edges require higher level.
    private func isColumnActive(column: Int, totalColumns: Int) -> Bool {
        let center = Float(totalColumns - 1) / 2.0
        let distanceFromCenter = abs(Float(column) - center)
        let maxDistance = center
        let normalizedDistance = distanceFromCenter / maxDistance  // 0.0 at center, 1.0 at edge

        // Center lights first (low threshold), edges light last (high threshold)
        return level >= normalizedDistance
    }

    /// Returns how many rows should be lit (1-3) based on level.
    /// Bottom row lights first, top row requires highest level.
    private func activeRowCount() -> Int {
        if level >= Constants.topRowThreshold { return 3 }
        if level >= Constants.midRowThreshold { return 2 }
        return 1
    }

    /// Determines dot color based on horizontal distance from center.
    /// Center = green, mid = yellow, edges = red. Or monochrome gray if setting enabled.
    private func dotColor(column: Int, totalColumns: Int, isActive: Bool) -> Color {
        if !isActive {
            return Color.gray.opacity(Constants.inactiveOpacity)
        }

        // Monochrome mode: adapts to light/dark mode via Color.primary
        if appSettings.audioVisualizerMonochrome {
            return Color.primary.opacity(Constants.monochromeOpacity)
        }

        // Colored mode (existing logic)
        let center = Float(totalColumns - 1) / 2.0
        let distanceFromCenter = abs(Float(column) - center)
        let normalizedDistance = distanceFromCenter / center  // 0.0 to 1.0

        if normalizedDistance >= Constants.redZoneStart {
            return .red
        } else if normalizedDistance >= Constants.yellowZoneStart {
            return .yellow
        } else {
            return .green
        }
    }
}

// MARK: - Previews

#Preview("With Transcript") {
    VStack {
        LiveTranscriptView(
            transcript: "This is a test transcript that shows how the live transcription looks during recording. It should auto-scroll as more text appears.",
            isRecording: true,
            duration: 45
        )
        .frame(height: 300)

        LiveRecordingControlsView(
            audioLevel: 0.6,
            onStop: {}
        )
        .frame(height: 200)
    }
    .padding()
}

#Preview("Recording Empty State") {
    VStack {
        LiveTranscriptView(
            transcript: "",
            isRecording: true,
            duration: 3
        )
        .frame(height: 300)

        LiveRecordingControlsView(
            audioLevel: 0.2,
            onStop: {}
        )
        .frame(height: 200)
    }
    .padding()
}

#Preview("Idle State") {
    LiveTranscriptView(
        transcript: "",
        isRecording: false,
        duration: 0
    )
    .frame(height: 300)
    .padding()
}
