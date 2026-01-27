//
//  MacSettingsView.swift
//  Voice Note (macOS)
//
//  Settings window for macOS preferences.
//

import SwiftUI

struct MacSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var appSettings

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("defaultTemplate") private var defaultTemplate = ""
    @AppStorage("autoStartRecording") private var autoStartRecording = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            recordingTab
                .tabItem {
                    Label("Recording", systemImage: "waveform")
                }

            storageTab
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }

            privacyTab
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .frame(width: 450, height: 350)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .help("Start Voice Note when you log in")

                Toggle("Show Panel on Launch", isOn: Bindable(appSettings).showPanelOnLaunch)
                    .help("Show the floating panel when Voice Note starts")

                Toggle("Show in Dock", isOn: $showInDock)
                    .help("Show Voice Note icon in the Dock (requires restart)")
            } header: {
                Text("Startup")
            }

            Section {
                Text("Version: 1.0.0")
                    .foregroundColor(.secondary)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Recording Tab

    private var recordingTab: some View {
        Form {
            Section {
                Toggle("Auto-start recording on launch", isOn: $autoStartRecording)
                    .help("Begin recording immediately when Voice Note starts")
            } header: {
                Text("Behavior")
            }

            Section {
                Picker("Default Template", selection: $defaultTemplate) {
                    Text("None").tag("")
                    Text("Cleanup").tag("cleanup")
                    Text("Smart Summary").tag("summary")
                    Text("Action Items").tag("actions")
                }
                .help("Automatically process recordings with this template")
            } header: {
                Text("Processing")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Storage Tab

    private var storageTab: some View {
        @Bindable var settings = appSettings

        return Form {
            Section {
                Picker("Keep recordings for", selection: $settings.retentionPolicy) {
                    ForEach(RetentionPolicy.pickerOptions, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .help("Recordings older than this will be automatically deleted")

                Text("Pinned recordings are never deleted, regardless of retention policy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Data Retention")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Retention enforcement coming soon")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Your retention preference is saved and will be applied when automatic cleanup is implemented in a future update.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Note")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Privacy Tab

    private var privacyTab: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Microphone Access")
                            .font(.body)
                        Text("Required for recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Open System Settings") {
                        coordinator.openSettings()
                    }
                }
            } header: {
                Text("Permissions")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech Recognition")
                            .font(.body)
                        Text("Required for live transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Data")
                        .font(.headline)

                    Text("All audio and transcriptions are stored locally and in your iCloud account. Voice Note does not send your data to external servers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    MacSettingsView()
        .frame(width: 450, height: 300)
}
