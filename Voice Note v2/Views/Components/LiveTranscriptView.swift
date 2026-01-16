import SwiftUI

/// Live transcript display during recording
/// Shows volatile (in-progress) and finalized text with visual distinction
struct LiveTranscriptView: View {
    let transcript: String
    let isRecording: Bool
    let duration: TimeInterval

    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 0) {
            // Transcript area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if transcript.isEmpty {
                            // Empty state - waiting for speech
                            emptyStateView
                        } else {
                            // Transcript text
                            Text(transcript)
                                .font(.system(.title3, design: .rounded))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }

                        // Invisible anchor for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: transcript) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom bar with recording indicator and duration
            recordingStatusBar
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.red, lineWidth: 3)
                .opacity(isPulsing ? 0.3 : 1.0)
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
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
                .symbolEffect(.variableColor.iterative, options: .repeating, value: isRecording)

            Text("Listening...")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var recordingStatusBar: some View {
        HStack {
            // Recording indicator
            HStack(spacing: 6) {
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
            Text(formatDuration(duration))
                .font(.system(.callout, design: .monospaced, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let safeDuration = duration.isFinite ? max(0, duration) : 0.0
        let minutes = Int(safeDuration) / 60
        let seconds = Int(safeDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

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
        VStack(spacing: 20) {
            // Audio level visualization
            AudioLevelBar(level: audioLevel, isVoiceDetected: isVoiceDetected)
                .frame(height: 44)

            Spacer()

            // Stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Text("Tap to stop")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 40)
    }
}

/// Simple horizontal audio level bar
struct AudioLevelBar: View {
    let level: Float
    let isVoiceDetected: Bool

    private let barCount = 20
    private let spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let threshold = Float(index) / Float(barCount)
                    let isActive = level > threshold

                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: index, isActive: isActive))
                        .frame(width: barWidth(geometry: geometry))
                        .scaleEffect(y: isActive ? 1.0 : 0.3, anchor: .bottom)
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func barWidth(geometry: GeometryProxy) -> CGFloat {
        let totalSpacing = spacing * CGFloat(barCount - 1)
        return (geometry.size.width - totalSpacing) / CGFloat(barCount)
    }

    private func barColor(for index: Int, isActive: Bool) -> Color {
        if !isActive {
            return Color.gray.opacity(0.3)
        }

        let position = Float(index) / Float(barCount)
        if position > 0.8 {
            return .red  // High levels
        } else if position > 0.5 {
            return .yellow  // Medium levels
        } else {
            return isVoiceDetected ? .green : .blue  // Normal levels
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

#Preview("Empty State") {
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
