//
//  TextNormalizer.swift
//  Voice Note v2
//
//  Pure functions for normalizing transcribed text.
//  Extracted for testability and reuse.
//

import Foundation

enum TextNormalizer {
    /// Normalizes whitespace in transcribed text.
    /// - Collapses multiple spaces, tabs, newlines → single space
    /// - Trims leading and trailing whitespace
    /// - Parameter text: Raw text to normalize
    /// - Returns: Normalized text with clean whitespace
    static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds final transcript from raw transcribed text.
    /// Applies whitespace normalization and returns empty string for empty/whitespace-only input.
    /// - Parameter text: Raw finalized text from transcription
    /// - Returns: Cleaned transcript ready for display/storage
    static func buildFinalTranscript(from text: String) -> String {
        normalizeWhitespace(text)
    }
}
