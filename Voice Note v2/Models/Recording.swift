import Foundation
import SwiftData
import os.log

// MARK: - AttributedString Helper

extension AttributedString {
    private static let logger = Logger(subsystem: "com.voicenote", category: "AttributedString")

    /// Initializes an AttributedString from text, parsing as markdown if possible.
    /// Parses each paragraph separately to preserve paragraph breaks.
    init(markdownOrPlain text: String) {
        let paragraphs = text.components(separatedBy: "\n\n")
        let inputBreaks = paragraphs.count - 1
        Self.logger.debug("markdownOrPlain input: \(text.count) chars, \(inputBreaks) paragraph breaks")

        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)

        var result = AttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let parsed = try? AttributedString(markdown: trimmed, options: options) {
                result.append(parsed)
            } else {
                result.append(AttributedString(trimmed))
            }

            // Add paragraph break between paragraphs (not after the last one)
            if index < paragraphs.count - 1 {
                result.append(AttributedString("\n\n"))
            }
        }

        self = result

        let outputChars = String(self.characters)
        let outputBreaks = outputChars.components(separatedBy: "\n\n").count - 1
        Self.logger.debug("markdownOrPlain output: \(outputChars.count) chars, \(outputBreaks) paragraph breaks")
    }
}

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String

    @Relationship(deleteRule: .cascade)
    var transcript: Transcript?

    @Relationship(deleteRule: .cascade)
    var processedNotes: [ProcessedNote] = []

    // MARK: - Cached Static Resources (performance optimization)

    /// Cached documents directory - avoids FileManager.default.urls() on every audioFileURL access
    private static let documentsDirectory: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

    /// Cached date formatter for title generation - Date.formatted() creates new formatter each call
    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var title: String {
        // Use AI-generated title if available, otherwise use cached formatter for date
        transcript?.aiTitle ?? "Recording \(Self.titleDateFormatter.string(from: createdAt))"
    }

    var audioFileURL: URL? {
        Self.documentsDirectory?.appendingPathComponent(audioFileName)
    }

    init(id: UUID = UUID(), audioFileName: String, duration: TimeInterval) {
        self.id = id
        self.createdAt = Date()
        self.audioFileName = audioFileName
        self.duration = duration
    }
}

// MARK: - Transcript Model
/// Stores transcript text using native SwiftData AttributedString support (iOS 26+).
/// No manual JSON encoding needed - SwiftData handles persistence directly.

@Model
final class Transcript {
    @Attribute(.unique) var id: UUID
    var rawText: AttributedString           // Direct native storage
    var cleanedText: AttributedString?      // Pro feature - nil for free users
    var aiTitle: String?
    var aiSummary: String?
    var createdAt: Date
    var language: String

    @Relationship(inverse: \Recording.transcript)
    var recording: Recording?

    // MARK: - Computed Properties

    /// Display text - cleaned if available, otherwise raw
    var displayText: AttributedString {
        cleanedText ?? rawText
    }

    /// Plain text string (for AI services, sharing, etc.)
    var plainText: String {
        String(displayText.characters)
    }

    // MARK: - Initialization

    init(id: UUID = UUID(), text: String, language: String = "en-US") {
        self.id = id
        self.rawText = AttributedString(markdownOrPlain: text)
        self.cleanedText = nil
        self.language = language
        self.createdAt = Date()
    }
}

// MARK: - ProcessedNote Model
/// Stores processed note content using native SwiftData AttributedString support (iOS 26+).
/// No manual JSON encoding needed - SwiftData handles persistence directly.

@Model
final class ProcessedNote {
    @Attribute(.unique) var id: UUID
    var templateId: UUID
    var templateName: String
    var content: AttributedString           // Direct native storage
    var createdAt: Date
    var processingTime: TimeInterval
    var tokenUsage: Int?

    @Relationship(inverse: \Recording.processedNotes)
    var recording: Recording?

    /// Plain text string (for sharing, export, etc.)
    var plainText: String {
        String(content.characters)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        templateId: UUID,
        templateName: String,
        processedText: String,
        processingTime: TimeInterval,
        tokenUsage: Int? = nil
    ) {
        self.id = id
        self.templateId = templateId
        self.templateName = templateName
        self.content = AttributedString(markdownOrPlain: processedText)
        self.processingTime = processingTime
        self.tokenUsage = tokenUsage
        self.createdAt = Date()
    }
}
