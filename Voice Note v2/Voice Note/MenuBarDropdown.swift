//
//  MenuBarDropdown.swift
//  Voice Note (macOS)
//
//  Menu bar content using .menu style (NSMenu-based) to avoid SwiftUI constraint bugs.
//

import SwiftUI

/// Menu content for MenuBarExtra with .menu style
@MainActor
struct MenuBarMenuContent: View {
    let recordingManager: RecordingManager

    @Environment(\.openWindow) private var openWindow
    @Environment(AppSettings.self) private var appSettings

    private var isRecording: Bool {
        recordingManager.recordingState == .recording
    }

    var body: some View {
        Button(action: toggleRecording) {
            if isRecording {
                Label("Stop Recording", systemImage: "stop.circle.fill")
            } else {
                Label("Start Recording", systemImage: "record.circle")
            }
        }
        .keyboardShortcut("r", modifiers: .command)

        Divider()

        Button("Open Library...") {
            WindowManager.openOrSurface(id: WindowManager.ID.library, using: openWindow)
        }
        .keyboardShortcut("l", modifiers: .command)

        Button("Toggle Floating Panel") {
            WindowManager.toggle(id: WindowManager.ID.floatingPanel, using: openWindow)
        }

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

    private func toggleRecording() {
        Task {
            await recordingManager.toggleRecording()
            // Check state AFTER toggle completes to avoid race condition
            if recordingManager.recordingState == .recording {
                openWindow(id: "floating-panel")
            }
        }
    }

}
