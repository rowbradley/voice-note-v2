//
//  TextNormalizerTests.swift
//  Voice Note v2 Tests
//
//  Unit tests for TextNormalizer pure functions.
//

import XCTest
@testable import Voice_Note_v2

final class TextNormalizerTests: XCTestCase {

    // MARK: - normalizeWhitespace Tests

    func testMultipleSpacesCollapse() {
        let input = "hello    world"
        let result = TextNormalizer.normalizeWhitespace(input)
        XCTAssertEqual(result, "hello world")
    }

    func testTabsCollapse() {
        let input = "hello\t\tworld"
        let result = TextNormalizer.normalizeWhitespace(input)
        XCTAssertEqual(result, "hello world")
    }

    func testNewlinesCollapse() {
        let input = "hello\n\nworld"
        let result = TextNormalizer.normalizeWhitespace(input)
        XCTAssertEqual(result, "hello world")
    }

    func testMixedWhitespaceCollapse() {
        let input = "hello \n\t  world"
        let result = TextNormalizer.normalizeWhitespace(input)
        XCTAssertEqual(result, "hello world")
    }

    func testTrimsLeadingAndTrailingWhitespace() {
        let input = "  hello world  "
        let result = TextNormalizer.normalizeWhitespace(input)
        XCTAssertEqual(result, "hello world")
    }

    func testEmptyStringReturnsEmpty() {
        let result = TextNormalizer.normalizeWhitespace("")
        XCTAssertEqual(result, "")
    }

    func testWhitespaceOnlyStringReturnsEmpty() {
        let result = TextNormalizer.normalizeWhitespace("   \n\t  ")
        XCTAssertEqual(result, "")
    }

    // MARK: - buildFinalTranscript Tests

    func testBuildFinalTranscriptNormalizesWhitespace() {
        let input = "hello    world"
        let result = TextNormalizer.buildFinalTranscript(from: input)
        XCTAssertEqual(result, "hello world")
    }

    func testBuildFinalTranscriptHandlesEmptyString() {
        let result = TextNormalizer.buildFinalTranscript(from: "")
        XCTAssertEqual(result, "")
    }

    func testBuildFinalTranscriptHandlesWhitespaceOnly() {
        let result = TextNormalizer.buildFinalTranscript(from: "   \n\t  ")
        XCTAssertEqual(result, "")
    }

    // MARK: - Edge Cases

    func testSingleWordUnchanged() {
        let result = TextNormalizer.normalizeWhitespace("hello")
        XCTAssertEqual(result, "hello")
    }

    func testPreservesInternalSingleSpaces() {
        let input = "hello world test"
        let result = TextNormalizer.normalizeWhitespace(input)
        XCTAssertEqual(result, "hello world test")
    }

    func testCarriageReturnCollapse() {
        let input = "hello\r\nworld"
        let result = TextNormalizer.normalizeWhitespace(input)
        XCTAssertEqual(result, "hello world")
    }
}
