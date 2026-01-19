import XCTest
import AVFoundation
@testable import Voice_Note_v2

/// Tests for AudioFormatConverter which converts audio buffers between formats
/// Required because SpeechAnalyzer does NOT perform audio conversion internally
class AudioFormatConverterTests: XCTestCase {

    // MARK: - Format Fixtures

    private lazy var sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 1,
        interleaved: false
    )!

    private lazy var targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Constants

    /// Resampler latency tolerance (~15ms at 16kHz target sample rate).
    /// AVAudioConverter holds back frames for polyphase resampling processing.
    private let resamplerToleranceFrames: AVAudioFrameCount = 250

    // MARK: - Test: Convert 48kHz Float32 to 16kHz Int16

    func testConvertFloat32To16BitInt() throws {
        // Given: A buffer with 100ms of audio at 48kHz
        let frameCount: AVAudioFrameCount = 4800  // 100ms at 48kHz
        let sourceBuffer = try createSineWaveBuffer(
            frequency: 440.0,
            frameCount: frameCount
        )

        // When: We convert the buffer
        let converter = AudioFormatConverter(from: sourceFormat, to: targetFormat)
        let convertedBuffer = try converter.convert(sourceBuffer)

        // Then: The output buffer should have the correct format
        XCTAssertEqual(convertedBuffer.format.sampleRate, 16000)
        XCTAssertEqual(convertedBuffer.format.commonFormat, .pcmFormatInt16)

        // Frame count should be proportional to sample rate ratio (48000/16000 = 3x less frames)
        // Allow tolerance for resampler priming latency
        let expectedFrameCount = frameCount / 3  // 1600 frames for 100ms at 16kHz
        XCTAssertEqual(
            convertedBuffer.frameLength,
            expectedFrameCount,
            accuracy: resamplerToleranceFrames,
            "Frame count should be ~1600 accounting for resampler latency"
        )
    }

    // MARK: - Test: Converter handles empty buffer gracefully

    func testConvertEmptyBuffer() throws {
        // Given: An empty buffer
        let sourceBuffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 1024),
            "Failed to create empty source buffer"
        )
        sourceBuffer.frameLength = 0

        // When: We convert the empty buffer
        let converter = AudioFormatConverter(from: sourceFormat, to: targetFormat)
        let convertedBuffer = try converter.convert(sourceBuffer)

        // Then: Output should also be empty
        XCTAssertEqual(convertedBuffer.frameLength, 0)
    }

    // MARK: - Test: Converter can be reused for multiple buffers

    func testConverterReusability() throws {
        let converter = AudioFormatConverter(from: sourceFormat, to: targetFormat)

        // Convert multiple buffers sequentially
        for iteration in 1...3 {
            let sourceBuffer = try XCTUnwrap(
                AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 1024),
                "Failed to create buffer for iteration \(iteration)"
            )
            sourceBuffer.frameLength = 1024

            let convertedBuffer = try converter.convert(sourceBuffer)
            XCTAssertGreaterThan(
                convertedBuffer.frameLength,
                0,
                "Iteration \(iteration): converted buffer should have content"
            )
        }
    }

    // MARK: - Helpers

    /// Creates a buffer filled with a sine wave for testing
    private func createSineWaveBuffer(
        frequency: Float,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount),
            "Failed to create source buffer with \(frameCount) frames"
        )
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            XCTFail("Failed to access buffer channel data")
            throw NSError(domain: "AudioFormatConverterTests", code: 1)
        }

        let sampleRate = Float(sourceFormat.sampleRate)
        for i in 0..<Int(frameCount) {
            channelData[i] = sin(2.0 * .pi * frequency * Float(i) / sampleRate)
        }

        return buffer
    }
}
