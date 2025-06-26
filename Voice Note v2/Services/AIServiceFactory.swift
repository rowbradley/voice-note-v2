import Foundation
import os.log

// MARK: - AI Service Factory
@MainActor
class AIServiceFactory {
    enum ServiceType {
        case cloud
        case mock
        case onDevice // Future
    }
    
    private let jwtManager = JWTManager()
    private let logger = Logger(subsystem: "com.voicenote", category: "AIServiceFactory")
    
    func createService(type: ServiceType = .cloud) -> any AIService {
        switch type {
        case .cloud:
            return CloudAIService(jwtManager: jwtManager)
            
        case .mock:
            return MockAIService(simulateDelay: true, shouldFail: false)
            
        case .onDevice:
            // Future: return OnDeviceAIService()
            // For now, fall back to mock
            return MockAIService(simulateDelay: false, shouldFail: false)
        }
    }
    
    func createDefaultService() -> any AIService {
        #if DEBUG
        // Use mock service in debug builds if not configured
        if !Config.isConfigured {
            logger.warning("Backend not configured, using mock AI service")
            return createService(type: .mock)
        }
        #endif
        
        logger.info("Creating CloudAIService")
        return createService(type: .cloud)
    }
}

// MARK: - Shared Instance
extension AIServiceFactory {
    static let shared = AIServiceFactory()
}