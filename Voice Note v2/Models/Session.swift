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

    // MARK: - Initialization

    /// Creates a new session for the given date (uses midnight of that day)
    init(date: Date = Date()) {
        self.startedAt = Calendar.current.startOfDay(for: date)
    }
}
