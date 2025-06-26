import SwiftUI
import MarkdownUI

/// Simple, clean markdown renderer with black-and-white formatting
/// Focuses on proper markdown structure without color distractions
struct EnhancedMarkdownView: View {
    let content: String
    let templateType: String
    
    init(content: String, templateType: String = "") {
        self.content = content
        self.templateType = templateType
    }
    
    var body: some View {
        Group {
            if content.isEmpty {
                EmptyContentView()
            } else {
                Markdown(content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Compact Markdown View

/// Compact version of markdown rendering optimized for card previews
struct CompactMarkdownView: View {
    let content: String
    let templateType: String
    
    init(content: String, templateType: String = "") {
        self.content = content
        self.templateType = templateType
    }
    
    var body: some View {
        Group {
            if content.isEmpty {
                EmptyContentView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Markdown(content)
                            .markdownTextStyle(\.text) {
                                FontSize(.em(0.9)) // 10% smaller than default
                                FontWeight(.regular)
                            }
                            .markdownTextStyle(\.strong) {
                                FontWeight(.semibold)
                            }
                            .markdownTextStyle(\.emphasis) {
                                FontStyle(.italic)
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4) // Prevent top clipping
                    }
                }
                .scrollDisabled(true) // Disable scrolling in compact view
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Empty State View

private struct EmptyContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No content available")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
}

// MARK: - Copy Support

extension EnhancedMarkdownView {
    
    /// Get attributed string for rich text copying
    var attributedStringForCopy: NSAttributedString {
        // Basic attributed string from markdown content
        do {
            let attributed = try AttributedString(
                markdown: content,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
            return NSAttributedString(attributed)
        } catch {
            return NSAttributedString(string: content)
        }
    }
    
    /// Get plain text for copying
    var plainTextForCopy: String {
        return content
    }
    
    /// Get markdown source for copying
    var markdownForCopy: String {
        return content
    }
}

// MARK: - Utility Methods

extension EnhancedMarkdownView {
    
    /// Detect if content contains meaningful markdown formatting
    static func hasMarkdownFormatting(_ text: String) -> Bool {
        let markdownPatterns = [
            #"^#{1,6}\s"#,           // Headers
            #"^\s*[-\*\+]\s"#,       // Unordered lists
            #"^\s*\d+\.\s"#,         // Ordered lists
            #"^\s*>\s"#,             // Blockquotes
            #"\*\*.*\*\*"#,          // Bold text
            #"\*.*\*"#,              // Italic text
            #"`.*`"#,                // Inline code
            #"```"#,                 // Code blocks
            #"^\s*-\s\[[ x]\]\s"#    // Task lists
        ]
        
        return markdownPatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
    
    /// Create optimized version for previews or list items
    static func preview(content: String, templateType: String = "", maxLength: Int = 500) -> EnhancedMarkdownView {
        let truncated = content.count > maxLength 
            ? String(content.prefix(maxLength)) + "..."
            : content
        
        return EnhancedMarkdownView(content: truncated, templateType: templateType)
    }
}

// MARK: - Debugging Support

extension EnhancedMarkdownView {
    
    /// Version with debug information for development
    func withDebugInfo() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Debug header
            HStack {
                Text("Template: \(templateType.isEmpty ? "None" : templateType)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Markdown: \(Self.hasMarkdownFormatting(content) ? "Yes" : "No")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .cornerRadius(4)
            
            // Main content
            self
        }
    }
}

// MARK: - Preview Support

#Preview("Basic Markdown") {
    ScrollView {
        VStack(spacing: 20) {
            EnhancedMarkdownView(
                content: """
                # Main Title
                
                This is a paragraph with **bold** and *italic* text.
                
                ## Subtitle
                
                - First item
                - Second item
                - Third item
                
                ### Code Example
                
                Here's some `inline code` and a block:
                
                ```swift
                let greeting = "Hello, World!"
                print(greeting)
                ```
                
                > This is a blockquote with important information.
                """,
                templateType: ""
            )
            .padding()
        }
    }
}

#Preview("Template Examples") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach([
                ("Key Quotes", """
                # Key Insights
                
                > "The most important thing is to understand your users' needs before building anything."
                
                **Context**: This quote emphasizes user-centered design principles.
                
                **Use case**: Perfect for team presentations about product strategy.
                """),
                
                ("Action List", """
                # Action Items
                
                ## High Priority
                - [ ] Review user feedback from last sprint
                - [ ] Schedule team meeting for Friday
                - [x] Complete market research analysis
                
                ## Normal Priority  
                - [ ] Update documentation
                - [ ] Prepare quarterly report
                """),
                
                ("Next Questions", """
                # Follow-up Questions
                
                1. **Market Analysis**: How does our pricing compare to competitors in the premium segment?
                
                2. **Feature Evaluation**: What specific features justify the price difference?
                
                3. **User Experience**: How do customers rate the comfort and usability?
                """)
            ], id: \.0) { name, content in
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    EnhancedMarkdownView(content: content, templateType: name.lowercased())
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
    }
}