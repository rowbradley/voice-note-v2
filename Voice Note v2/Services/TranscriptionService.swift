import Foundation
import Speech
import AVFoundation
import os.log

/// File-based transcription service using iOS 26+ SpeechAnalyzer API
/// For live transcription, use LiveTranscriptionService instead
class TranscriptionService {
    private let logger = Logger(subsystem: "com.voicenote", category: "Transcription")

    init() {
        // No setup needed - SpeechAnalyzer handles everything
    }

    func transcribe(audioURL: URL, progressCallback: ((String) -> Void)? = nil) async throws -> String {
        logger.info("TranscriptionService.transcribe() called with URL: \(audioURL)")

        // Check if file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            logger.error("Audio file does not exist at path: \(audioURL.path)")
            throw TranscriptionError.invalidResponse
        }

        // Log file info for debugging
        await logFileInfo(audioURL: audioURL)

        // Perform transcription
        progressCallback?("Transcribing...")

        logger.info("Starting SpeechAnalyzer transcription...")

        do {
            let result = try await performTranscription(audioURL: audioURL)

            if result.isEmpty {
                logger.info("⚠️ Transcription returned empty result")
                throw TranscriptionError.invalidResponse
            }

            logger.info("✅ Transcription succeeded with \(result.count) characters")
            return result

        } catch let error as TranscriptionError {
            throw error
        } catch {
            logger.error("❌ Transcription failed: \(error)")
            throw TranscriptionError.recognitionFailed(error)
        }
    }

    private func performTranscription(audioURL: URL) async throws -> String {
        logger.info("🔐 Starting SpeechAnalyzer transcription")

        // Get supported locale
        guard let locale = await getSupportedLocale() else {
            logger.error("❌ No supported locale found")
            throw TranscriptionError.speechRecognitionUnavailable
        }

        logger.info("📝 Using locale: \(locale.identifier)")

        // Create transcriber for file-based transcription
        // Using full initializer with empty options:
        // - reportingOptions: [] = only final results (no volatile/in-progress text)
        // - attributeOptions: [] = just text (no word-level timing metadata)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Check if model is available
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status == .installed else {
            logger.error("❌ Transcription model not installed. Status: \(String(describing: status))")
            throw TranscriptionError.speechRecognitionUnavailable
        }

        logger.info("✅ Transcription model is installed")

        // Create analyzer with high priority for user-initiated transcription
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: options)

        // Start collecting results in parallel with analysis
        // Use reduce to concatenate all final results
        async let transcriptionFuture: String = transcriber.results.reduce("") { accumulated, result in
            // Only append finalized text (ignore volatile results for file transcription)
            if result.isFinal {
                let text = String(result.text.characters)
                return accumulated.isEmpty ? text : accumulated + " " + text
            }
            return accumulated
        }

        logger.info("🚀 Starting analysis of audio file...")

        // Open the audio file - SpeechAnalyzer.analyzeSequence requires AVAudioFile, not URL
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: audioURL)
            logger.info("📁 Opened audio file: \(audioFile.length) frames, \(audioFile.fileFormat.sampleRate)Hz")
        } catch {
            logger.error("❌ Failed to open audio file: \(error)")
            throw TranscriptionError.recognitionFailed(error)
        }

        // Analyze the audio file
        let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile)

        // Finalize to ensure all results are processed
        if let lastSampleTime {
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        }

        logger.info("✅ Analysis complete, collecting results...")

        // Get the accumulated transcript
        let transcript = try await transcriptionFuture

        // Clean up whitespace
        let cleanedTranscript = transcript
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        logger.info("📝 Final transcript: \(cleanedTranscript.count) characters")

        return cleanedTranscript
    }

    /// Get a supported locale for transcription
    private func getSupportedLocale() async -> Locale? {
        // Try current locale first
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
            return locale
        }
        // Fall back to en-US
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }

    /// Log file information for debugging
    private func logFileInfo(audioURL: URL) async {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let fileSize = attributes[.size] as? NSNumber
            logger.info("Audio file size: \(fileSize?.intValue ?? 0) bytes")

            // Check audio duration and format
            let asset = AVURLAsset(url: audioURL)
            let duration = try await asset.load(.duration).seconds
            logger.info("Audio duration: \(duration) seconds")

            let tracks = try? await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = tracks?.first {
                let formats = try? await audioTrack.load(.formatDescriptions)
                logger.debug("Audio format: \(String(describing: formats ?? []))")
            }
        } catch {
            logger.warning("Could not get file attributes: \(error)")
        }
    }

    // MARK: - Transcription Quality Detection

    func isTranscriptionPoor(_ transcript: String, duration: TimeInterval) -> Bool {
        // Check if transcript is empty
        if transcript.isEmpty {
            return true
        }

        // Check if transcript is suspiciously short
        let words = transcript.split(separator: " ").count
        if words < 3 && duration > 3.0 {
            // Less than 3 words for recordings longer than 3 seconds
            return true
        }

        // Check words per minute ratio
        let wordsPerMinute = Double(words) / (duration / 60.0)
        if wordsPerMinute < 20 && duration > 5.0 {
            // Less than 20 words per minute is suspiciously low
            return true
        }

        // Check for repetitive patterns (iOS sometimes gets stuck)
        let components = transcript.components(separatedBy: " ")
        if components.count > 3 {
            let uniqueWords = Set(components)
            let uniqueRatio = Double(uniqueWords.count) / Double(components.count)
            if uniqueRatio < 0.3 {
                // Less than 30% unique words indicates repetition
                return true
            }
        }

        return false
    }
}

enum TranscriptionError: LocalizedError {
    case speechRecognitionUnavailable
    case recognitionFailed(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available"
        case .recognitionFailed(let error):
            return "Recognition failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from transcription service"
        }
    }
}
