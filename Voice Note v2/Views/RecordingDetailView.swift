import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import SwiftData
import os.log

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var processedNotes: [ProcessedNote]
    
    @State private var playbackManager = AudioPlaybackManager()
    @State private var showingTemplatePicker = false
    @State private var isProcessingNote = false
    @State private var processingError: String?
    @State private var isRetranscribing = false
    @State private var transcriptionError: String?
    @State private var retranscribeStatus: String = ""
    @State private var transcriptUpdateCounter = 0
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var isGeneratingTitle = false
    
    // Expanded content sheet
    @State private var expandedContent: ExpandedContentType?

    // Raw/cleaned transcript toggle (Pro feature)
    @State private var showingRawTranscript = false

    // Cached share content for performance (ShareLink accesses item multiple times)
    @State private var cachedShareContent: String = ""
    @State private var shareContentDebounceTask: Task<Void, Never>?

    // Save error feedback
    @State private var saveError: String?

    private let logger = Logger(subsystem: "com.voicenote", category: "RecordingDetailView")
    
    // Computed property for this recording's processed notes
    private var recordingNotes: [ProcessedNote] {
        recording.processedNotes.sorted { $0.createdAt > $1.createdAt }
    }
    
    enum ExpandedContentType: Identifiable {
        case transcript(editMode: Bool)
        case note(ProcessedNote, editMode: Bool)
        
        var id: String {
            switch self {
            case .transcript(let editMode):
                return "transcript-\(editMode)"
            case .note(let note, let editMode):
                return "note-\(note.id)-\(editMode)"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Grab bar indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 4)
            
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection
                
                // Compact Audio Player with integrated share
                CompactAudioPlayer(
                    playbackManager: playbackManager,
                    audioURL: recording.audioFileURL,
                    fileSize: getFileSize()
                )
                
                // Transcript
                if let transcript = recording.transcript {
                    VStack(spacing: 8) {
                        // Show retranscribe status if active
                        if isRetranscribing {
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Re-transcribing...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if !retranscribeStatus.isEmpty {
                                    Text(retranscribeStatus)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }

                        // Raw/cleaned toggle (only shown when cleaned version exists)
                        if transcript.cleanedText != nil {
                            Toggle("Show original", isOn: $showingRawTranscript)
                                .font(.caption)
                                .padding(.horizontal)
                        }

                        // Display content - use raw or cleaned based on toggle
                        let displayContent = showingRawTranscript ? transcript.rawText : transcript.displayText

                        NoteCardView(
                            title: "Transcript",
                            content: displayContent,
                            canEdit: true,
                            onTap: {
                                expandedContent = .transcript(editMode: false)
                            },
                            onEditTap: {
                                expandedContent = .transcript(editMode: true)
                            },
                            onRetranscribe: { Task { await retranscribe() } }
                        )
                        .disabled(isRetranscribing)
                        .opacity(isRetranscribing ? 0.6 : 1.0)
                        .id("transcript-\(transcriptUpdateCounter)")
                    }
                } else {
                    transcriptPlaceholder
                }
                
                // Modify Note Section
                modifyNoteSection
                
                // Processed Notes History
                if !recordingNotes.isEmpty {
                    processedNotesSection
                }
            }
            .padding()
        }
    }
    .navigationTitle("Note Details")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Share note content button (uses cached content for performance)
                ShareLink(item: cachedShareContent) {
                    Label("Share Note", systemImage: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            if let audioURL = recording.audioFileURL {
                playbackManager.setupAudio(url: audioURL)
            }
            updateShareContent()
        }
        .onDisappear {
            playbackManager.stopPlayback()
        }
        .onChange(of: recording.transcript?.rawText) { _, _ in
            // Debounce share content updates to reduce overhead on rapid transcript changes
            shareContentDebounceTask?.cancel()
            shareContentDebounceTask = Task {
                try? await Task.sleep(nanoseconds: AudioConstants.Debounce.shareContent)
                guard !Task.isCancelled else { return }
                updateShareContent()
            }
        }
        .onChange(of: recordingNotes.count) { _, _ in
            // Notes count changes less frequently, update immediately
            updateShareContent()
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerView(recording: recording) { template in
                showingTemplatePicker = false
                Task {
                    await processTemplate(template)
                }
            }
        }
        .sheet(item: $expandedContent) { contentType in
            switch contentType {
            case .transcript(let editMode):
                if let transcript = recording.transcript {
                    InlineExpandedContentView(
                        title: "Transcript",
                        initialContent: showingRawTranscript ? transcript.rawText : transcript.displayText,
                        startInEditMode: editMode,
                        onSave: { newContent in
                            // Save transcript content (JSON-encoded AttributedString)
                            transcript.rawText = newContent

                            guard modelContext.hasChanges else { return }
                            do {
                                try modelContext.save()
                                // Force UI refresh
                                transcriptUpdateCounter += 1
                            } catch {
                                logger.error("Transcript save failed: \(error)")
                                saveError = "Failed to save transcript"
                            }
                        }
                    )
                }
            case .note(let note, let editMode):
                InlineExpandedContentView(
                    title: note.templateName,
                    initialContent: note.content,
                    startInEditMode: editMode,
                    onSave: { newContent in
                        // Save note content (JSON-encoded AttributedString)
                        note.content = newContent

                        guard modelContext.hasChanges else { return }
                        do {
                            try modelContext.save()
                        } catch {
                            logger.error("Note save failed: \(error)")
                            saveError = "Failed to save note"
                        }
                    }
                )
            }
        }
        .alert("Save Error", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    } // End of NavigationStack
    } // End of top VStack
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isEditingTitle {
                    TextField("Enter title", text: $editedTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            saveEditedTitle()
                        }
                    
                    Button("Save") {
                        saveEditedTitle()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("Cancel") {
                        isEditingTitle = false
                        editedTitle = recording.title
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text(recording.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Menu {
                        Button(action: { startEditingTitle() }) {
                            Label("Edit Title", systemImage: "pencil")
                        }
                        
                        if recording.transcript != nil {
                            Button(action: { Task { await regenerateTitle() } }) {
                                Label("Regenerate Title", systemImage: "arrow.clockwise")
                            }
                            .disabled(isGeneratingTitle)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if isGeneratingTitle {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating title...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Label(Formatters.dateTime(recording.createdAt), systemImage: "calendar")
                Spacer()
                Label(Formatters.duration(recording.duration), systemImage: "clock")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
    
    private func getFileSize() -> String? {
        guard let url = recording.audioFileURL else { return nil }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? NSNumber {
                let sizeInMB = Double(fileSize.intValue) / 1048576.0
                if sizeInMB < 1 {
                    let sizeInKB = Double(fileSize.intValue) / 1024.0
                    return String(format: "%.0f KB", sizeInKB)
                } else {
                    return String(format: "%.1f MB", sizeInMB)
                }
            }
        } catch {
            // Unable to get file size
        }
        
        return nil
    }
    
    private var transcriptPlaceholder: some View {
        VStack(spacing: 12) {
            if isRetranscribing {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !retranscribeStatus.isEmpty {
                        Text(retranscribeStatus)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            } else if recording.createdAt.timeIntervalSinceNow > -300 {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Image(systemName: "text.quote")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                
                Text("No transcript available")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if let error = transcriptionError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Button(action: { Task { await retranscribe() } }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-transcribe")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isRetranscribing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var modifyNoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modify Note")
                .font(.headline)
            
            if isProcessingNote {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Processing note...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else if let error = processingError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Processing failed")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                Button(action: { showingTemplatePicker = true }) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Apply Template")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(recording.transcript?.rawText.characters.isEmpty == true)
            }
        }
    }
    
    private var processedNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note History")
                .font(.headline)
            
            ForEach(recordingNotes) { note in
                ProcessedNoteCard(
                    note: note,
                    onDelete: {
                        deleteProcessedNote(note)
                    },
                    onTap: {
                        expandedContent = .note(note, editMode: false)
                    },
                    onEditTap: {
                        expandedContent = .note(note, editMode: true)
                    }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func processTemplate(_ template: Template) async {
        guard let transcript = recording.transcript?.plainText else {
            processingError = "No transcript available"
            return
        }
        
        isProcessingNote = true
        processingError = nil
        
        do {
            let aiService = AIServiceFactory.shared.createDefaultService()
            let startTime = Date()
            
            let result = try await aiService.processTemplate(
                TemplateInfo(from: template),
                transcript: transcript
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            // Extract processing time based on result type
            let finalProcessingTime: TimeInterval

            switch result {
            case .local(let response):
                finalProcessingTime = response.deviceProcessingTime
            case .mock:
                finalProcessingTime = processingTime
            }

            // Save processed note
            let processedNote = ProcessedNote(
                templateId: template.id,
                templateName: template.name,
                processedText: result.text,
                processingTime: finalProcessingTime,
                tokenUsage: nil  // On-device processing doesn't track tokens
            )
            
            // Add to relationship and save
            recording.processedNotes.append(processedNote)
            
            do {
                try modelContext.save()
                logger.info("Processed note saved successfully")
            } catch {
                logger.error("Failed to save processed note: \(error)")
                // Try to recover by inserting the note explicitly
                modelContext.insert(processedNote)
                processedNote.recording = recording
                
                do {
                    try modelContext.save()
                    logger.info("Recovered and saved after explicit insert")
                } catch {
                    logger.error("Recovery failed: \(error)")
                    throw error
                }
            }
            
            isProcessingNote = false
        } catch {
            processingError = error.localizedDescription
            isProcessingNote = false
        }
    }
    
    private func retranscribe() async {
        guard let audioURL = recording.audioFileURL else {
            transcriptionError = "Audio file not found"
            return
        }
        
        isRetranscribing = true
        transcriptionError = nil
        retranscribeStatus = ""
        
        do {
            let transcriptionService = TranscriptionService()
            let transcriptText = try await transcriptionService.transcribe(
                audioURL: audioURL,
                progressCallback: { status in
                    Task { @MainActor in
                        self.retranscribeStatus = status
                    }
                }
            )
            
            
            if transcriptText.isEmpty {
                throw TranscriptionError.invalidResponse
            }
            
            // Create or update transcript
            if let existingTranscript = recording.transcript {
                existingTranscript.rawText = (try? AttributedString(markdown: transcriptText)) ?? AttributedString(transcriptText)
            } else {
                let transcript = Transcript(text: transcriptText)
                recording.transcript = transcript
            }
            
            try modelContext.save()
            
            // Generate AI title if needed
            if recording.transcript?.aiTitle == nil {
                Task {
                    do {
                        let aiService = AIServiceFactory.shared.createDefaultService()
                        let titleResult = try await aiService.generateTitle(from: transcriptText)
                        recording.transcript?.aiTitle = titleResult.text
                        try? modelContext.save()
                    } catch {
                        logger.error("Failed to generate title: \(error)")
                    }
                }
            }
            
            isRetranscribing = false
            retranscribeStatus = ""
            transcriptUpdateCounter += 1  // Force UI update
        } catch {
            await MainActor.run {
                self.transcriptionError = error.localizedDescription
                self.isRetranscribing = false
                self.retranscribeStatus = ""
            }
        }
    }
    
    
    private func deleteProcessedNote(_ note: ProcessedNote) {
        modelContext.delete(note)
        try? modelContext.save()
    }
    
    
    /// Updates the cached share content (call when transcript or notes change)
    private func updateShareContent() {
        cachedShareContent = fullNoteContent
    }

    private var fullNoteContent: String {
        var content = """
        \(recording.title)
        \(Formatters.dateTime(recording.createdAt))
        Duration: \(Formatters.duration(recording.duration))

        Transcript:
        \(recording.transcript?.plainText ?? "No transcript available")
        """

        // Add all processed notes
        for note in recordingNotes {
            content += """


            \(note.templateName) (\(Formatters.dateTime(note.createdAt))):
            \(note.plainText)
            """
        }
        
        content += """
        
        
        Generated with Voice Note
        """
        
        return content
    }

    private func startEditingTitle() {
        editedTitle = recording.title
        isEditingTitle = true
    }
    
    private func saveEditedTitle() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            recording.transcript?.aiTitle = trimmedTitle
            try? modelContext.save()
        }
        isEditingTitle = false
    }
    
    private func regenerateTitle() async {
        guard let transcript = recording.transcript?.plainText else { return }
        
        isGeneratingTitle = true
        
        do {
            let aiService = AIServiceFactory.shared.createDefaultService()
            
            // Truncate transcript for title generation
            let words = transcript.split(separator: " ")
            let truncatedTranscript = words.prefix(500).joined(separator: " ")
            
            let result = try await aiService.generateTitle(from: truncatedTranscript)
            recording.transcript?.aiTitle = result.text
            try? modelContext.save()
            
            isGeneratingTitle = false
        } catch {
            logger.error("Failed to regenerate title: \(error)")
            isGeneratingTitle = false
        }
    }
}

// MARK: - Processed Note Card
struct ProcessedNoteCard: View {
    let note: ProcessedNote
    let onDelete: () -> Void
    let onTap: () -> Void
    let onEditTap: () -> Void

    var body: some View {
        NoteCardView(
            title: note.templateName,
            content: note.content,  // Uses AttributedString computed property
            canEdit: true,
            createdAt: note.createdAt,
            showDeleteButton: true,
            onTap: onTap,
            onEditTap: onEditTap,
            onDelete: onDelete
        )
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        RecordingDetailView(
            recording: Recording(
                id: UUID(),
                audioFileName: "test.m4a", 
                duration: 120
            )
        )
    }
    .modelContainer(for: [Recording.self, Transcript.self, ProcessedNote.self])
}