//
//  QuickCapturePanel.swift
//  Voice Note (macOS)
//
//  Compact live preview panel for Quick Capture mode.
//  Appears near menu bar when recording starts, auto-dismisses on stop.
//

import SwiftUI

struct QuickCapturePanel: View {
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(\.dismiss) private var dismiss

    /// Brief delay before dismissing panel after recording stops.
    /// Allows user to see final transcript state before window closes.
    private let dismissDelayAfterIdle: Duration = .seconds(1)

    /// Task for delayed auto-dismiss. Stored to allow cancellation if view disappears.
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header: indicator + duration + stop button
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)

                Text(TimeFormatting.paddedDuration(recordingManager.currentDuration))
                    .font(.system(.caption, design: .monospaced))

                Spacer()

                Button(action: stopAndCopy) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            // Live transcript
            ScrollView {
                Text(recordingManager.liveTranscript.isEmpty
                     ? "Listening..."
                     : recordingManager.liveTranscript)
                    .font(.body)
                    .foregroundColor(recordingManager.liveTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 320, height: 200)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .onChange(of: recordingManager.recordingState) { _, newState in
            dismissTask?.cancel()
            guard newState == .idle else { return }
            dismissTask = Task {
                try? await Task.sleep(for: dismissDelayAfterIdle)
                guard !Task.isCancelled else { return }
                dismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func stopAndCopy() {
        Task {
            // Returns nil/empty if no speech detected - expected for short recordings.
            // Panel dismisses gracefully regardless; no user-facing error needed.
            _ = await recordingManager.stopRecordingAndCopyToClipboard()
        }
    }
}

#Preview {
    QuickCapturePanel()
        .environment(RecordingManager())
        .frame(width: 320, height: 200)
}
