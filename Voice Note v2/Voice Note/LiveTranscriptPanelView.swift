//
//  LiveTranscriptPanelView.swift
//  Voice Note (macOS)
//
//  Floating HUD panel showing live transcription during recording.
//  Uses translucent vibrancy material for macOS native look.
//

import SwiftUI

struct LiveTranscriptPanelView: View {
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header with recording indicator
            headerBar

            Divider()

            // Transcript content
            transcriptContent

            Divider()

            // Bottom controls
            controlBar
        }
        .frame(width: 400, height: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(recordingManager.recordingState == .recording ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                    .overlay {
                        if recordingManager.recordingState == .recording {
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.5)
                                .opacity(0.8)
                        }
                    }

                Text(recordingManager.recordingState == .recording ? "Recording" : "Stopped")
                    .font(.headline)
            }

            Spacer()

            // Duration
            if recordingManager.recordingState == .recording {
                Text(TimeFormatting.paddedDuration(recordingManager.currentDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Input device
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.caption)
                Text(recordingManager.liveAudioService.currentInputDevice)
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }

    // MARK: - Transcript Content

    private var transcriptContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if recordingManager.liveTranscript.isEmpty {
                        emptyTranscriptState
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
        .frame(maxHeight: .infinity)
    }

    private var emptyTranscriptState: some View {
        VStack(spacing: 12) {
            if recordingManager.recordingState == .recording {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Listening...")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "waveform")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("Start recording to see live transcription")
                    .font(.body)
                    .foregroundColor(.secondary)

                // Record button
                Button(action: startRecording) {
                    Label("Record", systemImage: "record.circle")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Stop button
            Button(action: stopRecording) {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(recordingManager.recordingState != .recording)

            Spacer()

            // Copy transcript button
            Button(action: copyTranscript) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(recordingManager.liveTranscript.isEmpty)

            // Close button
            Button(action: { dismiss() }) {
                Label("Close", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func stopRecording() {
        Task {
            await recordingManager.toggleRecording()
        }
    }

    private func copyTranscript() {
        PlatformPasteboard.shared.copyText(recordingManager.liveTranscript)
        PlatformFeedback.shared.success()
    }

    private func startRecording() {
        Task {
            await recordingManager.toggleRecording()
        }
    }
}

#Preview {
    LiveTranscriptPanelView()
        .frame(width: 400, height: 300)
}
