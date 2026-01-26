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
            Button {
                Task {
                    await recordingManager.toggleRecording()
                }
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
            }
            .keyboardShortcut("r", modifiers: .command)
        } else {
            Button {
                Task {
                    await recordingManager.toggleRecording()
                    openWindow(id: WindowManager.ID.floatingPanel)
                }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
            .keyboardShortcut("r", modifiers: .command)
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
        .keyboardShortcut("l", modifiers: .command)

        Divider()

        Toggle("Keep on Top", isOn: Bindable(appSettings).floatingPanelStayOnTop)

        Divider()

        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Voice Note") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
