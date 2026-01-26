//
//  Voice_NoteApp.swift
//  Voice Note (macOS)
//
//  macOS menu bar agent with floating HUD and library window.
//

import SwiftUI
import SwiftData
import os.log

@main
struct Voice_NoteApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var modelContainer: ModelContainer?
    @State private var recordingManager: RecordingManager

    private let logger = Logger(subsystem: "com.voicenote", category: "MacApp")
    private static let appSchema = Schema([Recording.self, Transcript.self, ProcessedNote.self, Template.self, Session.self])

    init() {
        // Initialize RecordingManager first (required before calling instance methods)
        let manager = RecordingManager()
        _recordingManager = State(initialValue: manager)

        // Set up SwiftData with proper error handling
        do {
            let container = try createModelContainer()
            _modelContainer = State(initialValue: container)

            // Configure RecordingManager immediately after container creation
            // This ensures recordings save to database even when started from menu bar
            manager.configure(with: container.mainContext)
            manager.prewarmTranscription()

            logger.info("RecordingManager configured with ModelContext")
        } catch {
            logger.error("Failed to create ModelContainer: \(error)")

            // RecordingManager remains unconfigured (in-memory only)

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
                logger.critical("Cannot create even in-memory database: \(error)")
            }
        }

        #if DEBUG
        logger.info("Voice Note macOS Starting...")
        logger.info("AI Processing: On-Device (Apple Intelligence)")
        Config.logConfiguration()
        #endif
    }

    var body: some Scene {
        // Menu bar (always visible)
        // Using .menu style to avoid SwiftUI constraint loop bug with .window style
        // Icon changes to red recording indicator when actively recording
        MenuBarExtra {
            MenuBarMenuContent(recordingManager: recordingManager)
                .environment(AppSettings.shared)
        } label: {
            // Dynamic icon based on recording state
            if recordingManager.isRecording {
                Image(systemName: "record.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .primary)
            } else {
                Image(systemName: "waveform.circle")
            }
        }
        .menuBarExtraStyle(.menu)

        // Library window (on demand)
        WindowGroup("Library", id: "library") {
            if let modelContainer = modelContainer {
                LibraryWindowView()
                    .environment(recordingManager)
                    .environment(coordinator)
                    .environment(AppSettings.shared)
                    .modelContainer(modelContainer)
                    .onAppear {
                        WindowManager.setIdentifier(WindowManager.ID.library, forWindowWithTitle: "Library")
                    }
            } else {
                Text("Database unavailable")
                    .foregroundColor(.secondary)
            }
        }

        // Floating panel for quick capture
        // Window level (stay on top) is managed dynamically via WindowManager in FloatingPanelView
        Window("Voice Note", id: "floating-panel") {
            if let modelContainer = modelContainer {
                FloatingPanelView()
                    .environment(recordingManager)
                    .environment(AppSettings.shared)
                    .modelContainer(modelContainer)
            }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { content, context in
            // Center horizontally, near top of screen (under menu bar)
            let displayBounds = context.defaultDisplay.visibleRect
            let size = content.sizeThatFits(.unspecified)
            let x = displayBounds.midX - size.width / 2
            let y = displayBounds.maxY - size.height - 50 // 50pt from top
            return WindowPlacement(CGPoint(x: x, y: y))
        }

        // Settings window
        Settings {
            MacSettingsView()
                .environment(coordinator)
                .environment(AppSettings.shared)
        }
    }

    // MARK: - Database Setup

    private func createModelContainer() throws -> ModelContainer {
        // Use a specific URL for the store
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask)[0]

        // Ensure Application Support directory exists
        try FileManager.default.createDirectory(at: appSupportURL,
                                                withIntermediateDirectories: true)

        let storeURL = appSupportURL.appendingPathComponent("VoiceNote.store")

        // Create configuration WITHOUT CloudKit for now (requires App Sandbox + proper setup)
        // TODO: Re-enable CloudKit once entitlements are properly configured
        let modelConfiguration = ModelConfiguration(
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none  // Disabled until CloudKit is properly configured
        )

        do {
            let container = try ModelContainer(
                for: Self.appSchema,
                configurations: modelConfiguration
            )

            container.mainContext.autosaveEnabled = true

            // Seed built-in templates if database is empty (first launch)
            seedTemplatesIfNeeded(in: container.mainContext)

            logger.info("ModelContainer created successfully at: \(storeURL)")
            return container
        } catch {
            logger.error("Migration failed: \(error)")

            #if DEBUG
            logger.debug("Attempting store reset...")
            try deleteStoreFiles()

            let container = try ModelContainer(
                for: Self.appSchema,
                configurations: modelConfiguration
            )

            container.mainContext.autosaveEnabled = true
            seedTemplatesIfNeeded(in: container.mainContext)

            logger.info("ModelContainer created after reset")
            return container
            #else
            throw error
            #endif
        }
    }

    private func deleteStoreFiles() throws {
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
