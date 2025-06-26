import XCTest
@testable import Voice_Note_v2

class TitleGenerationTests: XCTestCase {
    
    func testFallbackTitleGeneration() {
        let recordingManager = RecordingManager()
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        let datePrefix = formatter.string(from: Date())
        
        // Test empty transcript
        let emptyTitle = recordingManager.generateFallbackTitle(from: "")
        XCTAssertEqual(emptyTitle, datePrefix)
        
        // Test short transcript
        let shortTitle = recordingManager.generateFallbackTitle(from: "Quick note")
        XCTAssertEqual(shortTitle, "\(datePrefix) Quick note...")
        
        // Test exact 3 words
        let threeWordsTitle = recordingManager.generateFallbackTitle(from: "This is test")
        XCTAssertEqual(threeWordsTitle, "\(datePrefix) This is test...")
        
        // Test long transcript
        let longTitle = recordingManager.generateFallbackTitle(from: "This is a very long transcript that should be truncated")
        XCTAssertEqual(longTitle, "\(datePrefix) This is a...")
    }
}