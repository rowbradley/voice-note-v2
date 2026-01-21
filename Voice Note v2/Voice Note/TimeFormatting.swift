//
//  TimeFormatting.swift
//  Voice Note
//
//  Shared time formatting utilities.
//

import Foundation

enum TimeFormatting {
    /// Formats duration as "M:SS" (e.g., "1:05", "12:30")
    static func shortDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formats duration as "MM:SS" with zero-padded minutes (e.g., "01:05", "12:30")
    static func paddedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
