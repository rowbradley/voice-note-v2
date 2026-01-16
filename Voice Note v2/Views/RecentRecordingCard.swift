import SwiftUI

struct RecentRecordingCard: View {
    let recording: Recording
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Quotation mark accent
                Text("\u{201C}")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.3))

                // Title flowing into preview (Text concatenation)
                titleAndPreviewText
                    .lineLimit(3)

                Spacer(minLength: 0)

                // Metadata footer
                HStack {
                    Text(formatRelativeDate(recording.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDuration(recording.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Spacing.md)
            .frame(width: 180, height: 140)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var titleAndPreviewText: some View {
        if let aiTitle = recording.transcript?.aiTitle {
            // Title flowing into body
            (
                Text(aiTitle)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.primary)
                +
                Text(" — ")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                +
                Text(bodyPreview)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            )
        } else {
            // Just body preview
            Text(bodyPreview)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.primary)
        }
    }

    private var bodyPreview: String {
        if let transcript = recording.transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !transcript.isEmpty {
            return transcript
        }
        return "Transcribing..."
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