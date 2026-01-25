//
//  FloatingPanelView.swift
//  Voice Note (macOS)
//
//  Floating panel for quick capture from menu bar.
//  Features liquid glass vibrancy, pause/resume, and auto-archive.
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

/// Panel-specific states for UI rendering.
/// Separate from RecordingState because the panel needs a "complete" state
/// to show post-recording UI (copy button, transcript) while RecordingManager
/// returns to idle. This allows the panel to persist completion state across
/// the recording lifecycle.
private enum PanelState {
    case idle
    case recording
    case paused
    case stopped      // "Soft stopped" - can resume, auto-copied
    case processing
    case complete
}

struct FloatingPanelView: View {
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var hasCopied = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var persistedTranscript: String = ""
    @State private var isSoftStopped: Bool = false
    @State private var archivedRecordingId: UUID?  // Tracks archived recording to prevent duplicates

    /// Derived panel state from recording manager
    private var panelState: PanelState {
        switch recordingManager.recordingState {
        case .idle:
            // Check if we have persisted transcript from completed recording
            if !persistedTranscript.isEmpty {
                return .complete
            }
            return .idle
        case .recording:
            return .recording
        case .paused:
            // UI distinction: soft-stopped shows different controls than paused
            return isSoftStopped ? .stopped : .paused
        case .processing:
            return .processing
        }
    }

    /// Transcript to display - persisted for complete state, live for recording/paused
    /// Note: Accesses liveTranscriptionService.displayText directly to ensure @Observable
    /// properly tracks changes (computed properties through RecordingManager don't propagate).
    private var displayTranscript: String {
        panelState == .complete
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

        // Auto-finalize if panel closes while soft-stopped
        // This ensures the transcript is saved to database, not lost
        if isSoftStopped {
            Task {
                await recordingManager.finalizeRecording()
            }
        }
    }

    private func handleRecordingStateChange(_ oldState: RecordingState, _ newState: RecordingState) {
        // Handle recording completion: .recording/.paused/.processing → .idle
        let wasActiveSession = oldState == .recording || oldState == .paused || oldState == .processing
        if wasActiveSession && newState == .idle {
            handleRecordingCompleted()
        }
        // Handle new recording start (not resume from pause)
        if newState == .recording && oldState != .paused {
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

            if panelState == .recording || panelState == .paused || panelState == .stopped {
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
        case .idle:
            return PanelAppearance(indicatorColor: .gray, statusText: "Ready", statusTextColor: .primary)
        case .recording:
            return PanelAppearance(indicatorColor: .red, statusText: "Recording", statusTextColor: .red)
        case .paused:
            return PanelAppearance(indicatorColor: .orange, statusText: "Paused", statusTextColor: .orange)
        case .stopped:
            return PanelAppearance(indicatorColor: .green, statusText: hasCopied ? "Auto-copied" : "Stopped", statusTextColor: hasCopied ? .green : .primary)
        case .processing:
            return PanelAppearance(indicatorColor: .blue, statusText: "Processing...", statusTextColor: .primary)
        case .complete:
            return PanelAppearance(indicatorColor: .green, statusText: "Complete", statusTextColor: .primary)
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        Group {
            switch panelState {
            case .idle:
                idleContent
            case .recording, .paused, .stopped, .processing, .complete:
                // Keep showing transcript during all active/post-recording states
                transcriptContent
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var idleContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))

            Text("Start recording to capture your voice")
                .font(.body)
                .foregroundColor(.secondary)

            Button(action: startNewRecording) {
                Label("Record", systemImage: "record.circle")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
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
            if panelState == .paused {
                Image(systemName: "pause.circle")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                Text("Paused")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else if panelState == .stopped {
                Image(systemName: "stop.circle")
                    .font(.system(size: 32))
                    .foregroundColor(.green)
                Text("Stopped")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Listening...")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Control Bar

    /// Reusable copy button with optional checkmark feedback.
    @ViewBuilder
    private func copyButton(showFeedback: Bool = false) -> some View {
        let isFeedbackActive = showFeedback && hasCopied

        Button(action: copyTranscript) {
            Image(systemName: isFeedbackActive ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .tint(isFeedbackActive ? .green : nil)
        .help(isFeedbackActive ? "Copied!" : (showFeedback ? "Copy Again" : "Copy"))
        .disabled(displayTranscript.isEmpty)
    }

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
        HStack(spacing: 8) {
            switch panelState {
            case .recording:
                recordingControls
            case .paused:
                pausedControls
            case .stopped:
                stoppedControls
            case .processing:
                ProgressView()
                    .scaleEffect(0.8)
            case .idle, .complete:
                EmptyView()
            }
        }
    }

    /// Controls shown while recording: [Pause] [Stop]
    @ViewBuilder
    private var recordingControls: some View {
        if recordingManager.isUsingLiveTranscription {
            Button(action: pauseRecording) {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(.bordered)
            .help("Pause")
        }

        Button(action: softStop) {
            Image(systemName: "stop.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .help("Stop")
    }

    /// Controls shown while paused: [Resume] [Stop] [Copy]
    @ViewBuilder
    private var pausedControls: some View {
        Button(action: resumeRecording) {
            Image(systemName: "record.circle")
        }
        .buttonStyle(.bordered)
        .help("Resume")

        Button(action: softStop) {
            Image(systemName: "stop.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .help("Stop")

        copyButton()
    }

    /// Controls shown while soft-stopped: [Resume] [Copy]
    @ViewBuilder
    private var stoppedControls: some View {
        Button(action: resumeFromStop) {
            Image(systemName: "record.circle")
        }
        .buttonStyle(.bordered)
        .help("Resume Recording")

        copyButton(showFeedback: true)
    }

    /// Right side controls: New Recording button and complete-state copy
    @ViewBuilder
    private var rightControls: some View {
        HStack(spacing: 8) {
            if panelState == .stopped || panelState == .complete || panelState == .idle {
                Button(action: startNewRecording) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("New Recording")
            }

            if panelState == .complete {
                copyButton(showFeedback: true)
            }
        }
    }

    // MARK: - State Handlers

    /// Handles recording completion: persists transcript, auto-copies, optionally archives.
    private func handleRecordingCompleted() {
        isSoftStopped = false
        persistedTranscript = recordingManager.liveTranscriptionService.displayText

        guard !persistedTranscript.isEmpty else { return }

        PlatformPasteboard.shared.copyText(persistedTranscript)
        PlatformFeedback.shared.success()
        hasCopied = true
        archiveIfNeeded(recordingManager.lastRecordingId)
        showCopyFeedback()
    }

    /// Resets UI state when starting a new recording.
    private func handleRecordingStarted() {
        isSoftStopped = false
        persistedTranscript = ""
        hasCopied = false
        archivedRecordingId = nil
        copyFeedbackTask?.cancel()
    }

    // MARK: - Actions

    /// Starts a new recording, finalizing any previous session.
    private func startNewRecording() {
        isSoftStopped = false
        hasCopied = false
        archivedRecordingId = nil
        copyFeedbackTask?.cancel()

        Task {
            await recordingManager.finalizeAndStartNew()
        }
    }

    /// Soft stop: pauses recording and triggers auto-copy, but allows resume.
    private func softStop() {
        // Handle based on current state
        switch recordingManager.recordingState {
        case .recording:
            do {
                try recordingManager.pauseRecording()
            } catch {
                logger.error("Pause in softStop failed: \(error.localizedDescription)")
                return
            }
        case .paused:
            break  // Already paused, proceed to soft stop
        case .idle, .processing:
            logger.warning("softStop called in unexpected state: \(String(describing: recordingManager.recordingState))")
            return
        }

        isSoftStopped = true
        copyTranscript()
    }

    /// Resume from soft-stopped state.
    private func resumeFromStop() {
        do {
            try recordingManager.resumeRecording()
            isSoftStopped = false
            // Note: Don't clear hasCopied - let existing timeout handle it
        } catch {
            logger.error("Resume from stop failed: \(error.localizedDescription)")
        }
    }

    private func pauseRecording() {
        do {
            try recordingManager.pauseRecording()
        } catch {
            logger.error("Pause failed: \(error.localizedDescription)")
        }
    }

    private func resumeRecording() {
        do {
            try recordingManager.resumeRecording()
        } catch {
            logger.error("Resume failed: \(error.localizedDescription)")
        }
    }

    private func copyTranscript() {
        let text = displayTranscript
        guard !text.isEmpty else { return }

        PlatformPasteboard.shared.copyText(text)
        PlatformFeedback.shared.success()
        hasCopied = true

        archiveIfNeeded(recordingManager.lastRecordingId)
        showCopyFeedback()
    }

    /// Archives the recording if auto-archive setting is enabled.
    /// Guards against duplicate calls for the same recording.
    private func archiveIfNeeded(_ recordingId: UUID?) {
        guard appSettings.autoArchiveQuickCaptures,
              let recordingId = recordingId,
              archivedRecordingId != recordingId else { return }

        archivedRecordingId = recordingId
        recordingManager.archiveRecording(id: recordingId)
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
