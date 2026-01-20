import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Inline Expanded Content View
/// Full-screen view for viewing and editing transcript or note content.
/// Uses AttributedString for native iOS 26 rich text support.
///
/// Architecture: View owns its state via @State, calls onSave only on explicit save (checkmark).
/// This prevents binding corruption issues when parent re-renders.
struct InlineExpandedContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontResolutionContext) private var fontResolutionContext

    let title: String
    let initialContent: AttributedString
    let onSave: (AttributedString) -> Void

    @State private var content: AttributedString
    @State private var hasUnsavedChanges = false

    @State private var isEditing = false
    @FocusState private var isFocused: Bool
    @State private var selection = AttributedTextSelection()
    @State private var saveHapticTrigger = 0
    @State private var copyHapticTrigger = 0
    @State private var showCopySuccess = false
    @State private var headingLevel = 0 // 0 = normal, 1 = H1, 2 = H2
    @State private var copyFeedbackTask: Task<Void, Never>?

    /// Plain text content for copying and sharing
    private var plainTextContent: String {
        String(content.characters)
    }

    init(
        title: String,
        initialContent: AttributedString,
        startInEditMode: Bool = false,
        onSave: @escaping (AttributedString) -> Void
    ) {
        self.title = title
        self.initialContent = initialContent
        self.onSave = onSave
        self._content = State(initialValue: initialContent)
        self._isEditing = State(initialValue: startInEditMode)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEditing {
                    // Edit mode - TextEditor is already scrollable, no wrapper needed
                    TextEditor(text: $content, selection: $selection)
                        .focused($isFocused)
                        .font(.body)
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal)
                        .onChange(of: content) { _, _ in
                            hasUnsavedChanges = true
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                // Bold
                                Toggle("Bold", systemImage: "bold", isOn: boldBinding)

                                // Italic
                                Toggle("Italic", systemImage: "italic", isOn: italicBinding)

                                Divider()

                                // Heading toggle (H1/H2)
                                Button {
                                    toggleHeading()
                                } label: {
                                    Image(systemName: "textformat.size")
                                }

                                // Bullet list
                                Button {
                                    insertBullet()
                                } label: {
                                    Image(systemName: "list.bullet")
                                }

                                // Numbered list
                                Button {
                                    insertNumberedList()
                                } label: {
                                    Image(systemName: "list.number")
                                }
                            }
                        }
                } else {
                    // View mode - Native AttributedString rendering in ScrollView
                    ScrollView {
                        Text(content)
                            .font(.body)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onTapGesture {
                        startEditing()
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()  // Discard changes
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            copyContent()
                        }

                        ShareLink(item: plainTextContent) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button("Export as Markdown", systemImage: "doc.text") {
                            exportAsMarkdown()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(content)
                        saveHapticTrigger += 1  // Haptic only on explicit save
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: saveHapticTrigger)
        .onDisappear {
            // Cancel any pending tasks
            copyFeedbackTask?.cancel()
        }
    }

    private func startEditing() {
        isEditing = true
        isFocused = true
    }

    // MARK: - Formatting Helpers

    private var boldBinding: Binding<Bool> {
        Binding(
            get: {
                let font = selection.typingAttributes(in: content).font
                let resolved = (font ?? .default).resolve(in: fontResolutionContext)
                return resolved.isBold
            },
            set: { isBold in
                content.transformAttributes(in: &selection) {
                    $0.font = ($0.font ?? .default).bold(isBold)
                }
            }
        )
    }

    private var italicBinding: Binding<Bool> {
        Binding(
            get: {
                let font = selection.typingAttributes(in: content).font
                let resolved = (font ?? .default).resolve(in: fontResolutionContext)
                return resolved.isItalic
            },
            set: { isItalic in
                content.transformAttributes(in: &selection) {
                    $0.font = ($0.font ?? .default).italic(isItalic)
                }
            }
        )
    }

    private func insertBullet() {
        // Insert bullet at cursor/selection (replaces selection if any)
        content.replaceSelection(&selection, with: AttributedString("• "))
    }

    private func insertNumberedList() {
        // Insert numbered list item at cursor/selection
        content.replaceSelection(&selection, with: AttributedString("1. "))
    }

    private func toggleHeading() {
        // Cycle through: normal → H1 (title) → H2 (headline) → normal
        headingLevel = (headingLevel + 1) % 3

        let targetFont: Font
        switch headingLevel {
        case 1:
            targetFont = .title
        case 2:
            targetFont = .headline
        default:
            targetFont = .body
        }

        content.transformAttributes(in: &selection) {
            $0.font = targetFont
        }
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

        // Trigger haptic feedback
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

    /// Converts AttributedString content to markdown and copies to clipboard
    private func exportAsMarkdown() {
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
        UIPasteboard.general.string = output

        // Trigger haptic and visual feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopySuccess = true
        }
        copyHapticTrigger += 1

        // Reset after delay
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
}
