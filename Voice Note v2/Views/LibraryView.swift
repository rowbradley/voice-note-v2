//
//  LibraryView.swift
//  Voice Note v2
//
//  Unified library view for both tab navigation and sheet presentation.
//

import SwiftUI

struct LibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    var recordingManager: RecordingManager
    var showsDismissButton: Bool = true  // Set false when used in tab navigation
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    var filteredRecordings: [Recording] {
        if debouncedSearchText.isEmpty {
            return recordingManager.recentRecordings
        } else {
            return recordingManager.recentRecordings.filter { recording in
                recording.title.localizedCaseInsensitiveContains(debouncedSearchText) ||
                recording.transcript?.plainText.localizedCaseInsensitiveContains(debouncedSearchText) == true
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if recordingManager.recentRecordings.isEmpty && debouncedSearchText.isEmpty {
                    // Empty state
                    EmptyLibraryView()
                } else if filteredRecordings.isEmpty && !debouncedSearchText.isEmpty {
                    // No search results (use searchText for display, debouncedSearchText for filter)
                    NoSearchResultsView(searchText: debouncedSearchText)
                } else {
                    // Recordings list
                    List(filteredRecordings) { recording in
                        NavigationLink(destination: RecordingDetailView(recording: recording)) {
                            RecordingRowContent(recording: recording)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search recordings")
            .onChange(of: searchText) { _, newValue in
                // Debounce search to reduce filtering overhead on rapid typing
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: AudioConstants.Debounce.search)
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct RecordingRowContent: View {
    let recording: Recording
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .lineLimit(2)
                .foregroundColor(.primary)
            
            Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
            
            if let transcript = recording.transcript {
                Text(transcript.displayText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No recordings yet")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            
            Text("Tap the record button to create your first voice memo")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct NoSearchResultsView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No results found")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            
            Text("No matches for \"\(searchText)\"")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding()
    }
}


#Preview {
    LibraryView(recordingManager: RecordingManager())
}