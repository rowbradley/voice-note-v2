//
//  MenuBarDropdown.swift
//  Voice Note (macOS)
//
//  Menu bar content using .menu style (NSMenu-based) to avoid SwiftUI constraint bugs.
//  Supports two interaction modes: Quick Capture and Floating Window.
//

import SwiftUI

/// Menu content for MenuBarExtra with .menu style.
/// Adapts based on the selected interaction mode.
@MainActor
struct MenuBarMenuContent: View {
    let recordingManager: RecordingManager

    @Environment(\.openWindow) private var openWindow
    @Environment(AppSettings.self) private var appSettings

    /// Whether currently recording or paused (active recording session)
    private var isRecording: Bool {
        recordingManager.isRecordingOrPaused
    }

    var body: some View {
        // Primary action (mode-dependent)
        primaryAction

        Divider()

        // Mode selection submenu
        modeSelectionMenu

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

    // MARK: - Primary Action (Mode-Dependent)

    @ViewBuilder
    private var primaryAction: some View {
        switch appSettings.interactionMode {
        case .quickCapture:
            quickCaptureAction
        case .floatingWindow:
            floatingWindowAction
        }
    }

    /// Quick Capture mode: Start/Stop recording with live preview panel.
    /// Auto-copies transcript to clipboard on stop.
    @ViewBuilder
    private var quickCaptureAction: some View {
        if isRecording {
            Button {
                Task {
                    _ = await recordingManager.stopRecordingAndCopyToClipboard()
                }
            } label: {
                Label("Stop & Copy", systemImage: "stop.circle.fill")
            }
            .keyboardShortcut("r", modifiers: .command)
        } else {
            Button {
                Task {
                    await recordingManager.toggleRecording()
                    // Open Quick Capture panel when starting recording
                    openWindow(id: "quick-capture-panel")
                }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    /// Floating Window mode: Start recording and open floating panel.
    @ViewBuilder
    private var floatingWindowAction: some View {
        Button(action: toggleRecordingWithPanel) {
            if isRecording {
                Label("Stop Recording", systemImage: "stop.circle.fill")
            } else {
                Label("Start Recording", systemImage: "record.circle")
            }
        }
        .keyboardShortcut("r", modifiers: .command)
    }

    // MARK: - Mode Selection

    private var modeSelectionMenu: some View {
        Menu {
            ForEach(MenuBarInteractionMode.allCases, id: \.self) { mode in
                Button {
                    appSettings.interactionMode = mode
                } label: {
                    HStack {
                        Text(mode.displayName)
                        if mode == appSettings.interactionMode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(
                "Mode: \(appSettings.interactionMode.displayName)",
                systemImage: appSettings.interactionMode.icon
            )
        }
    }

    // MARK: - Actions

    /// Toggles recording and opens floating panel when starting (Floating Window mode).
    private func toggleRecordingWithPanel() {
        Task {
            await recordingManager.toggleRecording()
            // Open panel when STARTING recording in floating window mode
            if recordingManager.recordingState == .recording {
                openWindow(id: "floating-panel")
            }
        }
    }
}
