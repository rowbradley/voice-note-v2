import XCTest
import AVFoundation
@testable import Voice_Note_v2

/// Tests for AudioFormatConverter which converts audio buffers between formats
/// Required because SpeechAnalyzer does NOT perform audio conversion internally
class AudioFormatConverterTests: XCTestCase {

    // MARK: - Test: Convert 48kHz Float32 to 16kHz Int16

    func testConvertFloat32To16BitInt() throws {
        // Given: A buffer in 48000 Hz Float32 format (typical hardware format)
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        )!

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        // Create a source buffer with test audio data (sine wave)
        let frameCount: AVAudioFrameCount = 4800  // 100ms at 48kHz
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)!
        sourceBuffer.frameLength = frameCount

        // Fill with a simple sine wave
        let frequency: Float = 440.0  // A4 note
        let sampleRate = Float(sourceFormat.sampleRate)
        if let channelData = sourceBuffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) {
                channelData[i] = sin(2.0 * .pi * frequency * Float(i) / sampleRate)
            }
        }

        // When: We convert the buffer
        let converter = AudioFormatConverter(from: sourceFormat, to: targetFormat)
        let convertedBuffer = try converter.convert(sourceBuffer)

        // Then: The output buffer should have the correct format and frame count
        XCTAssertEqual(convertedBuffer.format.sampleRate, 16000)
        XCTAssertEqual(convertedBuffer.format.commonFormat, .pcmFormatInt16)

        // Frame count should be proportional to sample rate ratio (48000/16000 = 3x less frames)
        // AVAudioConverter resampler has ~15ms priming latency (holds back frames for processing)
        // Expected: 1600 frames, typical actual: ~1360 due to resampler internal buffering
        let expectedFrameCount = frameCount / 3  // 1600 frames for 100ms at 16kHz
        XCTAssertEqual(convertedBuffer.frameLength, expectedFrameCount, accuracy: 250)  // Allow 250 frames for resampler latency
    }

    // MARK: - Test: Converter handles empty buffer gracefully

    func testConvertEmptyBuffer() throws {
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        )!

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        // Given: An empty buffer
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 1024)!
        sourceBuffer.frameLength = 0

        // When: We convert the empty buffer
        let converter = AudioFormatConverter(from: sourceFormat, to: targetFormat)
        let convertedBuffer = try converter.convert(sourceBuffer)

        // Then: Output should also be empty
        XCTAssertEqual(convertedBuffer.frameLength, 0)
    }

    // MARK: - Test: Converter can be reused for multiple buffers

    func testConverterReusability() throws {
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        )!

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let converter = AudioFormatConverter(from: sourceFormat, to: targetFormat)

        // Convert multiple buffers sequentially
        for _ in 0..<3 {
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 1024)!
            sourceBuffer.frameLength = 1024

            let convertedBuffer = try converter.convert(sourceBuffer)
            XCTAssertGreaterThan(convertedBuffer.frameLength, 0)
        }
    }
}
