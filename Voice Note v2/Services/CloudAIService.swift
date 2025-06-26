import Foundation
import os.log


// MARK: - Cloud AI Service
actor CloudAIService: AIService {
    private let jwtManager: JWTManager
    private let networkManager = NetworkManager.shared
    private let logger = Logger(subsystem: "com.voicenote", category: "CloudAIService")
    
    // Request deduplication
    private var activeRequests: Set<String> = []
    
    init(jwtManager: JWTManager) {
        self.jwtManager = jwtManager
    }
    
    // MARK: - AIService Protocol
    
    func processTemplate(_ templateInfo: TemplateInfo, transcript: String) async throws -> AIResult {
        let requestKey = "\(templateInfo.id)_\(transcript.hashValue)"
        
        // Check for duplicate request
        if activeRequests.contains(requestKey) {
            logger.warning("Duplicate template request detected")
            throw AIError.retriable(
                NSError(domain: "DuplicateRequest", code: 409),
                retryAfter: 1
            )
        }
        
        activeRequests.insert(requestKey)
        defer { activeRequests.remove(requestKey) }
        
        // Get valid token
        let token = try await jwtManager.getValidToken()
        
        // Track performance
        let signpost = OSSignposter(subsystem: "com.voicenote", category: "TemplateProcessing")
        let signpostID = signpost.makeSignpostID()
        let state = signpost.beginInterval("ProcessTemplate", id: signpostID)
        defer { signpost.endInterval("ProcessTemplate", state) }
        
        // Stream template processing
        let stream = await networkManager.streamTemplateProcessing(
            templateId: templateInfo.id,
            templatePrompt: templateInfo.prompt,
            transcript: transcript,
            token: token
        )
        
        var fullResponse = ""
        var tokenUsage: TokenUsage?
        let startTime = Date()
        
        for try await chunk in stream {
            fullResponse += chunk.content
            if let usage = chunk.tokenUsage {
                tokenUsage = usage
            }
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        #if DEBUG
        logger.info("Template processed in \(processingTime)s, tokens: \(tokenUsage?.totalTokens ?? 0)")
        #endif
        
        // AI now outputs natural markdown, no post-processing needed
        return .cloud(CloudAIResponse(
            processedText: fullResponse,
            usage: tokenUsage,
            model: "gpt-4o-mini",
            processingTime: processingTime
        ))
    }
    
    func generateSummary(from transcript: String, maxLength: Int) async throws -> AIResult {
        let requestKey = "summary_\(transcript.hashValue)_\(maxLength)"
        
        // Check for duplicate request
        if activeRequests.contains(requestKey) {
            logger.warning("Duplicate summary request detected")
            throw AIError.retriable(
                NSError(domain: "DuplicateRequest", code: 409),
                retryAfter: 1
            )
        }
        
        activeRequests.insert(requestKey)
        defer { activeRequests.remove(requestKey) }
        
        // Get valid token
        let token = try await jwtManager.getValidToken()
        
        // Make request with retry logic
        let response = try await performWithRetry {
            try await self.networkManager.generateSummary(
                transcript: transcript,
                maxLength: maxLength,
                token: token
            )
        }
        
        return .cloud(response)
    }
    
    func generateTitle(from transcript: String) async throws -> AIResult {
        logger.debug("Title generation called. Transcript length: \(transcript.count) chars")
        
        // Get first sentence approach (no AI involved)
        let cleanedTranscript = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Find first sentence by looking for sentence endings
        let sentenceEndings = [".", "!", "?", ":", "..."]
        var firstSentence = cleanedTranscript
        
        for ending in sentenceEndings {
            if let range = cleanedTranscript.range(of: ending) {
                let endIndex = cleanedTranscript.index(range.lowerBound, offsetBy: ending.count)
                let potentialSentence = String(cleanedTranscript[..<endIndex])
                if potentialSentence.count >= 10 { // Minimum sentence length
                    firstSentence = potentialSentence
                    break
                }
            }
        }
        
        // If no sentence ending found or sentence too long, use first 50 characters
        if firstSentence == cleanedTranscript || firstSentence.count > 100 {
            let charLimit = min(60, cleanedTranscript.count)
            firstSentence = String(cleanedTranscript.prefix(charLimit))
            if cleanedTranscript.count > charLimit {
                firstSentence += "..."
            }
        }
        
        let title = firstSentence.isEmpty ? "Untitled Note" : firstSentence
        
        let response = LocalAIResponse(
            processedText: title,
            modelVersion: "first-sentence",
            deviceProcessingTime: 0.0
        )
        
        logger.info("Local title generated: '\(title)' (format: first sentence)")
        return .local(response)
    }
    
    // MARK: - Retry Logic
    
    private func performWithRetry<T>(
        maxRetries: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await operation()
            } catch let error as AIError {
                lastError = error
                
                switch error {
                case .retriable(_, let retryAfter):
                    let delay = retryAfter ?? Double(attempt * attempt)
                    logger.info("Retrying in \(delay)s (attempt \(attempt)/\(maxRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                case .quotaExceeded:
                    throw error // Don't retry quota errors
                    
                case .authenticationFailed(let needsRefresh) where needsRefresh && attempt < maxRetries:
                    logger.info("Token expired, refreshing...")
                    continue
                    
                default:
                    throw error
                }
            } catch {
                lastError = error
                
                if attempt < maxRetries {
                    let delay = Double(attempt) * 2.0
                    logger.info("Request failed, retrying in \(delay)s (attempt \(attempt)/\(maxRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }
        
        throw lastError ?? AIError.processingTimeout
    }
}
