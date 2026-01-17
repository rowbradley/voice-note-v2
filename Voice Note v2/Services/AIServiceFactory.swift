import Foundation
import os.log

// MARK: - AI Service Factory
@MainActor
class AIServiceFactory {
    enum ServiceType {
        case onDevice  // Primary: Apple Intelligence (iOS 26+)
        case mock      // Testing
    }

    private let logger = Logger(subsystem: "com.voicenote", category: "AIServiceFactory")

    func createService(type: ServiceType = .onDevice) -> any AIService {
        switch type {
        case .onDevice:
            logger.info("Creating OnDeviceAIService (Apple Intelligence)")
            return OnDeviceAIService()

        case .mock:
            return MockAIService(simulateDelay: true, shouldFail: false)
        }
    }

    func createDefaultService() -> any AIService {
        #if DEBUG
        // Check if we should use mock for testing
        if ProcessInfo.processInfo.environment["USE_MOCK_AI"] == "1" {
            logger.warning("USE_MOCK_AI=1, using mock AI service")
            return createService(type: .mock)
        }
        #endif

        logger.info("Creating default OnDeviceAIService")
        return createService(type: .onDevice)
    }
}

// MARK: - Shared Instance
extension AIServiceFactory {
    static let shared = AIServiceFactory()
}