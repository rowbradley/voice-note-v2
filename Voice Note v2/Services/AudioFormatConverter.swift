import AVFoundation
import os.log

/// Converts audio buffers between formats using AVAudioConverter
/// Required because SpeechAnalyzer does NOT perform audio conversion internally
final class AudioFormatConverter: Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let logger = Logger(subsystem: "com.voicenote", category: "AudioFormatConverter")

    /// Initialize converter for specific format transformation
    /// - Parameters:
    ///   - sourceFormat: The input audio format (e.g., hardware format: 48kHz Float32)
    ///   - targetFormat: The output audio format (e.g., SpeechAnalyzer format: 16kHz Int16)
    /// - Throws: AudioFormatConverterError.converterCreationFailed if formats are incompatible
    init(from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioFormatConverterError.converterCreationFailed(
                "Cannot convert from \(sourceFormat) to \(targetFormat)"
            )
        }
        self.converter = converter
        self.outputFormat = targetFormat

        logger.debug("Created converter: \(sourceFormat.sampleRate)Hz \(sourceFormat.commonFormat.rawValue) → \(targetFormat.sampleRate)Hz \(targetFormat.commonFormat.rawValue)")
    }

    /// Convert an audio buffer to the target format
    /// - Parameter buffer: Source buffer in the original format
    /// - Returns: Converted buffer in the target format
    /// - Throws: AudioFormatConverterError if conversion fails
    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        // Handle empty buffer case
        guard buffer.frameLength > 0 else {
            guard let emptyBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 0) else {
                throw AudioFormatConverterError.failedToCreateOutputBuffer
            }
            emptyBuffer.frameLength = 0
            return emptyBuffer
        }

        // Calculate output frame count based on sample rate ratio
        // Add small margin for resampling priming/latency edge cases
        let sampleRateRatio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(ceil(Double(buffer.frameLength) * sampleRateRatio)) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            throw AudioFormatConverterError.failedToCreateOutputBuffer
        }

        // Use the block-based convert method for sample rate conversion
        var error: NSError?
        var inputBufferConsumed = false

        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            throw AudioFormatConverterError.conversionFailed(error)
        }

        guard status != .error else {
            throw AudioFormatConverterError.conversionStatusError
        }

        return outputBuffer
    }

    /// Reset the converter state (call between discontinuous audio segments)
    func reset() {
        converter.reset()
    }
}

// MARK: - Errors

enum AudioFormatConverterError: LocalizedError {
    case converterCreationFailed(String)
    case failedToCreateOutputBuffer
    case conversionFailed(Error)
    case conversionStatusError

    var errorDescription: String? {
        switch self {
        case .converterCreationFailed(let message):
            return "Failed to create audio converter: \(message)"
        case .failedToCreateOutputBuffer:
            return "Failed to create output buffer for audio conversion"
        case .conversionFailed(let error):
            return "Audio conversion failed: \(error.localizedDescription)"
        case .conversionStatusError:
            return "Audio conversion returned error status"
        }
    }
}
