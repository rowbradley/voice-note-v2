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
            prompt: "Clean up this transcript for readability. Tasks:\n1. Remove filler words (um, uh, like, you know, I mean, actually, basically, right, so yeah)\n2. Fix repeated words and false starts\n3. Add proper punctuation and paragraph breaks at natural pauses\n4. Correct obvious grammar errors while preserving speaker's voice\n5. Remove timestamps and speaker labels unless critical for context\n6. Keep all meaningful content - only remove disruptions to flow\n\nPreserve the speaker's natural voice and tone.\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nFormat the output as clean paragraphs with minimal markdown:\n\nThis is a regular paragraph with natural flow and no special formatting except where someone *really* emphasized a word.\n\nThis is the next paragraph after a blank line.\n\n**Speaker Name:** Only use this format when there are multiple speakers and clarity is needed.\n\nDo NOT use headers (#, ##) or lists. Keep it simple and readable.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 1,
            version: 7
        ),
        
        TemplateJSON(
            id: "smart-summary",
            name: "Smart Summary",
            description: "One-sentence overview plus adaptive summary",
            prompt: "Create two summaries of this transcript:\n\n1. One-Sentence Overview: A single, clear sentence that captures the essence (max 30 words)\n2. Adaptive Summary: Length based on content complexity\n   - Brief content: One concise paragraph\n   - Moderate content: 2-3 paragraphs with main themes\n   - Complex content: Structured sections with headers\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nFormat your output EXACTLY like this:\n\nThe transcript discusses [main topic] with focus on [key point], ultimately concluding that [main takeaway].\n\n## Details\n\nFor brief content, write a single paragraph covering all key points. Use **bold** for important terms or decisions.\n\nFor longer content, use multiple paragraphs. When listing multiple items:\n- First important item\n- Second important item\n- Third important item\n\nFor complex content, add section headers:\n\n### Main topic area\n\nDetailed explanation of this topic...\n\n### Secondary topic\n\nExplanation of the second area...\n\nLet the content drive the length. Include what matters, exclude what doesn't.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 2,
            version: 7
        ),
        
        TemplateJSON(
            id: "brainstorm",
            name: "Brainstorm",
            description: "Extract ideas and cluster related concepts",
            prompt: "Extract all ideas from this transcript and organize them into thematic clusters. Capture everything - explicit proposals, implied possibilities, creative tangents, and \"what if\" moments.\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nIMPORTANT: Only extract what's actually in the transcript. If the content doesn't support the full structure shown in the example, adapt the output accordingly. Quality over quantity - 2 real items are better than 10 invented ones.\n\nFormat your output EXACTLY like this:\n\nThis brainstorming session focused on [main topic/problem], generating [number] ideas across [number] key themes. The discussion emphasized [primary focus area] with particular attention to [notable aspect].\n\n## Customer experience improvements\n- Implement self-service portal for common requests\n- Add live chat support during business hours\n- Create video tutorials for onboarding\n- Develop mobile app for on-the-go access\n- Gamify the user journey with achievement badges\n\n## Technical infrastructure upgrades\n- Migrate to cloud-based architecture\n- Implement automated testing pipeline\n- Add real-time monitoring dashboards\n- Create API for third-party integrations\n\n## Team development initiatives\n- Start weekly knowledge-sharing sessions\n- Implement peer programming practices\n- Create mentorship program\n- Hold quarterly hackathons\n\n---\n\n## Fresh angles\n\nBased on the patterns in this discussion, here are new perspectives not explicitly mentioned:\n\n1. **Cross-functional integration**: The ideas suggest siloed thinking - consider how customer experience and technical infrastructure could be designed together from the start.\n\n2. **Scalability framework**: Many ideas focus on immediate improvements but lack long-term scaling considerations. Consider building with 10x growth in mind.\n\n3. **Measurement strategy**: Notable absence of success metrics - each initiative needs clear KPIs to evaluate impact.\n\n---\n\n**Summary:**\n- Total ideas captured: 15\n- Most developed cluster: Customer experience (5 ideas)\n- Potential next steps: Prioritize ideas by impact vs effort matrix\n\nUse 2-4 word cluster labels. Include 3-8 ideas per cluster. Balance cluster sizes when possible.",
            category: TemplateCategory.creative.rawValue,
            isPremium: false,
            sortOrder: 3,
            version: 7
        ),
        
        TemplateJSON(
            id: "action-list",
            name: "Action List",
            description: "Extract actionable tasks with owners and deadlines",
            prompt: "Extract all actionable tasks from this transcript. Focus on concrete commitments, decisions that need implementation, and explicit next steps.\n\nLook for:\n- Direct commitments (\"I'll...\", \"We need to...\", \"Let's...\")\n- Decisions requiring action\n- Problems needing solutions\n- Follow-up items mentioned\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nIMPORTANT: Only extract what's actually in the transcript. If the content doesn't support the full structure shown in the example, adapt the output accordingly. Quality over quantity - 2 real items are better than 10 invented ones.\n\nFormat your output EXACTLY like this example:\n\n## High priority\n\n- [ ] **Review quarterly report** - Complete analysis of Q4 metrics\n  - **Owner:** Sarah Chen\n  - **Due:** Friday, March 15\n  - **Context:** Needed for board meeting\n\n- [ ] **Schedule team retrospective** - Book 2-hour session with all stakeholders\n  - **Owner:** [Unassigned]\n  - **Due:** Next week\n\n## Normal priority\n\n- [ ] **Update documentation** - Revise API docs with new endpoints\n  - **Owner:** Dev team\n  - **Due:** End of month\n\n## Low priority / Future consideration\n\n- [ ] **Research new tools** - Evaluate alternatives to current CRM\n  - **Owner:** [Unassigned]\n  - **Due:** Q2 2024\n\nUse markdown checkboxes (- [ ]) for all tasks. Start each task with a strong verb. Include all four fields (task, owner, due, context) when available. Group related tasks together.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 4,
            version: 7
        ),
        
        TemplateJSON(
            id: "message-ready",
            name: "Message Ready",
            description: "Transform spoken response into polished text reply",
            prompt: "Transform this spoken response into a natural written reply suitable for text/Slack/email. This transcript is someone's verbal response that needs to sound naturally typed, not transcribed.\n\nTransformation guidelines:\n1. Remove speech patterns: fillers (um, uh), false starts, repetitions, thinking-out-loud phrases\n2. Preserve the message: core points, tone, personality, warmth\n3. Format for text: natural paragraphs, appropriate punctuation\n4. Polish without changing voice: keep casual if casual, preserve humor\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nOutput the cleaned message ready to send. Use simple formatting:\n\nHey! Thanks for reaching out about that project.\n\nI've been thinking about your proposal, and I really like the direction you're taking. The timeline seems reasonable, though we might need an extra week for the testing phase.\n\nLet me know if you want to hop on a quick call to discuss the details. I'm free Tuesday afternoon or anytime Wednesday.\n\nThanks!\n\n---\n*Note: Review before sending to ensure it captures your intended tone*",
            category: TemplateCategory.business.rawValue,
            isPremium: false,
            sortOrder: 5,
            version: 7
        ),
        
        TemplateJSON(
            id: "idea-outline",
            name: "Idea Outline",
            description: "Transform into hierarchical outline",
            prompt: "Transform this transcript into a logical hierarchical outline. Reorganize content by themes and relationships, not chronological order.\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nFormat your output EXACTLY like this structure:\n\n# [Generate a descriptive title about the actual content]\n\n## I. First main theme\n\n- Primary point about this theme\n  - Supporting detail or evidence\n  - Another supporting element\n  - Additional context if needed\n\n- Secondary point within this theme\n  - Its supporting information\n  - Related detail\n\n## II. Second main theme\n\n- Key argument or concept\n  - Evidence or elaboration\n  - Example or illustration\n\n- Related point\n  - Supporting detail\n\n## III. Third main theme\n\n- Core insight\n  - Explanation\n  - Implications\n\n---\n\n**Key insights:**\n- Most important takeaway from the entire discussion\n- Second critical insight that emerged\n- Third key learning or conclusion\n\nUse Roman numerals (I, II, III) for main sections. Use - for main points and indent with two spaces for sub-points. Focus on logical grouping, not time sequence. Merge duplicate ideas. Elevate buried insights.",
            category: TemplateCategory.productivity.rawValue,
            isPremium: false,
            sortOrder: 6,
            version: 7
        ),
        
        TemplateJSON(
            id: "key-quotes",
            name: "Key Quotes",
            description: "Extract impactful and shareable quotes",
            prompt: "Extract 3-5 most impactful quotes from this transcript. Focus on statements that are memorable, insightful, or shareable.\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nIMPORTANT: Only extract what's actually in the transcript. If the content doesn't support the full structure shown in the example, adapt the output accordingly. Quality over quantity - 2 real items are better than 10 invented ones.\n\nFormat your output EXACTLY like this:\n\n## \"The real innovation isn't in the technology itself, but in how we make it invisible to the user.\"\n\n**Context:** Said during the discussion about product design philosophy, emphasizing user experience over feature complexity.\n\n**Use case:** Presentation slide, design principles document\n\n---\n\n## \"We're not just building a product, we're building trust.\"\n\n**Context:** CEO's response to customer service concerns, highlighting company values.\n\n**Use case:** Company culture deck, social media\n\n---\n\n## \"Data without action is just expensive storage.\"\n\n**Context:** During analytics discussion, pushing for actionable insights over vanity metrics.\n\n**Use case:** Data team motto, conference talk\n\n---\n\n## Quick copy list\n\nAll quotes for easy copying:\n\n1. \"The real innovation isn't in the technology itself, but in how we make it invisible to the user.\"\n\n2. \"We're not just building a product, we're building trust.\"\n\n3. \"Data without action is just expensive storage.\"\n\nUse quotes as headers. Keep quotes under 50 words. Light editing for clarity is OK. Remove obvious fillers but preserve authentic voice.",
            category: TemplateCategory.creative.rawValue,
            isPremium: false,
            sortOrder: 7,
            version: 7
        ),
        
        TemplateJSON(
            id: "next-questions",
            name: "Next Questions",
            description: "Suggest follow-up questions",
            prompt: "Based on this transcript, generate 5 thought-provoking follow-up questions that would deepen understanding or explore unaddressed angles.\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nIMPORTANT: Only extract what's actually in the transcript. If the content doesn't support the full structure shown in the example, adapt the output accordingly. Quality over quantity - 2 real items are better than 10 invented ones.\n\nFormat your output EXACTLY like this:\n\n## 1. [Clarifying]: How does the proposed timeline account for potential technical dependencies?\n\n**Why this matters:** Understanding dependencies helps identify potential bottlenecks before they impact the project schedule.\n\n**Potential angles:**\n- Map out all technical dependencies in a visual diagram\n- Identify which dependencies are critical path items\n- Explore backup plans if key dependencies are delayed\n\n---\n\n## 2. [Challenging]: What evidence supports the assumption that customers prefer speed over customization?\n\n**Why this matters:** This assumption drives major product decisions, so validating it with data could prevent costly mistakes.\n\n**Potential angles:**\n- Conduct A/B testing with different feature sets\n- Survey existing customers about their priorities\n- Analyze competitor offerings and market positioning\n\n---\n\n## 3. [Exploratory]: How might AI integration change our product roadmap in the next 18 months?\n\n**Why this matters:** AI is rapidly evolving and could offer competitive advantages or disrupt our current approach.\n\n**Potential angles:**\n- Research current AI applications in our industry\n- Identify specific use cases for our product\n- Evaluate build vs. buy vs. partner options\n\n---\n\n## 4. [Practical]: What specific metrics would indicate our new strategy is working?\n\n**Why this matters:** Clear success metrics enable objective evaluation and course correction.\n\n**Potential angles:**\n- Define leading vs. lagging indicators\n- Set up dashboards for real-time monitoring\n- Establish review cadence and decision criteria\n\n---\n\n## 5. [Connective]: How does this initiative align with our broader company mission?\n\n**Why this matters:** Ensuring alignment prevents mission drift and maintains organizational focus.\n\n**Potential angles:**\n- Review against stated company values\n- Consider long-term strategic implications\n- Identify potential conflicts or synergies\n\nUse [Category] labels: Clarifying, Challenging, Exploratory, Practical, or Connective. Each question should reference specific content from the transcript. Include diverse question types.",
            category: TemplateCategory.education.rawValue,
            isPremium: false,
            sortOrder: 8,
            version: 7
        ),
        
        TemplateJSON(
            id: "flashcard-maker",
            name: "Flashcard Maker",
            description: "Convert key concepts into study flashcards",
            prompt: "Extract key concepts from this transcript and convert them into effective study flashcards. Create 5-10 cards with a mix of difficulty levels.\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nIMPORTANT: Only extract what's actually in the transcript. If the content doesn't support the full structure shown in the example, adapt the output accordingly. Quality over quantity - 2 real items are better than 10 invented ones.\n\nFormat your output EXACTLY like this:\n\n## Card 1: Synchronous vs asynchronous communication\n**Q:** What is the primary difference between synchronous and asynchronous communication?\n\n**A:** Synchronous communication happens in real-time (like phone calls or meetings), while asynchronous communication has delays between messages (like email or Slack), allowing participants to respond when convenient.\n\n**Study tip:** Think \"sync\" = same time, \"async\" = any time\n\n---\n\n## Card 2: Technical debt\n**Q:** Define \"technical debt\" in software development\n\n**A:** Technical debt is the implied cost of future rework caused by choosing an easy (limited) solution now instead of using a better approach that would take longer to implement.\n\n**Study tip:** Like financial debt - quick gains now, but you pay \"interest\" later\n\n---\n\n## Card 3: Waterfall vs agile\n**Q:** How do waterfall and agile methodologies differ in their approach to project changes?\n\n**A:** Waterfall follows a linear sequence and resists changes after each phase is complete. Agile embraces change through iterative cycles, allowing adjustments based on feedback throughout the project.\n\n**Study tip:** Waterfall = rigid sequence, Agile = flexible iterations\n\n---\n\n## Quick review\n\nFor rapid self-testing:\n\n1. **Q:** Primary difference between sync/async communication? → **A:** Real-time vs. delayed response\n2. **Q:** What is technical debt? → **A:** Future cost of quick/limited solutions\n3. **Q:** Waterfall vs Agile on changes? → **A:** Rigid sequence vs. flexible iterations\n\n---\n\n**Coverage:** [List main topics covered]\n\nCreate clear Q&A pairs. Include study tips with memory hooks. Vary difficulty: 2-3 basic (definitions), 3-4 intermediate (relationships), 1-2 advanced (application).",
            category: TemplateCategory.education.rawValue,
            isPremium: false,
            sortOrder: 9,
            version: 7
        ),
        
        TemplateJSON(
            id: "tone-analysis",
            name: "Tone Analysis",
            description: "Analyze emotional tone and sentiment",
            prompt: "Analyze the emotional tone and sentiment of this transcript. Provide a concise assessment of the overall mood and key emotions present.\n\nCRITICAL OUTPUT RULES:\n- Never include template names in your output\n- Use sentence case for all headers\n- Start with meaningful content\n- Interpret transcript content intelligently - prioritize contextual sense over phonetic literalism\n\nFormat your output like this:\n\n## Overall sentiment: Positive and collaborative\n\n**Energy level:** Moderate - engaged but not intense\n**Key characteristic:** Solution-focused with some underlying concerns\n\n## Primary emotions\n\n- **Optimism**: Strong presence when discussing future possibilities\n- **Concern**: Moderate level around budget and timeline constraints  \n- **Frustration**: Mild, briefly when discussing past obstacles\n- **Enthusiasm**: Notable during creative brainstorming sections\n\n## Key observations\n\n- The conversation maintains a professional tone throughout\n- Shifts from cautious to more open as rapport builds\n- Underlying stress about resources balanced by excitement for the project\n- Team shows resilience when facing challenges\n\n## Summary\n\nOverall positive and productive tone with realistic acknowledgment of challenges. The discussion shows a healthy balance of enthusiasm and pragmatism, suggesting good team dynamics and realistic expectations.\n\nIdentify 3-5 main emotions with brief context. Keep analysis concise and practical.",
            category: TemplateCategory.personal.rawValue,
            isPremium: false,
            sortOrder: 10,
            version: 7
        )
    ]
}
