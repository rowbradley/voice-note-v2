import SwiftUI
import UniformTypeIdentifiers

/// Transferable wrapper for audio files that enables async file preparation
/// when sharing via ShareLink. This prevents main thread blocking during
/// AirPlay and other share operations.
///
/// Usage:
/// ```swift
/// ShareLink(item: ShareableAudioFile(url: audioURL)) {
///     Label("Share", systemImage: "square.and.arrow.up")
/// }
/// ```
struct ShareableAudioFile: Transferable, Sendable {
    let url: URL

    /// The content type for the audio file.
    /// Supports M4A (MPEG-4 Audio) which is the format used by Voice Note recordings.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Audio) { file in
            // FileRepresentation handles async file preparation off main thread
            SentTransferredFile(file.url)
        }
    }
}

// MARK: - Preview Support

extension ShareableAudioFile {
    /// Creates a shareable audio file for preview/testing purposes
    static var preview: ShareableAudioFile {
        ShareableAudioFile(url: URL(fileURLWithPath: "/tmp/preview.m4a"))
    }
}
