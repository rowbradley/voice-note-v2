import SwiftUI

struct RecentRecordingCard: View {
    let recording: Recording
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Top row: Duration and template indicator
                HStack {
                    // Duration badge
                    HStack(spacing: 2) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                        Text(formatDuration(recording.duration))
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    // Template indicators
                    if !recording.processedNotes.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(Array(recording.processedNotes.prefix(2)), id: \.id) { note in
                                Image(systemName: templateIcon(for: note.templateName))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            if recording.processedNotes.count > 2 {
                                Text("+\(recording.processedNotes.count - 2)")
                                    .font(.system(size: 8, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Title or transcript preview
                VStack(alignment: .leading, spacing: 2) {
                    if let aiTitle = recording.transcript?.aiTitle {
                        Text(aiTitle)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                    
                    if let transcript = recording.transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                       !transcript.isEmpty {
                        Text(transcript)
                            .font(.system(.caption2, design: .rounded))
                            .lineLimit(recording.transcript?.aiTitle != nil ? 1 : 2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Date
                Text(formatRelativeDate(recording.createdAt))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(width: 120, height: 120)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .day], from: date, to: now)
        
        if let days = components.day, days > 0 {
            return days == 1 ? "Yesterday" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        } else {
            return "Just now"
        }
    }
    
    private func templateIcon(for templateName: String) -> String {
        switch templateName.lowercased() {
        case let name where name.contains("summary"):
            return "doc.text"
        case let name where name.contains("action"):
            return "checklist"
        case let name where name.contains("brainstorm"):
            return "lightbulb"
        case let name where name.contains("quote"):
            return "quote.bubble"
        case let name where name.contains("outline"):
            return "list.bullet.indent"
        case let name where name.contains("flashcard"):
            return "rectangle.stack"
        case let name where name.contains("mood"):
            return "heart"
        case let name where name.contains("reply"):
            return "bubble.left.and.bubble.right"
        case let name where name.contains("section"):
            return "text.alignleft"
        case let name where name.contains("question"):
            return "questionmark.circle"
        default:
            return "wand.and.stars"
        }
    }
}

#Preview {
    HStack {
        RecentRecordingCard(
            recording: Recording(
                audioFileName: "test-recording-1.m4a",
                duration: 125
            )
        ) { }
        
        RecentRecordingCard(
            recording: Recording(
                audioFileName: "test-recording-2.m4a",
                duration: 45
            )
        ) { }
    }
    .padding()
}