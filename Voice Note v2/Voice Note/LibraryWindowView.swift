//
//  LibraryWindowView.swift
//  Voice Note (macOS)
//
//  Main library window with NavigationSplitView showing recordings grouped by session.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os.log

// MARK: - Selection State

/// Represents what's currently selected in the library sidebar
enum LibrarySelection: Hashable {
    case session(Session)
    case recording(Recording)
}

// MARK: - Shared Context Menu

@ViewBuilder
func recordingContextMenuContent(
    for recording: Recording,
    modelContext: ModelContext,
    onDelete: (() -> Void)? = nil
) -> some View {
    Button("Copy Transcript") {
        if let plainText = recording.transcript?.plainText {
            PlatformPasteboard.shared.copyText(plainText)
            PlatformFeedback.shared.success()
        }
    }

    if let url = recording.audioFileURL,
       FileManager.default.fileExists(atPath: url.path) {
        Button("Reveal Audio File in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    Divider()

    if recording.isArchived {
        Button("Unarchive") {
            recording.isArchived = false
            try? modelContext.save()
        }
    } else {
        Button("Archive") {
            recording.isArchived = true
            try? modelContext.save()
        }
    }

    if recording.isPinned {
        Button("Unpin") {
            recording.isPinned = false
            try? modelContext.save()
        }
    } else {
        Button("Pin (Prevent Deletion)") {
            recording.isPinned = true
            try? modelContext.save()
        }
    }

    if let onDelete {
        Divider()
        Button("Delete", role: .destructive) {
            onDelete()
        }
    }
}

struct LibraryWindowView: View {
    @Environment(RecordingManager.self) private var recordingManager
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    private let logger = Logger(subsystem: "com.voicenote", category: "LibraryWindowView")

    // MARK: - Feature Flags

    /// Enable device-based filters (Mac/iOS) when cross-device sync is implemented
    private static let showDeviceFilters = false

    @Query(sort: \Session.startedAt, order: .reverse)
    private var allSessions: [Session]

    @Query(sort: \Recording.createdAt, order: .reverse)
    private var allRecordings: [Recording]

    @State private var selection: LibrarySelection?
    @State private var searchText = ""
    @State private var selectedFilter: LibraryFilter = .all
    @State private var expandedSessions: Set<UUID> = []

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

        /// Filters to display based on feature flags
        static var availableFilters: [LibraryFilter] {
            if LibraryWindowView.showDeviceFilters {
                return allCases
            } else {
                return [.all, .archive]
            }
        }
    }

    /// Sessions filtered by current filter and search
    private var filteredSessions: [Session] {
        allSessions.filter { session in
            let recordings = filteredRecordings(for: session)
            return !recordings.isEmpty
        }
    }

    /// Recordings for a specific session, filtered by current filter and search
    private func filteredRecordings(for session: Session) -> [Recording] {
        var results = session.recordings.sorted { $0.createdAt > $1.createdAt }

        // Filter by archive status and device
        switch selectedFilter {
        case .all:
            results = results.filter { !$0.isArchived }
        case .archive:
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

    /// Orphan recordings (no session assigned) - shouldn't happen but handle gracefully
    private var orphanRecordings: [Recording] {
        allRecordings.filter { $0.session == nil }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar with filters and session-grouped recordings
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            // Main content area
            detailContent
        }
        .searchable(text: $searchText, prompt: "Search recordings")
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            // Delay ensures window is fully initialized before policy change
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: false)
            }
            // Sessions start collapsed - user expands what they want
        }
        .onDisappear {
            // Only switch back if no other standard windows are visible
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))

                let hasStandardWindows = NSApp.windows.contains { window in
                    window.isVisible &&
                    window.level == .normal &&
                    !(window is NSPanel) &&
                    window.styleMask.contains(.titled)
                }

                if !hasStandardWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .session(let session):
            SessionDetailView(session: session)
        case .recording(let recording):
            RecordingDetailMacView(recording: recording)
                .id(recording.id)
        case nil:
            emptyDetailState
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selection) {
            // Filter section
            Section("Filter") {
                ForEach(LibraryFilter.availableFilters, id: \.self) { filter in
                    Button(action: { selectedFilter = filter }) {
                        Label(filter.rawValue, systemImage: filter.icon)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedFilter == filter ? .accentColor : .primary)
                }
            }

            // Sessions grouped by day
            Section("Sessions") {
                ForEach(filteredSessions) { session in
                    SessionDisclosureGroup(
                        session: session,
                        recordings: filteredRecordings(for: session),
                        isExpanded: Binding(
                            get: { expandedSessions.contains(session.id) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedSessions.insert(session.id)
                                } else {
                                    expandedSessions.remove(session.id)
                                }
                            }
                        ),
                        selection: $selection
                    )
                }
            }

            // Orphan recordings (no session) - edge case handling
            if !orphanRecordings.isEmpty {
                Section("Unsorted") {
                    ForEach(orphanRecordings) { recording in
                        RecordingListRow(recording: recording)
                            .tag(LibrarySelection.recording(recording))
                            .contextMenu {
                                recordingContextMenuContent(
                                    for: recording,
                                    modelContext: modelContext,
                                    onDelete: { deleteRecording(recording) }
                                )
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Empty State

    private var emptyDetailState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select a Recording or Session")
                .font(.title2)
                .foregroundColor(.primary)

            Text("Choose a recording to view details, or select a session header to see the combined transcript")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Actions

    private func deleteRecording(_ recording: Recording) {
        // Delete audio file
        if let audioURL = recording.audioFileURL {
            try? FileManager.default.removeItem(at: audioURL)
        }

        // Delete from database
        modelContext.delete(recording)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to delete recording: \(error.localizedDescription)")
        }

        // Clear selection if deleted recording was selected
        if case .recording(let selected) = selection, selected.id == recording.id {
            selection = nil
        }
    }
}

// MARK: - Session Disclosure Group

struct SessionDisclosureGroup: View {
    let session: Session
    let recordings: [Recording]
    @Binding var isExpanded: Bool
    @Binding var selection: LibrarySelection?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(recordings) { recording in
                RecordingListRow(recording: recording)
                    .tag(LibrarySelection.recording(recording))
                    .contextMenu {
                        recordingContextMenuContent(
                            for: recording,
                            modelContext: modelContext
                        )
                    }
            }
        } label: {
            SessionHeaderRow(session: session, recordingCount: recordings.count)
        }
        .tag(LibrarySelection.session(session))  // Native List selection
    }
}

// MARK: - Session Header Row

struct SessionHeaderRow: View {
    let session: Session
    let recordingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayDate)
                .font(.headline)

            HStack(spacing: 8) {
                Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s")")
                Text("•")
                Text(session.formattedDuration)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recording List Row

struct RecordingListRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if recording.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

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
                Text(recording.createdAt.formatted(date: .omitted, time: .shortened))
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
        .padding(.leading, 12)  // Indent under session header
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: Session

    private let logger = Logger(subsystem: "com.voicenote", category: "SessionDetailView")

    @State private var isCombinedTranscriptExpanded = false
    @State private var sortNewestFirst = false

    /// Static date formatter for export filenames (performance optimization)
    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                sessionHeader

                Divider()

                // Combined transcript
                combinedTranscriptSection

                Divider()

                // Individual recordings with copy buttons
                individualRecordingsSection
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                CopyConfirmButton(text: session.combinedTranscript, label: "Copy All")
                    .help("Copy combined transcript")

                Button(action: exportSession) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export session as Markdown")
            }
        }
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.displayDate)
                .font(.largeTitle)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                Label("\(session.recordingCount) recordings", systemImage: "waveform")
                Label(session.formattedDuration, systemImage: "clock")

                if session.isActive {
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }

    private var combinedTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with copy button
            HStack {
                Text("Combined Transcript")
                    .font(.headline)
                Spacer()
                CopyConfirmButton(text: session.combinedTranscript, showLabel: false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy combined transcript")
            }

            if session.combinedTranscript.isEmpty {
                Text("No transcripts in this session")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                // Collapsible preview
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.combinedTranscript)
                        .font(.body)
                        .textSelection(.enabled)
                        .lineLimit(isCombinedTranscriptExpanded ? nil : 6)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                        .mask(
                            VStack(spacing: 0) {
                                Color.black
                                if !isCombinedTranscriptExpanded {
                                    LinearGradient(
                                        colors: [.black, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 30)
                                }
                            }
                        )

                    // Expand/collapse button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCombinedTranscriptExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isCombinedTranscriptExpanded ? "chevron.up" : "chevron.down")
                            Text(isCombinedTranscriptExpanded ? "Show less" : "Show more")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var individualRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with sort dropdown
            HStack {
                Text("Individual Recordings")
                    .font(.headline)
                Spacer()
                Picker("Sort", selection: $sortNewestFirst) {
                    Text("Oldest First").tag(false)
                    Text("Newest First").tag(true)
                }
                .pickerStyle(.menu)
            }

            if session.recordings.isEmpty {
                Text("No recordings in this session")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                let sortedRecordings = session.recordings.sorted {
                    sortNewestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt
                }
                ForEach(sortedRecordings) { recording in
                    IndividualRecordingRow(recording: recording)
                }
            }
        }
    }

    private func exportSession() {
        let content = """
        # Session: \(session.displayDate)

        **Recordings:** \(session.recordingCount)
        **Total Duration:** \(session.formattedDuration)

        ---

        \(session.combinedTranscript)
        """

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]

        // Format date for filename: 2026-01-26
        let dateString = Self.exportDateFormatter.string(from: session.startedAt)

        panel.nameFieldStringValue = "Session-\(dateString).md"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                logger.info("Exported session to: \(url.path)")
            } catch {
                logger.error("Failed to export session: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Individual Recording Row

struct IndividualRecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: time + duration + copy button
            HStack {
                Text(recording.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("·")
                    .foregroundColor(.secondary)

                Text(TimeFormatting.shortDuration(recording.duration))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                CopyConfirmButton(text: recording.transcript?.plainText, showLabel: false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy this recording's transcript")
            }

            // Transcript text
            if let transcript = recording.transcript?.plainText, !transcript.isEmpty {
                Text(transcript)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            } else {
                Text("No transcript")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Recording Detail View (Mac-specific)

struct RecordingDetailMacView: View {
    @Bindable var recording: Recording

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var transcriptSaveTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.voicenote", category: "RecordingDetailMacView")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with title
                headerSection

                Divider()

                // Audio section (simplified - just reveal in Finder)
                audioSection

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

                CopyConfirmButton(text: recording.transcript?.plainText, showLabel: false)
                    .help("Copy Transcript")
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if recording.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                }

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

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio")
                .font(.headline)

            if let url = recording.audioFileURL,
               FileManager.default.fileExists(atPath: url.path) {
                HStack {
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }) {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        NSWorkspace.shared.open(url)
                    }) {
                        Label("Play in Default App", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Audio file not available")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
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
                TextEditor(text: transcriptBinding)
                    .font(.body)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
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

    // MARK: - Transcript Binding

    /// Computed binding for transcript editing - writes directly to model with debounced save
    private var transcriptBinding: Binding<String> {
        Binding(
            get: { recording.transcript?.plainText ?? "" },
            set: { newValue in
                recording.transcript?.rawText = AttributedString(newValue)
                debouncedSave()
            }
        )
    }

    private func debouncedSave() {
        transcriptSaveTask?.cancel()
        transcriptSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? modelContext.save()
        }
    }
}

// MARK: - Copy Confirm Button

struct CopyConfirmButton: View {
    let text: String?
    var label: String = "Copy"
    var showLabel: Bool = true

    @State private var showingCheckmark = false

    var body: some View {
        Button(action: performCopy) {
            if showLabel {
                Label(
                    showingCheckmark ? "Copied" : label,
                    systemImage: showingCheckmark ? "checkmark" : "doc.on.doc"
                )
            } else {
                Image(systemName: showingCheckmark ? "checkmark" : "doc.on.doc")
            }
        }
        .foregroundColor(showingCheckmark ? .green : nil)
        .disabled(text?.isEmpty ?? true)
    }

    private func performCopy() {
        guard let text, !text.isEmpty else { return }
        PlatformPasteboard.shared.copyText(text)
        PlatformFeedback.shared.success()

        withAnimation(.easeInOut(duration: 0.15)) {
            showingCheckmark = true
        }

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.15)) {
                showingCheckmark = false
            }
        }
    }
}

#Preview {
    LibraryWindowView()
        .frame(width: 800, height: 600)
}
