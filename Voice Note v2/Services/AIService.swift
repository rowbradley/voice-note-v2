import Foundation

// MARK: - AI Result Types
enum AIResult: Sendable, Codable {
    case cloud(CloudAIResponse)
    case local(LocalAIResponse)
    case mock(MockAIResponse)
    
    var text: String {
        switch self {
        case .cloud(let response):
            return response.processedText
        case .local(let response):
            return response.processedText
        case .mock(let response):
            return response.processedText
        }
    }
    
    var model: String? {
        switch self {
        case .cloud(let response):
            return response.model
        case .local(let response):
            return response.modelVersion
        case .mock:
            return "mock"
        }
    }
}

struct CloudAIResponse: Sendable, Codable {
    let processedText: String
    let usage: TokenUsage?
    let model: String
    let processingTime: TimeInterval
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
    case retriable(Error, retryAfter: TimeInterval?)
    case quotaExceeded(resetDate: Date)
    case userCancelled
    case networkUnavailable
    case invalidTemplate(reason: String)
    case authenticationFailed(needsRefresh: Bool)
    case contentTooLong(maxTokens: Int)
    case processingTimeout
    
    var errorDescription: String? {
        switch self {
        case .retriable(let error, _):
            return "Processing failed: \(error.localizedDescription)"
        case .quotaExceeded:
            return "Daily template limit reached"
        case .userCancelled:
            return "Processing cancelled"
        case .networkUnavailable:
            return "No internet connection available"
        case .invalidTemplate(let reason):
            return "Invalid template: \(reason)"
        case .authenticationFailed:
            return "Authentication failed"
        case .contentTooLong(let maxTokens):
            return "Content too long (max \(maxTokens) tokens)"
        case .processingTimeout:
            return "Processing took too long"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .retriable(_, let retryAfter):
            if let retry = retryAfter {
                return "Please try again in \(Int(retry)) seconds"
            }
            return "Please try again"
        case .quotaExceeded(let reset):
            return "Template limit resets \(reset.formatted(date: .abbreviated, time: .shortened))"
        case .userCancelled:
            return nil
        case .networkUnavailable:
            return "Check your internet connection and try again"
        case .invalidTemplate:
            return "Please select a different template"
        case .authenticationFailed(let needsRefresh):
            return needsRefresh ? "Please sign in again" : "Please check your account"
        case .contentTooLong:
            return "Try using a shorter recording or summary"
        case .processingTimeout:
            return "Try again with a simpler template"
        }
    }
}