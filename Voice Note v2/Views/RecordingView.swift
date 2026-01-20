//
//  RecordingView.swift
//  Voice Note v2
//
//  Main recording interface. Extracted from ContentView for tab-based navigation.
//

import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Bindable var recordingManager: RecordingManager
    @Environment(\.modelContext) private var modelContext
    @State private var pendingTemplateId: String?

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Voice Note")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.primary, Color.primary.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Record, transcribe, transform.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .tracking(0.5)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var recentRecordingsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                Color.clear.frame(width: 0)

                if !recordingManager.recentRecordings.isEmpty {
                    ForEach(Array(recordingManager.recentRecordings.prefix(3).enumerated()), id: \.element.id) { index, recording in
                        RecentRecordingCard(recording: recording) {
                            coordinator.showRecordingDetail(recording)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                } else {
                    emptyStateCard
                }

                Color.clear.frame(width: Spacing.md)
            }
            .padding(.horizontal, 1)
        }
    }

    @ViewBuilder
    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mic")
                    .foregroundColor(.gray)
                Text("--:--")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text("Record a note")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .lineLimit(2)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(10)
        .frame(width: 120, height: 120)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var recentRecordingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Recent")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            recentRecordingsScroll
                .padding(.horizontal, -16)
        }
        .animation(.easeInOut(duration: 0.3), value: recordingManager.recentRecordings)
    }

    @ViewBuilder
    private var recordingInterface: some View {
        VStack(spacing: 16) {
            if recordingManager.recordingState == .recording && recordingManager.isUsingLiveTranscription {
                liveTranscriptionInterface
            } else {
                standardRecordingInterface
            }
        }
    }

    @ViewBuilder
    private var standardRecordingInterface: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                if recordingManager.recordingState == .recording {
                    RecordingDisplay(
                        duration: recordingManager.currentDuration,
                        isRecording: true
                    )
                }
            }
            .frame(height: 40)

            VStack {
                // Show device indicator when recording OR when external device connected in idle
                if recordingManager.recordingState == .recording || recordingManager.isExternalInputConnected {
                    HStack(spacing: 4) {
                        Image(systemName: microphoneIcon(for: recordingManager.currentInputDevice))
                            .font(.system(size: 10))
                        Text(recordingManager.currentInputDevice)
                            .font(.system(.caption2, design: .rounded))
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .frame(height: 16)
            .animation(.easeInOut(duration: 0.25), value: recordingManager.recordingState)
            .animation(.easeInOut(duration: 0.25), value: recordingManager.currentInputDevice)
            .animation(.easeInOut(duration: 0.25), value: recordingManager.isExternalInputConnected)

            HStack(alignment: .center, spacing: 24) {
                AudioLevelVisualizer(
                    audioLevel: recordingManager.currentAudioLevel,
                    isRecording: recordingManager.recordingState == .recording,
                    isVoiceDetected: recordingManager.isVoiceDetected
                )

                RecordButton(
                    state: recordingManager.recordingState,
                    action: {
                        Task {
                            await recordingManager.toggleRecording()
                        }
                    }
                )

                AudioLevelVisualizer(
                    audioLevel: recordingManager.currentAudioLevel,
                    isRecording: recordingManager.recordingState == .recording,
                    isVoiceDetected: recordingManager.isVoiceDetected
                )
            }

            VStack {
                if !recordingManager.statusText.isEmpty {
                    Text(recordingManager.statusText)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 20)
        }
    }

    @ViewBuilder
    private var liveTranscriptionInterface: some View {
        VStack(alignment: .center, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.xs) {
                Image(systemName: microphoneIcon(for: recordingManager.currentInputDevice))
                    .font(.system(size: 10))
                Text(recordingManager.currentInputDevice)
                    .font(.system(.caption2, design: .rounded))
            }
            .foregroundColor(.secondary.opacity(0.8))

            LiveTranscriptView(
                transcript: recordingManager.liveTranscriptionService.displayText,
                isRecording: true,
                duration: recordingManager.currentDuration
            )
            .frame(maxHeight: 280)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .opacity
            ))

            LiveRecordingControlsView(
                audioLevel: recordingManager.currentAudioLevel,
                onStop: {
                    Task {
                        await recordingManager.toggleRecording()
                    }
                }
            )
            .frame(height: 140)
        }
        .animation(.easeInOut(duration: 0.3), value: recordingManager.isUsingLiveTranscription)
    }

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                    .padding(.bottom, Spacing.md)

                recordingInterface
                    .frame(minHeight: 300)
                    .frame(maxHeight: .infinity)

                recentRecordingsSection
                    .padding(.top, Spacing.md)
                    .frame(maxHeight: 180)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $coordinator.activeSheet) { sheet in
            switch sheet {
            case .library:
                // Library is now a tab, but keep for backwards compatibility
                LibraryView(recordingManager: recordingManager)
            case .settings:
                SettingsView()
            case .templatePicker(let recording):
                TemplatePickerView(recording: recording) { template in
                    if let recording = recording {
                        Task {
                            try await recordingManager.processTemplate(template, for: recording)
                        }
                    }
                }
            case .recordingDetail(let recording):
                RecordingDetailView(recording: recording)
            }
        }
        .alert("Permission Required", isPresented: $coordinator.showPermissionAlert) {
            Button("Settings") {
                coordinator.openSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Voice Note needs microphone access to record audio. Please enable it in Settings.")
        }
        .alert("Transcription Failed", isPresented: $recordingManager.showFailedTranscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(recordingManager.failedTranscriptionMessage)
        }
        .onAppear {
            // Update device indicator for pre-record screen
            recordingManager.updateCurrentAudioDevice()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Refresh when app becomes active (user may have connected/disconnected headphones)
            recordingManager.updateCurrentAudioDevice()
        }
        .onChange(of: recordingManager.lastRecordingId) { oldValue, newValue in
            if let recordingId = newValue,
               let templateId = pendingTemplateId,
               let recording = recordingManager.recentRecordings.first(where: { $0.id == recordingId }) {
                pendingTemplateId = nil

                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    let descriptor = FetchDescriptor<Template>(
                        predicate: #Predicate { template in
                            template.id.uuidString == templateId
                        }
                    )

                    if let templates = try? modelContext.fetch(descriptor),
                       let template = templates.first {
                        try? await recordingManager.processTemplate(template, for: recording)
                        coordinator.showRecordingDetail(recording)
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func microphoneIcon(for device: String) -> String {
        if device.contains("AirPods") || device.contains("Bluetooth") {
            return "airpodspro"
        } else if device.contains("Headset") || device.contains("Wired") {
            return "headphones"
        } else if device.contains("Car") {
            return "car.fill"
        } else if device.contains("USB") || device.contains("External") {
            return "mic.fill"
        } else {
            return "mic"
        }
    }
}

#Preview {
    RecordingView(recordingManager: RecordingManager())
        .environment(AppCoordinator())
}
