import Foundation
import SwiftData
import os.log

// MARK: - Schema V1
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Recording.self, Transcript.self, ProcessedNote.self, Template.self]
    }
    
    @Model
    class Recording {
        @Attribute(.unique) var id: UUID
        var audioFileName: String
        var duration: TimeInterval
        var createdAt: Date
        
        @Relationship(deleteRule: .cascade, inverse: \Transcript.recording)
        var transcript: Transcript?
        
        @Relationship(deleteRule: .cascade, inverse: \ProcessedNote.recording)
        var processedNotes: [ProcessedNote] = []
        
        var audioFileURL: URL? {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documentsPath.appendingPathComponent("Recordings").appendingPathComponent(audioFileName)
        }
        
        var title: String {
            transcript?.aiTitle ?? "Recording \(formattedDate)"
        }
        
        private var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: createdAt)
        }
        
        init(id: UUID = UUID(), audioFileName: String, duration: TimeInterval, createdAt: Date = Date()) {
            self.id = id
            self.audioFileName = audioFileName
            self.duration = duration
            self.createdAt = createdAt
        }
    }
    
    @Model
    class Transcript {
        @Attribute(.unique) var id: UUID
        var text: String
        var aiTitle: String?
        var createdAt: Date
        var language: String?
        
        var recording: Recording?
        
        init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
            self.id = id
            self.text = text
            self.createdAt = createdAt
        }
    }
    
    @Model
    class ProcessedNote {
        @Attribute(.unique) var id: UUID
        var templateId: UUID
        var templateName: String
        var processedText: String
        var createdAt: Date
        var processingTime: TimeInterval
        var tokenUsage: Int?
        
        var recording: Recording?
        
        init(id: UUID = UUID(), templateId: UUID, templateName: String, processedText: String, createdAt: Date = Date(), processingTime: TimeInterval, tokenUsage: Int? = nil) {
            self.id = id
            self.templateId = templateId
            self.templateName = templateName
            self.processedText = processedText
            self.createdAt = createdAt
            self.processingTime = processingTime
            self.tokenUsage = tokenUsage
        }
    }
    
    @Model
    class Template {
        @Attribute(.unique) var id: UUID
        var name: String
        var templateDescription: String
        var prompt: String
        var category: String
        var exampleOutput: String
        var isCustom: Bool
        var usageCount: Int
        var lastUsedAt: Date?
        var createdAt: Date
        
        init(id: UUID = UUID(), name: String, description: String, prompt: String, category: String = "Custom", exampleOutput: String = "", isCustom: Bool = true, createdAt: Date = Date()) {
            self.id = id
            self.name = name
            self.templateDescription = description
            self.prompt = prompt
            self.category = category
            self.exampleOutput = exampleOutput
            self.isCustom = isCustom
            self.usageCount = 0
            self.createdAt = createdAt
        }
    }
}

// MARK: - Schema V2
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Recording.self, Transcript.self, ProcessedNote.self, Template.self]
    }
    
    // Recording, Transcript, and ProcessedNote remain unchanged from V1
    typealias Recording = SchemaV1.Recording
    typealias Transcript = SchemaV1.Transcript
    typealias ProcessedNote = SchemaV1.ProcessedNote
    
    @Model
    class Template {
        @Attribute(.unique) var id: UUID
        var name: String
        var templateDescription: String
        var prompt: String
        var category: String
        var exampleOutput: String
        var isCustom: Bool
        var usageCount: Int
        var lastUsedAt: Date?
        var createdAt: Date
        var isFavorite: Bool = false  // NEW with default value!
        
        init(id: UUID = UUID(), name: String, description: String, prompt: String, category: String = "Custom", exampleOutput: String = "", isCustom: Bool = true, isFavorite: Bool = false, createdAt: Date = Date()) {
            self.id = id
            self.name = name
            self.templateDescription = description
            self.prompt = prompt
            self.category = category
            self.exampleOutput = exampleOutput
            self.isCustom = isCustom
            self.usageCount = 0
            self.createdAt = createdAt
            self.isFavorite = isFavorite
        }
    }
}

// MARK: - Migration Plan
struct V1toV2MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [
        SchemaV1.self,
        SchemaV2.self
    ]
    
    static var stages: [MigrationStage] = [
        migrateV1toV2
    ]
    
    // Lightweight migration - SwiftData will automatically populate isFavorite with false
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}

// MARK: - Store Resetter
enum StoreResetter {
    static func nuke() throws {
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceNote.store")
        
        // Remove all SQLite files (main, WAL, SHM)
        for ext in ["", "-wal", "-shm"] {
            let url = ext.isEmpty ? storeURL : storeURL.appendingPathExtension(String(ext.dropFirst()))
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                Logger(subsystem: "com.voicenote", category: "StoreResetter").info("Deleted: \(url.lastPathComponent)")
            }
        }
        
        Logger(subsystem: "com.voicenote", category: "StoreResetter").info("Store reset complete")
    }
}