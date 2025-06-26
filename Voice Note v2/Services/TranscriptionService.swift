import Foundation
import Speech
import AVFoundation
import os.log
import CoreMedia

class TranscriptionService {
    private var speechRecognizer: SFSpeechRecognizer?
    private let logger = Logger(subsystem: "com.voicenote", category: "Transcription")
    
    init() {
        setupSpeechRecognizer()
    }
    
    private func setupSpeechRecognizer() {
        // Try current locale first
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        
        // If current locale doesn't support on-device, try en-US
        if speechRecognizer?.supportsOnDeviceRecognition != true {
            self.logger.warning("Current locale \(Locale.current) doesn't support on-device recognition, trying en-US")
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        
        // Log recognition mode
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            self.logger.info("On-device recognition is available")
        } else {
            self.logger.warning("On-device recognition not available, will use online recognition")
        }
    }
    
    func transcribe(audioURL: URL, progressCallback: ((String) -> Void)? = nil) async throws -> String {
        self.logger.info("TranscriptionService.transcribe() called with URL: \(audioURL)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            self.logger.error("Audio file does not exist at path: \(audioURL.path)")
            throw TranscriptionError.invalidResponse
        }
        
        // Check file size and duration
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let fileSize = attributes[.size] as? NSNumber
            self.logger.info("Audio file size: \(fileSize?.intValue ?? 0) bytes")
            
            // Check audio duration and format
            let asset = AVURLAsset(url: audioURL)
            let duration: Double
            if #available(iOS 16.0, *) {
                duration = try await asset.load(.duration).seconds
            } else {
                duration = CMTimeGetSeconds(asset.duration)
            }
            self.logger.info("Audio duration: \(duration) seconds")
            
            // Check if audio has proper format
            if #available(iOS 16.0, *) {
                let tracks = try? await asset.loadTracks(withMediaType: .audio)
                if let audioTrack = tracks?.first {
                    let formats = try? await audioTrack.load(.formatDescriptions)
                    self.logger.debug("Audio format: \(String(describing: formats ?? []))")
                }
            } else {
                if let audioTrack = asset.tracks(withMediaType: .audio).first {
                    self.logger.debug("Audio format: \(audioTrack.formatDescriptions)")
                }
            }
        } catch {
            self.logger.warning("Could not get file attributes: \(error)")
        }
        
        // Perform transcription using iOS Speech Recognition
        do {
            self.logger.info("Attempting on-device transcription...")
            progressCallback?("Transcribing...")
            
            let result = try await performOnDeviceTranscription(audioURL: audioURL)
            
            if !result.isEmpty {
                self.logger.info("✅ Transcription succeeded with \(result.count) characters")
                return result
            }
            
            self.logger.info("⚠️ Transcription returned empty result")
            throw TranscriptionError.invalidResponse
            
        } catch {
            self.logger.info("❌ Transcription failed: \(error)")
            throw error
        }
    }
    
    private func performOnDeviceTranscription(audioURL: URL) async throws -> String {
        self.logger.info("🔐 Attempting on-device transcription")
        
        // Ensure speech recognizer is properly set up
        if speechRecognizer == nil {
            setupSpeechRecognizer()
        }
        
        self.logger.info("🔐 Recognition mode: \(self.speechRecognizer?.supportsOnDeviceRecognition == true ? "On-device" : "Online (fallback)")")
        
        // Check speech recognizer
        guard let recognizer = speechRecognizer else {
            self.logger.info("❌ Speech recognizer is nil")
            throw TranscriptionError.speechRecognitionUnavailable
        }
        
        guard recognizer.isAvailable else {
            self.logger.info("❌ Speech recognizer is not available")
            throw TranscriptionError.speechRecognitionUnavailable
        }
        
        self.logger.info("✅ Speech recognizer is available")
        
        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        self.logger.info("🔐 Speech recognition authorization status: \(authStatus.rawValue)")
        
        if authStatus == .notDetermined {
            self.logger.info("🔍 Requesting speech recognition permission...")
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            
            if !granted {
                self.logger.info("❌ Speech recognition permission denied")
                throw TranscriptionError.speechRecognitionUnavailable
            }
            self.logger.info("✅ Speech recognition permission granted")
        } else if authStatus != .authorized {
            self.logger.info("❌ Speech recognition not authorized. Status: \(String(describing: authStatus))")
            throw TranscriptionError.speechRecognitionUnavailable
        }
        
        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        // Try with partial results but handle them better
        request.shouldReportPartialResults = true
        
        // Configure for on-device recognition when available
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }
        
        // Additional configuration for better recognition
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // Set task hint to unspecified for more general recognition
        request.taskHint = .unspecified
        
        // Add contextual strings to help with quiet syllables
        if #available(iOS 13.0, *) {
            // Common words/phrases that might be spoken quietly
            request.contextualStrings = [
                "um", "uh", "like", "you know", "I mean", "basically",
                "actually", "literally", "right", "okay", "so", "well",
                "yes", "no", "yeah", "nope", "sure", "thanks"
            ]
        }
        
        self.logger.info("📝 Created SFSpeechURLRecognitionRequest (requiring on-device: \(recognizer.supportsOnDeviceRecognition))")
        
        // Add timeout to prevent hanging
        return try await withThrowingTaskGroup(of: String.self) { group in
            // Add transcription task
            group.addTask {
                self.logger.info("🚀 Starting transcription task...")
                return try await withCheckedThrowingContinuation { continuation in
                    // Track transcription state
                    var currentTranscript = ""
                    var accumulatedSegments: [String] = []
                    var lastStableLength = 0
                    var hasResumed = false
                    
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        if let error = error {
                            self.logger.info("❌ Recognition error: \(error)")
                            guard !hasResumed else { return }
                            hasResumed = true
                            
                            // Return accumulated transcript on error
                            let finalTranscript = Self.combineTranscripts(
                                segments: accumulatedSegments,
                                current: currentTranscript
                            )
                            
                            if !finalTranscript.isEmpty {
                                self.logger.info("✅ Returning transcript after error (length: \(finalTranscript.count))")
                                continuation.resume(returning: finalTranscript)
                            } else {
                                continuation.resume(throwing: TranscriptionError.recognitionFailed(error))
                            }
                            return
                        }
                        
                        if let result = result {
                            let newTranscript = result.bestTranscription.formattedString
                            
                            // Detect segment boundary: significant length drop indicates iOS restarted
                            let isNewSegment = !currentTranscript.isEmpty && 
                                             newTranscript.count < Int(Double(currentTranscript.count) * 0.7)
                            
                            if isNewSegment {
                                // Save current segment before starting new one
                                self.logger.info("🔄 Segment boundary detected - saving \(currentTranscript.count) chars")
                                accumulatedSegments.append(currentTranscript)
                                currentTranscript = newTranscript
                                lastStableLength = 0
                            } else {
                                // Update current transcript (following o3's suggestion to keep longest)
                                if newTranscript.count >= currentTranscript.count {
                                    currentTranscript = newTranscript
                                }
                                
                                // Track stable length for debugging
                                if newTranscript.count > lastStableLength {
                                    lastStableLength = newTranscript.count
                                }
                            }
                            
                            self.logger.info("📊 Transcript update - isFinal: \(result.isFinal), current: \(currentTranscript.count), segments: \(accumulatedSegments.count), stable: \(lastStableLength)")
                            
                            if result.isFinal {
                                guard !hasResumed else { return }
                                hasResumed = true
                                
                                let finalTranscript = Self.combineTranscripts(
                                    segments: accumulatedSegments,
                                    current: currentTranscript
                                )
                                
                                self.logger.info("✅ Final transcript - segments: \(accumulatedSegments.count + 1), total length: \(finalTranscript.count)")
                                
                                continuation.resume(returning: finalTranscript)
                            }
                        }
                    }
                    
                    self.logger.info("📋 Recognition task created: \(String(describing: task))")
                }
            }
            
            // Add timeout task - increased for better results
            group.addTask {
                self.logger.info("⏱️ Starting timeout task (60 seconds)...")
                try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds for on-device
                self.logger.info("⏰ Timeout reached!")
                throw TranscriptionError.transcriptionTimeout
            }
            
            // Return first completed task (transcription or timeout)
            self.logger.info("⏳ Waiting for first task to complete...")
            
            do {
                let result = try await group.next()!
                self.logger.info("🏁 Task completed with result: '\(result)'")
                group.cancelAll()
                return result
            } catch {
                self.logger.info("⚠️ Task group error: \(error)")
                group.cancelAll()
                throw error
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private static func combineTranscripts(segments: [String], current: String) -> String {
        var allSegments = segments
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            allSegments.append(current)
        }
        
        // Join segments with a space, then clean up extra whitespace
        let combined = allSegments
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return combined
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
    case transcriptionTimeout
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available"
        case .recognitionFailed(let error):
            return "Recognition failed: \(error.localizedDescription)"
        case .transcriptionTimeout:
            return "Transcription timed out. Please try again."
        case .invalidResponse:
            return "Invalid response from transcription service"
        }
    }
}