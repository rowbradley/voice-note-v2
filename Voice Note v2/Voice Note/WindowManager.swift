//
//  WindowManager.swift
//  Voice Note (macOS)
//
//  Centralized window management utilities for macOS.
//  Eliminates duplicate NSWindow lookup code across views.
//

import SwiftUI

/// Centralized window management for macOS.
/// All methods are @MainActor since they interact with NSApp.windows.
@MainActor
enum WindowManager {

    // MARK: - Window Operations

    /// Surfaces an existing window or opens a new one.
    /// - Parameters:
    ///   - id: Window identifier (matches WindowGroup id)
    ///   - openWindow: SwiftUI openWindow action for creating new windows
    static func openOrSurface(id: String, using openWindow: OpenWindowAction) {
        if let window = window(id: id), window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            openWindow(id: id)
        }
    }

    /// Toggles window visibility (show/hide).
    /// Uses orderOut for hiding (faster than close, preserves state).
    /// - Parameters:
    ///   - id: Window identifier
    ///   - openWindow: SwiftUI openWindow action for creating new windows
    static func toggle(id: String, using openWindow: OpenWindowAction) {
        if let window = window(id: id) {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        } else {
            openWindow(id: id)
        }
    }

    /// Updates window level (floating vs normal).
    /// - Parameters:
    ///   - id: Window identifier
    ///   - floating: Whether window should float above others
    static func setFloating(_ floating: Bool, for id: String) {
        guard let window = window(id: id) else { return }
        window.level = floating ? .floating : .normal
        if floating {
            window.orderFront(nil)
        }
    }

    /// Sets window identifier by matching title.
    /// Call from onAppear to establish identifier for reliable lookup.
    /// - Parameters:
    ///   - id: Identifier to assign
    ///   - title: Window title to match
    static func setIdentifier(_ id: String, forWindowWithTitle title: String) {
        if let window = NSApp.windows.first(where: { $0.title == title }) {
            window.identifier = NSUserInterfaceItemIdentifier(id)
        }
    }

    // MARK: - Private

    /// Finds window by identifier.
    private static func window(id: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == id }
    }
}

// MARK: - Window Identifiers

extension WindowManager {
    /// Known window identifiers for type-safe access.
    enum ID {
        static let floatingPanel = "floating-panel"
        static let library = "library"
    }
}
