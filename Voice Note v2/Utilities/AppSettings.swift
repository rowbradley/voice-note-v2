import Foundation
import Observation
import os.log

/// Centralized app settings using Swift 6 Observation framework.
///
/// ## Storage Strategy (Hybrid iCloud/Local)
///
/// **iCloud KVS** (syncs across devices via NSUbiquitousKeyValueStore):
/// - `isProUser` — Subscription follows user across devices
/// - `audioSyncPolicy` — User's sync preferences
/// - `retentionPolicy` — Data retention rules
/// - `autoCopyOnComplete` — Workflow preference
/// - `recentClipsCount` — UI preference
///
/// **UserDefaults** (device-specific):
/// - `lowPowerMode` — Battery varies by device
/// - `showAudioVisualizer` — Performance varies by device
/// - `audioVisualizerMonochrome` — Per-device UI preference
///
/// ## Why @Observable instead of @AppStorage everywhere:
/// 1. Single source of truth — settings live in one place
/// 2. Computed properties — derived values like `frameRateInterval` update automatically
/// 3. No boilerplate — views observe automatically, no manual NotificationCenter
/// 4. Testable — can inject mock settings in previews/tests
///
/// ## Usage in Views:
/// ```swift
/// struct MyView: View {
///     @Environment(AppSettings.self) private var appSettings
///
///     var body: some View {
///         // Automatically re-renders when lowPowerMode changes
///         Text(appSettings.lowPowerMode ? "30fps" : "60fps")
///
///         // Create binding for Toggle
///         Toggle("Low Power", isOn: Bindable(appSettings).lowPowerMode)
///     }
/// }
/// ```
///
/// ## Usage in Services (non-SwiftUI):
/// ```swift
/// let interval = AppSettings.shared.frameRateCFInterval
/// ```
///
/// Thread safety:
/// `@MainActor` ensures all access is compiler-verified to be on the main thread.
/// This is the correct approach since `@Observable` requires main thread observation
/// and all SwiftUI access happens there anyway. Removes need for `@unchecked Sendable`.
@MainActor @Observable
final class AppSettings {

    // MARK: - Singleton

    /// Shared instance for app-wide access.
    /// Injected into SwiftUI environment at app root.
    static let shared = AppSettings()

    // MARK: - Storage Backends

    /// iCloud Key-Value Store for settings that sync across devices.
    /// Limits: 1MB total, 1024 keys max (plenty for settings).
    private let syncedStore = NSUbiquitousKeyValueStore.default

    /// Local storage for device-specific settings.
    private let localStore = UserDefaults.standard

    private let logger = Logger(subsystem: "com.voicenote", category: "AppSettings")

    // MARK: - iCloud-Synced Settings (follow user across devices)

    /// Pro user flag - enables auto-cleanup of transcripts.
    /// Synced via iCloud so subscription follows user.
    var isProUser: Bool {
        didSet {
            syncedStore.set(isProUser, forKey: Keys.isProUser)
            syncedStore.synchronize()
        }
    }

    /// Audio sync policy for iCloud - how much audio to sync.
    /// Synced via iCloud so user preference follows them.
    var audioSyncPolicy: AudioSyncPolicy {
        didSet {
            syncedStore.set(audioSyncPolicy.rawValue, forKey: Keys.audioSyncPolicy)
            syncedStore.synchronize()
        }
    }

    /// Data retention policy for recordings.
    /// Synced via iCloud.
    var retentionPolicy: RetentionPolicy {
        didSet {
            syncedStore.set(retentionPolicy.rawValue, forKey: Keys.retentionPolicy)
            syncedStore.synchronize()
        }
    }

    /// Automatically copy processed note to clipboard when template completes.
    /// Synced via iCloud.
    var autoCopyOnComplete: Bool {
        didSet {
            syncedStore.set(autoCopyOnComplete, forKey: Keys.autoCopyOnComplete)
            syncedStore.synchronize()
        }
    }

    /// Number of recent clips to show in UI (5, 10, or 15).
    /// Synced via iCloud.
    var recentClipsCount: Int {
        didSet {
            syncedStore.set(recentClipsCount, forKey: Keys.recentClipsCount)
            syncedStore.synchronize()
        }
    }

    // MARK: - Device-Local Settings (vary by device)

    /// Reduces animation frame rate from 60fps to 30fps to save battery.
    ///
    /// When enabled:
    /// - TimelineView animations run at 30fps
    /// - Audio level bars reduce from 20 to 12
    /// - UI update throttling in audio callbacks uses 30fps interval
    ///
    /// Stored locally - battery varies by device.
    var lowPowerMode: Bool {
        didSet {
            localStore.lowPowerMode = lowPowerMode
        }
    }

    /// When false, hides the audio level visualization during recording.
    /// Some users find animation distracting.
    /// Stored locally - performance varies by device.
    var showAudioVisualizer: Bool {
        didSet {
            localStore.set(showAudioVisualizer, forKey: Keys.showAudioVisualizer)
        }
    }

    /// When true, uses monochrome (gray) dots instead of colored (green/yellow/red).
    /// Provides subtler appearance while retaining motion feedback.
    /// Stored locally - per-device UI preference.
    var audioVisualizerMonochrome: Bool {
        didSet {
            localStore.set(audioVisualizerMonochrome, forKey: Keys.audioVisualizerMonochrome)
        }
    }

    // MARK: - macOS Floating Panel Settings

    /// Whether the floating panel stays on top of other windows.
    /// Stored locally - per-device preference.
    var floatingPanelStayOnTop: Bool {
        didSet {
            localStore.set(floatingPanelStayOnTop, forKey: Keys.floatingPanelStayOnTop)
        }
    }

    /// Whether to show red glowing border during recording.
    /// Stored locally - per-device visual preference.
    var showRecordingBorder: Bool {
        didSet {
            localStore.set(showRecordingBorder, forKey: Keys.showRecordingBorder)
        }
    }

    /// Whether to show floating panel when app launches.
    /// Stored locally - per-device preference.
    var showPanelOnLaunch: Bool {
        didSet {
            localStore.set(showPanelOnLaunch, forKey: Keys.showPanelOnLaunch)
        }
    }


    // MARK: - Initialization

    /// Private initializer ensures singleton pattern.
    /// Loads initial values from appropriate stores synchronously to prevent
    /// UI flash on first render (settings are available immediately).
    private init() {
        // Migrate existing UserDefaults settings to iCloud on first run
        // (Must be called before reading from iCloud store)
        Self.migrateToICloudIfNeeded()

        // Local references to avoid repeated access
        let iCloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard

        // Load iCloud-synced settings
        self.isProUser = iCloud.bool(forKey: Keys.isProUser)
        self.audioSyncPolicy = AudioSyncPolicy(
            rawValue: iCloud.string(forKey: Keys.audioSyncPolicy) ?? ""
        ) ?? .last7Days
        self.retentionPolicy = RetentionPolicy(
            rawValue: iCloud.string(forKey: Keys.retentionPolicy) ?? ""
        ) ?? .forever
        self.autoCopyOnComplete = iCloud.bool(forKey: Keys.autoCopyOnComplete)

        // recentClipsCount: default to 10 if not set
        let storedCount = iCloud.longLong(forKey: Keys.recentClipsCount)
        self.recentClipsCount = storedCount > 0 ? Int(storedCount) : 10

        // Load device-local settings
        self.lowPowerMode = local.lowPowerMode
        self.showAudioVisualizer = local.object(forKey: Keys.showAudioVisualizer) as? Bool ?? true
        self.audioVisualizerMonochrome = local.bool(forKey: Keys.audioVisualizerMonochrome)

        // Load macOS floating panel settings
        self.floatingPanelStayOnTop = local.object(forKey: Keys.floatingPanelStayOnTop) as? Bool ?? true
        self.showRecordingBorder = local.object(forKey: Keys.showRecordingBorder) as? Bool ?? true
        self.showPanelOnLaunch = local.object(forKey: Keys.showPanelOnLaunch) as? Bool ?? true

        // Listen for external iCloud changes (from other devices)
        setupExternalChangeObserver()

        logger.info("AppSettings initialized (iCloud sync enabled)")
    }

    // MARK: - iCloud External Change Handling

    /// Observes changes pushed from other devices via iCloud.
    private func setupExternalChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: syncedStore,
            queue: .main
        ) { [weak self] notification in
            self?.handleExternalChange(notification)
        }

        // Trigger initial sync
        syncedStore.synchronize()
    }

    /// Handles settings changes from other devices.
    @MainActor
    private func handleExternalChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // Update local state from iCloud
            for key in changedKeys {
                updateFromExternalChange(key: key)
            }
            logger.info("Synced \(changedKeys.count) settings from iCloud")

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            logger.warning("iCloud KVS quota exceeded")

        case NSUbiquitousKeyValueStoreAccountChange:
            logger.info("iCloud account changed, reloading settings")
            reloadAllSyncedSettings()

        default:
            break
        }
    }

    /// Updates a single property from external iCloud change.
    @MainActor
    private func updateFromExternalChange(key: String) {
        switch key {
        case Keys.isProUser:
            isProUser = syncedStore.bool(forKey: key)
        case Keys.audioSyncPolicy:
            if let value = syncedStore.string(forKey: key),
               let policy = AudioSyncPolicy(rawValue: value) {
                audioSyncPolicy = policy
            }
        case Keys.retentionPolicy:
            if let value = syncedStore.string(forKey: key),
               let policy = RetentionPolicy(rawValue: value) {
                retentionPolicy = policy
            }
        case Keys.autoCopyOnComplete:
            autoCopyOnComplete = syncedStore.bool(forKey: key)
        case Keys.recentClipsCount:
            let value = syncedStore.longLong(forKey: key)
            if value > 0 {
                recentClipsCount = Int(value)
            }
        default:
            break
        }
    }

    /// Reloads all synced settings (e.g., after iCloud account change).
    @MainActor
    private func reloadAllSyncedSettings() {
        isProUser = syncedStore.bool(forKey: Keys.isProUser)
        audioSyncPolicy = AudioSyncPolicy(
            rawValue: syncedStore.string(forKey: Keys.audioSyncPolicy) ?? ""
        ) ?? .last7Days
        retentionPolicy = RetentionPolicy(
            rawValue: syncedStore.string(forKey: Keys.retentionPolicy) ?? ""
        ) ?? .forever
        autoCopyOnComplete = syncedStore.bool(forKey: Keys.autoCopyOnComplete)
        let count = syncedStore.longLong(forKey: Keys.recentClipsCount)
        recentClipsCount = count > 0 ? Int(count) : 10
    }

    // MARK: - Migration

    /// Migrates existing UserDefaults settings to iCloud on first run.
    /// Only runs once per device.
    private static func migrateToICloudIfNeeded() {
        let migrationKey = "hasCompletedICloudMigration"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let logger = Logger(subsystem: "com.voicenote", category: "AppSettings")
        let syncedStore = NSUbiquitousKeyValueStore.default
        let localStore = UserDefaults.standard

        // Migrate isProUser if it exists in UserDefaults but not in iCloud
        if localStore.object(forKey: "isProUser") != nil &&
           syncedStore.object(forKey: Keys.isProUser) == nil {
            let wasProUser = localStore.bool(forKey: "isProUser")
            syncedStore.set(wasProUser, forKey: Keys.isProUser)
            logger.info("Migrated isProUser to iCloud: \(wasProUser)")
        }

        syncedStore.synchronize()
        localStore.set(true, forKey: migrationKey)
        logger.info("Completed iCloud settings migration")
    }

    // MARK: - Computed Properties (Derived from Settings)
    //
    // These provide convenient access to values that depend on settings.
    // Because AppSettings is @Observable, views using these will
    // automatically update when the underlying setting changes.

    /// Current frame rate interval for TimelineView animations.
    /// Returns 1/30 (0.033s) in low power mode, 1/60 (0.017s) otherwise.
    var frameRateInterval: Double {
        AudioConstants.FrameRate.interval(lowPowerMode: lowPowerMode)
    }

    /// Current frame rate interval as CFAbsoluteTime for audio callbacks.
    /// Same value as `frameRateInterval` but typed for audio callback usage.
    var frameRateCFInterval: CFAbsoluteTime {
        AudioConstants.FrameRate.cfInterval(lowPowerMode: lowPowerMode)
    }

    /// Number of bars to display in audio level visualizer.
    /// Returns 12 in low power mode, 20 otherwise.
    var levelBarCount: Int {
        AudioConstants.LevelBar.barCount(lowPowerMode: lowPowerMode)
    }
}

// MARK: - Storage Keys

private enum Keys {
    static let isProUser = "isProUser"
    static let audioSyncPolicy = "audioSyncPolicy"
    static let retentionPolicy = "retentionPolicy"
    static let autoCopyOnComplete = "autoCopyOnComplete"
    static let recentClipsCount = "recentClipsCount"
    static let showAudioVisualizer = "showAudioVisualizer"
    static let audioVisualizerMonochrome = "audioVisualizerMonochrome"
    // macOS floating panel settings
    static let floatingPanelStayOnTop = "floatingPanelStayOnTop"
    static let showRecordingBorder = "showRecordingBorder"
    static let showPanelOnLaunch = "showPanelOnLaunch"
}

// MARK: - Audio Sync Policy

/// Controls how much audio data syncs via iCloud.
/// Audio files are large, so user can choose bandwidth vs convenience tradeoff.
enum AudioSyncPolicy: String, CaseIterable, Codable {
    /// Never sync audio files - metadata only
    case never = "never"

    /// Sync audio from last 7 days
    case last7Days = "last7Days"

    /// Sync audio from last 30 days
    case last30Days = "last30Days"

    /// Sync all audio files
    case all = "all"

    var displayName: String {
        switch self {
        case .never: return "Never"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .all: return "All Recordings"
        }
    }
}

// MARK: - Retention Policy

/// Controls automatic deletion of old recordings.
enum RetentionPolicy: String, CaseIterable, Codable {
    /// Keep recordings forever
    case forever = "forever"

    /// Delete recordings older than 7 days
    case days7 = "7days"

    /// Delete recordings older than 30 days
    case days30 = "30days"

    /// Delete recordings older than 90 days
    case days90 = "90days"

    /// Delete recordings older than 1 year (kept for backwards compatibility)
    case year1 = "1year"

    var displayName: String {
        switch self {
        case .forever: return "Forever"
        case .days7: return "7 Days"
        case .days30: return "30 Days"
        case .days90: return "90 Days"
        case .year1: return "1 Year"
        }
    }

    /// Retention options shown in settings picker (excludes year1 for cleaner UI)
    static var pickerOptions: [RetentionPolicy] {
        [.forever, .days7, .days30, .days90]
    }
}

