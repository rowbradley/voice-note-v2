import SwiftUI

struct LibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    var recordingManager: RecordingManager
    @State private var searchText = ""
    
    var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordingManager.recentRecordings
        } else {
            return recordingManager.recentRecordings.filter { recording in
                recording.title.localizedCaseInsensitiveContains(searchText) ||
                recording.transcript?.text.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if recordingManager.recentRecordings.isEmpty && searchText.isEmpty {
                    // Empty state
                    EmptyLibraryView()
                } else if filteredRecordings.isEmpty && !searchText.isEmpty {
                    // No search results
                    NoSearchResultsView(searchText: searchText)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RecordingRow: View {
    let recording: Recording
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            RecordingRowContent(recording: recording)
        }
        .buttonStyle(PlainButtonStyle())
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
                Text(transcript.text)
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
            
            Text("Try a different search term")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding()
    }
}


#Preview {
    LibraryView(recordingManager: RecordingManager())
}