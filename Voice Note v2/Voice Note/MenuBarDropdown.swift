//
//  MenuBarDropdown.swift
//  Voice Note (macOS)
//
//  Menu bar content using .menu style (NSMenu-based).
//  Simplified: single floating panel mode, no Quick Capture.
//

import SwiftUI

/// Menu content for MenuBarExtra with .menu style.
@MainActor
struct MenuBarMenuContent: View {
    let recordingManager: RecordingManager

    @Environment(\.openWindow) private var openWindow
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        // Start Recording / Stop Recording
        if recordingManager.isRecording {
            Button("Stop Recording") {
                Task {
                    await recordingManager.toggleRecording()
                }
            }
        } else {
            Button("Start Recording") {
                Task {
                    await recordingManager.toggleRecording()
                    openWindow(id: WindowManager.ID.floatingPanel)
                }
            }
        }

        // Show Panel (when not recording)
        if !recordingManager.isRecording {
            Button("Show Panel") {
                openWindow(id: WindowManager.ID.floatingPanel)
            }
        }

        Divider()

        Button("Open Library...") {
            WindowManager.openOrSurface(id: WindowManager.ID.library, using: openWindow)
        }

        Button("New Session") {
            recordingManager.startNewSession()
        }
        .disabled(recordingManager.isRecording)

        Divider()

        Toggle("Keep on Top", isOn: Bindable(appSettings).floatingPanelStayOnTop)

        Divider()

        SettingsLink {
            Text("Settings...")
        }

        Divider()

        Button("Quit Voice Note") {
            NSApplication.shared.terminate(nil)
        }
    }
}
