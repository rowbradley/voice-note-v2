import Foundation
import os.log

enum Config {
    private static let logger = Logger(subsystem: "com.voicenote", category: "Config")
    
    // Load configuration from plist
    private static let configDict: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            logger.warning("Failed to load Config.plist")
            return [:]
        }
        return plist
    }()
    
    // Backend Configuration
    static let backendURL: String = {
        configDict["backend_url"] as? String ?? "https://voicenote-backend-api.vercel.app"
    }()
    
    // No more auth key in the app! Will use bootstrap tokens instead
    
    // Feature Flags
    static let isDebugLoggingEnabled: Bool = {
        #if DEBUG
        return configDict["enable_debug_logging"] as? Bool ?? true
        #else
        return false
        #endif
    }()
    
    // API Configuration
    static let apiTimeout: TimeInterval = 30.0
    static let maxRecordingDuration: TimeInterval = 600.0 // 10 minutes
    
    // Bootstrap token configuration
    static let bootstrapTokenTTL: TimeInterval = 3600 // 1 hour
    static let tokenRefreshBuffer: TimeInterval = 300 // Refresh 5 min before expiry
    
    // Computed Properties
    static var isProduction: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }
    
    static var isConfigured: Bool {
        !backendURL.isEmpty
    }
}

// MARK: - Debug Helpers
extension Config {
    static func logConfiguration() {
        guard isDebugLoggingEnabled else { return }
        
        logger.info("Voice Note Configuration:")
        logger.info("   Backend URL: \(backendURL.isEmpty ? "Not set" : backendURL)")
        logger.info("   Auth Method: Bootstrap Tokens")
        logger.info("   Debug Logging: \(isDebugLoggingEnabled ? "Enabled" : "Disabled")")
        logger.info("   API Timeout: \(apiTimeout)s")
        logger.info("   Max Recording: \(maxRecordingDuration)s")
        logger.info("   Token TTL: \(bootstrapTokenTTL)s")
        logger.info("   Environment: \(isProduction ? "Production" : "Development")")
        logger.info("   Config Source: Config.plist")
    }
}