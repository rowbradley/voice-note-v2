//
//  LibraryWindowView.swift
//  Voice Note (macOS)
//
//  Main library window with NavigationSplitView showing all recordings.
//

import SwiftUI
import SwiftData
import os.log

struct LibraryWindowView: View {
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    private let logger = Logger(subsystem: "com.voicenote", category: "LibraryWindowView")

    @Query(sort: \Recording.createdAt, order: .reverse)
    private var allRecordings: [Recording]

    @State private var selectedRecording: Recording?
    @State private var searchText = ""
    @State private var selectedFilter: LibraryFilter = .all

    enum LibraryFilter: String, CaseIterable {
        case all = "All Notes"
        case archive = "Archive"
        case mac = "Mac"
        case ios = "iPhone/iPad"

        var icon: String {
            switch self {
            case .all: return "note.text"
            case .archive: return "archivebox"
            case .mac: return "desktopcomputer"
            case .ios: return "iphone"
            }
        }
    }

    private var filteredRecordings: [Recording] {
        var results = allRecordings

        // Filter by archive status and device
        switch selectedFilter {
        case .all:
            // All Notes excludes archived recordings
            results = results.filter { !$0.isArchived }
        case .archive:
            // Archive shows only archived recordings
            results = results.filter { $0.isArchived }
        case .mac:
            results = results.filter { $0.sourceDevice == .macOS && !$0.isArchived }
        case .ios:
            results = results.filter { $0.sourceDevice == .iOS && !$0.isArchived }
        }

        // Filter by search text
        if !searchText.isEmpty {
            results = results.filter { recording in
                recording.title.localizedCaseInsensitiveContains(searchText) ||
                recording.transcript?.plainText.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return results
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar with filters
            sidebarContent
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            // Main content area
            if let recording = selectedRecording {
                RecordingDetailMacView(recording: recording)
                    .id(recording.id)
            } else {
                emptyDetailState
            }
        }
        .searchable(text: $searchText, prompt: "Search recordings")
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedRecording) {
            Section("Filter") {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    Button(action: { selectedFilter = filter }) {
                        Label(filter.rawValue, systemImage: filter.icon)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedFilter == filter ? .accentColor : .primary)
                }
            }

            Section("Transcripts (\(filteredRecordings.count))") {
                ForEach(filteredRecordings) { recording in
                    RecordingListRow(recording: recording)
                        .tag(recording)
                }
                .onDelete(perform: deleteRecordings)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    // TODO: Implement new recording from library window
                }) {
                    Image(systemName: "plus")
                }
                .help("New Recording")
            }
        }
    }

    // MARK: - Empty State

    private var emptyDetailState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select a Recording")
                .font(.title2)
                .foregroundColor(.primary)

            Text("Choose a recording from the sidebar to view details")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = filteredRecordings[index]
            modelContext.delete(recording)
        }
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to delete recordings: \(error.localizedDescription)")
        }
    }
}

// MARK: - Recording List Row

struct RecordingListRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(recording.title)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                // Device icon
                Image(systemName: recording.sourceDevice.iconName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)
                Text(TimeFormatting.shortDuration(recording.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recording Detail View (Mac-specific)

struct RecordingDetailMacView: View {
    @Bindable var recording: Recording

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var transcriptText = ""  // Local state for TextEditor
    @State private var transcriptSaveTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.voicenote", category: "RecordingDetailMacView")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with title
                headerSection

                Divider()

                // Audio player
                if let audioURL = recording.audioFileURL {
                    AudioPlayerSection(url: audioURL)
                }

                Divider()

                // Transcript section
                transcriptSection

                // Processed notes section
                processedNotesSection
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if recording.isArchived {
                    Button(action: unarchiveRecording) {
                        Label("Unarchive", systemImage: "archivebox")
                    }
                    .help("Unarchive Recording")
                }

                Button(action: shareRecording) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share")

                Button(action: copyTranscript) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy Transcript")
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isEditingTitle {
                    TextField("Title", text: $editedTitle)
                        .font(.title)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            saveTitle()
                        }
                } else {
                    Text(recording.title)
                        .font(.title)
                }

                Spacer()

                Button(action: {
                    if isEditingTitle {
                        saveTitle()
                    } else {
                        // Populate editedTitle when entering edit mode
                        editedTitle = recording.transcript?.aiTitle ?? ""
                    }
                    isEditingTitle.toggle()
                }) {
                    Image(systemName: isEditingTitle ? "checkmark" : "pencil")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Label(recording.createdAt.formatted(date: .long, time: .shortened), systemImage: "calendar")

                Label(TimeFormatting.shortDuration(recording.duration), systemImage: "clock")

                Label(recording.sourceDevice.rawValue, systemImage: recording.sourceDevice.iconName)

                if recording.isArchived {
                    Label("Archived", systemImage: "archivebox.fill")
                        .foregroundColor(.orange)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.headline)

                Spacer()

                Text("Auto-saves")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if recording.transcript != nil {
                TextEditor(text: $transcriptText)
                    .font(.body)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    .task(id: recording.id) {
                        // Sync local state when recording changes
                        transcriptText = recording.transcript?.plainText ?? ""
                    }
                    .onChange(of: transcriptText) { _, newValue in
                        // Debounced auto-save when user edits
                        transcriptSaveTask?.cancel()
                        transcriptSaveTask = Task {
                            try? await Task.sleep(for: .seconds(1))
                            guard !Task.isCancelled else { return }
                            recording.transcript?.rawText = AttributedString(newValue)
                            try? modelContext.save()
                        }
                    }
                    .onDisappear {
                        transcriptSaveTask?.cancel()
                    }
            } else {
                Text("No transcript available")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    private var processedNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processed Notes")
                .font(.headline)

            if recording.processedNotes.isEmpty {
                Text("No processed notes")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(recording.processedNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.templateName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(note.plainText)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func saveTitle() {
        recording.transcript?.aiTitle = editedTitle
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save title: \(error.localizedDescription)")
        }
        isEditingTitle = false
    }

    private func unarchiveRecording() {
        recording.isArchived = false
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to unarchive: \(error.localizedDescription)")
        }
    }

    private func shareRecording() {
        // TODO: Implement sharing
    }

    private func copyTranscript() {
        if let plainText = recording.transcript?.plainText {
            PlatformPasteboard.shared.copyText(plainText)
            PlatformFeedback.shared.success()
        }
    }
}

// MARK: - Audio Player Section

struct AudioPlayerSection: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio")
                .font(.headline)

            HStack {
                Button(action: {
                    // TODO: Implement audio playback with AudioPlaybackManager
                }) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.bordered)

                // TODO: Replace with real waveform visualization
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 40)
            }
        }
    }
}

#Preview {
    LibraryWindowView()
        .frame(width: 800, height: 600)
}
