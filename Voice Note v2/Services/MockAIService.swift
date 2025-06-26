import Foundation
import os.log

// MARK: - Mock AI Service for Testing
actor MockAIService: AIService {
    private let simulateDelay: Bool
    private let shouldFail: Bool
    private let logger = Logger(subsystem: "com.voicenote", category: "MockAIService")
    
    init(simulateDelay: Bool = true, shouldFail: Bool = false) {
        self.simulateDelay = simulateDelay
        self.shouldFail = shouldFail
    }
    
    func processTemplate(_ templateInfo: TemplateInfo, transcript: String) async throws -> AIResult {
        if shouldFail {
            throw AIError.processingTimeout
        }
        
        if simulateDelay {
            // Simulate processing time
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        // Generate mock response based on template
        let mockResponse: String
        
        switch templateInfo.name.lowercased() {
        case "meeting notes":
            mockResponse = """
            **Meeting Summary**
            This was a productive discussion about the upcoming product launch and marketing strategy.
            
            **Key Discussion Points**
            • Product timeline has been adjusted to allow for additional testing
            • Marketing campaign will focus on social media and influencer partnerships
            • Budget allocation was reviewed and approved
            
            **Decisions Made**
            1. Launch date moved to March 15th
            2. Allocated $50K for influencer partnerships
            3. Weekly sync meetings will continue through launch
            
            **Action Items**
            • Sarah: Finalize product packaging design by Feb 1st
            • Mike: Set up meetings with top 5 influencers by Jan 25th
            • Team: Review and approve marketing materials by Feb 10th
            
            **Next Steps**
            Schedule follow-up meeting for next week to review progress on action items.
            """
            
        case "brainstorm summary":
            mockResponse = """
            **Main Theme/Problem**
            How to improve user engagement on our mobile app
            
            **Key Ideas Generated**
            
            *Gamification Features*
            • Daily streaks and achievements
            • Points system for completing tasks
            • Leaderboards for friendly competition
            
            *Social Features*
            • User profiles and following system
            • Sharing accomplishments
            • Community challenges
            
            *Personalization*
            • AI-powered recommendations
            • Customizable dashboard
            • Personal goal setting
            
            **Most Promising Concepts**
            1. Daily streak system with rewards
            2. AI recommendations based on user behavior
            3. Monthly community challenges
            4. Achievement badges for milestones
            5. Personalized dashboard widgets
            
            **Potential Challenges**
            • Implementation complexity for AI features
            • Balancing gamification without being overwhelming
            • Privacy concerns with social features
            
            **Recommended Next Steps**
            Create mockups for top 3 features and conduct user testing
            """
            
        case "action items":
            mockResponse = """
            **Unassigned Tasks**
            • Task: Research competitor pricing strategies
              Deadline: End of week
              Priority: High
            
            • Task: Update project documentation
              Deadline: Not specified
              Priority: Medium
            
            **John's Tasks**
            • Task: Complete code review for authentication module
              Deadline: Tomorrow
              Priority: High
            
            • Task: Schedule team retrospective meeting
              Deadline: This week
              Priority: Medium
            
            **Sarah's Tasks**
            • Task: Design new onboarding flow mockups
              Deadline: Friday
              Priority: High
            
            • Task: Send weekly status report
              Deadline: EOD today
              Priority: Medium
            """
            
        default:
            mockResponse = """
            # Processed Transcript
            
            This is a mock response for testing purposes.
            
            **Summary**
            The transcript has been processed using the "\(templateInfo.name)" template.
            
            **Key Points**
            • Mock point 1
            • Mock point 2
            • Mock point 3
            
            **Conclusion**
            This demonstrates the template processing functionality.
            """
        }
        
        return .mock(MockAIResponse(processedText: mockResponse))
    }
    
    func generateSummary(from transcript: String, maxLength: Int) async throws -> AIResult {
        if shouldFail {
            throw AIError.networkUnavailable
        }
        
        if simulateDelay {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        let words = transcript.split(separator: " ")
        let summaryLength = min(maxLength, words.count / 3)
        let summary = words.prefix(summaryLength).joined(separator: " ") + "..."
        
        return .mock(MockAIResponse(processedText: summary))
    }
    
    func generateTitle(from transcript: String) async throws -> AIResult {
        logger.debug("generateTitle called with transcript length: \(transcript.count) chars")
        
        if shouldFail {
            throw AIError.quotaExceeded(resetDate: Date().addingTimeInterval(3600))
        }
        
        if simulateDelay {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Generate a simple title from first few words
        let words = transcript.split(separator: " ").prefix(5)
        let title = words.joined(separator: " ").capitalized
        
        logger.info("Returning mock title: '\(title)'")
        return .mock(MockAIResponse(processedText: title))
    }
}