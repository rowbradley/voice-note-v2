import SwiftUI
import UniformTypeIdentifiers

struct NoteCardView: View {
    let title: String
    let content: String
    let isMarkdown: Bool
    let canEdit: Bool
    let createdAt: Date?
    let showDeleteButton: Bool
    
    @State private var showCopySuccess = false
    @State private var copyButtonText = "Copy"
    @State private var showingDeleteAlert = false
    
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
        content: String,
        isMarkdown: Bool,
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
        self.isMarkdown = isMarkdown
        self.canEdit = canEdit
        self.createdAt = createdAt
        self.showDeleteButton = showDeleteButton
        self.onTap = onTap
        self.onEditTap = onEditTap
        self.onRetranscribe = onRetranscribe
        self.onDelete = onDelete
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
                            
                            Text(formatDate(createdAt))
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
            
            // Content preview with fade
            ZStack(alignment: .bottom) {
                if isMarkdown {
                    CompactMarkdownView(
                        content: content,
                        templateType: detectTemplateType()
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: previewHeight)
                    .clipped()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(content)
                                .font(.callout) // Smaller font for compact view
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4) // Consistent with markdown padding
                        }
                    }
                    .scrollDisabled(true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: previewHeight)
                    .clipped()
                }
                
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
                    
                    ShareLink(item: content) {
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
    }
    
    private func detectTemplateType() -> String {
        // Trust the actual template name from the database - no guessing from content
        let titleLower = title.lowercased()
        
        // Exact template name matches only
        if titleLower == "key quotes" {
            return "key quotes"
        } else if titleLower == "next questions" {
            return "next questions"
        } else if titleLower == "action list" {
            return "action list"
        } else if titleLower == "smart summary" {
            return "smart summary"
        } else if titleLower == "flashcard maker" {
            return "flashcard maker"
        } else if titleLower == "brainstorm" {
            return "brainstorm"
        } else if titleLower == "cleanup" {
            return "cleanup"
        } else if titleLower == "message ready" {
            return "message ready"
        } else if titleLower == "idea outline" {
            return "idea outline"
        } else if titleLower == "tone analysis" {
            return "tone analysis"
        }
        
        // Return empty string for unknown templates (use default rendering)
        return ""
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func copyContent() {
        if isMarkdown {
            // Copy as rich text
            copyRichText()
        } else {
            // Copy as plain text
            UIPasteboard.general.string = content
        }
        
        // Visual feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            copyButtonText = "Copied!"
            showCopySuccess = true
        }
        
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copyButtonText = "Copy"
                showCopySuccess = false
            }
        }
        
        // Haptic feedback
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.success)
    }
    
    private func copyRichText() {
        do {
            // Parse markdown to attributed string
            let attributed = try AttributedString(
                markdown: content,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
            
            let nsAttributed = NSAttributedString(attributed)
            
            // Convert NSAttributedString to RTF data
            let rtfData = try nsAttributed.data(from: NSRange(location: 0, length: nsAttributed.length), 
                                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            
            UIPasteboard.general.setItems([
                [UTType.plainText.identifier: String(attributed.characters)],
                [UTType.rtf.identifier: rtfData]
            ])
        } catch {
            // Fallback to plain text if RTF conversion fails
            UIPasteboard.general.string = content
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        NoteCardView(
            title: "Transcript",
            content: "This is a sample transcript text that can be edited. It contains multiple lines to show how the preview works with the fade effect at the bottom. The content continues beyond what is visible in the preview area.",
            isMarkdown: false,
            canEdit: true,
            onTap: { },
            onEditTap: { }
        )
        
        NoteCardView(
            title: "Key Quotes",
            content: "## Key Insights\n\n> \"This is a powerful insight that demonstrates the markdown rendering capabilities.\"\n\n**Context**: This quote shows how the system handles blockquotes and formatting.\n\n> \"Another important perspective that adds depth to the discussion.\"\n\n**Context**: Demonstrates multiple quotes with proper styling.",
            isMarkdown: true,
            canEdit: false,
            createdAt: Date(),
            showDeleteButton: true,
            onTap: { }
        )
    }
    .padding()
}