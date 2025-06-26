import Foundation
import Speech

// MARK: - Protocol for testability
protocol SpeechTranscribing {
    func transcribe(url: URL, locale: Locale, onDevice: Bool) async throws -> String
    func isAvailable() -> Bool
}

// MARK: - Production implementation
class SpeechRecognizerAdapter: SpeechTranscribing {
    private var speechRecognizer: SFSpeechRecognizer?
    
    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        if speechRecognizer == nil {
            // Fallback to en-US if current locale not supported
            self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }
    
    func isAvailable() -> Bool {
        return speechRecognizer?.isAvailable ?? false
    }
    
    func transcribe(url: URL, locale: Locale, onDevice: Bool) async throws -> String {
        // Ensure we have the right recognizer for the locale
        if speechRecognizer?.locale != locale {
            speechRecognizer = SFSpeechRecognizer(locale: locale)
            if speechRecognizer == nil {
                speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            }
        }
        
        guard let recognizer = speechRecognizer else {
            throw TranscriptionError.speechRecognitionUnavailable
        }
        
        guard recognizer.isAvailable else {
            throw TranscriptionError.speechRecognitionUnavailable
        }
        
        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            if authStatus == .notDetermined {
                let granted = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { status in
                        continuation.resume(returning: status == .authorized)
                    }
                }
                if !granted {
                    throw TranscriptionError.speechRecognitionUnavailable
                }
            } else {
                throw TranscriptionError.speechRecognitionUnavailable
            }
        }
        
        // Create request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        
        // Configure for on-device recognition
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = onDevice && recognizer.supportsOnDeviceRecognition
        }
        
        // Additional configuration
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        request.taskHint = .dictation
        
        // Perform transcription
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var finalTranscript = ""
            
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    guard !hasResumed else { return }
                    hasResumed = true
                    
                    if !finalTranscript.isEmpty {
                        continuation.resume(returning: finalTranscript)
                    } else {
                        continuation.resume(throwing: TranscriptionError.recognitionFailed(error))
                    }
                    return
                }
                
                if let result = result {
                    finalTranscript = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        guard !hasResumed else { return }
                        hasResumed = true
                        continuation.resume(returning: finalTranscript)
                    }
                }
            }
            
            // Add timeout
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                guard !hasResumed else { return }
                hasResumed = true
                
                task.cancel()
                if !finalTranscript.isEmpty {
                    continuation.resume(returning: finalTranscript)
                } else {
                    continuation.resume(throwing: TranscriptionError.networkError(NSError(domain: "Timeout", code: -1001)))
                }
            }
        }
    }
}

// MARK: - Mock implementation for testing
class MockTranscriber: SpeechTranscribing {
    var calledWithOnDevice: [Bool] = []
    var onDeviceResult = ""
    var cloudResult = "All right testing a British clip with full cloud transcription"
    var shouldFailOnDevice = true
    var isAvailableValue = true
    
    func isAvailable() -> Bool {
        return isAvailableValue
    }
    
    func transcribe(url: URL, locale: Locale, onDevice: Bool) async throws -> String {
        calledWithOnDevice.append(onDevice)
        
        if onDevice {
            if shouldFailOnDevice || onDeviceResult.isEmpty {
                return ""
            }
            return onDeviceResult
        } else {
            return cloudResult
        }
    }
}