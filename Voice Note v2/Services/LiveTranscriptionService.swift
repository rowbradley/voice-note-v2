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

    // Store continuation as Any to avoid direct type dependency issues
    private var inputContinuationStorage: Any?

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

    /// Start transcribing from an audio buffer stream
    /// - Parameters:
    ///   - buffers: AsyncStream of audio buffers from LiveAudioService
    ///   - format: The audio format of the buffers
    func startTranscribing(buffers: AsyncStream<AVAudioPCMBuffer>, format: AVAudioFormat) async {
        guard isAvailable else {
            logger.error("SpeechTranscriber not available")
            return
        }

        // Reset state
        volatileText = ""
        finalizedText = ""
        isTranscribing = true

        logger.info("Starting live transcription...")

        // Find supported locale
        guard let locale = await getSupportedLocale() else {
            logger.error("No supported locale found")
            isTranscribing = false
            return
        }

        transcriptionTask = Task {
            do {
                // Create transcriber with progressive preset for live audio
                let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

                // Create input sequence
                let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                self.inputContinuationStorage = continuation

                // Create analyzer
                let analyzer = SpeechAnalyzer(modules: [transcriber])

                // Get the best available audio format for SpeechAnalyzer
                // SpeechAnalyzer does NOT perform audio conversion internally
                guard let targetFormat = try await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber],
                    considering: format
                ) else {
                    self.logger.error("No compatible audio format available")
                    return
                }

                // Create converter if formats differ
                let needsConversion = format.sampleRate != targetFormat.sampleRate ||
                                      format.commonFormat != targetFormat.commonFormat
                let converter: AudioFormatConverter? = needsConversion ?
                    AudioFormatConverter(from: format, to: targetFormat) : nil

                if needsConversion {
                    self.logger.info("Audio conversion enabled: \(format.sampleRate)Hz \(format.commonFormat.rawValue) → \(targetFormat.sampleRate)Hz \(targetFormat.commonFormat.rawValue)")
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

                // Feed audio buffers to analyzer
                Task {
                    var sampleTime: CMTime = .zero
                    // Use target format's sample rate for timing calculations after conversion
                    let outputSampleRate = targetFormat.sampleRate

                    for await buffer in buffers {
                        guard !Task.isCancelled else { break }

                        // Convert buffer if needed (48kHz Float32 → 16kHz Int16)
                        let outputBuffer: AVAudioPCMBuffer
                        if let converter = converter {
                            do {
                                outputBuffer = try converter.convert(buffer)
                            } catch {
                                self.logger.error("Buffer conversion failed: \(error)")
                                continue  // Skip this buffer
                            }
                        } else {
                            outputBuffer = buffer
                        }

                        let input = AnalyzerInput(buffer: outputBuffer, bufferStartTime: sampleTime)
                        continuation.yield(input)

                        // Update sample time based on OUTPUT buffer frame count
                        let frameDuration = Double(outputBuffer.frameLength) / outputSampleRate
                        sampleTime = CMTimeAdd(sampleTime, CMTime(seconds: frameDuration, preferredTimescale: 600))
                    }

                    self.logger.debug("Buffer stream ended")
                    continuation.finish()
                }

                // Consume transcription results
                Task {
                    do {
                        var accumulatedText = ""
                        for try await result in transcriber.results {
                            guard !Task.isCancelled else { break }

                            // Get the text from the result
                            let text = String(result.text.characters)

                            await MainActor.run {
                                // Update the accumulated finalized text
                                accumulatedText = text
                                self.finalizedText = accumulatedText
                                self.volatileText = ""  // Clear volatile when we get a result
                                self.logger.debug("Transcription result: '\(text)'")
                            }
                        }
                    } catch {
                        self.logger.error("Result stream error: \(error)")
                    }
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
