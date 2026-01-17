import Foundation
import os.log

enum Config {
    private static let logger = Logger(subsystem: "com.voicenote", category: "Config")

    // Feature Flags
    static let isDebugLoggingEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    // Recording Configuration
    static let maxRecordingDuration: TimeInterval = 600.0 // 10 minutes

    // Computed Properties
    static var isProduction: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }
}

// MARK: - Debug Helpers
extension Config {
    static func logConfiguration() {
        guard isDebugLoggingEnabled else { return }

        logger.info("Voice Note Configuration:")
        logger.info("   AI Processing: On-Device (Apple Intelligence)")
        logger.info("   Debug Logging: \(isDebugLoggingEnabled ? "Enabled" : "Disabled")")
        logger.info("   Max Recording: \(maxRecordingDuration)s")
        logger.info("   Environment: \(isProduction ? "Production" : "Development")")
    }
}