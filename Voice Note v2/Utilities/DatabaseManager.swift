import Foundation
import SwiftData
import os.log
import CoreData

@MainActor
class DatabaseManager {
    static let shared = DatabaseManager()
    private let logger = Logger(subsystem: "com.voicenote", category: "DatabaseManager")
    
    private init() {}
    
    // Get the default store URL
    var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                 in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("VoiceNote.store")
    }
    
    // Check if store exists
    var storeExists: Bool {
        FileManager.default.fileExists(atPath: storeURL.path)
    }
    
    // Delete the store and related files
    func deleteStore() throws {
        let storeDirectory = storeURL.deletingLastPathComponent()
        let storeFiles = try FileManager.default.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: nil
        )
        
        // Delete the store and its companion files (WAL, SHM)
        let extensions = ["", "-wal", "-shm"]
        for ext in extensions {
            let fileURL = ext.isEmpty ? storeURL : URL(fileURLWithPath: storeURL.path + ext)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                logger.info("Deleted: \(fileURL.lastPathComponent)")
            }
        }
        
        // Also clean up any other default stores that might exist
        for file in storeFiles {
            if file.lastPathComponent.hasPrefix("default.store") {
                try? FileManager.default.removeItem(at: file)
                logger.info("Cleaned up: \(file.lastPathComponent)")
            }
        }
    }
    
    // Create ModelContainer with proper error handling
    func createModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Recording.self, 
            Transcript.self, 
            ProcessedNote.self
        ])
        
        // Check if we need to delete incompatible store
        if storeExists {
            do {
                // Try to create container to test compatibility
                let testConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: false
                )
                
                _ = try ModelContainer(
                    for: schema,
                    configurations: [testConfiguration]
                )
                
                logger.info("Existing store is compatible")
            } catch {
                logger.warning("Store incompatible, deleting: \(error)")
                try deleteStore()
            }
        }
        
        // Create the actual container with specific URL
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )
        
        let container = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
        
        // Configure the context
        container.mainContext.autosaveEnabled = true
        
        logger.info("ModelContainer created successfully")
        return container
    }
    
    // Reset database (for settings)
    func resetDatabase() async throws {
        try deleteStore()
        logger.info("Database reset complete")
    }
}