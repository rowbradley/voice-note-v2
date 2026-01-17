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
                    Text(Formatters.relativeDate(recording.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Formatters.duration(recording.duration))
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