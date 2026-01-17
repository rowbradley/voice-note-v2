import Foundation

// MARK: - AI Result Types
enum AIResult: Sendable, Codable {
    case local(LocalAIResponse)
    case mock(MockAIResponse)

    var text: String {
        switch self {
        case .local(let response):
            return response.processedText
        case .mock(let response):
            return response.processedText
        }
    }

    var model: String? {
        switch self {
        case .local(let response):
            return response.modelVersion
        case .mock:
            return "mock"
        }
    }
}

struct LocalAIResponse: Sendable, Codable {
    let processedText: String
    let modelVersion: String
    let deviceProcessingTime: TimeInterval
}

struct MockAIResponse: Sendable, Codable {
    let processedText: String
}

// MARK: - Template Info for AI Processing
struct TemplateInfo: Sendable, Codable {
    let id: UUID
    let name: String
    let prompt: String

    init(id: UUID, name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }

    init(from template: Template) {
        self.id = template.id
        self.name = template.name
        self.prompt = template.prompt
    }
}

// MARK: - AI Service Protocol
protocol AIService: Sendable {
    func processTemplate(_ templateInfo: TemplateInfo, transcript: String) async throws -> AIResult
    func generateSummary(from transcript: String, maxLength: Int) async throws -> AIResult
    func generateTitle(from transcript: String) async throws -> AIResult
}

// MARK: - AI Error Types
enum AIError: LocalizedError, Sendable {
    case userCancelled
    case invalidTemplate(reason: String)
    case contentTooLong(maxTokens: Int)
    case processingTimeout
    case aiUnavailable(reason: String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Processing cancelled"
        case .invalidTemplate(let reason):
            return "Invalid template: \(reason)"
        case .contentTooLong(let maxTokens):
            return "Content too long (max \(maxTokens) tokens)"
        case .processingTimeout:
            return "Processing took too long"
        case .aiUnavailable(let reason):
            return "AI unavailable: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .userCancelled:
            return nil
        case .invalidTemplate:
            return "Please select a different template"
        case .contentTooLong:
            return "Try using a shorter recording or summary"
        case .processingTimeout:
            return "Try again with a simpler template"
        case .aiUnavailable:
            return "Enable Apple Intelligence in Settings to use templates"
        }
    }
}
