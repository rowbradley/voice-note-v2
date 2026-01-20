import Foundation
import FoundationModels

// MARK: - Markdown Convertible Protocol

/// All Generable template outputs must be convertible to markdown for display
protocol MarkdownConvertible {
    func toMarkdown() -> String
}

// MARK: - 1. CleanedTranscript (Cleanup template)

@Generable
struct CleanedTranscript: MarkdownConvertible {
    @Guide(description: "Break transcript into 3-8 paragraphs. Each paragraph: 2-4 sentences on one topic. Remove filler words (um, uh, like, you know). Fix punctuation. Preserve meaning.", .minimumCount(3), .maximumCount(8))
    var paragraphs: [String]

    func toMarkdown() -> String {
        paragraphs.joined(separator: "\n\n")
    }
}

// MARK: - 2. Summary (Smart Summary template)

@Generable
struct Summary: MarkdownConvertible {
    @Guide(description: "Main point in one sentence, max 25 words, with key terms that could be bolded")
    var coreMessage: String

    @Guide(description: "Key details from the transcript", .count(3))
    var keyDetails: [KeyDetail]

    func toMarkdown() -> String {
        """
        ## Core Message

        \(coreMessage)

        ## Key Details

        \(keyDetails.map { "- **\($0.label):** \($0.detail)" }.joined(separator: "\n"))
        """
    }
}

@Generable
struct KeyDetail {
    @Guide(description: "Topic name, 1-3 words")
    var label: String

    @Guide(description: "Brief explanation, one phrase")
    var detail: String
}

// MARK: - 3. Brainstorm (Brainstorm template)

@Generable
struct Brainstorm: MarkdownConvertible {
    @Guide(description: "Themes identified in the conversation", .minimumCount(1), .maximumCount(5))
    var themes: [Theme]

    func toMarkdown() -> String {
        let themesMarkdown = themes.map { theme in
            """
            ## \(theme.name)

            \(theme.ideas.map { "- \($0)" }.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n")

        let totalIdeas = themes.reduce(0) { $0 + $1.ideas.count }
        return """
        \(themesMarkdown)

        ---
        **Summary:** \(totalIdeas) ideas across \(themes.count) themes.
        """
    }
}

@Generable
struct Theme {
    @Guide(description: "Theme name, 1-4 words")
    var name: String

    @Guide(description: "Ideas belonging to this theme", .minimumCount(1), .maximumCount(5))
    var ideas: [String]
}

// MARK: - 4. ActionList (Action List template)

@Generable
struct ActionList: MarkdownConvertible {
    @Guide(description: "High priority tasks requiring immediate attention")
    var highPriority: [ActionItem]

    @Guide(description: "Normal priority tasks")
    var normalPriority: [ActionItem]

    @Guide(description: "Low priority tasks that can wait")
    var lowPriority: [ActionItem]

    func toMarkdown() -> String {
        var sections: [String] = []

        if !highPriority.isEmpty {
            sections.append("## High\n\n\(highPriority.map { $0.toMarkdown() }.joined(separator: "\n\n"))")
        }
        if !normalPriority.isEmpty {
            sections.append("## Normal\n\n\(normalPriority.map { $0.toMarkdown() }.joined(separator: "\n\n"))")
        }
        if !lowPriority.isEmpty {
            sections.append("## Low\n\n\(lowPriority.map { $0.toMarkdown() }.joined(separator: "\n\n"))")
        }

        return sections.isEmpty ? "No action items found." : sections.joined(separator: "\n\n")
    }
}

@Generable
struct ActionItem {
    @Guide(description: "Action verb + object, 3-7 words")
    var task: String

    @Guide(description: "Brief context or description")
    var itemDescription: String

    @Guide(description: "Person responsible, or 'Unassigned'")
    var owner: String

    @Guide(description: "Due date mentioned, or 'Not specified'")
    var due: String

    func toMarkdown() -> String {
        """
        - [ ] **\(task)** — \(itemDescription)
          Owner: \(owner)
          Due: \(due)
        """
    }
}

// MARK: - 5. IdeaOutline (Idea Outline template)

@Generable
struct IdeaOutline: MarkdownConvertible {
    @Guide(description: "Title summarizing the main topic, 3-8 words")
    var title: String

    @Guide(description: "Main sections of the outline", .minimumCount(2), .maximumCount(5))
    var sections: [OutlineSection]

    @Guide(description: "Key insight or takeaway in one sentence")
    var keyInsight: String

    func toMarkdown() -> String {
        let sectionsMarkdown = sections.enumerated().map { index, section in
            let roman = ["I", "II", "III", "IV", "V"][index]
            let points = section.points.map { "- \($0)" }.joined(separator: "\n")
            return "## \(roman). \(section.heading)\n\(points)"
        }.joined(separator: "\n\n")

        return """
        # \(title)

        \(sectionsMarkdown)

        ---
        **Key insight:** \(keyInsight)
        """
    }
}

@Generable
struct OutlineSection {
    @Guide(description: "Section heading, 2-5 words")
    var heading: String

    @Guide(description: "Key points in this section", .minimumCount(1), .maximumCount(4))
    var points: [String]
}

// MARK: - 6. KeyQuotes (Key Quotes template)

@Generable
struct KeyQuotes: MarkdownConvertible {
    @Guide(description: "Notable quotes from the transcript", .minimumCount(2), .maximumCount(5))
    var quotes: [Quote]

    func toMarkdown() -> String {
        let quotesMarkdown = quotes.map { quote in
            """
            ## "\(quote.text)"

            **Why it matters:** \(quote.significance)
            """
        }.joined(separator: "\n\n")

        let numberedList = quotes.enumerated().map { index, quote in
            "\(index + 1). \"\(quote.text)\""
        }.joined(separator: "\n")

        return """
        \(quotesMarkdown)

        ---
        \(numberedList)
        """
    }
}

@Generable
struct Quote {
    @Guide(description: "The quote text, lightly edited for clarity")
    var text: String

    @Guide(description: "Why this quote matters, one sentence")
    var significance: String
}

// MARK: - 7. NextQuestions (Next Questions template)

@Generable
struct NextQuestions: MarkdownConvertible {
    @Guide(description: "Follow-up questions to deepen understanding", .minimumCount(3), .maximumCount(5))
    var questions: [FollowUpQuestion]

    func toMarkdown() -> String {
        questions.map { q in
            """
            ## \(q.question)

            **Why it matters:** \(q.rationale)
            """
        }.joined(separator: "\n\n")
    }
}

@Generable
struct FollowUpQuestion {
    @Guide(description: "A thought-provoking question ending with ?")
    var question: String

    @Guide(description: "Why this question matters, one sentence")
    var rationale: String
}

// MARK: - 8. ToneAnalysis (Tone Analysis template)

@Generable
struct ToneAnalysis: MarkdownConvertible {
    @Guide(description: "Overall emotional tone", .anyOf(["Optimistic", "Neutral", "Concerned", "Excited", "Frustrated", "Confident", "Uncertain"]))
    var overallTone: String

    @Guide(description: "Energy level of the speaker", .anyOf(["High", "Moderate", "Low"]))
    var energyLevel: String

    @Guide(description: "Primary emotions detected", .minimumCount(2), .maximumCount(4))
    var emotions: [EmotionDetail]

    @Guide(description: "Notable pattern or observation about the tone")
    var keyObservation: String

    func toMarkdown() -> String {
        let emotionsMarkdown = emotions.map { "- \($0.emotion): \($0.context)" }.joined(separator: "\n")

        return """
        ## Overall: \(overallTone) — \(energyLevel) energy

        **Primary emotions:**
        \(emotionsMarkdown)

        **Key observation:** \(keyObservation)
        """
    }
}

@Generable
struct EmotionDetail {
    @Guide(description: "Emotion name")
    var emotion: String

    @Guide(description: "Context where this emotion appears")
    var context: String
}
