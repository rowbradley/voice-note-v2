import SwiftUI
import Combine

struct ExpandedContentView: View {
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    @Binding var content: String
    let isMarkdown: Bool
    let canEdit: Bool
    
    @State private var isEditing = false
    @FocusState private var isFocused: Bool
    @State private var saveTimer: Timer?
    @State private var lastSavedContent: String = ""
    
    // Callback for when content changes (with built-in debouncing)
    var onContentChange: ((String) -> Void)?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if canEdit && isEditing {
                        // Edit mode
                        TextEditor(text: $content)
                            .focused($isFocused)
                            .font(.body)
                            .foregroundColor(.primary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal)
                            .frame(minHeight: 300)
                            .onChange(of: content) { oldValue, newValue in
                                scheduleAutoSave()
                            }
                    } else if isMarkdown {
                        // View mode - Markdown
                        EnhancedMarkdownView(
                            content: content,
                            templateType: detectTemplateTypeFromTitle(title)
                        )
                        .padding()
                        .onTapGesture {
                            if canEdit {
                                startEditing()
                            }
                        }
                    } else {
                        // View mode - Plain text
                        Text(content)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                if canEdit {
                                    startEditing()
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(.systemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveIfNeeded()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            lastSavedContent = content
            
            // If opened in edit mode, start editing
            if canEdit && isEditing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
        .onDisappear {
            // Cancel any pending timer
            saveTimer?.invalidate()
            saveTimer = nil
            
            // Save any unsaved changes
            saveIfNeeded()
        }
    }
    
    private func startEditing() {
        isEditing = true
        isFocused = true
    }
    
    private func scheduleAutoSave() {
        // Cancel existing timer
        saveTimer?.invalidate()
        
        // Schedule new save after 1.0 seconds of inactivity (increased for better battery life)
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            saveIfNeeded()
        }
    }
    
    private func saveIfNeeded() {
        guard content != lastSavedContent else { return }
        
        onContentChange?(content)
        lastSavedContent = content
        
        // Haptic feedback for save
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
    }
}

// MARK: - Convenience Initializers
extension ExpandedContentView {
    /// Initialize for viewing/editing with automatic edit mode
    init(title: String, content: Binding<String>, isMarkdown: Bool, startInEditMode: Bool = false, onContentChange: ((String) -> Void)? = nil) {
        self.title = title
        self._content = content
        self.isMarkdown = isMarkdown
        self.canEdit = true
        self._isEditing = State(initialValue: startInEditMode)
        self.onContentChange = onContentChange
    }
    
    /// Initialize for read-only viewing
    init(title: String, content: String, isMarkdown: Bool) {
        self.title = title
        self._content = .constant(content)
        self.isMarkdown = isMarkdown
        self.canEdit = false
        self._isEditing = State(initialValue: false)
        self.onContentChange = nil
    }
    
    // MARK: - Helper Functions
    
    private func detectTemplateTypeFromTitle(_ title: String) -> String {
        let titleLower = title.lowercased()
        
        if titleLower.contains("quote") {
            return "key quotes"
        } else if titleLower.contains("question") {
            return "next questions"
        } else if titleLower.contains("action") {
            return "action list"
        } else if titleLower.contains("summary") {
            return "smart summary"
        } else if titleLower.contains("outline") {
            return "idea outline"
        } else if titleLower.contains("brainstorm") {
            return "brainstorm"
        } else if titleLower.contains("flashcard") {
            return "flashcard maker"
        } else if titleLower.contains("tone") {
            return "tone analysis"
        }
        
        return ""
    }
}