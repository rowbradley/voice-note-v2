//
//  Voice_Note_v2App.swift
//  Voice Note v2
//
//  Created by Rowan Bradley on 6/17/25.
//

import SwiftUI
import SwiftData
import os.log

@main
struct Voice_Note_v2App: App {
    @State private var coordinator = AppCoordinator()
    @State private var modelContainer: ModelContainer?
    @State private var databaseError: String?
    @State private var showingDatabaseError = false
    private let logger = Logger(subsystem: "com.voicenote", category: "App")
    private static let appSchema = Schema([Recording.self, Transcript.self, ProcessedNote.self, Template.self])

    init() {
        // Set up SwiftData with proper error handling
        do {
            let container = try createModelContainer()
            _modelContainer = State(initialValue: container)
        } catch {
            logger.error("Failed to create ModelContainer: \(error)")
            _databaseError = State(initialValue: error.localizedDescription)
            _showingDatabaseError = State(initialValue: true)
            
            // Create in-memory container as fallback
            do {
                let config = ModelConfiguration(
                    isStoredInMemoryOnly: true,
                    allowsSave: true
                )
                let fallbackContainer = try ModelContainer(
                    for: Self.appSchema,
                    configurations: config
                )
                _modelContainer = State(initialValue: fallbackContainer)
                logger.warning("Using in-memory database as fallback")
            } catch {
                // This should never happen, but handle gracefully
                logger.critical("Cannot create even in-memory database: \(error)")
            }
        }
        
        // Debug: Log configuration
        #if DEBUG
        logger.info("Voice Note Starting...")
        logger.info("AI Processing: On-Device (Apple Intelligence)")
        Config.logConfiguration()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            if let modelContainer = modelContainer {
                MainTabView()
                    .environment(coordinator)
                    .environment(\.appSettings, AppSettings.shared)
                    .modelContainer(modelContainer)
                    .onAppear {
                        coordinator.bootstrap()
                    }
                    .alert("Database Error", isPresented: $showingDatabaseError) {
                        Button("Try Reset", role: .destructive) {
                            Task {
                                await resetDatabase()
                            }
                        }
                        Button("Continue", role: .cancel) { }
                    } message: {
                        Text(databaseError ?? "Failed to load database. You can try resetting or continue with limited functionality.")
                    }
            } else {
                // Fallback UI when database completely fails
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Database Error")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text("Voice Note cannot access its database.")
                        .foregroundColor(.secondary)
                    
                    Button("Reset Database") {
                        Task {
                            await resetDatabase()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }
    
    private func resetDatabase() async {
        do {
            // Delete the store
            try deleteStoreFiles()

            // Allow file system to complete deletion before recreating container.
            // Without this delay, SQLite may still hold locks on the old store files,
            // causing the new container creation to fail or reference stale data.
            try? await Task.sleep(for: .milliseconds(100))
            
            // Recreate container
            let newContainer = try createModelContainer()
            
            await MainActor.run {
                modelContainer = newContainer
                showingDatabaseError = false
                databaseError = nil
            }
            
            logger.info("Database reset successfully")
        } catch {
            logger.error("Reset failed: \(error)")
            await MainActor.run {
                databaseError = "Reset failed: \(error.localizedDescription)"
                showingDatabaseError = true
            }
        }
    }
    
    private func createModelContainer() throws -> ModelContainer {
        // Use a specific URL for the store
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                               in: .userDomainMask)[0]
            .appendingPathComponent("VoiceNote.store")
        
        // Create configuration with the specific URL
        let modelConfiguration = ModelConfiguration(
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        
        do {
            // Try to create container with schema
            let container = try ModelContainer(
                for: Self.appSchema,
                configurations: modelConfiguration
            )
            
            // Configure the context
            container.mainContext.autosaveEnabled = true

            // Seed built-in templates if database is empty (first launch)
            seedTemplatesIfNeeded(in: container.mainContext)

            logger.info("ModelContainer created successfully at: \(storeURL)")
            return container
        } catch {
            logger.error("Migration failed: \(error)")
            
            #if DEBUG
            // In debug, try to reset if migration fails
            logger.debug("Attempting store reset...")
            try deleteStoreFiles()
            
            // Try again after reset
            let container = try ModelContainer(
                for: Self.appSchema,
                configurations: modelConfiguration
            )
            
            container.mainContext.autosaveEnabled = true

            // Seed built-in templates after reset
            seedTemplatesIfNeeded(in: container.mainContext)

            logger.info("ModelContainer created after reset")
            return container
            #else
            // In release, throw the error to show user-friendly message
            throw error
            #endif
        }
    }

    private func deleteStoreFiles() throws {
        // Clean up SwiftData store files
        // Note: Store filename matches what's used in createModelContainer() - "VoiceNote.store"
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                    in: .userDomainMask)[0]
        if let files = try? FileManager.default.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files {
                if file.lastPathComponent.hasPrefix("VoiceNote.store") {
                    try? FileManager.default.removeItem(at: file)
                    logger.debug("Cleaned up: \(file.lastPathComponent)")
                }
            }
        }
    }

    /// Seeds built-in templates into SwiftData if the database is empty.
    /// Called synchronously during container creation to guarantee templates
    /// exist before any view renders (avoids @Query returning empty array).
    private func seedTemplatesIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Template>()
        guard (try? context.fetchCount(descriptor)) == 0 else { return }

        for (index, templateData) in Template.builtInTemplates.enumerated() {
            let template = Template(
                name: templateData.name,
                description: templateData.description,
                prompt: templateData.prompt,
                category: templateData.category,
                isPremium: templateData.isPremium,
                sortOrder: index,
                version: templateData.version
            )
            context.insert(template)
        }

        try? context.save()
        logger.info("Seeded \(Template.builtInTemplates.count) built-in templates")
    }
}
