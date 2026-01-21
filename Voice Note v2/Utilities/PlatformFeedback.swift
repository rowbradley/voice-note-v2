//
//  PlatformFeedback.swift
//  Voice Note
//
//  Platform-agnostic haptic feedback abstraction.
//  iOS: UIImpactFeedbackGenerator
//  macOS: NSHapticFeedbackManager
//

import Foundation

#if canImport(UIKit)
import UIKit

/// Haptic feedback provider for iOS
@MainActor
final class PlatformFeedback {
    static let shared = PlatformFeedback()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        // Pre-warm generators for responsive feedback
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }

    /// Light tap feedback (e.g., button press)
    func lightTap() {
        lightGenerator.impactOccurred()
    }

    /// Medium tap feedback (e.g., toggle switch)
    func mediumTap() {
        mediumGenerator.impactOccurred()
    }

    /// Heavy tap feedback (e.g., drag completion)
    func heavyTap() {
        heavyGenerator.impactOccurred()
    }

    /// Selection changed feedback
    func selectionChanged() {
        selectionGenerator.selectionChanged()
    }

    /// Success notification feedback
    func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    /// Warning notification feedback
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Error notification feedback
    func error() {
        notificationGenerator.notificationOccurred(.error)
    }
}

#elseif canImport(AppKit)
import AppKit

/// Haptic feedback provider for macOS
@MainActor
final class PlatformFeedback {
    static let shared = PlatformFeedback()

    private init() {}

    /// Light tap feedback
    func lightTap() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }

    /// Medium tap feedback
    func mediumTap() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }

    /// Heavy tap feedback
    func heavyTap() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }

    /// Selection changed feedback
    func selectionChanged() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }

    /// Success notification feedback
    func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }

    /// Warning notification feedback
    func warning() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }

    /// Error notification feedback
    func error() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }
}

#endif
