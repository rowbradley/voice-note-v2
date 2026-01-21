import Foundation

/// Recording state enum shared across iOS and macOS
/// Originally in RecordButton.swift, extracted for cross-platform use
enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case processing
}
