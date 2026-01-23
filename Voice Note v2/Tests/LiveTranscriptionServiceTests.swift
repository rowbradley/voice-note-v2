//
//  LiveTranscriptionServiceTests.swift
//  Voice Note v2 Tests
//
//  Unit tests for LiveTranscriptionService state management and cleanup.
//

import XCTest
@testable import Voice_Note_v2

@MainActor
final class LiveTranscriptionServiceTests: XCTestCase {

    var service: LiveTranscriptionService!

    override func setUp() {
        super.setUp()
        service = LiveTranscriptionService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - cancelTranscription() Tests

    func testCancelTranscriptionClearsVolatileText() async {
        // Given: Service with volatile text
        service.setTestState(volatile: "partial text")

        // When: Cancel transcription
        await service.cancelTranscription()

        // Then: Volatile text is cleared
        XCTAssertEqual(service.volatileText, "")
    }

    func testCancelTranscriptionClearsFinalizedText() async {
        // Given: Service with finalized text
        service.setTestState(finalized: "finalized text")

        // When: Cancel transcription
        await service.cancelTranscription()

        // Then: Finalized text is cleared
        XCTAssertEqual(service.finalizedText, "")
    }

    func testCancelTranscriptionResetsTranscribingFlag() async {
        // Given: Service that is transcribing
        service.setTestState(transcribing: true)

        // When: Cancel transcription
        await service.cancelTranscription()

        // Then: Transcribing flag is reset
        XCTAssertFalse(service.isTranscribing)
    }

    func testCancelTranscriptionResetsPausedFlag() async {
        // Given: Service that is paused
        service.setTestState(paused: true)

        // When: Cancel transcription
        await service.cancelTranscription()

        // Then: Paused flag is reset
        XCTAssertFalse(service.isPaused)
    }

    func testCancelTranscriptionClearsAllState() async {
        // Given: Service with all state set
        service.setTestState(
            volatile: "volatile",
            finalized: "finalized",
            transcribing: true,
            paused: true
        )

        // When: Cancel transcription
        await service.cancelTranscription()

        // Then: All state is cleared
        XCTAssertEqual(service.volatileText, "")
        XCTAssertEqual(service.finalizedText, "")
        XCTAssertFalse(service.isTranscribing)
        XCTAssertFalse(service.isPaused)
    }

    // MARK: - stopTranscribing() Tests

    func testStopTranscribingReturnsNormalizedText() async {
        // Given: Service with finalized text containing extra whitespace
        service.setTestState(finalized: "hello    world")

        // When: Stop transcribing
        let result = await service.stopTranscribing()

        // Then: Returns normalized text
        XCTAssertEqual(result, "hello world")
    }

    func testStopTranscribingReturnsEmptyForNoText() async {
        // Given: Service with no finalized text
        service.setTestState(finalized: "")

        // When: Stop transcribing
        let result = await service.stopTranscribing()

        // Then: Returns empty string
        XCTAssertEqual(result, "")
    }

    func testStopTranscribingTrimsWhitespace() async {
        // Given: Service with text having leading/trailing whitespace
        service.setTestState(finalized: "  hello world  ")

        // When: Stop transcribing
        let result = await service.stopTranscribing()

        // Then: Returns trimmed text
        XCTAssertEqual(result, "hello world")
    }

    func testStopTranscribingResetsFlags() async {
        // Given: Service that is transcribing and paused
        service.setTestState(finalized: "text", transcribing: true, paused: true)

        // When: Stop transcribing
        _ = await service.stopTranscribing()

        // Then: Flags are reset
        XCTAssertFalse(service.isTranscribing)
        XCTAssertFalse(service.isPaused)
    }

    // MARK: - displayText Tests

    func testDisplayTextCombinesVolatileAndFinalized() {
        // Given: Service with both volatile and finalized text
        service.setTestState(volatile: "in progress", finalized: "completed")

        // When: Get display text
        let result = service.displayText

        // Then: Combines both with space
        XCTAssertEqual(result, "completed in progress")
    }

    func testDisplayTextShowsOnlyFinalizedWhenNoVolatile() {
        // Given: Service with only finalized text
        service.setTestState(finalized: "completed")

        // When: Get display text
        let result = service.displayText

        // Then: Shows only finalized
        XCTAssertEqual(result, "completed")
    }

    func testDisplayTextShowsOnlyVolatileWhenNoFinalized() {
        // Given: Service with only volatile text
        service.setTestState(volatile: "in progress")

        // When: Get display text
        let result = service.displayText

        // Then: Shows only volatile
        XCTAssertEqual(result, "in progress")
    }
}
