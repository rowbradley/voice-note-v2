import Foundation

// MARK: - Typed UserDefaults Keys
//
// Why: String literals like "lowPowerMode" are error-prone (typos compile fine but fail silently).
// This extension provides:
// 1. Centralized key definitions (Keys enum)
// 2. Type-safe computed properties (no casting needed)
// 3. Autocomplete support in Xcode

extension UserDefaults {
    /// Centralized storage for all UserDefaults key strings.
    /// Add new keys here to maintain consistency across the app.
    enum Keys {
        // Performance
        static let lowPowerMode = "lowPowerMode"

        // Recording
        static let recordingQuality = "recordingQuality"

        // Storage
        static let autoDeleteOldRecordings = "autoDeleteOldRecordings"
        static let deleteRecordingsAfterDays = "deleteRecordingsAfterDays"

        // Templates
        static let defaultTemplateId = "defaultTemplateId"
        static let autoApplyDefaultTemplate = "autoApplyDefaultTemplate"

        // Transcription
        static let autoGenerateTitles = "autoGenerateTitles"
    }

    // MARK: - Typed Accessors

    /// Whether Low Power Mode is enabled.
    /// When true, animations run at 30fps instead of 60fps to save battery.
    /// Default: false (full quality animations)
    var lowPowerMode: Bool {
        get { bool(forKey: Keys.lowPowerMode) }
        set { set(newValue, forKey: Keys.lowPowerMode) }
    }
}
