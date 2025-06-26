import Foundation
import SwiftData

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
    
    var title: String {
        // Use AI-generated title if available, otherwise use date
        transcript?.aiTitle ?? "Recording \(createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
    
    var audioFileURL: URL? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent(audioFileName)
    }
    
    init(id: UUID = UUID(), audioFileName: String, duration: TimeInterval) {
        self.id = id
        self.createdAt = Date()
        self.audioFileName = audioFileName
        self.duration = duration
    }
}

@Model
final class Transcript {
    @Attribute(.unique) var id: UUID
    var text: String
    var aiTitle: String?
    var aiSummary: String?
    var createdAt: Date
    var language: String
    
    @Relationship(inverse: \Recording.transcript)
    var recording: Recording?
    
    init(text: String, language: String = "en-US") {
        self.id = UUID()
        self.text = text
        self.language = language
        self.createdAt = Date()
    }
}

@Model
final class ProcessedNote {
    @Attribute(.unique) var id: UUID
    var templateId: UUID
    var templateName: String
    var processedText: String
    var createdAt: Date
    var processingTime: TimeInterval
    var tokenUsage: Int?
    
    @Relationship(inverse: \Recording.processedNotes)
    var recording: Recording?
    
    init(
        templateId: UUID,
        templateName: String,
        processedText: String,
        processingTime: TimeInterval,
        tokenUsage: Int? = nil
    ) {
        self.id = UUID()
        self.templateId = templateId
        self.templateName = templateName
        self.processedText = processedText
        self.processingTime = processingTime
        self.tokenUsage = tokenUsage
        self.createdAt = Date()
    }
}

// MARK: - Schema Versioning
enum RecordingSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Recording.self, Transcript.self, ProcessedNote.self]
    }
}