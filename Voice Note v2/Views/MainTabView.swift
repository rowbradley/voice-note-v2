//
//  MainTabView.swift
//  Voice Note v2
//
//  Root tab view using iOS 26 Liquid Glass styling.
//  Automatically adopts glass tab bar appearance.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var recordingManager = RecordingManager()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Record", systemImage: "mic.fill", value: 0) {
                RecordingView(recordingManager: recordingManager)
            }

            Tab("Library", systemImage: "folder.fill", value: 1) {
                LibraryView(recordingManager: recordingManager, showsDismissButton: false)
            }

            Tab("Tools", systemImage: "wrench.and.screwdriver.fill", value: 2) {
                ToolsView()
            }
        }
        .onAppear {
            recordingManager.configure(with: modelContext)
            recordingManager.prewarmTranscription()
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppCoordinator())
}
