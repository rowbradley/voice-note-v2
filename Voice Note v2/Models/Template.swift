import Foundation
import SwiftData

// MARK: - Template Model
@Model
final class Template {
    @Attribute(.unique) var id: UUID
    var name: String
    var templateDescription: String
    var prompt: String
    var category: String?
    var isPremium: Bool
    var sortOrder: Int
    var version: Int
    var createdAt: Date
    var modifiedAt: Date
    var isFavorite: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        prompt: String,
        category: String? = nil,
        isPremium: Bool = false,
        sortOrder: Int = 0,
        version: Int = 1,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.templateDescription = description
        self.prompt = prompt
        self.category = category
        self.isPremium = isPremium
        self.sortOrder = sortOrder
        self.version = version
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isFavorite = isFavorite
    }
}

// MARK: - Template Category
enum TemplateCategory: String, CaseIterable, Codable {
    case business = "Business"
    case personal = "Personal"
    case creative = "Creative"
    case productivity = "Productivity"
    case education = "Education"
    
    var icon: String {
        switch self {
        case .business: return "briefcase.fill"
        case .personal: return "person.fill"
        case .creative: return "paintbrush.fill"
        case .productivity: return "checkmark.circle.fill"
        case .education: return "graduationcap.fill"
        }
    }
}

// MARK: - Schema Versioning
enum TemplateSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Template.self]
    }
}

// MARK: - Template JSON Model (for seed data)
struct TemplateJSON: Codable {
    let id: String
    let name: String
    let description: String
    let prompt: String
    let category: String?
    let isPremium: Bool
    let sortOrder: Int
    let version: Int
}

// MARK: - Built-in Templates
extension Template {
    static let builtInTemplates: [TemplateJSON] = [
        TemplateJSON(
            id: "cleanup",
            name: "Cleanup",
            description: "Remove fillers, fix grammar, and improve readability",
            prompt: "You are a transcript editor. Clean this transcript for reading. Remove filler words (um, uh, like, you know, I mean, basically). Remove repeated words and false starts. Fix punctuation and capitalization. Preserve the speaker's meaning, intent, subject, tense, names, and all specific details.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 1,
            version: 15
        ),

        TemplateJSON(
            id: "smart-summary",
            name: "Smart Summary",
            description: "One-sentence overview plus key details",
            prompt: "You are a summarizer. Capture the essence of this transcript efficiently. Identify the core message in one sentence with key terms that could be bolded. Extract exactly 3 key details with topic labels and brief explanations.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 2,
            version: 14
        ),

        TemplateJSON(
            id: "brainstorm",
            name: "Brainstorm",
            description: "Extract ideas and cluster related concepts",
            prompt: "You are an idea extractor. Find patterns and themes in this conversation. Group related ideas together under theme names. Note when ideas are mentioned multiple times as higher priority.",
            category: TemplateCategory.creative.rawValue,
            isPremium: false,
            sortOrder: 3,
            version: 13
        ),

        TemplateJSON(
            id: "action-list",
            name: "Action List",
            description: "Extract actionable tasks with owners and deadlines",
            prompt: "You are a task extractor. Find commitments and action items in this transcript. For each task, identify who is responsible (or 'Unassigned') and any mentioned deadline (or 'Not specified'). Categorize by priority: high for urgent/immediate, normal for standard, low for can-wait items.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 4,
            version: 13
        ),

        TemplateJSON(
            id: "idea-outline",
            name: "Idea Outline",
            description: "Transform into hierarchical outline",
            prompt: "You are an outline creator. Find structure in this conversation. Create a title summarizing the main topic. Organize into 2-5 main sections with key points under each. End with a key insight or takeaway.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 5,
            version: 13
        ),

        TemplateJSON(
            id: "key-quotes",
            name: "Key Quotes",
            description: "Extract impactful and shareable quotes",
            prompt: "You are a quote curator. Find memorable and impactful moments in this transcript. Extract 2-5 notable quotes, lightly editing for clarity while preserving the speaker's voice. For each quote, explain why it matters.",
            category: TemplateCategory.creative.rawValue,
            isPremium: false,
            sortOrder: 6,
            version: 13
        ),

        TemplateJSON(
            id: "next-questions",
            name: "Next Questions",
            description: "Suggest follow-up questions",
            prompt: "You are a question generator. Based on this transcript, suggest 3-5 thought-provoking follow-up questions that would deepen understanding. For each question, explain why it matters.",
            category: TemplateCategory.education.rawValue,
            isPremium: false,
            sortOrder: 7,
            version: 13
        ),

        TemplateJSON(
            id: "tone-analysis",
            name: "Tone Analysis",
            description: "Analyze emotional tone and sentiment",
            prompt: "You are a sentiment analyst. Analyze the emotional tone and sentiment in this transcript. Identify the overall tone, energy level, and 2-4 primary emotions with context for where each appears. End with a key observation about the emotional pattern.",
            category: TemplateCategory.personal.rawValue,
            isPremium: false,
            sortOrder: 8,
            version: 13
        )
    ]
}
