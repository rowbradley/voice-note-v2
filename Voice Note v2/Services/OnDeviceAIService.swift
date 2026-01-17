import Foundation
import FoundationModels
import os.log

// MARK: - On-Device AI Service using Apple Foundation Models (iOS 26+)
actor OnDeviceAIService: AIService {
    private let logger = Logger(subsystem: "com.voicenote", category: "OnDeviceAIService")

    // MARK: - Availability State

    enum AvailabilityState: Sendable {
        case available
        case notEligible      // Device doesn't support Apple Intelligence
        case notEnabled       // User hasn't enabled in Settings
        case modelNotReady    // Model still downloading
    }

    func checkAvailability() -> AvailabilityState {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .notEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        @unknown default:
            return .notEligible
        }
    }

    // MARK: - AIService Protocol

    func processTemplate(_ templateInfo: TemplateInfo, transcript: String) async throws -> AIResult {
        let startTime = Date()

        guard checkAvailability() == .available else {
            logger.info("Apple Intelligence not available, using fallback formatting")
            let result = formatWithoutAI(templateInfo, transcript)
            return .local(LocalAIResponse(
                processedText: result,
                modelVersion: "fallback",
                deviceProcessingTime: Date().timeIntervalSince(startTime)
            ))
        }

        do {
            logger.info("Processing template '\(templateInfo.name)' with on-device AI")
            let result = try await processWithChunking(transcript, templateInfo: templateInfo)
            logger.info("Template processing completed: \(result.count) chars")

            return .local(LocalAIResponse(
                processedText: result,
                modelVersion: "apple-intelligence",
                deviceProcessingTime: Date().timeIntervalSince(startTime)
            ))
        } catch {
            logger.error("On-device AI failed: \(error), using fallback")
            let result = formatWithoutAI(templateInfo, transcript)
            return .local(LocalAIResponse(
                processedText: result,
                modelVersion: "fallback",
                deviceProcessingTime: Date().timeIntervalSince(startTime)
            ))
        }
    }

    func generateSummary(from transcript: String, maxLength: Int) async throws -> AIResult {
        let startTime = Date()

        guard checkAvailability() == .available else {
            // Simple fallback: first N words
            let words = transcript.split(separator: " ")
            let summary = words.prefix(maxLength / 5).joined(separator: " ") + "..."
            return .local(LocalAIResponse(
                processedText: summary,
                modelVersion: "fallback",
                deviceProcessingTime: Date().timeIntervalSince(startTime)
            ))
        }

        do {
            let session = LanguageModelSession(instructions: """
                Create a concise summary of the transcript. Keep it under \(maxLength) characters.
                Focus on the main points and key takeaways.
                """)

            let response = try await session.respond(to: transcript)
            return .local(LocalAIResponse(
                processedText: response.content,
                modelVersion: "apple-intelligence",
                deviceProcessingTime: Date().timeIntervalSince(startTime)
            ))
        } catch {
            logger.error("Summary generation failed: \(error)")
            let words = transcript.split(separator: " ")
            let summary = words.prefix(maxLength / 5).joined(separator: " ") + "..."
            return .local(LocalAIResponse(
                processedText: summary,
                modelVersion: "fallback",
                deviceProcessingTime: Date().timeIntervalSince(startTime)
            ))
        }
    }

    func generateTitle(from transcript: String) async throws -> AIResult {
        let startTime = Date()

        // Title generation uses simple first-line extraction (no AI needed)
        // This matches the existing behavior in RecordingManager
        let firstLine = transcript
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let title: String
        if firstLine.count > 50 {
            title = String(firstLine.prefix(47)) + "..."
        } else if !firstLine.isEmpty {
            title = firstLine
        } else {
            title = "Voice Note"
        }

        return .local(LocalAIResponse(
            processedText: title,
            modelVersion: "local",
            deviceProcessingTime: Date().timeIntervalSince(startTime)
        ))
    }

    // MARK: - Chunking for Long Transcripts (Apple TN3193)

    /// Apple's recommended pattern: split into chunks, process each in separate session,
    /// combine results. Preserves context by passing previous summary to next chunk.
    private func processWithChunking(_ transcript: String, templateInfo: TemplateInfo) async throws -> String {
        let chunks = splitIntoChunks(transcript, maxWords: 1500)  // Leave room for instructions + response

        guard chunks.count > 1 else {
            // Single chunk, process normally
            return try await processSingleChunk(chunks[0], templateInfo: templateInfo, previousContext: nil)
        }

        logger.info("Processing \(chunks.count) chunks for long transcript")

        var combinedResult = ""
        for (index, chunk) in chunks.enumerated() {
            logger.debug("Processing chunk \(index + 1)/\(chunks.count)")

            // Pass previous result as context (Apple's recommendation)
            let context = combinedResult.isEmpty ? nil : combinedResult
            let chunkResult = try await processSingleChunk(chunk, templateInfo: templateInfo, previousContext: context)

            if index == chunks.count - 1 {
                // Final chunk - this is the combined result
                combinedResult = chunkResult
            } else {
                // Intermediate chunk - accumulate for context
                combinedResult += (combinedResult.isEmpty ? "" : "\n\n") + chunkResult
            }
        }

        return combinedResult
    }

    private func processSingleChunk(_ chunk: String, templateInfo: TemplateInfo, previousContext: String?) async throws -> String {
        // New session per chunk (Apple's recommendation)
        let session = LanguageModelSession(instructions: templateInfo.prompt)

        let prompt: String
        if let context = previousContext {
            prompt = "Previous context:\n\(context)\n\nContinue processing this transcript:\n\(chunk)"
        } else {
            prompt = chunk
        }

        let response = try await session.respond(to: prompt)
        return response.content
    }

    private func splitIntoChunks(_ text: String, maxWords: Int) -> [String] {
        let words = text.split(separator: " ")
        guard words.count > maxWords else { return [text] }

        var chunks: [String] = []
        var currentChunk: [Substring] = []

        for word in words {
            currentChunk.append(word)
            if currentChunk.count >= maxWords {
                chunks.append(currentChunk.joined(separator: " "))
                currentChunk = []
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }

        return chunks
    }

    // MARK: - Fallback Formatting

    private func formatWithoutAI(_ templateInfo: TemplateInfo, _ transcript: String) -> String {
        // Simple markdown formatting when AI is not available
        return """
        # \(templateInfo.name)

        \(transcript)

        ---
        *Note: AI processing unavailable. Raw transcript shown.*
        """
    }
}
