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
    @State private var transcriptBinding: String = ""
    @State private var noteBinding: String = ""
    
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
                if recording.transcript != nil {
                    VStack(spacing: 0) {
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
                            .padding(.bottom, 8)
                        }
                        
                        NoteCardView(
                            title: "Transcript",
                            content: recording.transcript?.text ?? "",
                            isMarkdown: false,
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
                // Share note content button
                ShareLink(item: fullNoteContent) {
                    Label("Share Note", systemImage: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            if let audioURL = recording.audioFileURL {
                playbackManager.setupAudio(url: audioURL)
            }
        }
        .onDisappear {
            playbackManager.stopPlayback()
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
                InlineExpandedContentView(
                    title: "Transcript",
                    content: $transcriptBinding,
                    isMarkdown: false,
                    startInEditMode: editMode,
                    onContentChange: { newText in
                        recording.transcript?.text = newText
                        try? modelContext.save()
                    }
                )
                .onAppear {
                    transcriptBinding = recording.transcript?.text ?? ""
                }
            case .note(let note, let editMode):
                InlineExpandedContentView(
                    title: note.templateName,
                    content: $noteBinding,
                    isMarkdown: true,
                    startInEditMode: editMode,
                    onContentChange: { newText in
                        note.processedText = newText
                        try? modelContext.save()
                    }
                )
                .onAppear {
                    noteBinding = note.processedText
                }
            }
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
                Label(formatDate(recording.createdAt), systemImage: "calendar")
                Spacer()
                Label(formatDuration(recording.duration), systemImage: "clock")
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
                .disabled(recording.transcript?.text.isEmpty == true)
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
        guard let transcript = recording.transcript?.text else { 
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
            
            // Extract processing time and token usage based on result type
            let finalProcessingTime: TimeInterval
            let tokenUsage: Int?
            
            switch result {
            case .cloud(let response):
                finalProcessingTime = response.processingTime
                tokenUsage = response.usage?.totalTokens
            case .local(let response):
                finalProcessingTime = response.deviceProcessingTime
                tokenUsage = nil
            case .mock:
                finalProcessingTime = processingTime
                tokenUsage = nil
            }
            
            // Save processed note
            let processedNote = ProcessedNote(
                templateId: template.id,
                templateName: template.name,
                processedText: result.text,
                processingTime: finalProcessingTime,
                tokenUsage: tokenUsage
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
                existingTranscript.text = transcriptText
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
    
    
    private var fullNoteContent: String {
        var content = """
        \(recording.title)
        \(formatDate(recording.createdAt))
        Duration: \(formatDuration(recording.duration))
        
        Transcript:
        \(recording.transcript?.text ?? "No transcript available")
        """
        
        // Add all processed notes
        for note in recordingNotes {
            content += """
            
            
            \(note.templateName) (\(formatDate(note.createdAt))):
            \(note.processedText)
            """
        }
        
        content += """
        
        
        Generated with Voice Note
        """
        
        return content
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
        guard let transcript = recording.transcript?.text else { return }
        
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
            content: note.processedText,
            isMarkdown: true,
            canEdit: true,
            createdAt: note.createdAt,
            showDeleteButton: true,
            onTap: onTap,
            onEditTap: onEditTap,
            onDelete: onDelete
        )
    }
}

// MARK: - Inline Expanded Content View
struct InlineExpandedContentView: View {
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    @Binding var content: String
    let isMarkdown: Bool
    let canEdit: Bool
    
    @State private var isEditing = false
    @FocusState private var isFocused: Bool
    @State private var saveTimer: Timer?
    @State private var lastSavedContent: String = ""
    
    // Callback for when content changes (with built-in debouncing)
    var onContentChange: ((String) -> Void)?
    
    init(title: String, content: Binding<String>, isMarkdown: Bool, startInEditMode: Bool = false, onContentChange: ((String) -> Void)? = nil) {
        self.title = title
        self._content = content
        self.isMarkdown = isMarkdown
        self.canEdit = true
        self._isEditing = State(initialValue: startInEditMode)
        self.onContentChange = onContentChange
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if canEdit && isEditing {
                        // Edit mode
                        TextEditor(text: $content)
                            .focused($isFocused)
                            .font(.body)
                            .foregroundColor(.primary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal)
                            .frame(minHeight: 300)
                            .onChange(of: content) { oldValue, newValue in
                                scheduleAutoSave()
                            }
                    } else if isMarkdown {
                        // View mode - Markdown
                        EnhancedMarkdownView(
                            content: content,
                            templateType: detectTemplateTypeFromContent(content)
                        )
                        .padding()
                        .onTapGesture {
                            if canEdit {
                                startEditing()
                            }
                        }
                    } else {
                        // View mode - Plain text
                        Text(content)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                if canEdit {
                                    startEditing()
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(.systemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveIfNeeded()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            lastSavedContent = content
            
            // If opened in edit mode, start editing
            if canEdit && isEditing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
        .onDisappear {
            // Cancel any pending timer
            saveTimer?.invalidate()
            saveTimer = nil
            
            // Save any unsaved changes
            saveIfNeeded()
        }
    }
    
    private func startEditing() {
        isEditing = true
        isFocused = true
    }
    
    private func scheduleAutoSave() {
        // Cancel existing timer
        saveTimer?.invalidate()
        
        // Schedule new save after 1.0 seconds of inactivity (increased for better battery life)
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            saveIfNeeded()
        }
    }
    
    private func saveIfNeeded() {
        guard content != lastSavedContent else { return }
        
        onContentChange?(content)
        lastSavedContent = content
        
        // Haptic feedback for save
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Helper Functions
    
    private func detectTemplateTypeFromContent(_ content: String) -> String {
        let contentLower = content.lowercased()
        
        // Look for template-specific patterns in the content
        if contentLower.contains("quote") || contentLower.contains(">") {
            return "key quotes"
        } else if contentLower.contains("follow-up") || contentLower.contains("questions") {
            return "next questions"
        } else if contentLower.contains("action") || contentLower.contains("- [ ]") || contentLower.contains("todo") {
            return "action list"
        } else if contentLower.contains("summary") || contentLower.contains("overview") {
            return "smart summary"
        } else if contentLower.contains("outline") || contentLower.contains("## ") {
            return "idea outline"
        } else if contentLower.contains("brainstorm") || contentLower.contains("ideas") {
            return "brainstorm"
        } else if contentLower.contains("flashcard") || contentLower.contains("q:") && contentLower.contains("a:") {
            return "flashcard maker"
        } else if contentLower.contains("tone") || contentLower.contains("emotion") {
            return "tone analysis"
        }
        
        return ""
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