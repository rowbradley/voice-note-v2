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

// MARK: - Device Origin Tracking

/// Identifies which platform created a recording for iCloud sync.
/// Default `.iOS` ensures existing recordings get correct origin.
enum SourceDevice: String, Codable {
    case iOS
    case macOS

    /// The platform currently running the app
    static var current: SourceDevice {
        #if os(macOS)
        .macOS
        #else
        .iOS
        #endif
    }

    /// SF Symbol name for this device type
    var iconName: String {
        switch self {
        case .iOS: return "iphone"
        case .macOS: return "desktopcomputer"
        }
    }
}

@Model
final class Recording {
    var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var audioFileName: String

    // Device origin tracking for iCloud sync
    // Default SourceDevice.iOS for migration compatibility (existing records are from iOS)
    var sourceDevice: SourceDevice = SourceDevice.iOS
    var isAudioSynced: Bool = false

    // Quick capture & archiving (macOS floating panel)
    // Auto-set to true after copying from floating panel; filtered from "All Notes" view
    var isArchived: Bool = false

    // Retention support (v1 schema, v2 enforcement)
    // nil = never expires; date set by retention policy when implemented
    var expiresAt: Date?
    // User can pin to prevent expiration regardless of retention policy
    var isPinned: Bool = false

    // Session grouping (v1 schema)
    @Relationship var session: Session?

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
        self.sourceDevice = .current  // Platform detected at runtime
        // Note: isAudioSynced uses property default (= false), no init assignment needed
    }
}

// MARK: - Transcript Model
/// Stores transcript text using native SwiftData AttributedString support (iOS 26+).
/// No manual JSON encoding needed - SwiftData handles persistence directly.

@Model
final class Transcript {
    var id: UUID

    // User-generated content encrypted in CloudKit for privacy
    @Attribute(.allowsCloudEncryption)
    var rawText: AttributedString           // Direct native storage

    @Attribute(.allowsCloudEncryption)
    var cleanedText: AttributedString?      // Pro feature - nil for free users

    var aiTitle: String?

    @Attribute(.allowsCloudEncryption)
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
    var id: UUID
    var templateId: UUID
    var templateName: String

    // User-generated content encrypted in CloudKit for privacy
    @Attribute(.allowsCloudEncryption)
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
