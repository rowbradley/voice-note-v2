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

    /// Derived panel state from recording manager
    private var panelState: PanelState {
        switch recordingManager.recordingState {
        case .idle:
            // Check if we just completed a recording (have transcript)
            if !recordingManager.liveTranscript.isEmpty || lastCopiedRecordingId != nil {
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

    /// Whether to show the red recording border
    private var showRecordingBorder: Bool {
        appSettings.showRecordingBorder &&
        (panelState == .recording || panelState == .paused)
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
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(recordingBorderOverlay)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
        .onChange(of: recordingManager.recordingState) { oldState, newState in
            if oldState != .recording && newState == .recording {
                lastCopiedRecordingId = nil
                hasCopied = false
                copyFeedbackTask?.cancel()
            }
        }
    }

    // MARK: - Recording Border Overlay

    @ViewBuilder
    private var recordingBorderOverlay: some View {
        if showRecordingBorder {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    panelState == .paused ? Color.orange.opacity(0.6) : Color.red.opacity(0.8),
                    lineWidth: 2
                )
                .shadow(
                    color: panelState == .paused ? Color.orange.opacity(0.3) : Color.red.opacity(0.4),
                    radius: panelState == .recording ? 8 : 4
                )
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            recordingIndicator

            Spacer()

            if panelState == .recording || panelState == .paused {
                Text(TimeFormatting.paddedDuration(recordingManager.currentDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Button(action: { openWindow(id: "library") }) {
                Image(systemName: "books.vertical")
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
                    if recordingManager.liveTranscript.isEmpty {
                        listeningPlaceholder
                    } else {
                        Text(recordingManager.liveTranscript)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("transcript-bottom")
                    }
                }
                .padding(16)
            }
            .onChange(of: recordingManager.liveTranscript) { _, _ in
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
        HStack(spacing: 12) {
            controlBarContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var controlBarContent: some View {
        switch panelState {
        case .idle:
            Spacer()
            Button(action: startNewRecording) {
                Label("Record", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            Spacer()

        case .recording:
            recordingControls

        case .paused:
            pausedControls

        case .processing:
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
            Spacer()

        case .complete:
            completeControls
        }
    }

    private var recordingControls: some View {
        Group {
            if recordingManager.isUsingLiveTranscription {
                Button(action: pauseRecording) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
            }

            Button(action: stopRecording) {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Spacer()

            copyButton
        }
    }

    private var pausedControls: some View {
        Group {
            Button(action: resumeRecording) {
                Label("Resume", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button(action: stopRecording) {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)

            Spacer()

            copyButton
        }
    }

    private var completeControls: some View {
        Group {
            Button(action: startNewRecording) {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .help("New Recording")

            Spacer()

            copyButton

            Button(action: { dismiss() }) {
                Label("Close", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Copy Button with Feedback

    private var copyButton: some View {
        Button(action: copyTranscript) {
            HStack(spacing: 4) {
                Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                Text(hasCopied ? "Copied!" : "Copy")
            }
        }
        .buttonStyle(.bordered)
        .tint(hasCopied ? .green : nil)
        .disabled(recordingManager.liveTranscript.isEmpty)
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
        let text = recordingManager.liveTranscript
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
