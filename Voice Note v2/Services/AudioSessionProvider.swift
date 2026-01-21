//
//  AudioSessionProvider.swift
//  Voice Note
//
//  Protocol-based abstraction for platform-specific audio session management.
//  iOS uses AVAudioSession, macOS uses AVAudioEngine directly.
//

import AVFoundation
import Foundation

/// Platform-agnostic audio session provider protocol.
/// iOS implementation wraps AVAudioSession; macOS implementation uses CoreAudio.
protocol AudioSessionProvider: Sendable {
    /// Configure the audio session for recording
    func configure() async throws

    /// Activate the audio session
    func activate() async throws

    /// Deactivate the audio session
    func deactivate() throws

    /// Current audio input device name
    var currentInputDevice: String { get async }

    /// Whether external input is connected (Bluetooth, USB, etc.)
    var isExternalInputConnected: Bool { get async }

    /// Start observing route/device changes
    /// - Parameter handler: Called when audio route changes (e.g., headphones connected)
    func observeRouteChanges(_ handler: @escaping @Sendable () -> Void)

    /// Stop observing route changes
    func stopObservingRouteChanges()

    /// Start observing audio interruptions (phone calls, Siri, etc.)
    /// - Parameters:
    ///   - began: Called when interruption begins
    ///   - ended: Called when interruption ends, with shouldResume flag
    func observeInterruptions(
        began: @escaping @Sendable () -> Void,
        ended: @escaping @Sendable (Bool) -> Void
    )

    /// Stop observing interruptions
    func stopObservingInterruptions()
}

/// Errors specific to audio session management
enum AudioSessionError: LocalizedError {
    case configurationFailed(String)
    case activationFailed(String)
    case deviceNotAvailable

    var errorDescription: String? {
        switch self {
        case .configurationFailed(let reason):
            return "Audio session configuration failed: \(reason)"
        case .activationFailed(let reason):
            return "Audio session activation failed: \(reason)"
        case .deviceNotAvailable:
            return "No audio input device available"
        }
    }
}
