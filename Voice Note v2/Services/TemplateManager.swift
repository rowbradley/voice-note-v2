import Foundation
import SwiftData
import SwiftUI
import os.log

@MainActor
@Observable
class TemplateManager {
    private(set) var templates: [Template] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.voicenote", category: "TemplateManager")

    /// Initialize with the shared ModelContext from the app's ModelContainer
    /// This ensures Template data is stored in the same database as Recording, Transcript, etc.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Load templates on init
        Task {
            await loadTemplates()
        }
    }
    
    // MARK: - Public Methods
    
    func loadTemplates() async {
        isLoading = true
        error = nil
        
        do {
            // First, check if we need to seed built-in templates
            let descriptor = FetchDescriptor<Template>()
            let existingTemplates = try modelContext.fetch(descriptor)
            
            // Clean up any duplicate templates (one-time fix for development issues)
            await deduplicateTemplates(existingTemplates)
            
            if existingTemplates.isEmpty {
                logger.info("No templates found, loading built-in templates")
                await seedBuiltInTemplates()
            } else {
                // Check for built-in template updates
                await updateBuiltInTemplatesIfNeeded()
            }
            
            // Fetch all templates sorted by category and order
            let sortedDescriptor = FetchDescriptor<Template>(
                sortBy: [
                    SortDescriptor(\.category),
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.name)
                ]
            )
            
            templates = try modelContext.fetch(sortedDescriptor)
            
            // Initialize default order for first-time users
            initializeDefaultOrder()
            
            logger.info("Loaded \(self.templates.count) templates")
            
        } catch {
            self.error = error
            logger.error("Failed to load templates: \(error)")
        }
        
        isLoading = false
    }
    
    func createCustomTemplate(
        name: String,
        description: String,
        prompt: String,
        category: TemplateCategory
    ) async throws {
        let template = Template(
            name: name,
            description: description,
            prompt: prompt,
            category: category.rawValue,
            isPremium: false,
            sortOrder: 1000 // Custom templates go to the end
        )
        
        modelContext.insert(template)
        
        try modelContext.save()
        
        await loadTemplates()
    }
    
    func updateTemplate(_ template: Template) async throws {
        template.modifiedAt = Date()
        template.version += 1
        
        try modelContext.save()
        
        await loadTemplates()
    }
    
    func deleteTemplate(_ template: Template) async throws {
        modelContext.delete(template)
        
        try modelContext.save()
        
        await loadTemplates()
    }
    
    func applyTemplate(_ template: Template, to recording: Recording?) async {
        // This will be called from the UI to apply a template
        // The actual processing will happen through AIService
        logger.info("Applying template: \(template.name)")
    }
    
    // MARK: - Private Methods
    
    private func seedBuiltInTemplates() async {
        for (index, templateJSON) in Template.builtInTemplates.enumerated() {
            let template = Template(
                name: templateJSON.name,
                description: templateJSON.description,
                prompt: templateJSON.prompt,
                category: templateJSON.category,
                isPremium: templateJSON.isPremium,
                sortOrder: index,
                version: templateJSON.version
            )
            
            modelContext.insert(template)
        }
        
        do {
            try modelContext.save()
            logger.info("Seeded \(Template.builtInTemplates.count) built-in templates")
        } catch {
            logger.error("Failed to seed templates: \(error)")
        }
    }
    
    private func updateBuiltInTemplatesIfNeeded() async {
        logger.info("Checking for built-in template updates...")
        
        // Get existing templates by ID
        let descriptor = FetchDescriptor<Template>()
        guard let existingTemplates = try? modelContext.fetch(descriptor) else {
            logger.error("Failed to fetch existing templates for update check")
            return
        }
        
        // One-time cleanup: Remove obsolete templates
        let obsoleteTemplates = existingTemplates.filter {
            $0.name == "Mood Snapshot" || $0.name == "Reply Polish" ||
            $0.name == "Message Ready" || $0.name == "Flashcard Maker"
        }
        for template in obsoleteTemplates {
            logger.info("Removing obsolete template: \(template.name)")
            modelContext.delete(template)
        }
        
        // Create lookup by template name (handle duplicates by taking the first one)
        var existingByName: [String: Template] = [:]
        for template in existingTemplates {
            let isObsolete = template.name == "Mood Snapshot" || template.name == "Reply Polish" ||
                             template.name == "Message Ready" || template.name == "Flashcard Maker"
            if existingByName[template.name] == nil && !isObsolete {
                existingByName[template.name] = template
            }
        }
        
        var updatedCount = 0
        
        // Check each built-in template for updates
        for templateJSON in Template.builtInTemplates {
            // Find existing template by name - only update existing ones, never add
            guard let existing = existingByName[templateJSON.name] else {
                // Template doesn't exist - skip it (seeding handles adding)
                logger.debug("Built-in template '\(templateJSON.name)' not found in database - skipping update")
                continue
            }
            
            // Check if built-in template has newer version
            if templateJSON.version > existing.version {
                logger.info("Updating built-in template: \(templateJSON.name) v\(existing.version) → v\(templateJSON.version)")
                
                // Update the existing template with new prompt and version
                existing.prompt = templateJSON.prompt
                existing.templateDescription = templateJSON.description
                existing.version = templateJSON.version
                existing.modifiedAt = Date()
                
                updatedCount += 1
            }
        }
        
        if updatedCount > 0 {
            do {
                try modelContext.save()
                logger.info("Updated \(updatedCount) built-in templates")
            } catch {
                logger.error("Failed to save template updates: \(error)")
            }
        } else {
            logger.info("All built-in templates are up to date")
        }
    }
    
    private func deduplicateTemplates(_ templates: [Template]) async {
        // Group templates by name to find duplicates
        let groupedByName = Dictionary(grouping: templates) { $0.name }
        let duplicateGroups = groupedByName.filter { $1.count > 1 }
        
        guard !duplicateGroups.isEmpty else {
            logger.debug("No duplicate templates found")
            return
        }
        
        logger.info("Found \(duplicateGroups.count) sets of duplicate templates, cleaning up...")
        
        var deletedCount = 0
        
        for (templateName, duplicates) in duplicateGroups {
            // Sort by version (highest first), then by creation date (newest first)
            let sorted = duplicates.sorted { first, second in
                if first.version != second.version {
                    return first.version > second.version
                }
                return first.createdAt > second.createdAt
            }
            
            // Keep the first one (highest version/newest), delete the rest
            let toKeep = sorted.first!
            let toDelete = Array(sorted.dropFirst())
            
            logger.info("Template '\(templateName)': keeping v\(toKeep.version), deleting \(toDelete.count) duplicates")
            
            for duplicate in toDelete {
                modelContext.delete(duplicate)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            do {
                try modelContext.save()
                logger.info("Deleted \(deletedCount) duplicate templates")
            } catch {
                logger.error("Failed to save after deleting duplicates: \(error)")
            }
        }
    }
}

// MARK: - Template Groups
extension TemplateManager {
    var groupedTemplates: [(category: TemplateCategory, templates: [Template])] {
        let grouped = Dictionary(grouping: templates) { template in
            template.category.flatMap { TemplateCategory(rawValue: $0) } ?? .personal
        }
        
        return TemplateCategory.allCases.compactMap { category in
            guard let categoryTemplates = grouped[category], !categoryTemplates.isEmpty else {
                return nil
            }
            return (category, categoryTemplates)
        }
    }
    
    var freeTemplates: [Template] {
        templates.filter { !$0.isPremium }
    }
    
    var premiumTemplates: [Template] {
        templates.filter { $0.isPremium }
    }
    
    // MARK: - Template Ordering
    
    var orderedTemplates: [Template] {
        // Get saved order from UserDefaults
        let savedOrder = UserDefaults.standard.array(forKey: "templateOrder") as? [String] ?? []
        
        // Create a lookup dictionary for templates by ID
        let templateDict = Dictionary(uniqueKeysWithValues: templates.map { ($0.id.uuidString, $0) })
        
        // Build ordered list starting with saved order
        var orderedList: [Template] = []
        
        // First, add templates in saved order
        for templateId in savedOrder {
            if let template = templateDict[templateId] {
                orderedList.append(template)
            }
        }
        
        // Then add any new templates not in saved order (preserving original sort order)
        let addedIds = Set(orderedList.map { $0.id.uuidString })
        let remainingTemplates = templates
            .filter { !addedIds.contains($0.id.uuidString) }
            .sorted { $0.sortOrder < $1.sortOrder }
        
        orderedList.append(contentsOf: remainingTemplates)
        
        return orderedList
    }
    
    func reorderTemplates(from source: IndexSet, to destination: Int) {
        var mutableTemplates = orderedTemplates
        mutableTemplates.move(fromOffsets: source, toOffset: destination)
        
        // Save new order to UserDefaults
        let newOrder = mutableTemplates.map { $0.id.uuidString }
        UserDefaults.standard.set(newOrder, forKey: "templateOrder")
        
        // Update internal state
        templates = mutableTemplates
    }
    
    private func initializeDefaultOrder() {
        // Only set default order if no saved order exists
        guard UserDefaults.standard.array(forKey: "templateOrder") == nil else { return }
        
        // Create a mapping from template names to UUIDs
        let templateDict = Dictionary(uniqueKeysWithValues: templates.map { ($0.name, $0.id.uuidString) })
        
        let defaultOrder = [
            "Cleanup", "Smart Summary", "Action List", "Idea Outline",
            "Brainstorm", "Key Quotes", "Next Questions", "Tone Analysis"
        ]
        
        let orderedIds = defaultOrder.compactMap { templateDict[$0] }
        UserDefaults.standard.set(orderedIds, forKey: "templateOrder")
    }
}