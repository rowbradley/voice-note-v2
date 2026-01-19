import Speech
import AVFoundation
import os

/// Unified transcription using native iOS 26 APIs
/// Auto-selects best available: SpeechTranscriber (Apple Intelligence) → DictationTranscriber
@MainActor
@Observable
final class UnifiedTranscriptionService {

    // MARK: - Tier Detection

    enum TranscriptionTier: Sendable {
        case premium   // SpeechTranscriber (Apple Intelligence)
        case standard  // DictationTranscriber (all iOS 26+ devices)

        var displayName: String {
            switch self {
            case .premium: return "Apple Intelligence"
            case .standard: return "Standard"
            }
        }
    }

    // MARK: - Public State

    /// Detected transcription tier
    private(set) var tier: TranscriptionTier = .standard

    /// Whether the service is prepared and ready to transcribe
    private(set) var isReady: Bool = false

    /// Whether the on-device model is downloaded
    private(set) var isModelDownloaded: Bool = false

    /// Current volatile (in-progress) transcript text - may change
    private(set) var volatileText: String = ""

    /// Finalized (confirmed) transcript text - won't change
    private(set) var finalizedText: String = ""

    /// Combined display text (finalized + volatile)
    var displayText: String {
        let combined = finalizedText + (volatileText.isEmpty ? "" : " " + volatileText)
        return combined.trimmingCharacters(in: .whitespaces)
    }

    /// Whether transcription is currently active
    private(set) var isTranscribing: Bool = false

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.voicenote", category: "UnifiedTranscription")

    // Cached components for low-latency startup
    private var cachedLocale: Locale?
    private var cachedFormat: AVAudioFormat?
    private var cachedAnalyzer: SpeechAnalyzer?

    // Module storage - we need to keep a reference to iterate results
    private var speechTranscriber: SpeechTranscriber?
    private var dictationTranscriber: DictationTranscriber?

    // Task tracking
    private var transcriptionTask: Task<Void, Never>?
    private var bufferTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    // MARK: - Initialization

    init() {
        Task {
            await detectTier()
        }
    }

    /// Detect best available transcription tier
    private func detectTier() async {
        tier = SpeechTranscriber.isAvailable ? .premium : .standard
        logger.info("Detected transcription tier: \(self.tier.displayName)")
    }

    /// Check if transcription is available on this device
    var isAvailable: Bool {
        // DictationTranscriber should be available on all iOS 26+ devices
        // SpeechTranscriber requires Apple Intelligence
        return true // iOS 26+ always has at least DictationTranscriber
    }

    // MARK: - Preparation

    /// Prepare the transcription service for low-latency startup
    /// Call this at app launch or before recording starts
    func prepare(locale: Locale = .current) async throws {
        logger.info("Preparing transcription service...")

        // Detect tier
        tier = SpeechTranscriber.isAvailable ? .premium : .standard
        logger.info("Using tier: \(self.tier.displayName)")

        // Get supported locale based on tier
        let supportedLocale: Locale
        if tier == .premium {
            // Try current locale, then fall back to en-US
            if let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                supportedLocale = loc
            } else if let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) {
                supportedLocale = loc
            } else {
                throw UnifiedTranscriptionError.localeNotSupported(locale)
            }
        } else {
            // Try current locale, then fall back to en-US
            if let loc = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
                supportedLocale = loc
            } else if let loc = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) {
                supportedLocale = loc
            } else {
                throw UnifiedTranscriptionError.localeNotSupported(locale)
            }
        }
        cachedLocale = supportedLocale
        logger.info("Using locale: \(supportedLocale.identifier)")

        // Create appropriate module
        let modules: [any SpeechModule]
        switch tier {
        case .premium:
            let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveLiveTranscription)
            speechTranscriber = transcriber
            dictationTranscriber = nil
            modules = [transcriber]
        case .standard:
            let transcriber = DictationTranscriber(locale: supportedLocale, preset: .progressiveLiveTranscription)
            dictationTranscriber = transcriber
            speechTranscriber = nil
            modules = [transcriber]
        }

        // Check and download model if needed
        let status = await AssetInventory.status(forModules: modules)
        if status != .installed {
            logger.info("Model not installed, requesting download...")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
        }
        isModelDownloaded = true

        // Get best audio format
        cachedFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: nil
        )
        if let format = cachedFormat {
            logger.info("Cached format: \(format.sampleRate)Hz, \(format.commonFormat.rawValue)")
        }

        // Create analyzer with preheat
        let options = SpeechAnalyzer.Options(
            priority: .userInitiated,
            modelRetention: .processLifetime
        )
        let analyzer = SpeechAnalyzer(modules: modules, options: options)

        // Preheat the analyzer
        if let format = cachedFormat {
            try await analyzer.prepareToAnalyze(in: format)
        }
        cachedAnalyzer = analyzer

        isReady = true
        logger.info("Transcription service ready (\(self.tier.displayName))")
    }

    /// Get the audio format required by the transcription engine
    var requiredFormat: AVAudioFormat? { cachedFormat }

    // MARK: - Transcription

    /// Start transcription from audio buffer stream
    /// - Parameters:
    ///   - buffers: AsyncStream of audio buffers with timestamps from LiveAudioService
    ///   - format: The audio format of the buffers
    func startTranscribing(buffers: AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>, format: AVAudioFormat) async {
        guard isReady else {
            logger.error("Service not prepared. Call prepare() first.")
            return
        }

        // Reset state
        volatileText = ""
        finalizedText = ""
        isTranscribing = true

        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("Starting transcription (\(self.tier.displayName))...")

        // Use cached or create fresh components
        let analyzer: SpeechAnalyzer
        if let cached = cachedAnalyzer {
            analyzer = cached
            logger.info("Using cached analyzer")
        } else {
            logger.warning("No cached analyzer, creating fresh")
            guard let locale = cachedLocale else {
                logger.error("No cached locale")
                isTranscribing = false
                return
            }

            let modules: [any SpeechModule]
            if tier == .premium {
                let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveLiveTranscription)
                speechTranscriber = transcriber
                modules = [transcriber]
            } else {
                let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLiveTranscription)
                dictationTranscriber = transcriber
                modules = [transcriber]
            }

            let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
            analyzer = SpeechAnalyzer(modules: modules, options: options)
        }

        transcriptionTask = Task {
            do {
                // Create input sequence
                let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                self.inputContinuation = continuation

                continuation.onTermination = { @Sendable [weak self] _ in
                    Task { @MainActor in
                        self?.logger.debug("AnalyzerInput stream terminated")
                    }
                }

                // Get target format
                let targetFormat: AVAudioFormat
                if let cached = self.cachedFormat {
                    targetFormat = cached
                } else {
                    var modules: [any SpeechModule] = []
                    if self.tier == .premium, let transcriber = self.speechTranscriber {
                        modules = [transcriber]
                    } else if let transcriber = self.dictationTranscriber {
                        modules = [transcriber]
                    }

                    guard !modules.isEmpty,
                          let computed = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: modules,
                        considering: format
                    ) else {
                        self.logger.error("No compatible audio format")
                        continuation.finish()
                        return
                    }
                    targetFormat = computed
                }

                // Create converter if needed
                let needsConversion = format.sampleRate != targetFormat.sampleRate ||
                                      format.commonFormat != targetFormat.commonFormat
                let converter: AudioFormatConverter? = needsConversion ?
                    AudioFormatConverter(from: format, to: targetFormat) : nil

                if needsConversion {
                    self.logger.info("Audio conversion: \(format.sampleRate)Hz → \(targetFormat.sampleRate)Hz")
                }

                // First buffer synchronization
                let firstBufferSignal = AsyncStream<Void>.makeStream()
                var firstBufferContinuation: AsyncStream<Void>.Continuation? = firstBufferSignal.1

                // Feed buffers to analyzer
                self.bufferTask = Task {
                    var bufferCount = 0
                    for await (buffer, _) in buffers {
                        guard !Task.isCancelled else { break }

                        let outputBuffer: AVAudioPCMBuffer
                        if let converter = converter {
                            do {
                                outputBuffer = try converter.convert(buffer)
                            } catch {
                                self.logger.error("Buffer conversion failed: \(error)")
                                continue
                            }
                        } else {
                            outputBuffer = buffer
                        }

                        let input = AnalyzerInput(buffer: outputBuffer)
                        continuation.yield(input)
                        bufferCount += 1

                        if bufferCount == 1 {
                            firstBufferContinuation?.yield()
                            firstBufferContinuation?.finish()
                            firstBufferContinuation = nil
                        }

                        if bufferCount % 50 == 0 {
                            self.logger.debug("Fed \(bufferCount) buffers")
                        }
                    }
                    self.logger.info("Buffer stream ended after \(bufferCount) buffers")
                    firstBufferContinuation?.finish()
                    continuation.finish()
                }

                // Consume results based on tier
                self.resultsTask = Task {
                    do {
                        var accumulatedText = ""

                        // Use the appropriate transcriber's results
                        if self.tier == .premium, let transcriber = self.speechTranscriber {
                            for try await result in transcriber.results {
                                guard !Task.isCancelled else { break }
                                self.processResult(result, accumulatedText: &accumulatedText)
                            }
                        } else if let transcriber = self.dictationTranscriber {
                            for try await result in transcriber.results {
                                guard !Task.isCancelled else { break }
                                self.processResult(result, accumulatedText: &accumulatedText)
                            }
                        }

                        self.logger.info("Results stream ended")
                    } catch {
                        self.logger.error("Results stream error: \(error)")
                    }
                }

                // Wait for first buffer
                for await _ in firstBufferSignal.0 {
                    break
                }
                self.logger.info("[T+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))] Starting analysis")

                // Start analysis
                let lastSampleTime = try await analyzer.analyzeSequence(inputSequence)

                if let lastSampleTime {
                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                }

                self.logger.info("Transcription analysis completed")

            } catch {
                self.logger.error("Transcription error: \(error)")
            }

            await MainActor.run {
                self.isTranscribing = false
            }
        }
    }

    /// Process a transcription result (works for both SpeechTranscriber and DictationTranscriber results)
    private func processResult(_ result: SpeechTranscriber.Result, accumulatedText: inout String) {
        let text = String(result.text.characters)

        if result.isFinal {
            if !text.isEmpty {
                accumulatedText += (accumulatedText.isEmpty ? "" : " ") + text
            }
            finalizedText = accumulatedText
            volatileText = ""
            logger.debug("FINALIZED: '\(text.prefix(30))...'")
        } else {
            volatileText = text
            logger.debug("VOLATILE: '\(text.prefix(30))...'")
        }
    }

    /// Process a transcription result from DictationTranscriber
    private func processResult(_ result: DictationTranscriber.Result, accumulatedText: inout String) {
        let text = String(result.text.characters)

        if result.isFinal {
            if !text.isEmpty {
                accumulatedText += (accumulatedText.isEmpty ? "" : " ") + text
            }
            finalizedText = accumulatedText
            volatileText = ""
            logger.debug("FINALIZED: '\(text.prefix(30))...'")
        } else {
            volatileText = text
            logger.debug("VOLATILE: '\(text.prefix(30))...'")
        }
    }

    /// Stop transcription and return the final transcript
    func stopTranscribing() async -> String {
        logger.info("Stopping transcription...")

        // Signal end of input
        inputContinuation?.finish()
        inputContinuation = nil

        // Wait for transcription to complete
        await transcriptionTask?.value
        transcriptionTask = nil

        // Cancel child tasks
        bufferTask?.cancel()
        resultsTask?.cancel()
        bufferTask = nil
        resultsTask = nil

        isTranscribing = false

        // Build final transcript
        let finalTranscript = finalizedText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        logger.info("Final transcript: \(finalTranscript.count) characters")

        // Invalidate analyzer (can't be reused after analyzeSequence)
        cachedAnalyzer = nil
        speechTranscriber = nil
        dictationTranscriber = nil

        return finalTranscript
    }

    /// Reset all state
    func reset() {
        transcriptionTask?.cancel()
        transcriptionTask = nil

        bufferTask?.cancel()
        resultsTask?.cancel()
        bufferTask = nil
        resultsTask = nil

        inputContinuation?.finish()
        inputContinuation = nil

        cachedAnalyzer = nil
        speechTranscriber = nil
        dictationTranscriber = nil

        volatileText = ""
        finalizedText = ""
        isTranscribing = false
        isReady = false
    }
}

// MARK: - Errors

enum UnifiedTranscriptionError: LocalizedError {
    case notPrepared
    case localeNotSupported(Locale)
    case modelDownloadFailed

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "Transcription service not prepared. Call prepare() first."
        case .localeNotSupported(let locale):
            return "Locale not supported: \(locale.identifier)"
        case .modelDownloadFailed:
            return "Failed to download transcription model."
        }
    }
}
