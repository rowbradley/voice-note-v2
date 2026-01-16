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

    // Expose audioRecordingService directly - views access its properties via this
    let audioRecordingService = AudioRecordingService()
    private let transcriptionService = TranscriptionService()
    private let aiService: any AIService
    
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
        logger.debug("Starting recording...")
        recordingState = .recording
        statusText = "Recording..."
        
        do {
            try await audioRecordingService.startRecording()
            logger.debug("Recording started successfully")
        } catch {
            logger.error("Recording failed: \(error)")
            recordingState = .idle
            statusText = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() async {
        logger.debug("Stopping recording...")
        recordingState = .processing
        statusText = "Processing..."
        
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
                    
                    // Generate AI title in background with timeout protection
                    let shouldGenerateTitle = UserDefaults.standard.bool(forKey: "autoGenerateTitles")
                    self.logger.debug("Auto-generate titles enabled: \(shouldGenerateTitle)")
                    
                    if shouldGenerateTitle {
                        Task.detached { [weak self] in
                            guard let self = self else { return }
                            
                            do {
                            // Truncate transcript for title generation (max 500 words)
                            let words = transcriptText.split(separator: " ")
                            let truncatedTranscript = words.prefix(500).joined(separator: " ")
                            self.logger.debug("Requesting title generation. Transcript length: \(truncatedTranscript.count) chars")
                            
                            // Add timeout protection - increased to 20 seconds
                            let titleTask = Task {
                                try await self.aiService.generateTitle(from: truncatedTranscript)
                            }
                            
                            // Wait for result with timeout
                            let result = try await withThrowingTaskGroup(of: AIResult.self) { group in
                                group.addTask { try await titleTask.value }
                                group.addTask {
                                    try await Task.sleep(nanoseconds: 20_000_000_000) // 20 second timeout
                                    throw AIError.processingTimeout
                                }
                                
                                if let first = try await group.next() {
                                    group.cancelAll()
                                    return first
                                }
                                throw AIError.processingTimeout
                            }
                            
                            await MainActor.run {
                                transcript.aiTitle = result.text
                                try? self.modelContext?.save()
                                self.logger.info("Generated title: '\(result.text)' (method: \(result.model ?? "unknown"))")
                                
                                // Reload to update UI
                                self.loadRecentRecordings()
                            }
                        } catch {
                            await MainActor.run {
                                self.logger.warning("Failed to generate title: \(error)")
                                // Generate fallback title
                                let fallbackTitle = self.generateFallbackTitle(from: transcriptText)
                                transcript.aiTitle = fallbackTitle
                                self.logger.debug("Using fallback title: '\(fallbackTitle)'")
                                try? self.modelContext?.save()
                                self.loadRecentRecordings()
                            }
                        }
                    }
                    } else {
                        // Set default title if auto-generation is disabled
                        transcript.aiTitle = self.generateFallbackTitle(from: transcriptText)
                        try? modelContext?.save()
                        loadRecentRecordings()
                    }
                    
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
            
            // Extract processing time and token usage based on result type
            let processingTime: TimeInterval
            let tokenUsage: Int?
            
            switch result {
            case .cloud(let response):
                processingTime = response.processingTime
                tokenUsage = response.usage?.totalTokens
            case .local(let response):
                processingTime = response.deviceProcessingTime
                tokenUsage = nil
            case .mock:
                processingTime = 0
                tokenUsage = nil
            }
            
            // Create processed note
            let processedNote = ProcessedNote(
                templateId: template.id,
                templateName: template.name,
                processedText: result.text,
                processingTime: processingTime,
                tokenUsage: tokenUsage
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