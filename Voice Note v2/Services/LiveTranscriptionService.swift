import Foundation
import Speech
import AVFoundation
import os.log
import CoreMedia

/// Live transcription service using iOS 26+ SpeechAnalyzer API
/// Provides real-time transcription with volatile results that refine to finalized text
@MainActor
@Observable
final class LiveTranscriptionService {
    // MARK: - Public State

    /// Whether the iOS 26+ SpeechAnalyzer is available on this device
    var isAvailable: Bool {
        SpeechTranscriber.isAvailable
    }

    /// Whether the on-device model is downloaded and ready
    private(set) var isModelDownloaded: Bool = false

    /// Progress of model download (0.0 to 1.0)
    private(set) var downloadProgress: Double = 0.0

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

    private let logger = Logger(subsystem: "com.voicenote", category: "LiveTranscription")
    private var transcriptionTask: Task<Void, Never>?

    // MARK: - Type-Erased Continuation Storage
    //
    // Why `Any?` instead of `AsyncStream<AnalyzerInput>.Continuation?`:
    //
    // The `AnalyzerInput` type is part of the Speech framework's SpeechAnalyzer API
    // and is only available within async method bodies where SpeechAnalyzer is used.
    // Attempting to declare a property as `AsyncStream<AnalyzerInput>.Continuation?`
    // at the class level would require importing the continuation's generic type
    // parameter into the class scope, which can cause compilation issues with
    // module boundaries and incremental builds.
    //
    // The `Any` type erasure pattern allows us to:
    // 1. Store the continuation without exposing AnalyzerInput at the class level
    // 2. Cast back to the specific type when needed (stopTranscribing, reset)
    // 3. Avoid complex type erasure wrappers for a simple store-and-retrieve case
    //
    // Usage:
    //   Store:   self.inputContinuationStorage = continuation
    //   Retrieve: if let c = inputContinuationStorage as? AsyncStream<AnalyzerInput>.Continuation { ... }
    //
    private var inputContinuationStorage: Any?

    // Pre-warmed analyzer components (Optimization 2)
    private var cachedLocale: Locale?
    private var cachedTranscriber: SpeechTranscriber?
    private var cachedAnalyzer: SpeechAnalyzer?
    private var isPrepared: Bool = false

    // Cached audio format (Optimization 4)
    // bestAvailableAudioFormat() result doesn't change per-device, so cache it
    private var cachedTargetFormat: AVAudioFormat?

    // MARK: - Lifecycle

    init() {
        Task {
            await checkModelStatus()
        }
    }

    /// Helper to get supported locale (handles async calls properly)
    private func getSupportedLocale() async -> Locale? {
        // Try current locale first
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
            return locale
        }
        // Fall back to en-US
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }

    /// Check if the on-device model is already downloaded
    private func checkModelStatus() async {
        do {
            // Check if model supports current locale
            guard let locale = await getSupportedLocale() else {
                logger.warning("No supported locale found")
                isModelDownloaded = false
                return
            }

            // Create a transcriber to check status
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            let status = await AssetInventory.status(forModules: [transcriber])

            switch status {
            case .installed:
                isModelDownloaded = true
                downloadProgress = 1.0
                logger.info("On-device transcription model is installed for locale: \(locale.identifier)")
            case .supported, .downloading:
                isModelDownloaded = false
                downloadProgress = status == .downloading ? 0.5 : 0.0
                logger.info("On-device transcription model status: \(String(describing: status))")
            case .unsupported:
                isModelDownloaded = false
                downloadProgress = 0.0
                logger.warning("On-device transcription model is unsupported for locale: \(locale.identifier)")
            @unknown default:
                isModelDownloaded = false
            }
        } catch {
            logger.error("Failed to check model status: \(error)")
            isModelDownloaded = false
        }
    }

    /// Ensure the on-device model is available, downloading if necessary
    func ensureModelAvailable() async throws {
        guard isAvailable else {
            throw LiveTranscriptionError.unavailable
        }

        // Already downloaded
        if isModelDownloaded {
            return
        }

        // Find supported locale
        guard let locale = await getSupportedLocale() else {
            throw LiveTranscriptionError.localeNotSupported
        }

        logger.info("Requesting model download for locale: \(locale.identifier)")

        // Create transcriber for the locale
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

        // Reserve the locale
        try await AssetInventory.reserve(locale: locale)

        // Request asset installation
        guard let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            // Already installed
            isModelDownloaded = true
            downloadProgress = 1.0
            return
        }

        // Download and install (Progress reporting via ProgressReporting protocol uses KVO)
        // For simplicity, just download without detailed progress monitoring
        try await installationRequest.downloadAndInstall()

        // Verify installation
        await checkModelStatus()

        guard isModelDownloaded else {
            throw LiveTranscriptionError.downloadFailed
        }

        logger.info("Model download completed successfully")
    }

    /// Prepare the analyzer for minimal startup delay (Optimization 2)
    /// Call this after ensureModelAvailable() to preheat the ML model
    func prepareAnalyzer() async {
        guard isAvailable else {
            logger.info("🔥 prepareAnalyzer skipped: not available")
            return
        }

        guard isModelDownloaded else {
            logger.info("🔥 prepareAnalyzer skipped: model not downloaded yet")
            return
        }

        guard !isPrepared else {
            logger.info("🔥 prepareAnalyzer skipped: already prepared")
            return
        }

        logger.info("🔥 Preparing analyzer for low-latency startup...")

        do {
            // Get supported locale
            guard let locale = await getSupportedLocale() else {
                logger.warning("🔥 prepareAnalyzer: No supported locale")
                return
            }
            cachedLocale = locale

            // Create transcriber
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            cachedTranscriber = transcriber
            logger.info("🔥 SpeechTranscriber created for locale: \(locale.identifier)")

            // Create analyzer with processLifetime retention (Optimization 3)
            // Keeps ML models in memory until process exits, avoiding reload on subsequent recordings
            let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
            let analyzer = SpeechAnalyzer(modules: [transcriber], options: options)
            cachedAnalyzer = analyzer
            logger.info("🔥 SpeechAnalyzer created with processLifetime retention")

            // Cache the best available audio format (Optimization 4)
            // This negotiation takes ~100-300ms, so do it once at launch
            // Pass nil for considering - we'll use this format for any input
            if let targetFormat = try await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: nil
            ) {
                cachedTargetFormat = targetFormat
                logger.info("🔥 Cached target format: \(targetFormat.sampleRate)Hz, \(targetFormat.commonFormat.rawValue)")
            }

            // Preheat the analyzer with prepareToAnalyze(in:)
            // Pass the cached format if available for optimal preheating
            try await analyzer.prepareToAnalyze(in: cachedTargetFormat)
            logger.info("🔥 Analyzer preheated with prepareToAnalyze(in:)")

            isPrepared = true
            logger.info("🔥 Analyzer preparation complete - ready for low-latency recording")

        } catch {
            logger.warning("🔥 prepareAnalyzer failed (will create fresh on recording): \(error)")
            // Non-fatal: will create fresh analyzer when recording starts
            cachedTranscriber = nil
            cachedAnalyzer = nil
            cachedLocale = nil
            cachedTargetFormat = nil
            isPrepared = false
        }
    }

    /// Start transcribing from an audio buffer stream
    /// - Parameters:
    ///   - buffers: AsyncStream of audio buffers with timestamps from LiveAudioService
    ///   - format: The audio format of the buffers
    func startTranscribing(buffers: AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>, format: AVAudioFormat) async {
        guard isAvailable else {
            logger.error("SpeechTranscriber not available")
            return
        }

        // Reset state
        volatileText = ""
        finalizedText = ""
        isTranscribing = true

        // Timing diagnostics to understand race condition
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("🎤 [T+0.000] Starting live transcription...")
        logger.info("🎤 Input format: \(format.sampleRate)Hz, \(format.channelCount) channels, \(format.commonFormat.rawValue)")

        // Use cached locale/transcriber/analyzer if prepared, otherwise create fresh
        let locale: Locale
        let transcriber: SpeechTranscriber
        let analyzer: SpeechAnalyzer

        if isPrepared, let cachedLocale = cachedLocale, let cachedTranscriber = cachedTranscriber, let cachedAnalyzer = cachedAnalyzer {
            // Use pre-warmed components (Optimization 2 - saves ~200-500ms)
            locale = cachedLocale
            transcriber = cachedTranscriber
            analyzer = cachedAnalyzer
            logger.info("🎤 Using pre-warmed analyzer (isPrepared=true)")
        } else {
            // Create fresh components (fallback path)
            guard let supportedLocale = await getSupportedLocale() else {
                logger.error("🎤 No supported locale found")
                isTranscribing = false
                return
            }
            locale = supportedLocale
            transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            // Use processLifetime retention even for fallback path (Optimization 3)
            let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
            analyzer = SpeechAnalyzer(modules: [transcriber], options: options)
            logger.info("🎤 Created fresh transcriber/analyzer with processLifetime retention (isPrepared=false)")
        }
        logger.info("🎤 Using locale: \(locale.identifier)")

        transcriptionTask = Task {
            do {
                // Create input sequence
                let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                self.inputContinuationStorage = continuation

                // Get the best available audio format for SpeechAnalyzer
                // SpeechAnalyzer does NOT perform audio conversion internally
                // Use cached format if available (Optimization 4 - saves ~100-300ms)
                let targetFormat: AVAudioFormat
                if let cached = self.cachedTargetFormat {
                    targetFormat = cached
                    logger.info("🎤 Using cached target format: \(targetFormat.sampleRate)Hz, \(targetFormat.commonFormat.rawValue)")
                } else {
                    logger.info("🎤 Getting best available audio format (no cache)...")
                    guard let computed = try await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [transcriber],
                        considering: format
                    ) else {
                        self.logger.error("🎤 No compatible audio format available")
                        return
                    }
                    targetFormat = computed
                    // Cache for future recordings
                    self.cachedTargetFormat = computed
                    logger.info("🎤 Computed and cached target format: \(targetFormat.sampleRate)Hz, \(targetFormat.commonFormat.rawValue)")
                }

                // Create converter if formats differ
                let needsConversion = format.sampleRate != targetFormat.sampleRate ||
                                      format.commonFormat != targetFormat.commonFormat
                let converter: AudioFormatConverter? = needsConversion ?
                    AudioFormatConverter(from: format, to: targetFormat) : nil

                if needsConversion {
                    self.logger.info("🎤 Audio conversion enabled: \(format.sampleRate)Hz \(format.commonFormat.rawValue) → \(targetFormat.sampleRate)Hz \(targetFormat.commonFormat.rawValue)")
                } else {
                    self.logger.info("🎤 No audio conversion needed")
                }

                // Set up volatile range handler to track in-progress text
                // Signature: (CMTimeRange, Bool, Bool) -> Void
                // - range: The volatile time range
                // - isWaiting: Whether the analyzer is waiting for more input
                // - isFinished: Whether analysis has finished
                await analyzer.setVolatileRangeChangedHandler { [weak self] range, isWaiting, isFinished in
                    Task { @MainActor in
                        self?.logger.debug("Volatile range changed: \(String(describing: range)), waiting: \(isWaiting), finished: \(isFinished)")
                    }
                }

                // Create synchronization for first buffer (Optimization 5 - replaces fixed 150ms delay)
                // This ensures analyzeSequence() isn't called before buffers start flowing
                let firstBufferSignal = AsyncStream<Void>.makeStream()
                var firstBufferContinuation: AsyncStream<Void>.Continuation? = firstBufferSignal.1

                // Feed audio buffers to analyzer
                logger.info("🎤 [T+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))] Spawning buffer feeding task")
                Task {
                    self.logger.info("🎤 [T+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))] Buffer feeding task STARTED")
                    var bufferCount = 0

                    for await (buffer, _) in buffers {
                        guard !Task.isCancelled else {
                            self.logger.info("🎤 Buffer task cancelled")
                            break
                        }

                        // Convert buffer if needed (48kHz Float32 → 16kHz Int16)
                        let outputBuffer: AVAudioPCMBuffer
                        if let converter = converter {
                            do {
                                outputBuffer = try converter.convert(buffer)
                            } catch {
                                self.logger.error("🎤 Buffer conversion failed: \(error)")
                                continue  // Skip this buffer
                            }
                        } else {
                            outputBuffer = buffer
                        }

                        // Use simple initializer - Apple handles contiguous audio timing automatically
                        // Per Apple docs: "assumed to start immediately after the previous buffer"
                        let input = AnalyzerInput(buffer: outputBuffer)
                        continuation.yield(input)
                        bufferCount += 1

                        // Signal first buffer arrival (Optimization 5)
                        if bufferCount == 1 {
                            self.logger.info("🎤 [T+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))] First buffer fed to analyzer - signaling ready")
                            firstBufferContinuation?.yield()
                            firstBufferContinuation?.finish()
                            firstBufferContinuation = nil
                        }

                        // Log every 50 buffers to track progress
                        if bufferCount % 50 == 0 {
                            self.logger.debug("🎤 Fed \(bufferCount) buffers")
                        }
                    }

                    self.logger.info("🎤 Buffer stream ended after \(bufferCount) buffers")
                    // Ensure signal is sent even if no buffers arrived (edge case)
                    firstBufferContinuation?.finish()
                    continuation.finish()
                }

                // Consume transcription results
                logger.info("🎤 [T+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))] Spawning results consuming task")
                Task {
                    do {
                        var accumulatedText = ""
                        var resultCount = 0
                        self.logger.info("🎤 Waiting for transcriber.results...")

                        for try await result in transcriber.results {
                            resultCount += 1
                            guard !Task.isCancelled else {
                                self.logger.info("🎤 Results task cancelled after \(resultCount) results")
                                break
                            }

                            // Get the text from the result
                            let text = String(result.text.characters)
                            self.logger.info("🎤 Result #\(resultCount): isFinal=\(result.isFinal), text='\(text.prefix(50))...'")

                            await MainActor.run {
                                if result.isFinal {
                                    // Finalized result: APPEND to accumulated text, clear volatile
                                    if !text.isEmpty {
                                        accumulatedText += (accumulatedText.isEmpty ? "" : " ") + text
                                    }
                                    self.finalizedText = accumulatedText
                                    self.volatileText = ""
                                    self.logger.info("🎤 FINALIZED: '\(text.prefix(30))...' → total: \(accumulatedText.count) chars")
                                } else {
                                    // Volatile result: show as in-progress (replaces previous volatile)
                                    self.volatileText = text
                                    self.logger.debug("🎤 VOLATILE: '\(text.prefix(30))...'")
                                }
                                self.logger.debug("🎤 displayText now: '\(self.displayText.prefix(50))...'")
                            }
                        }
                        self.logger.info("🎤 Results stream ended after \(resultCount) results")
                    } catch {
                        self.logger.error("🎤 Result stream error: \(error)")
                    }
                }

                // Wait for first buffer before starting analysis (Optimization 5 - replaces fixed 150ms delay)
                // This is more robust - we start exactly when audio is flowing, not after arbitrary delay
                logger.info("🎤 [T+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))] Waiting for first buffer...")

                // Wait for first buffer signal (stream finishes after first yield or if no buffers arrive)
                var gotFirstBuffer = false
                for await _ in firstBufferSignal.0 {
                    gotFirstBuffer = true
                    break
                }

                if gotFirstBuffer {
                    logger.info("🎤 [T+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))] First buffer received, starting analyzer")
                } else {
                    logger.warning("🎤 [T+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))] No first buffer signal, starting analyzer anyway")
                }

                // Start analysis
                let lastSampleTime = try await analyzer.analyzeSequence(inputSequence)

                // Finalize when done
                if let lastSampleTime {
                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                }

                logger.info("Transcription analysis completed")

            } catch {
                logger.error("Transcription error: \(error)")
            }

            await MainActor.run {
                self.isTranscribing = false
            }
        }
    }

    /// Stop transcribing and return the final transcript
    /// - Returns: The complete finalized transcript text
    func stopTranscribing() async -> String {
        logger.info("Stopping live transcription...")

        // Signal end of input - cast from Any storage
        if let continuation = inputContinuationStorage as? AsyncStream<AnalyzerInput>.Continuation {
            continuation.finish()
        }
        inputContinuationStorage = nil

        // Wait for transcription task to complete (with timeout)
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 second timeout
        }

        _ = await Task {
            await transcriptionTask?.value
        }.result

        timeoutTask.cancel()
        transcriptionTask = nil

        isTranscribing = false

        // Build final transcript
        let finalTranscript = finalizedText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        logger.info("Final transcript: \(finalTranscript.count) characters")

        return finalTranscript
    }

    /// Reset all transcription state
    func reset() {
        transcriptionTask?.cancel()
        transcriptionTask = nil

        if let continuation = inputContinuationStorage as? AsyncStream<AnalyzerInput>.Continuation {
            continuation.finish()
        }
        inputContinuationStorage = nil

        // Invalidate cached components (analyzer may not be reusable after analyzeSequence)
        // The underlying model stays in memory via ModelRetention (Optimization 3)
        cachedTranscriber = nil
        cachedAnalyzer = nil
        cachedLocale = nil
        isPrepared = false

        volatileText = ""
        finalizedText = ""
        isTranscribing = false
    }
}

// MARK: - Errors

enum LiveTranscriptionError: LocalizedError {
    case unavailable
    case localeNotSupported
    case downloadFailed
    case notReady

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Live transcription is not available on this device"
        case .localeNotSupported:
            return "Your language is not supported for on-device transcription"
        case .downloadFailed:
            return "Failed to download the transcription model"
        case .notReady:
            return "Transcription service is not ready"
        }
    }
}
