import SwiftUI

/// Live transcript display during recording
/// Shows volatile (in-progress) and finalized text with visual distinction
struct LiveTranscriptView: View {
    let transcript: String
    let isRecording: Bool
    let duration: TimeInterval

    @State private var isPulsing = false
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
                .stroke(isRecording ? Color.red : Color(.systemGray4), lineWidth: isRecording ? 2 : 1)
                .opacity(isRecording ? (isPulsing ? 0.4 : 0.8) : 1.0)
        )
        .onAppear {
            if isRecording {
                startPulsing()
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startPulsing()
            } else {
                stopPulsing()
            }
        }
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
                    .opacity(isPulsing ? 0.5 : 1.0)

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

    // MARK: - Helpers

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    private func stopPulsing() {
        withAnimation(.easeOut(duration: 0.3)) {
            isPulsing = false
        }
    }
}

/// Controls view displayed below the transcript during live recording
struct LiveRecordingControlsView: View {
    let audioLevel: Float
    let isVoiceDetected: Bool
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: Spacing.sm) {
            // Audio level visualization
            AudioLevelBar(level: audioLevel, isVoiceDetected: isVoiceDetected)
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

/// High-performance horizontal audio level bar using TimelineView + Canvas.
///
/// Responds to Low Power Mode:
/// - Standard: 60fps, 20 bars
/// - Low Power: 30fps, 12 bars
struct AudioLevelBar: View {
    /// Current audio level (0.0 to 1.0)
    let level: Float

    /// Whether voice is currently detected (affects color)
    let isVoiceDetected: Bool

    /// App settings for frame rate and bar count
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        let interval = appSettings.frameRateInterval
        let barCount = appSettings.levelBarCount
        let spacing = AudioConstants.LevelBar.barSpacing

        TimelineView(.animation(minimumInterval: interval)) { _ in
            Canvas { context, size in
                let totalSpacing = spacing * CGFloat(barCount - 1)
                let barWidth = (size.width - totalSpacing) / CGFloat(barCount)

                for index in 0..<barCount {
                    let x = CGFloat(index) * (barWidth + spacing)
                    let threshold = Float(index) / Float(barCount)
                    let isActive = level > threshold

                    let barHeight = isActive ? size.height : size.height * 0.3
                    let y = size.height - barHeight

                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let path = Path(roundedRect: rect, cornerRadius: 2)
                    context.fill(path, with: .color(barColor(for: index, isActive: isActive, barCount: barCount)))
                }
            }
            .drawingGroup()
        }
    }

    private func barColor(for index: Int, isActive: Bool, barCount: Int) -> Color {
        if !isActive {
            return Color.gray.opacity(0.3)
        }

        let position = Float(index) / Float(barCount)
        if position > AudioConstants.LevelThreshold.high {
            return .red
        } else if position > AudioConstants.LevelThreshold.medium {
            return .yellow
        } else {
            // Green when voice detected, blue otherwise
            return isVoiceDetected ? .green : .blue
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
            isVoiceDetected: true,
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
            isVoiceDetected: false,
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
