//
//  PlatformPasteboard.swift
//  Voice Note
//
//  Platform-agnostic pasteboard/clipboard abstraction.
//  iOS: UIPasteboard
//  macOS: NSPasteboard
//

import Foundation

#if canImport(UIKit)
import UIKit

/// Clipboard access for iOS
@MainActor
final class PlatformPasteboard {
    static let shared = PlatformPasteboard()

    private init() {}

    /// Copy text to clipboard
    func copyText(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// Get text from clipboard
    func getText() -> String? {
        UIPasteboard.general.string
    }

    /// Check if clipboard has text
    var hasText: Bool {
        UIPasteboard.general.hasStrings
    }

    /// Copy URL to clipboard
    func copyURL(_ url: URL) {
        UIPasteboard.general.url = url
    }

    /// Get URL from clipboard
    func getURL() -> URL? {
        UIPasteboard.general.url
    }
}

#elseif canImport(AppKit)
import AppKit

/// Clipboard access for macOS
@MainActor
final class PlatformPasteboard {
    static let shared = PlatformPasteboard()

    private init() {}

    /// Copy text to clipboard
    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Get text from clipboard
    func getText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Check if clipboard has text
    var hasText: Bool {
        NSPasteboard.general.string(forType: .string) != nil
    }

    /// Copy URL to clipboard
    func copyURL(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        pasteboard.writeObjects([url as NSURL])
    }

    /// Get URL from clipboard
    func getURL() -> URL? {
        if let urlString = NSPasteboard.general.string(forType: .string),
           let url = URL(string: urlString) {
            return url
        }
        return NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL
    }
}

#endif
