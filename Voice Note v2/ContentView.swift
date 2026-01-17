//
//  ContentView.swift
//  Voice Note v2
//
//  Legacy entry point - now forwards to MainTabView.
//  Kept for backwards compatibility with any existing references.
//
//  Design tokens and utilities moved to DesignTokens.swift
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environment(AppCoordinator())
}
