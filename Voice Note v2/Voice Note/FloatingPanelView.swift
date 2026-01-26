//
//  FloatingPanelView.swift
//  Voice Note (macOS)
//
//  Floating panel for quick capture from menu bar.
//  Simplified 3-state model: Ready → Recording → Done
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.voicenote", category: "FloatingPanel")

// MARK: - Layout Constants

private enum Layout {
    static let width: CGFloat = 420
    static let height: CGFloat = 320
    static let cornerRadius: CGFloat = 14
    static let windowTitle = "Voice Note"  // Must match Window title in Voice_NoteApp
}

/// Panel states for UI rendering.
/// Simplified from 6 states to 3: ready, recording, done.
private enum PanelState {
    case ready      // Idle, waiting to record
    case recording  // Actively recording
    case done       // Recording complete, transcript shown
}

struct FloatingPanelView: View {
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var hasCopied = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var persistedTranscript: String = ""

    /// Derived panel state from recording manager
    private var panelState: PanelState {
        switch recordingManager.recordingState {
        case .idle:
            // Check if we have persisted transcript from completed recording
            if !persistedTranscript.isEmpty {
                return .done
            }
            return .ready
        case .recording:
            return .recording
        case .processing:
            // Show as done during brief processing (user sees "Copied!" feedback)
            return .done
        }
    }

    /// Transcript to display - persisted for done state, live for recording
    private var displayTranscript: String {
        panelState == .done
            ? persistedTranscript
            : recordingManager.liveTranscriptionService.displayText
    }

    var body: some View {
        panelContent
            .frame(width: Layout.width, height: Layout.height)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
            .overlay(panelBorder)
            .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 10)
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            .onAppear(perform: handleOnAppear)
            .onDisappear(perform: handleOnDisappear)
            .onChange(of: appSettings.floatingPanelStayOnTop) { _, newValue in
                WindowManager.setFloating(newValue, for: WindowManager.ID.floatingPanel)
            }
            .onChange(of: recordingManager.recordingState, handleRecordingStateChange)
            .onChange(of: recordingManager.completedTranscript) { _, transcript in
                // Observe completedTranscript directly — set AFTER stopTranscribing() finishes.
                // This eliminates the race condition where displayText was read before finalization.
                if let transcript, !transcript.isEmpty {
                    handleRecordingCompleted(transcript: transcript)
                }
            }
    }

    /// Main panel content layout
    private var panelContent: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.5)
            contentArea
            Divider().opacity(0.5)
            controlBar
        }
    }

    /// Border overlay for panel
    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: Layout.cornerRadius)
            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
    }

    private func handleOnAppear() {
        WindowManager.setIdentifier(WindowManager.ID.floatingPanel, forWindowWithTitle: Layout.windowTitle)
        WindowManager.setFloating(appSettings.floatingPanelStayOnTop, for: WindowManager.ID.floatingPanel)
    }

    private func handleOnDisappear() {
        copyFeedbackTask?.cancel()

        // Finalize if panel closes while recording
        if recordingManager.recordingState == .recording {
            Task {
                await recordingManager.finalizeRecording()
            }
        }
    }

    private func handleRecordingStateChange(_ oldState: RecordingState, _ newState: RecordingState) {
        // Handle new recording start (clears UI state for fresh session)
        // Note: Completion is handled by observing completedTranscript directly,
        // which is set AFTER stopTranscribing() finishes — no race condition.
        if newState == .recording && oldState != .recording {
            handleRecordingStarted()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Close button (top-left)
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Close")

            recordingIndicator

            Spacer()

            if panelState == .recording {
                Text(TimeFormatting.paddedDuration(recordingManager.currentDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Button {
                WindowManager.openOrSurface(id: WindowManager.ID.library, using: openWindow)
            } label: {
                Image(systemName: "rectangle.stack")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Open Library")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(panelAppearance.indicatorColor)
                .frame(width: 10, height: 10)
                .overlay {
                    if panelState == .recording {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.6)
                            .opacity(0.7)
                    }
                }

            Text(panelAppearance.statusText)
                .font(.headline)
                .foregroundColor(panelAppearance.statusTextColor)
        }
    }

    /// Consolidated panel appearance properties
    private struct PanelAppearance {
        let indicatorColor: Color
        let statusText: String
        let statusTextColor: Color
    }

    private var panelAppearance: PanelAppearance {
        switch panelState {
        case .ready:
            return PanelAppearance(indicatorColor: .gray, statusText: "Ready", statusTextColor: .primary)
        case .recording:
            return PanelAppearance(indicatorColor: .red, statusText: "Recording", statusTextColor: .red)
        case .done:
            return PanelAppearance(
                indicatorColor: .green,
                statusText: hasCopied ? "Copied!" : "Done",
                statusTextColor: hasCopied ? .green : .primary
            )
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        Group {
            switch panelState {
            case .ready:
                readyContent
            case .recording, .done:
                transcriptContent
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var readyContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))

            Text("Ready to record")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if displayTranscript.isEmpty {
                        listeningPlaceholder
                    } else {
                        Text(displayTranscript)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("transcript-bottom")
                    }
                }
                .padding(16)
            }
            .onChange(of: displayTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var listeningPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Listening...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack {
            leftControls
            Spacer()
            rightControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 44)
    }

    /// Left side controls based on panel state
    @ViewBuilder
    private var leftControls: some View {
        switch panelState {
        case .ready:
            // Record button
            Button(action: toggleRecording) {
                Label("Record", systemImage: "record.circle")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        case .recording:
            // Done button (stops recording)
            Button(action: toggleRecording) {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        case .done:
            // Record Again button
            Button(action: startNewRecording) {
                Label("Record", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    /// Right side controls: Copy button in done state
    @ViewBuilder
    private var rightControls: some View {
        if panelState == .done && !displayTranscript.isEmpty {
            Button(action: copyTranscript) {
                Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .tint(hasCopied ? .green : nil)
            .help(hasCopied ? "Copied!" : "Copy")
        }
    }

    // MARK: - State Handlers

    /// Handles recording completion with the authoritative, finalized transcript.
    /// Called when `completedTranscript` is set — guaranteed to be after `stopTranscribing()` finishes.
    private func handleRecordingCompleted(transcript: String) {
        persistedTranscript = transcript

        // Auto-copy to clipboard
        PlatformPasteboard.shared.copyText(transcript)
        PlatformFeedback.shared.success()
        hasCopied = true
        showCopyFeedback()
    }

    /// Resets UI state when starting a new recording.
    private func handleRecordingStarted() {
        persistedTranscript = ""
        hasCopied = false
        copyFeedbackTask?.cancel()
    }

    // MARK: - Actions

    /// Toggle recording state (start or stop).
    private func toggleRecording() {
        Task {
            await recordingManager.toggleRecording()
        }
    }

    /// Starts a new recording, finalizing any previous session.
    private func startNewRecording() {
        hasCopied = false
        copyFeedbackTask?.cancel()

        Task {
            await recordingManager.finalizeAndStartNew()
        }
    }

    private func copyTranscript() {
        let text = displayTranscript
        guard !text.isEmpty else { return }

        PlatformPasteboard.shared.copyText(text)
        PlatformFeedback.shared.success()
        hasCopied = true
        showCopyFeedback()
    }

    /// Shows copy feedback with auto-reset after 2 seconds.
    private func showCopyFeedback() {
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hasCopied = false
        }
    }

}

#Preview {
    FloatingPanelView()
        .environment(RecordingManager())
        .environment(AppSettings.shared)
        .frame(width: Layout.width, height: Layout.height)
}
