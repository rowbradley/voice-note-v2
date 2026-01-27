import Foundation
import SwiftData

/// Groups recordings into natural work periods (calendar-day based).
/// v1: Schema and auto-assignment only
/// v2: AI compaction, retention service, manual "End Session" button
@Model
final class Session {
    var id: UUID = UUID()

    /// When this session started (midnight of the calendar day)
    var startedAt: Date

    /// When this session ended (set when next day's session is created, or nil if today)
    var endedAt: Date?

    /// AI-generated summary of the session (v2 feature)
    @Attribute(.allowsCloudEncryption)
    var summary: String?

    /// When the compaction/summary was generated (v2 feature)
    var summaryGeneratedAt: Date?

    /// Recordings in this session
    @Relationship(deleteRule: .nullify, inverse: \Recording.session)
    var recordings: [Recording] = []

    // MARK: - Computed Properties

    /// Whether this session is still active (today's session)
    var isActive: Bool { endedAt == nil }

    /// Number of recordings in this session
    var recordingCount: Int { recordings.count }

    /// Total duration of all recordings in this session
    var totalDuration: TimeInterval {
        recordings.reduce(0) { $0 + $1.duration }
    }

    /// Formatted date for display.
    /// Auto-created sessions (midnight): "January 26, 2026"
    /// Manually created sessions: "January 26, 2026 at 2:30 PM"
    var displayDate: String {
        let calendar = Calendar.current
        let isStartOfDay = calendar.startOfDay(for: startedAt) == startedAt

        if isStartOfDay {
            return startedAt.formatted(date: .long, time: .omitted)
        } else {
            return startedAt.formatted(date: .long, time: .shortened)
        }
    }

    /// Combined transcript from all recordings, chronologically ordered.
    /// Empty recordings/transcripts are filtered out.
    var combinedTranscript: String {
        recordings
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { $0.transcript?.plainText }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n---\n\n")
    }

    /// Formatted total duration for display (e.g., "23:45")
    var formattedDuration: String {
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Initialization

    /// Creates a new session for the given date.
    /// - Parameters:
    ///   - date: The date for this session
    ///   - useExactTime: If true, uses exact timestamp. If false (default), uses midnight.
    init(date: Date = Date(), useExactTime: Bool = false) {
        self.startedAt = useExactTime ? date : Calendar.current.startOfDay(for: date)
    }
}
