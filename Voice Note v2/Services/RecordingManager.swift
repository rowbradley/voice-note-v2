import SwiftUI
import AVFoundation
import Speech
import SwiftData
import Observation
import os.log

@MainActor
@Observable
final class RecordingManager {
    var recordingState: RecordButton.RecordingState = .idle
    var statusText = ""
    var recentRecordings: [Recording] = []
    var isTranscribing = false
    var isProcessingTemplate = false
    var lastRecordingId: UUID? = nil
    var showFailedTranscriptionAlert = false
    var failedTranscriptionMessage = ""

    // MARK: - Live Transcription State

    /// Current live transcript text (volatile + finalized)
    var liveTranscript: String {
        liveTranscriptionService.displayText
    }

    /// Whether live transcription is currently active
    var isLiveTranscribing: Bool {
        liveTranscriptionService.isTranscribing
    }

    /// Whether live transcription is available on this device
    var transcriptionAvailable: Bool {
        liveTranscriptionService.isAvailable
    }

    /// Whether using live transcription for current recording
    private(set) var isUsingLiveTranscription: Bool = false

    // MARK: - Services

    // Legacy service (fallback) - exposed for views that need audio level/duration during fallback
    let audioRecordingService = AudioRecordingService()

    // New iOS 26+ services for live transcription
    let liveAudioService = LiveAudioService()
    let liveTranscriptionService = LiveTranscriptionService()

    // Transcription services
    private let transcriptionService = TranscriptionService()  // Fallback for post-recording
    private let aiService: any AIService

    // MARK: - Computed Properties for UI

    /// Audio level - uses live service when available, falls back to legacy
    var currentAudioLevel: Float {
        isUsingLiveTranscription ? liveAudioService.currentAudioLevel : audioRecordingService.currentAudioLevel
    }

    /// Recording duration - uses live service when available, falls back to legacy
    var currentDuration: TimeInterval {
        isUsingLiveTranscription ? liveAudioService.currentDuration : audioRecordingService.currentDuration
    }

    /// Input device name - uses live service when available, falls back to legacy
    var currentInputDevice: String {
        isUsingLiveTranscription ? liveAudioService.currentInputDevice : audioRecordingService.currentInputDevice
    }

    /// Voice detection - uses live service when available, falls back to legacy
    var isVoiceDetected: Bool {
        isUsingLiveTranscription ? liveAudioService.isVoiceDetected : audioRecordingService.isVoiceDetected
    }
    
    private var modelContext: ModelContext?
    private let logger = Logger(subsystem: "com.voicenote", category: "RecordingManager")
    
    init() {
        // Set up AI service
        self.aiService = AIServiceFactory.shared.createDefaultService()

        // Set default values for UserDefaults if not already set
        if UserDefaults.standard.object(forKey: "autoGenerateTitles") == nil {
            UserDefaults.standard.set(true, forKey: "autoGenerateTitles")
        }
    }

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        loadRecentRecordings()
    }

    /// Prewarm transcription assets at app launch (non-blocking)
    /// Downloads the on-device speech recognition model if needed
    func prewarmTranscription() {
        guard liveTranscriptionService.isAvailable else {
            logger.info("🔥 Prewarm skipped: Live transcription not available")
            return
        }

        guard !liveTranscriptionService.isModelDownloaded else {
            logger.info("🔥 Prewarm skipped: Model already downloaded")
            return
        }

        logger.info("🔥 Prewarming transcription assets...")

        Task {
            do {
                try await liveTranscriptionService.ensureModelAvailable()
                logger.info("🔥 Prewarm complete: Model ready")
            } catch {
                logger.warning("🔥 Prewarm failed (will retry on first recording): \(error)")
                // Non-fatal: will retry when user starts recording
            }
        }
    }
    
    func toggleRecording() async {
        logger.debug("Toggle recording called. Current state: \(String(describing: self.recordingState))")
        let oldState = recordingState
        
        switch recordingState {
        case .idle:
            await startRecording()
        case .recording:
            await stopRecording()
        case .processing:
            logger.debug("Currently processing, ignoring tap")
            break // Do nothing while processing
        }
        
        logger.debug("State transition: \(String(describing: oldState)) → \(String(describing: self.recordingState))")
    }
    
    private func startRecording() async {
        logger.info("🔴 Starting recording...")
        recordingState = .recording
        statusText = "Recording..."

        // Try live transcription first (iOS 26+)
        logger.info("🔴 Checking live transcription availability: \(self.liveTranscriptionService.isAvailable)")
        if liveTranscriptionService.isAvailable {
            logger.info("🔴 Live transcription IS available, attempting to start...")
            do {
                // Ensure model is downloaded
                logger.info("🔴 Model downloaded: \(self.liveTranscriptionService.isModelDownloaded)")
                if !liveTranscriptionService.isModelDownloaded {
                    statusText = "Preparing transcription..."
                    logger.info("🔴 Downloading model...")
                    try await liveTranscriptionService.ensureModelAvailable()
                    logger.info("🔴 Model ready")
                }

                // Start live audio recording
                logger.info("🔴 Starting live audio service...")
                let bufferStream = try await liveAudioService.startRecording()
                logger.info("🔴 Live audio started, format: \(String(describing: self.liveAudioService.audioFormat))")

                // Start live transcription
                if let format = liveAudioService.audioFormat {
                    logger.info("🔴 Starting live transcription with format: \(format)")
                    await liveTranscriptionService.startTranscribing(buffers: bufferStream, format: format)
                    logger.info("🔴 Live transcription started")
                } else {
                    logger.error("🔴 No audio format available!")
                }

                isUsingLiveTranscription = true
                statusText = "Recording with live transcription..."
                logger.info("🔴 SUCCESS: Live transcription recording started, isUsingLiveTranscription=\(self.isUsingLiveTranscription)")
                return

            } catch {
                logger.warning("🔴 Live transcription failed to start, falling back to legacy: \(error)")
                // Fall through to legacy recording
                await liveAudioService.cancelRecording()
                liveTranscriptionService.reset()
            }
        } else {
            logger.info("🔴 Live transcription NOT available, using legacy path")
        }

        // Fallback to legacy recording (no live transcription)
        isUsingLiveTranscription = false
        logger.info("🔴 Using LEGACY recording (no live transcription)")
        do {
            try await audioRecordingService.startRecording()
            logger.info("🔴 Legacy recording started successfully")
        } catch {
            logger.error("🔴 Recording failed: \(error)")
            recordingState = .idle
            statusText = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() async {
        logger.debug("Stopping recording...")
        recordingState = .processing
        statusText = "Processing..."

        // Handle live transcription case
        if isUsingLiveTranscription {
            await stopLiveRecording()
            return
        }

        // Legacy recording flow
        await stopLegacyRecording()
    }

    /// Stop recording when using live transcription (iOS 26+)
    private func stopLiveRecording() async {
        do {
            // Stop audio recording
            let (audioURL, duration) = try await liveAudioService.stopRecording()
            logger.info("Live recording stopped. Duration: \(duration)s")

            // Get live transcript
            let liveTranscriptText = await liveTranscriptionService.stopTranscribing()
            logger.info("Live transcript: \(liveTranscriptText.count) chars")

            // Reset live transcription flag
            isUsingLiveTranscription = false

            // Save audio file to Documents directory
            let fileName = "\(UUID().uuidString).m4a"
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documentsDir.appendingPathComponent(fileName)

            try FileManager.default.moveItem(at: audioURL, to: destinationURL)
            logger.debug("Audio file saved to: \(destinationURL)")

            // Create recording record
            let recording = Recording(
                audioFileName: fileName,
                duration: duration
            )

            // Save to SwiftData
            modelContext?.insert(recording)
            try modelContext?.save()

            // Set last recording ID
            lastRecordingId = recording.id

            // Reload recent recordings
            loadRecentRecordings()
            logger.info("Recording saved to database")

            // Reset state
            recordingState = .idle
            statusText = "Recording saved!"

            // Process transcript
            Task {
                await processTranscript(
                    liveTranscriptText: liveTranscriptText,
                    audioURL: destinationURL,
                    recording: recording
                )
            }

            // Clear status after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.statusText = ""
            }

        } catch {
            logger.error("Failed to stop live recording: \(error)")
            recordingState = .idle
            statusText = "Failed to process recording"
            isUsingLiveTranscription = false
            liveTranscriptionService.reset()
        }
    }

    /// Process transcript - use live transcript if available, fall back to file-based
    private func processTranscript(liveTranscriptText: String, audioURL: URL, recording: Recording) async {
        var transcriptText = liveTranscriptText

        // If live transcript is empty or poor quality, fall back to file-based transcription
        if transcriptText.isEmpty || transcriptionService.isTranscriptionPoor(transcriptText, duration: recording.duration) {
            logger.info("Live transcript insufficient, falling back to file-based transcription")
            isTranscribing = true
            statusText = "Transcribing..."

            do {
                transcriptText = try await transcriptionService.transcribe(audioURL: audioURL, progressCallback: nil)
                logger.info("File-based transcription completed: \(transcriptText.count) chars")
            } catch {
                logger.error("File-based transcription failed: \(error)")
                isTranscribing = false
                statusText = "Transcription failed"
                failedTranscriptionMessage = "Recording saved. Transcription failed - recording may be too short or contain no audio."
                showFailedTranscriptionAlert = true
                return
            }
        }

        // Create and assign transcript
        let transcript = Transcript(text: transcriptText)
        recording.transcript = transcript

        // Generate title (synchronous - uses first line)
        generateTitle(for: transcript, from: transcriptText, recording: recording)

        // Save and update UI
        try? modelContext?.save()
        isTranscribing = false
        statusText = "Transcription complete!"
        loadRecentRecordings()
    }

    /// Generate title from first line of transcript (synchronous, no AI)
    private func generateTitle(for transcript: Transcript, from transcriptText: String, recording: Recording) {
        // Simple: first line of transcript, truncated to fit
        let firstLine = transcriptText
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        // Truncate to ~50 chars with ellipsis if needed
        if firstLine.count > 50 {
            let truncated = String(firstLine.prefix(47)) + "..."
            transcript.aiTitle = truncated
            logger.info("Generated title from first line (truncated): '\(truncated)'")
        } else if !firstLine.isEmpty {
            transcript.aiTitle = firstLine
            logger.info("Generated title from first line: '\(firstLine)'")
        } else {
            // Fallback to date-based title if transcript is empty
            transcript.aiTitle = "Recording \(recording.createdAt.formatted(date: .abbreviated, time: .shortened))"
            logger.info("Generated fallback title")
        }
    }

    /// Legacy recording flow (fallback when live transcription unavailable)
    private func stopLegacyRecording() async {
        do {
            let (audioURL, duration) = try await audioRecordingService.stopRecording()

            logger.info("Recording stopped. Duration: \(duration)s, File: \(audioURL)")

            // Save audio file to Documents directory
            let fileName = "\(UUID().uuidString).m4a"
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documentsDir.appendingPathComponent(fileName)

            do {
                try FileManager.default.moveItem(at: audioURL, to: destinationURL)
                logger.debug("Audio file saved to: \(destinationURL)")
            } catch {
                logger.error("Failed to save audio file: \(error)")
                throw error
            }

            // Create recording record
            let recording = Recording(
                audioFileName: fileName,
                duration: duration
            )

            // Save to SwiftData
            modelContext?.insert(recording)
            try modelContext?.save()

            // Set last recording ID
            lastRecordingId = recording.id

            // Reload recent recordings
            loadRecentRecordings()
            logger.info("Recording saved to database. Total recordings: \(self.recentRecordings.count)")

            // Reset state immediately - don't block UI
            recordingState = .idle
            statusText = "Recording saved!"

            // Start transcription in background (don't block UI)
            Task {
                // Declare progressTask at function level for proper scope
                var progressTask: Task<Void, Never>?

                do {
                    isTranscribing = true
                    statusText = "Transcribing..."
                    self.logger.debug("Starting transcription for file: \(destinationURL)")

                    // Show progress updates with cancellable task
                    progressTask = Task {
                        for i in 1...6 {
                            guard !Task.isCancelled else { break }
                            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                            if isTranscribing && !Task.isCancelled {
                                await MainActor.run {
                                    let messages = [
                                        "Processing audio...",
                                        "Still transcribing...",
                                        "This may take a moment...",
                                        "Almost there...",
                                        "Finalizing transcript...",
                                        "Taking longer than expected..."
                                    ]
                                    statusText = messages[min(i-1, messages.count-1)]
                                }
                            } else {
                                break
                            }
                        }
                    }

                    let transcriptText = try await transcriptionService.transcribe(audioURL: destinationURL, progressCallback: nil)
                    
                    // Cancel progress updates task
                    progressTask?.cancel()
                    
                    self.logger.info("Transcription completed. Length: \(transcriptText.count) chars")
                    
                    // The transcribe method handles transcription
                    // Just use the result we got
                    
                    // Create transcript object
                    self.logger.debug("Creating transcript. Length: \(transcriptText.count) chars")
                    let transcript = Transcript(text: transcriptText)
                    recording.transcript = transcript
                    self.logger.debug("Assigned transcript to recording")

                    // Generate title (synchronous - uses first line)
                    self.generateTitle(for: transcript, from: transcriptText, recording: recording)
                    
                    // Save transcript
                    try modelContext?.save()
                    self.logger.debug("Saved transcript to database")
                    
                    // Verify it was saved
                    if let savedTranscript = recording.transcript {
                        self.logger.debug("Verified saved transcript. Length: \(savedTranscript.text.count) chars")
                    } else {
                        self.logger.error("Transcript not found after save!")
                    }
                    
                    await MainActor.run {
                        isTranscribing = false
                        statusText = "Transcription complete!"
                        loadRecentRecordings() // Refresh UI
                        self.logger.debug("Recording transcript updated, reloading UI")
                    }
                } catch {
                    // Cancel progress updates task
                    progressTask?.cancel()
                    
                    await MainActor.run {
                        isTranscribing = false
                        statusText = "Transcription failed"
                        self.logger.error("Transcription error: \(error)")
                        
                        // Show alert about failed transcription
                        failedTranscriptionMessage = "Recording saved to Library. Transcription failed - recording may be too short or contain no audio."
                        showFailedTranscriptionAlert = true
                        
                        // Remove from recent recordings to keep it clean
                        if let index = recentRecordings.firstIndex(where: { $0.id == recording.id }) {
                            recentRecordings.remove(at: index)
                        }
                    }
                }
            }
            
            // Clear status after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.statusText = ""
            }
            
        } catch {
            recordingState = .idle
            statusText = "Failed to process recording: \(error.localizedDescription)"
        }
    }
    
    private func loadRecentRecordings() {
        guard let modelContext = modelContext else {
            logger.warning("ModelContext not available yet")
            recentRecordings = []
            return
        }
        
        do {
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            
            let allRecordings = try modelContext.fetch(descriptor)
            // Log all recordings for debugging
            for (index, recording) in allRecordings.prefix(3).enumerated() {
                let transcriptInfo = recording.transcript != nil ? "'\(recording.transcript!.text.prefix(30))...'" : "nil"
                logger.debug("Recording \(index): transcript = \(transcriptInfo)")
            }
            
            // Only show recordings with transcripts in recent (successful transcriptions)
            recentRecordings = allRecordings.filter { $0.transcript != nil && !($0.transcript?.text.isEmpty ?? true) }
            logger.info("Loaded \(self.recentRecordings.count) recordings with transcripts (total: \(allRecordings.count))")
            
            // Debug: Show first recent recording
            if let first = recentRecordings.first {
                logger.debug("First recent recording transcript: '\(first.transcript?.text.prefix(50) ?? "nil")...'")
            }
        } catch {
            logger.error("Failed to load recordings: \(error)")
            recentRecordings = []
        }
    }
    
    // MARK: - Title Generation
    
    func generateFallbackTitle(from transcript: String) -> String {
        // Use same format as AI title generation
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        let datePrefix = formatter.string(from: Date())
        
        // Clean up the transcript
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // If transcript is empty, use date only
        if cleanedTranscript.isEmpty {
            return datePrefix
        }
        
        // Get first 3 words
        let words = cleanedTranscript.split(separator: " ").prefix(3)
        let wordsPart = words.joined(separator: " ")
        
        return "\(datePrefix) \(wordsPart)..."
    }
    
    // MARK: - Template Processing
    
    func processTemplate(_ template: Template, for recording: Recording) async throws {
        guard let transcript = recording.transcript else {
            throw AIError.invalidTemplate(reason: "No transcript available")
        }
        
        isProcessingTemplate = true
        statusText = "Processing template..."
        
        do {
            let templateInfo = TemplateInfo(from: template)
            let result = try await aiService.processTemplate(templateInfo, transcript: transcript.text)
            
            // Extract processing time based on result type
            let processingTime: TimeInterval

            switch result {
            case .local(let response):
                processingTime = response.deviceProcessingTime
            case .mock:
                processingTime = 0
            }
            
            // Create processed note
            let processedNote = ProcessedNote(
                templateId: template.id,
                templateName: template.name,
                processedText: result.text,
                processingTime: processingTime,
                tokenUsage: nil  // On-device processing doesn't track tokens
            )
            
            // Add to relationship and save
            recording.processedNotes.append(processedNote)
            
            do {
                try modelContext?.save()
                logger.debug("Processed note saved successfully")
            } catch {
                logger.error("Failed to save processed note: \(error)")
                // Try to recover by inserting the note explicitly
                modelContext?.insert(processedNote)
                processedNote.recording = recording
                
                do {
                    try modelContext?.save()
                    logger.debug("Recovered and saved after explicit insert")
                } catch {
                    logger.error("Recovery failed: \(error)")
                    throw error
                }
            }
            
            await MainActor.run {
                isProcessingTemplate = false
                statusText = "Template applied!"
                loadRecentRecordings()
            }
            
            // Clear status after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.statusText = ""
            }
            
        } catch {
            await MainActor.run {
                isProcessingTemplate = false
                statusText = "Template processing failed"
            }
            throw error
        }
    }
    
}