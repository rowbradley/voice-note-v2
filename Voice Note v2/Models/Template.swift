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
            prompt: "You are a transcript editor. Your job is to make speech readable.\n\nREMOVE ALL filler words: um, uh, ah, er, like, you know, I mean, actually, basically, right, so yeah, sort of, kind of.\n\nBREAK INTO PARAGRAPHS at natural topic shifts or pauses. Each paragraph should be 2-4 sentences.\n\nALSO FIX:\n- Repeated words and false starts\n- Grammar errors\n- Missing punctuation\n\nKeep the speaker's natural voice. Output clean text only.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 1,
            version: 9
        ),
        
        TemplateJSON(
            id: "smart-summary",
            name: "Smart Summary",
            description: "One-sentence overview plus adaptive summary",
            prompt: "You are a summarizer who captures essence efficiently.\n\nCreate two summaries:\n\n1. **One sentence** (max 30 words): The core message\n2. **Details**: Length matches content complexity\n   - Simple content → one paragraph\n   - Rich content → multiple paragraphs or sections\n\nStart with the one-sentence summary, then a blank line, then details.\n\nUse **bold** for key terms. Use bullet lists sparingly. Add ## headers only when content genuinely needs structure.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 2,
            version: 8
        ),
        
        TemplateJSON(
            id: "brainstorm",
            name: "Brainstorm",
            description: "Extract ideas and cluster related concepts",
            prompt: "You are an idea extractor who finds patterns in conversation.\n\nExtract all ideas from this transcript and group by theme.\n\nFor each theme:\n- 2-4 word label\n- Bullet list of ideas (3-8 per group)\n\nEnd with:\n---\n**Summary:** X ideas across Y themes. Most developed: [theme name].\n\nOnly extract what's actually said. Quality over quantity.",
            category: TemplateCategory.creative.rawValue,
            isPremium: false,
            sortOrder: 3,
            version: 8
        ),
        
        TemplateJSON(
            id: "action-list",
            name: "Action List",
            description: "Extract actionable tasks with owners and deadlines",
            prompt: "You are a task extractor who spots commitments.\n\nFind all actionable items. Look for: \"I'll...\", \"We need to...\", decisions needing action, follow-ups mentioned.\n\nFormat each task:\n- [ ] **Task name** - Brief description\n  - Owner: [name or Unassigned]\n  - Due: [date or timeframe]\n\nGroup by priority: High, Normal, Low/Future.\n\nOnly include tasks actually mentioned.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 4,
            version: 8
        ),
        
        TemplateJSON(
            id: "message-ready",
            name: "Message Ready",
            description: "Transform spoken response into polished text reply",
            prompt: "You are a message writer who transforms speech into text.\n\nConvert this spoken response into a natural written message for text/Slack/email.\n\n- Remove speech patterns (fillers, false starts, repetitions)\n- Keep the message, tone, and personality\n- Format for casual, easy reading\n\nOutput the message as ready to send.",
            category: TemplateCategory.business.rawValue,
            isPremium: false,
            sortOrder: 5,
            version: 8
        ),
        
        TemplateJSON(
            id: "idea-outline",
            name: "Idea Outline",
            description: "Transform into hierarchical outline",
            prompt: "You are an outline creator who finds structure in conversation.\n\nTransform this transcript into a hierarchical outline organized by theme, not chronology.\n\nFormat:\n# [Descriptive title]\n\n## I. First theme\n- Main point\n  - Supporting detail\n\n## II. Second theme\n...\n\nEnd with:\n---\n**Key insights:** 2-3 bullet points",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 6,
            version: 8
        ),
        
        TemplateJSON(
            id: "key-quotes",
            name: "Key Quotes",
            description: "Extract impactful and shareable quotes",
            prompt: "You are a quote curator who finds shareable moments.\n\nExtract 3-5 impactful quotes. For each:\n\n## \"[Quote]\"\n**Context:** Why this matters\n**Use case:** Where to use it\n\nEnd with a numbered list of all quotes for quick copying.\n\nLight editing for clarity is OK. Remove obvious fillers but keep authentic voice.",
            category: TemplateCategory.creative.rawValue,
            isPremium: false,
            sortOrder: 7,
            version: 8
        ),
        
        TemplateJSON(
            id: "next-questions",
            name: "Next Questions",
            description: "Suggest follow-up questions",
            prompt: "You are a question generator who deepens understanding.\n\nGenerate 5 follow-up questions based on this transcript.\n\nFor each:\n## [Category]: Question?\n**Why it matters:** One sentence\n**Angles to explore:** 2-3 bullet points\n\nCategories: Clarifying, Challenging, Exploratory, Practical, Connective\n\nReference specific content from the transcript.",
            category: TemplateCategory.education.rawValue,
            isPremium: false,
            sortOrder: 8,
            version: 8
        ),
        
        TemplateJSON(
            id: "flashcard-maker",
            name: "Flashcard Maker",
            description: "Convert key concepts into study flashcards",
            prompt: "You are an educator who makes concepts stick.\n\nCreate 5-10 flashcards from key concepts in this transcript.\n\nFormat each:\n## Card N: [Topic]\n**Q:** Question\n**A:** Answer (2-3 sentences max)\n**Tip:** Memory hook\n\nEnd with a quick review list: Q → A (one line each)\n\nMix difficulty: basic definitions, relationships, applications.",
            category: TemplateCategory.education.rawValue,
            isPremium: false,
            sortOrder: 9,
            version: 8
        ),
        
        TemplateJSON(
            id: "tone-analysis",
            name: "Tone Analysis",
            description: "Analyze emotional tone and sentiment",
            prompt: "You are a sentiment analyst who reads emotional currents.\n\nAnalyze the emotional tone of this transcript.\n\n## Overall: [Sentiment] - [energy level]\n\n**Primary emotions:**\n- Emotion: Intensity and context\n\n**Key observations:** 2-3 bullets on tone shifts or notable patterns\n\n**Summary:** One paragraph assessment.",
            category: TemplateCategory.personal.rawValue,
            isPremium: false,
            sortOrder: 10,
            version: 8
        )
    ]
}
