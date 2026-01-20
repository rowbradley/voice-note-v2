import Foundation
import FoundationModels
import os.log

// MARK: - On-Device AI Service using Apple Foundation Models (iOS 26+)
actor OnDeviceAIService: AIService {
    private let logger = Logger(subsystem: "com.voicenote", category: "OnDeviceAIService")

    // Universal prefix for all template prompts - handles transcript quality issues
    private let transcriptQualityNote = """
        Note: This is an automated transcript. Interpret meaning contextually,
        not literally. Fix obvious errors silently while preserving intent.
        """

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

    // MARK: - Transcript Cleanup (Pro Feature)

    /// Cleans up a raw transcript by removing filler words, fixing punctuation,
    /// and adding paragraph breaks while preserving the speaker's original words.
    func cleanupTranscript(_ rawText: AttributedString) async throws -> AttributedString {
        guard checkAvailability() == .available else {
            logger.info("Apple Intelligence not available, returning raw text")
            return rawText
        }

        let prompt = """
        Clean up this voice transcript. Output ONLY the cleaned transcript text.

        Rules:
        1. Remove filler words (um, uh, like, you know, I mean)
        2. Remove false starts and stutters
        3. Fix punctuation and capitalization
        4. Add paragraph breaks at natural topic transitions
        5. DO NOT rephrase, summarize, or change the speaker's actual words
        6. DO NOT include any preamble, introduction, or commentary
        7. DO NOT say "Here is", "Sure", "The cleaned transcript is", etc.
        8. Start directly with the transcript content

        Transcript to clean:
        \(String(rawText.characters))
        """

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            logger.info("Transcript cleanup completed: \(response.content.count) chars")
            return AttributedString(response.content)
        } catch {
            logger.error("Transcript cleanup failed: \(error)")
            throw error
        }
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

            // Pass limited previous result as context to prevent drift
            let context = combinedResult.isEmpty ? nil : limitedContext(combinedResult, maxWords: 200)
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
        // Role-first instruction assembly per Apple guidelines
        let instructions = """
            \(templateInfo.prompt)

            Note: Input is an automated transcript. Fix obvious errors silently.
            """
        let session = LanguageModelSession(instructions: instructions)

        let prompt: String
        if let context = previousContext {
            prompt = "Previous context:\n\(context)\n\nContinue processing this transcript:\n\(chunk)"
        } else {
            // Explicit transcript framing to prevent meaning drift
            prompt = """
                Process this transcript exactly as instructed:
                ---
                \(chunk)
                ---
                Output the processed version only. Do not add commentary or change meaning.
                """
        }

        // Helper for Generable calls with string fallback
        func tryGenerable<T: Generable & MarkdownConvertible>(_ type: T.Type) async throws -> String {
            do {
                let response = try await session.respond(to: prompt, generating: type)
                let markdown = response.content.toMarkdown()
                logger.info("✅ Generable succeeded for \(templateInfo.name): \(markdown.count) chars")
                return markdown
            } catch {
                logger.warning("⚠️ Generable failed for \(templateInfo.name), falling back to string: \(error)")
                let response = try await session.respond(to: prompt)
                return response.content
            }
        }

        // Route to appropriate Generable based on template name
        logger.info("Template routing: '\(templateInfo.name)' → checking for Generable type")
        switch templateInfo.name {
        case "Cleanup":
            logger.info("Using CleanedTranscript Generable for constrained decoding")
            return try await tryGenerable(CleanedTranscript.self)

        case "Smart Summary":
            return try await tryGenerable(Summary.self)

        case "Brainstorm":
            return try await tryGenerable(Brainstorm.self)

        case "Action List":
            return try await tryGenerable(ActionList.self)

        case "Idea Outline":
            return try await tryGenerable(IdeaOutline.self)

        case "Key Quotes":
            return try await tryGenerable(KeyQuotes.self)

        case "Next Questions":
            return try await tryGenerable(NextQuestions.self)

        case "Tone Analysis":
            return try await tryGenerable(ToneAnalysis.self)

        default:
            // Fallback for custom templates: use string response
            let response = try await session.respond(to: prompt)

            // Debug: Log newline presence in AI output
            let newlineCount = response.content.components(separatedBy: "\n\n").count - 1
            logger.info("AI response: \(response.content.count) chars, \(newlineCount) paragraph breaks (\\n\\n)")
            if newlineCount == 0 {
                logger.warning("⚠️ AI output has NO paragraph breaks - may appear as wall of text")
            }

            return response.content
        }
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

    private func limitedContext(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        guard words.count > maxWords else { return text }
        return "..." + words.suffix(maxWords).joined(separator: " ")
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
