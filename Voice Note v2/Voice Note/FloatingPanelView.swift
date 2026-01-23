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

/// Panel-specific states for UI rendering.
/// Separate from RecordingState because the panel needs a "complete" state
/// to show post-recording UI (copy button, transcript) while RecordingManager
/// returns to idle. This allows the panel to persist completion state across
/// the recording lifecycle.
private enum PanelState {
    case idle
    case recording
    case paused
    case processing
    case complete
}

struct FloatingPanelView: View {
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var hasCopied = false
    @State private var lastCopiedRecordingId: UUID?
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var persistedTranscript: String = ""

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
            return .paused
        case .processing:
            return .processing
        }
    }

    /// Transcript to display - persisted for complete state, live for recording/paused
    private var displayTranscript: String {
        panelState == .complete ? persistedTranscript : recordingManager.liveTranscript
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()
                .opacity(0.5)

            contentArea

            Divider()
                .opacity(0.5)

            controlBar
        }
        .frame(width: 420, height: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            WindowManager.setIdentifier(WindowManager.ID.floatingPanel, forWindowWithTitle: "Voice Note")
            WindowManager.setFloating(appSettings.floatingPanelStayOnTop, for: WindowManager.ID.floatingPanel)
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
        .onChange(of: appSettings.floatingPanelStayOnTop) { _, newValue in
            WindowManager.setFloating(newValue, for: WindowManager.ID.floatingPanel)
        }
        .onChange(of: recordingManager.recordingState) { oldState, newState in
            let wasRecording = oldState == .recording || oldState == .paused
            if wasRecording && newState == .idle {
                handleRecordingCompleted()
            }
            if newState == .recording && oldState != .paused {
                handleRecordingStarted()
            }
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

            if panelState == .recording || panelState == .paused {
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
            case .recording, .paused, .complete:
                transcriptContent
            case .processing:
                processingContent
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

    private var processingContent: some View {
        VStack(spacing: 16) {
            ProgressView()

            Text("Finalizing...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack {
            // LEFT SIDE: Pause/Resume + Stop
            HStack(spacing: 8) {
                // Pause/Resume button (only during recording)
                if panelState == .recording {
                    if recordingManager.isUsingLiveTranscription {
                        Button(action: pauseRecording) {
                            Image(systemName: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Pause")
                    }
                } else if panelState == .paused {
                    Button(action: resumeRecording) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Resume")
                }

                // Stop button (during recording or paused)
                if panelState == .recording || panelState == .paused {
                    Button(action: stopRecording) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .help("Stop")
                }
            }

            Spacer()

            // RIGHT SIDE: New Recording + Copy
            HStack(spacing: 8) {
                // Processing indicator
                if panelState == .processing {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                // New Recording button (+ icon)
                // Show when complete or idle (ready to start fresh)
                if panelState == .complete || panelState == .idle {
                    Button(action: startNewRecording) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("New Recording")
                }

                // Copy button (re-copy after auto-copy, or first copy)
                if panelState == .complete {
                    Button(action: copyTranscript) {
                        Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .tint(hasCopied ? .green : nil)
                    .help(hasCopied ? "Copied!" : "Copy Again")
                    .disabled(displayTranscript.isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 44)
    }

    // MARK: - State Handlers

    /// Handles recording completion: persists transcript, auto-copies, optionally archives.
    private func handleRecordingCompleted() {
        persistedTranscript = recordingManager.liveTranscript

        guard !persistedTranscript.isEmpty else { return }

        PlatformPasteboard.shared.copyText(persistedTranscript)
        PlatformFeedback.shared.success()
        hasCopied = true
        lastCopiedRecordingId = recordingManager.lastRecordingId

        if appSettings.autoArchiveQuickCaptures,
           let recordingId = recordingManager.lastRecordingId {
            recordingManager.archiveRecording(id: recordingId)
        }

        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hasCopied = false
        }
    }

    /// Resets UI state when starting a new recording.
    private func handleRecordingStarted() {
        persistedTranscript = ""
        lastCopiedRecordingId = nil
        hasCopied = false
        copyFeedbackTask?.cancel()
    }

    // MARK: - Actions

    /// Starts a new recording, resetting any previous state.
    private func startNewRecording() {
        lastCopiedRecordingId = nil
        hasCopied = false
        copyFeedbackTask?.cancel()

        Task {
            await recordingManager.toggleRecording()
        }
    }

    private func stopRecording() {
        Task {
            await recordingManager.toggleRecording()
        }
    }

    private func pauseRecording() {
        do {
            try recordingManager.pauseRecording()
        } catch {
            // Pause failed - user can still stop recording
            logger.error("Pause failed: \(error.localizedDescription)")
        }
    }

    private func resumeRecording() {
        do {
            try recordingManager.resumeRecording()
        } catch {
            // Resume failed - user can still stop recording
            logger.error("Resume failed: \(error.localizedDescription)")
        }
    }

    private func copyTranscript() {
        let text = displayTranscript
        guard !text.isEmpty else { return }

        // Capture ID immediately before any async work to prevent race condition
        // if user rapidly starts new recording after copy
        let recordingIdToArchive = recordingManager.lastRecordingId

        PlatformPasteboard.shared.copyText(text)
        PlatformFeedback.shared.success()
        hasCopied = true

        // Use captured ID for archiving
        if appSettings.autoArchiveQuickCaptures,
           let recordingId = recordingIdToArchive {
            recordingManager.archiveRecording(id: recordingId)
        }

        // Use captured ID for state tracking
        lastCopiedRecordingId = recordingIdToArchive

        // Cancellable task for resetting copy button state
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
        .frame(width: 420, height: 320)
}
