import Foundation
import os.log

// MARK: - Token Usage
struct TokenUsage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

// MARK: - Template Response Chunk
struct TemplateChunk: Codable, Sendable {
    let id: String?
    let content: String
    let isComplete: Bool
    let tokenUsage: TokenUsage?
}

// MARK: - Network Manager
actor NetworkManager {
    static let shared = NetworkManager()
    
    private let session: URLSession
    private let maxTokens = 6000
    private let logger = Logger(subsystem: "com.voicenote", category: "NetworkManager")
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 120.0
        config.httpMaximumConnectionsPerHost = 2 // Reduce from 4 to 2 for battery efficiency
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        // Battery optimization: reduce cellular data usage and connection overhead
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        config.isDiscretionary = false // Don't wait for better network conditions
        
        // HTTP/2 is enabled by default in modern URLSession
        
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Streaming Template Processing
    
    func streamTemplateProcessing(
        templateId: UUID,
        templatePrompt: String,
        transcript: String,
        token: String
    ) -> AsyncThrowingStream<TemplateChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Validate token count
                    let estimatedTokens = (templatePrompt.count + transcript.count) / 4
                    if estimatedTokens > maxTokens {
                        continuation.finish(throwing: AIError.contentTooLong(maxTokens: maxTokens))
                        return
                    }
                    
                    // Create request
                    guard let url = URL(string: "\(Config.backendURL)/api/process-template") else {
                        continuation.finish(throwing: AIError.networkUnavailable)
                        return
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    let body = [
                        "templateId": templateId.uuidString,
                        "templateName": "Template",
                        "prompt": templatePrompt,
                        "transcript": transcript
                    ] as [String: Any]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    // Make non-streaming request
                    let (data, response) = try await session.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.networkUnavailable)
                        return
                    }
                    
                    if httpResponse.statusCode == 429 {
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                            .flatMap { Double($0) } ?? 30
                        continuation.finish(throwing: AIError.retriable(
                            NSError(domain: "RateLimit", code: 429),
                            retryAfter: retryAfter
                        ))
                        return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
                        logger.error("Template processing error: \(httpResponse.statusCode) - \(errorData)")
                        continuation.finish(throwing: AIError.processingTimeout)
                        return
                    }
                    
                    // Parse response
                    let decoder = JSONDecoder()
                    let templateResponse = try decoder.decode(TemplateResponse.self, from: data)
                    
                    // Create chunk from response
                    let chunk = TemplateChunk(
                        id: templateResponse.templateId,
                        content: templateResponse.processedText,
                        isComplete: true,
                        tokenUsage: templateResponse.usage
                    )
                    
                    continuation.yield(chunk)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Non-Streaming Requests
    
    func generateSummary(
        transcript: String,
        maxLength: Int,
        token: String
    ) async throws -> CloudAIResponse {
        guard let url = URL(string: "\(Config.backendURL)/api/generate-summary") else {
            throw AIError.networkUnavailable
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "transcript": transcript,
            "maxLength": maxLength
        ] as [String: Any]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let startTime = Date()
        let (data, response) = try await session.data(for: request)
        let processingTime = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkUnavailable
        }
        
        try handleHTTPResponse(httpResponse)
        
        let result = try JSONDecoder().decode(SummaryResponse.self, from: data)
        
        return CloudAIResponse(
            processedText: result.summary,
            usage: result.usage,
            model: result.model ?? "gpt-4o-mini",
            processingTime: processingTime
        )
    }
    
    func generateTitle(
        transcript: String,
        token: String
    ) async throws -> CloudAIResponse {
        // TEMPORARY: Using summary endpoint until /api/generate-title is implemented
        guard let url = URL(string: "\(Config.backendURL)/api/generate-summary") else {
            logger.error("Invalid URL for title generation")
            throw AIError.networkUnavailable
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // TEMPORARY: Using summary format until title endpoint is available
        let body = [
            "transcript": transcript,
            "maxLength": 10  // Request very short summary to use as title
        ] as [String: Any]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        logger.debug("Sending request to \(url) with transcript length: \(transcript.count) chars")
        
        let startTime = Date()
        let (data, response) = try await session.data(for: request)
        let processingTime = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid HTTP response")
            throw AIError.networkUnavailable
        }
        
        logger.info("HTTP Status: \(httpResponse.statusCode), Processing time: \(processingTime)s")
        
        if let responseString = String(data: data, encoding: .utf8) {
            logger.debug("Raw response preview: \(responseString.prefix(200))")
        }
        
        try handleHTTPResponse(httpResponse)
        
        // TEMPORARY: Decode as SummaryResponse until title endpoint is available
        let result = try JSONDecoder().decode(SummaryResponse.self, from: data)
        
        // Clean up summary to use as title (remove trailing dots, limit length)
        let titleText = result.summary
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .prefix(7)
            .joined(separator: " ")
        
        logger.info("Decoded title: '\(titleText)', model: \(result.model ?? "unknown")")
        
        return CloudAIResponse(
            processedText: titleText,
            usage: result.usage,
            model: result.model ?? "gpt-4o-mini",
            processingTime: processingTime
        )
    }
    
    
    // MARK: - Helper Methods
    
    private func handleHTTPResponse(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw AIError.authenticationFailed(needsRefresh: true)
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) } ?? 30
            throw AIError.retriable(
                NSError(domain: "RateLimit", code: 429),
                retryAfter: retryAfter
            )
        case 500...599:
            throw AIError.retriable(
                NSError(domain: "ServerError", code: response.statusCode),
                retryAfter: nil
            )
        default:
            throw AIError.processingTimeout
        }
    }
}

// MARK: - Response Models
private struct SummaryResponse: Codable {
    let summary: String
    let usage: TokenUsage?
    let model: String?
}

private struct TitleResponse: Codable {
    let title: String
    let usage: TokenUsage?
    let model: String?
}

private struct TemplateResponse: Codable {
    let templateId: String
    let templateName: String
    let processedText: String
    let usage: TokenUsage?
    let model: String?
}

