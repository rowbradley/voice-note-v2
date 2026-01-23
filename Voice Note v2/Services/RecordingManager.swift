import SwiftUI
import AVFoundation
import Speech
import SwiftData
import Observation
import os.log

@MainActor
@Observable
final class RecordingManager {
    var recordingState: RecordingState = .idle
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

    /// Whether recording is currently paused (only available with live transcription)
    var isPaused: Bool {
        liveAudioService.isPaused
    }

    // MARK: - Services
    //
    // Recording Architecture:
    //
    // PRIMARY PATH (iOS 26+): LiveAudioService + LiveTranscriptionService
    //   - Uses AVAudioEngine for real-time buffer streaming
    //   - Feeds audio to SpeechAnalyzer for live transcription
    //   - User sees transcript as they speak
    //
    // FALLBACK PATH: AudioRecordingService (deprecated)
    //   - Uses AVAudioRecorder (simpler, no buffer access)
    //   - Records to file, transcribes after recording stops
    //   - Used when: speech permissions denied, Siri disabled, etc.
    //
    // Decision made in startRecording(): checks liveTranscriptionService.isAvailable

    #if os(iOS)
    /// @deprecated Fallback recording service for when live transcription unavailable.
    /// Uses AVAudioRecorder — cannot stream buffers for real-time transcription.
    /// iOS-only: macOS always uses LiveAudioService.
    let audioRecordingService = AudioRecordingService()
    #endif

    /// Primary recording service using AVAudioEngine.
    /// Streams audio buffers to SpeechAnalyzer for live transcription.
    let liveAudioService = LiveAudioService()

    /// Live transcription coordinator.
    /// Manages SpeechAnalyzer and provides transcript updates during recording.
    let liveTranscriptionService = LiveTranscriptionService()

    // Transcription services
    private let transcriptionService = TranscriptionService()  // Fallback for post-recording
    private let aiService: any AIService

    // MARK: - Computed Properties for UI

    /// Convenience property for checking if actively in a recording session.
    /// True when recording or paused; false when idle or processing.
    var isRecordingOrPaused: Bool {
        recordingState == .recording || recordingState == .paused
    }

    /// Audio level - uses live service when available, falls back to legacy (iOS only)
    var currentAudioLevel: Float {
        #if os(iOS)
        isUsingLiveTranscription ? liveAudioService.currentAudioLevel : audioRecordingService.currentAudioLevel
        #else
        liveAudioService.currentAudioLevel
        #endif
    }

    /// Recording duration - uses live service when available, falls back to legacy (iOS only)
    var currentDuration: TimeInterval {
        #if os(iOS)
        isUsingLiveTranscription ? liveAudioService.currentDuration : audioRecordingService.currentDuration
        #else
        liveAudioService.currentDuration
        #endif
    }

    /// Input device name - uses live service when available, falls back to legacy (iOS only)
    var currentInputDevice: String {
        #if os(iOS)
        isUsingLiveTranscription ? liveAudioService.currentInputDevice : audioRecordingService.currentInputDevice
        #else
        liveAudioService.currentInputDevice
        #endif
    }

    /// Voice detection - uses live service when available, falls back to legacy (iOS only)
    var isVoiceDetected: Bool {
        #if os(iOS)
        isUsingLiveTranscription ? liveAudioService.isVoiceDetected : audioRecordingService.isVoiceDetected
        #else
        liveAudioService.isVoiceDetected
        #endif
    }

    /// Cached value of whether an external input device is connected (updated by updateCurrentAudioDevice)
    private(set) var isExternalInputConnected: Bool = false

    /// Update current audio input device (call on view appear to show device indicator)
    func updateCurrentAudioDevice() {
        Task {
            await liveAudioService.updateAudioInputDevice()
            isExternalInputConnected = await liveAudioService.isExternalInputConnected
        }
    }
    
    private var modelContext: ModelContext?
    private let logger = Logger(subsystem: "com.voicenote", category: "RecordingManager")

    // MARK: - Helper Methods (extracted to reduce duplication)

    /// Saves audio file from temporary location to Documents directory
    /// Returns the destination URL and generated filename
    private func saveAudioFile(from sourceURL: URL) throws -> (destinationURL: URL, fileName: String) {
        let fileName = "\(UUID().uuidString).m4a"
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Documents directory unavailable")
            throw NSError(domain: "RecordingManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Documents directory unavailable"])
        }
        let destinationURL = documentsDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            logger.debug("Audio file saved to: \(destinationURL)")
            return (destinationURL, fileName)
        } catch {
            logger.error("Failed to save audio file: \(error)")
            throw error
        }
    }

    /// Creates a Recording, saves it to SwiftData, and updates the UI
    private func createAndSaveRecording(fileName: String, duration: TimeInterval) throws -> Recording {
        let recording = Recording(
            audioFileName: fileName,
            duration: duration
        )

        // Auto-assign to today's session
        if let session = findOrCreateTodaySession() {
            recording.session = session
            logger.debug("Recording assigned to session: \(session.startedAt)")
        }

        modelContext?.insert(recording)
        try modelContext?.save()

        lastRecordingId = recording.id
        loadRecentRecordings()
        logger.info("Recording saved to database")

        return recording
    }

    // MARK: - Session Management

    /// Finds or creates a session for today (calendar-day based).
    /// Sessions group recordings by calendar day using device's local timezone.
    private func findOrCreateTodaySession() -> Session? {
        guard let modelContext = modelContext else { return nil }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        // Try to find existing session for today
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { session in
                session.startedAt == todayStart
            }
        )

        do {
            let existingSessions = try modelContext.fetch(descriptor)
            if let todaySession = existingSessions.first {
                return todaySession
            }

            // No session for today - create one
            let newSession = Session(date: Date())
            modelContext.insert(newSession)

            // Close previous day's session if it exists and is still open
            closePreviousSession(before: todayStart)

            logger.info("Created new session for \(todayStart)")
            return newSession

        } catch {
            logger.error("Failed to find/create session: \(error)")
            return nil
        }
    }

    /// Closes any open session from before the given date
    private func closePreviousSession(before date: Date) {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { session in
                session.endedAt == nil && session.startedAt < date
            }
        )

        do {
            let openSessions = try modelContext.fetch(descriptor)
            for session in openSessions {
                session.endedAt = date
                logger.debug("Closed session from \(session.startedAt)")
            }
        } catch {
            logger.error("Failed to close previous sessions: \(error)")
        }
    }

    /// Clears the status text after a delay using structured concurrency
    private func clearStatusAfterDelay(_ delay: TimeInterval = 2.0) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            self.statusText = ""
        }
    }
    
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

    /// Prewarm transcription and audio assets at app launch (non-blocking)
    /// Downloads the on-device speech recognition model if needed, preheats the analyzer,
    /// and pre-warms audio hardware to prevent first-recording failures.
    func prewarmTranscription() {
        guard liveTranscriptionService.isAvailable else {
            logger.info("🔥 Prewarm skipped: Live transcription not available")
            return
        }

        logger.info("🔥 Prewarming transcription assets...")

        Task {
            do {
                // Step 1: Ensure model is downloaded (Optimization 1)
                if !liveTranscriptionService.isModelDownloaded {
                    try await liveTranscriptionService.ensureModelAvailable()
                    logger.info("🔥 Model download complete")
                } else {
                    logger.info("🔥 Model already downloaded")
                }

                // Step 2: Preheat the analyzer (Optimization 2)
                await liveTranscriptionService.prepareAnalyzer()
                logger.info("🔥 Transcription prewarm complete")

                // Step 3: Pre-warm audio hardware (fixes first-recording failure bug)
                // Apple: inputNode is created "on demand when first accessing" - must
                // access after session is configured or hardware returns 0 sample rate
                try await liveAudioService.prewarmAudioSystem()
                logger.info("🔥 Prewarm complete: Ready for low-latency recording")

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
        case .paused:
            await stopRecording()  // Stop from paused state
        case .processing:
            logger.debug("Currently processing, ignoring tap")
            break // Do nothing while processing
        }

        logger.debug("State transition: \(String(describing: oldState)) → \(String(describing: self.recordingState))")
    }

    /// Stops recording and copies transcript to clipboard (for Quick Capture mode).
    ///
    /// Used by menu bar Quick Capture mode where there's no floating panel.
    /// Recording happens "headlessly" and transcript is auto-copied on stop.
    ///
    /// - Returns: The transcript if successful, nil otherwise
    func stopRecordingAndCopyToClipboard() async -> String? {
        guard recordingState == .recording || recordingState == .paused else {
            logger.debug("stopRecordingAndCopyToClipboard called but not recording")
            return nil
        }

        // Stop recording via normal flow
        await toggleRecording()

        // Get the transcript that was just recorded
        let transcript = liveTranscript
        guard !transcript.isEmpty else {
            logger.info("No transcript to copy (empty)")
            return nil
        }

        // Copy to clipboard
        PlatformPasteboard.shared.copyText(transcript)
        PlatformFeedback.shared.success()
        logger.info("Transcript copied to clipboard (\(transcript.count) chars)")

        return transcript
    }

    /// Pause recording (only available with live transcription).
    ///
    /// Note: Pause/resume only works with LiveAudioService (AVAudioEngine).
    /// AVAudioRecorder.pause() has known bugs - see https://developer.apple.com/forums/thread/721749
    ///
    /// - Throws: Error if pause fails
    func pauseRecording() throws {
        guard isUsingLiveTranscription else {
            throw RecordingManagerError.pauseNotAvailable
        }
        guard recordingState == .recording else {
            throw RecordingManagerError.invalidState("Cannot pause: not recording")
        }

        try liveAudioService.pauseRecording()
        liveTranscriptionService.pauseTranscribing()
        recordingState = .paused
        statusText = "Paused"
        logger.info("Recording paused")
    }

    /// Resume recording (only available with live transcription)
    /// - Throws: Error if resume fails
    func resumeRecording() throws {
        guard isUsingLiveTranscription else {
            throw RecordingManagerError.resumeNotAvailable
        }
        guard recordingState == .paused else {
            throw RecordingManagerError.invalidState("Cannot resume: not paused")
        }

        try liveAudioService.resumeRecording()
        liveTranscriptionService.resumeTranscribing()
        recordingState = .recording
        statusText = "Recording..."
        logger.info("Recording resumed")
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
                await liveTranscriptionService.cancelTranscription()
            }
        } else {
            logger.info("🔴 Live transcription NOT available, using legacy path")
        }

        #if os(iOS)
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
        #else
        // macOS: No fallback, live transcription required
        logger.error("🔴 Recording failed: Live transcription unavailable on macOS")
        recordingState = .idle
        statusText = "Recording unavailable - speech recognition required"
        #endif
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

        #if os(iOS)
        // Legacy recording flow (iOS only)
        await stopLegacyRecording()
        #else
        // macOS: Should never reach here - live transcription always used
        logger.error("Unexpected: stopRecording called without live transcription on macOS")
        recordingState = .idle
        statusText = "Recording error"
        #endif
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

            // Save audio file and create recording (using helper methods)
            let (destinationURL, fileName) = try saveAudioFile(from: audioURL)
            let recording = try createAndSaveRecording(fileName: fileName, duration: duration)

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

            clearStatusAfterDelay()

        } catch {
            logger.error("Failed to stop live recording: \(error)")
            recordingState = .idle
            statusText = "Failed to process recording"
            isUsingLiveTranscription = false
            await liveTranscriptionService.cancelTranscription()
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

        // Auto-cleanup for Pro users
        if AppSettings.shared.isProUser {
            do {
                let onDeviceAI = OnDeviceAIService()
                let cleaned = try await onDeviceAI.cleanupTranscript(transcript.rawText)
                transcript.cleanedText = cleaned
                logger.info("Auto-cleanup completed: \(String(cleaned.characters).count) chars")
            } catch {
                logger.warning("Auto-cleanup failed: \(error)")
            }
        }

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

    #if os(iOS)
    /// Legacy recording flow (fallback when live transcription unavailable)
    /// iOS-only: macOS always uses LiveAudioService.
    private func stopLegacyRecording() async {
        do {
            let (audioURL, duration) = try await audioRecordingService.stopRecording()
            logger.info("Recording stopped. Duration: \(duration)s, File: \(audioURL)")

            // Save audio file and create recording (using helper methods)
            let (destinationURL, fileName) = try saveAudioFile(from: audioURL)
            let recording = try createAndSaveRecording(fileName: fileName, duration: duration)
            logger.info("Recording saved to database. Total recordings: \(self.recentRecordings.count)")

            // Reset state immediately - don't block UI
            recordingState = .idle
            statusText = "Recording saved!"

            // Start transcription in background (don't block UI)
            Task {
                await transcribeLegacyRecording(recording, audioURL: destinationURL)
            }

            clearStatusAfterDelay()

        } catch {
            recordingState = .idle
            statusText = "Failed to process recording: \(error.localizedDescription)"
        }
    }

    /// Transcribes a legacy recording with progress updates
    /// iOS-only: macOS always uses live transcription.
    private func transcribeLegacyRecording(_ recording: Recording, audioURL: URL) async {
        var progressTask: Task<Void, Never>?

        do {
            isTranscribing = true
            statusText = "Transcribing..."
            logger.debug("Starting transcription for file: \(audioURL)")

            // Show progress updates with cancellable task
            progressTask = Task {
                let messages = [
                    "Processing audio...",
                    "Still transcribing...",
                    "This may take a moment...",
                    "Almost there...",
                    "Finalizing transcript...",
                    "Taking longer than expected..."
                ]
                for i in 1...6 {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    if isTranscribing && !Task.isCancelled {
                        await MainActor.run {
                            statusText = messages[min(i-1, messages.count-1)]
                        }
                    } else {
                        break
                    }
                }
            }

            let transcriptText = try await transcriptionService.transcribe(audioURL: audioURL, progressCallback: nil)
            progressTask?.cancel()
            logger.info("Transcription completed. Length: \(transcriptText.count) chars")

            // Create and save transcript
            let transcript = Transcript(text: transcriptText)
            recording.transcript = transcript
            generateTitle(for: transcript, from: transcriptText, recording: recording)

            try modelContext?.save()
            logger.debug("Saved transcript to database")

            // Class is @MainActor, no need for MainActor.run wrapper
            isTranscribing = false
            statusText = "Transcription complete!"
            loadRecentRecordings()

        } catch {
            progressTask?.cancel()

            // Class is @MainActor, no need for MainActor.run wrapper
            isTranscribing = false
            statusText = "Transcription failed"
            logger.error("Transcription error: \(error)")

            failedTranscriptionMessage = "Recording saved to Library. Transcription failed - recording may be too short or contain no audio."
            showFailedTranscriptionAlert = true

            if let index = recentRecordings.firstIndex(where: { $0.id == recording.id }) {
                recentRecordings.remove(at: index)
            }
        }
    }
    #endif

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
                let transcriptInfo = recording.transcript != nil ? "'\(recording.transcript!.plainText.prefix(30))...'" : "nil"
                logger.debug("Recording \(index): transcript = \(transcriptInfo)")
            }
            
            // Only show recordings with transcripts in recent (successful transcriptions)
            recentRecordings = allRecordings.filter { $0.transcript != nil && !($0.transcript?.plainText.isEmpty ?? true) }
            logger.info("Loaded \(self.recentRecordings.count) recordings with transcripts (total: \(allRecordings.count))")
            
            // Debug: Show first recent recording
            if let first = recentRecordings.first {
                logger.debug("First recent recording transcript: '\(first.transcript?.plainText.prefix(50) ?? "nil")...'")
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
            let result = try await aiService.processTemplate(templateInfo, transcript: transcript.plainText)
            
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
            
            // Class is @MainActor, no need for MainActor.run wrapper
            isProcessingTemplate = false
            statusText = "Template applied!"
            loadRecentRecordings()

            clearStatusAfterDelay()

        } catch {
            // Class is @MainActor, no need for MainActor.run wrapper
            isProcessingTemplate = false
            statusText = "Template processing failed"
            throw error
        }
    }

    // MARK: - Archive Management

    /// Archive a recording by ID.
    /// Used by FloatingPanelView to auto-archive quick captures after copying.
    ///
    /// - Parameter id: The recording ID to archive
    /// - Returns: true if archiving succeeded, false otherwise
    @discardableResult
    func archiveRecording(id: UUID) -> Bool {
        guard let modelContext = modelContext else {
            logger.warning("Cannot archive: ModelContext not available")
            return false
        }

        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate<Recording> { recording in
                recording.id == id
            }
        )

        do {
            if let recording = try modelContext.fetch(descriptor).first {
                recording.isArchived = true
                try modelContext.save()
                logger.info("Archived recording: \(id)")
                return true
            } else {
                logger.warning("Recording not found for archiving: \(id)")
                return false
            }
        } catch {
            logger.error("Failed to archive recording: \(error)")
            return false
        }
    }

}

// MARK: - Errors

enum RecordingManagerError: LocalizedError {
    case pauseNotAvailable
    case resumeNotAvailable
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .pauseNotAvailable:
            return "Pause is only available with live transcription"
        case .resumeNotAvailable:
            return "Resume is only available with live transcription"
        case .invalidState(let message):
            return message
        }
    }
}