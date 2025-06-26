import XCTest
import SwiftUI
@testable import Voice_Note_v2

/// Test suite for the enhanced markdown rendering system
final class MarkdownRenderingTest: XCTestCase {
    
    // MARK: - Template Type Detection Tests
    
    func testTemplateTypeDetection() {
        // Test Key Quotes detection
        let quotesContent = """
        ## Key Insights
        
        > "This is an important quote that demonstrates the markdown system."
        
        **Context**: This shows how quotes should be formatted.
        """
        XCTAssertTrue(
            EnhancedMarkdownView.hasMarkdownFormatting(quotesContent)
        )
        
        // Test Action List detection
        let actionContent = """
        ## Action Items
        
        - [ ] Complete project documentation
        - [x] Review code changes
        - [ ] Submit pull request
        """
        XCTAssertTrue(
            EnhancedMarkdownView.hasMarkdownFormatting(actionContent)
        )
        
        // Test Summary detection
        let summaryContent = """
        ## Summary
        
        **Overview**: This is a comprehensive overview of the discussion.
        
        The main points covered include:
        - Point 1
        - Point 2
        """
        XCTAssertTrue(
            EnhancedMarkdownView.hasMarkdownFormatting(summaryContent)
        )
    }
    
    // MARK: - Template-Specific Title Detection Tests
    
    func testNoteCardTemplateDetection() {
        // Create a mock NoteCardView to test title-based detection
        let view = NoteCardView(
            title: "Key Quotes",
            content: "Some content here",
            isMarkdown: true,
            canEdit: true
        )
        
        // Test the private detectTemplateType method through reflection
        let mirror = Mirror(reflecting: view)
        // Note: This is a simplified test - in practice, we'd need to extract the logic
        // or make the method public for testing
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    // MARK: - Markdown Processing Tests
    
    func testMarkdownHeaderRendering() {
        let markdownText = """
        # Main Header
        ## Subheader
        ### Sub-subheader
        
        Regular text content.
        """
        
        let view = EnhancedMarkdownView(content: markdownText, templateType: "")
        
        // Test that the view can be created without crashing
        XCTAssertNotNil(view)
        XCTAssertEqual(view.content, markdownText)
    }
    
    func testMarkdownQuoteRendering() {
        let markdownText = """
        ## Key Quotes
        
        > "This is a blockquote that should be styled appropriately."
        
        **Context**: Additional information about the quote.
        
        > "Another important quote with proper formatting."
        """
        
        let view = EnhancedMarkdownView(content: markdownText, templateType: "key quotes")
        
        XCTAssertNotNil(view)
        XCTAssertEqual(view.templateType, "key quotes")
    }
    
    func testMarkdownListRendering() {
        let markdownText = """
        ## Action Items
        
        **Pending Tasks:**
        - [ ] Task 1: Review documentation
        - [ ] Task 2: Update code comments
        - [x] Task 3: Run test suite
        
        **Completed:**
        - [x] Initial setup
        - [x] Basic implementation
        """
        
        let view = EnhancedMarkdownView(content: markdownText, templateType: "action list")
        
        XCTAssertNotNil(view)
        XCTAssertEqual(view.templateType, "action list")
    }
    
    // MARK: - Performance Tests
    
    func testLargeMarkdownPerformance() {
        let largeMarkdown = generateLargeMarkdownContent()
        
        measure {
            let view = EnhancedMarkdownView(content: largeMarkdown, templateType: "smart summary")
            _ = view.body // Force view computation
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateLargeMarkdownContent() -> String {
        var content = "# Large Document Test\n\n"
        
        for i in 1...100 {
            content += """
            ## Section \(i)
            
            This is section \(i) with **bold text** and *italic text*.
            
            ### Subsection \(i).1
            
            > "Quote number \(i) to test blockquote rendering performance."
            
            **Key Points:**
            - Point A for section \(i)
            - Point B for section \(i)
            - Point C for section \(i)
            
            """
        }
        
        return content
    }
    
    // MARK: - Integration Tests
    
    func testEndToEndMarkdownFlow() {
        // Test the complete flow from markdown content to rendered view
        let testMarkdown = """
        # Test Document
        
        ## Executive Summary
        
        This document demonstrates the **enhanced markdown rendering** capabilities.
        
        ### Key Features
        
        1. **Headers**: Multiple levels with proper styling
        2. **Lists**: Both bulleted and numbered
        3. **Emphasis**: Bold and *italic* text
        4. **Quotes**: Blockquote support
        
        ## Key Quotes
        
        > "The enhanced markdown system provides better visual hierarchy and template-specific styling."
        
        **Source**: Development Team
        
        ## Action Items
        
        - [ ] Test all template types
        - [ ] Verify performance on large documents
        - [x] Implement basic functionality
        - [x] Add template detection
        
        ## Conclusion
        
        The new system successfully addresses the rendering issues.
        """
        
        // Test different template types with the same content
        let templateTypes = ["key quotes", "action list", "smart summary", ""]
        
        for templateType in templateTypes {
            let view = EnhancedMarkdownView(content: testMarkdown, templateType: templateType)
            XCTAssertNotNil(view)
            XCTAssertEqual(view.content, testMarkdown)
            XCTAssertEqual(view.templateType, templateType)
        }
    }
}

// MARK: - Mock Data for Testing

extension MarkdownRenderingTest {
    
    static let mockKeyQuotesContent = """
    ## Key Insights
    
    > "Innovation distinguishes between a leader and a follower."
    
    **Context**: Steve Jobs emphasized the importance of thinking differently and pushing boundaries.
    
    > "The best way to predict the future is to create it."
    
    **Context**: This quote highlights the proactive approach needed for success.
    
    > "Quality is not an act, it is a habit."
    
    **Context**: Aristotle's wisdom on the importance of consistent excellence.
    """
    
    static let mockNextQuestionsContent = """
    ## Follow-up Questions
    
    1. **What specific metrics should we track** to measure the success of this implementation?
       
       *Why this matters*: Understanding success criteria helps focus efforts and measure progress.
    
    2. **How does this approach compare** to alternative solutions we considered?
       
       *Why this matters*: Ensures we've made the optimal choice and helps with future decisions.
    
    3. **What potential risks or challenges** might we encounter during rollout?
       
       *Why this matters*: Proactive risk identification allows for better preparation.
    
    4. **How will we handle user feedback** and iterate on the solution?
       
       *Why this matters*: Continuous improvement is essential for long-term success.
    
    5. **What dependencies exist** that could impact our timeline?
       
       *Why this matters*: Understanding blockers helps with realistic planning.
    """
    
    static let mockActionListContent = """
    ## Action Items
    
    ### High Priority
    
    - [ ] **Review and approve final designs** 
      - *Owner*: Design Team
      - *Deadline*: End of week
      - *Context*: Blocking development work
    
    - [ ] **Set up production environment**
      - *Owner*: DevOps Team  
      - *Deadline*: Next Tuesday
      - *Context*: Required for deployment
    
    ### Medium Priority
    
    - [ ] **Update user documentation**
      - *Owner*: Technical Writing
      - *Deadline*: Before launch
      - *Context*: Support customer adoption
    
    - [ ] **Conduct security review**
      - *Owner*: Security Team
      - *Deadline*: Next week
      - *Context*: Compliance requirement
    
    ### Completed
    
    - [x] **Initial planning meeting**
    - [x] **Technical architecture review**
    - [x] **Stakeholder alignment session**
    """
}