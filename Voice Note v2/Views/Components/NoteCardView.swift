import SwiftUI
import UniformTypeIdentifiers

struct NoteCardView: View {
    let title: String
    let content: AttributedString
    let canEdit: Bool
    let createdAt: Date?
    let showDeleteButton: Bool

    @State private var showCopySuccess = false
    @State private var showingDeleteAlert = false
    @State private var copyHapticTrigger = 0
    @State private var copyFeedbackTask: Task<Void, Never>?

    /// Derived copy button text from state
    private var copyButtonText: String {
        showCopySuccess ? "Copied!" : "Copy"
    }

    // Callbacks
    var onTap: (() -> Void)?
    var onEditTap: (() -> Void)?
    var onRetranscribe: (() -> Void)?
    var onDelete: (() -> Void)?

    // Constants for preview
    private let previewLineHeight: CGFloat = 18 // Reduced for compact view
    private let previewLines: Int = 6
    private var previewHeight: CGFloat {
        previewLineHeight * CGFloat(previewLines) + 8 // Added 8 points for padding
    }

    // MARK: - Initializers

    init(
        title: String,
        content: AttributedString,
        canEdit: Bool,
        createdAt: Date? = nil,
        showDeleteButton: Bool = false,
        onTap: (() -> Void)? = nil,
        onEditTap: (() -> Void)? = nil,
        onRetranscribe: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.title = title
        self.content = content
        self.canEdit = canEdit
        self.createdAt = createdAt
        self.showDeleteButton = showDeleteButton
        self.onTap = onTap
        self.onEditTap = onEditTap
        self.onRetranscribe = onRetranscribe
        self.onDelete = onDelete
    }

    /// Plain text content for copying and sharing
    private var plainTextContent: String {
        String(content.characters)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with consolidated metadata
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    // Template name and date on same line
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.callout)
                            .fontWeight(.medium)
                        
                        if let createdAt = createdAt {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(Formatters.timeOnly(createdAt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if canEdit {
                        Button(action: { onEditTap?() }) {
                            Text("Edit")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // Subtle separator line
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
                    .opacity(0.3)
            }
            
            // Content preview with fade - Native AttributedString rendering
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(content)
                            .font(.callout) // Smaller font for compact view
                            .lineSpacing(6) // Increased for visible paragraph spacing
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .scrollDisabled(true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: previewHeight)
                .clipped()

                // Always show fade overlay
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.7),
                        .init(color: Color(.systemGray6), location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                // Left side: Delete button and transcript menu
                HStack(spacing: 8) {
                    if showDeleteButton {
                        Button(action: { showingDeleteAlert = true }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    // Menu for transcript-specific actions
                    if title == "Transcript" {
                        Menu {
                            if let onRetranscribe = onRetranscribe {
                                Button(action: onRetranscribe) {
                                    Label("Re-transcribe", systemImage: "arrow.clockwise")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                Spacer()
                
                // Right side: Copy and Share buttons
                HStack(spacing: 8) {
                    Button(action: copyContent) {
                        Label(copyButtonText, systemImage: showCopySuccess ? "checkmark.circle.fill" : "doc.on.clipboard")
                            .font(.caption)
                            .foregroundColor(showCopySuccess ? .green : .primary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .animation(.easeInOut(duration: 0.2), value: showCopySuccess)
                    
                    ShareLink(item: plainTextContent) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .fixedSize()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onTapGesture {
            onTap?()
        }
        .alert("Delete Note?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("This will permanently delete this processed note.")
        }
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
    }
    
    private func copyContent() {
        // Copy as rich text with RTF + plain text fallback
        do {
            let nsAttributed = NSAttributedString(content)

            // Convert NSAttributedString to RTF data
            let rtfData = try nsAttributed.data(
                from: NSRange(location: 0, length: nsAttributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )

            UIPasteboard.general.setItems([
                [UTType.plainText.identifier: plainTextContent],
                [UTType.rtf.identifier: rtfData]
            ])
        } catch {
            // Fallback to plain text if RTF conversion fails
            UIPasteboard.general.string = plainTextContent
        }

        // Visual feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopySuccess = true
        }

        // Trigger haptic feedback via sensoryFeedback modifier
        copyHapticTrigger += 1

        // Reset after delay - cancel previous task to avoid conflicts
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCopySuccess = false
                }
            }
        }
    }

    // MARK: - Markdown Export

    /// Converts AttributedString content to markdown for sharing/export
    func markdownForExport() -> String {
        var output = ""
        for run in content.runs {
            var text = String(content[run.range].characters)
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                text = "**\(text)**"
            }
            if run.inlinePresentationIntent?.contains(.emphasized) == true {
                text = "*\(text)*"
            }
            output += text
        }
        return output
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        NoteCardView(
            title: "Transcript",
            content: AttributedString("This is a sample transcript text that can be edited. It contains multiple lines to show how the preview works with the fade effect at the bottom. The content continues beyond what is visible in the preview area."),
            canEdit: true,
            onTap: { },
            onEditTap: { }
        )

        NoteCardView(
            title: "Key Quotes",
            content: (try? AttributedString(markdown: "## Key Insights\n\n> \"This is a powerful insight that demonstrates the markdown rendering capabilities.\"\n\n**Context**: This quote shows how the system handles blockquotes and formatting.\n\n> \"Another important perspective that adds depth to the discussion.\"\n\n**Context**: Demonstrates multiple quotes with proper styling.")) ?? AttributedString("Preview content"),
            canEdit: false,
            createdAt: Date(),
            showDeleteButton: true,
            onTap: { }
        )
    }
    .padding()
}