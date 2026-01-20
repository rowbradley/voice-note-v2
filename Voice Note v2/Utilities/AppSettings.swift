import Foundation
import Observation

/// Centralized app settings using Swift 6 Observation framework.
///
/// Why @Observable instead of @AppStorage everywhere:
/// 1. Single source of truth — settings live in one place
/// 2. Computed properties — derived values like `frameRateInterval` update automatically
/// 3. No boilerplate — views observe automatically, no manual NotificationCenter
/// 4. Testable — can inject mock settings in previews/tests
///
/// Usage in Views:
/// ```swift
/// struct MyView: View {
///     @Environment(\.appSettings) private var appSettings
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
/// Usage in Services (non-SwiftUI):
/// ```swift
/// let interval = AppSettings.shared.frameRateCFInterval
/// ```
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

    // MARK: - Performance Settings

    /// Reduces animation frame rate from 60fps to 30fps to save battery.
    ///
    /// When enabled:
    /// - TimelineView animations run at 30fps
    /// - Audio level bars reduce from 20 to 12
    /// - UI update throttling in audio callbacks uses 30fps interval
    ///
    /// Persisted to UserDefaults automatically via didSet.
    var lowPowerMode: Bool {
        didSet {
            UserDefaults.standard.lowPowerMode = lowPowerMode
        }
    }

    /// Pro user flag - enables auto-cleanup of transcripts.
    /// Persisted to UserDefaults automatically via didSet.
    var isProUser: Bool {
        didSet {
            UserDefaults.standard.set(isProUser, forKey: "isProUser")
        }
    }

    // MARK: - Audio Visualizer Settings

    /// When false, hides the audio level visualization during recording.
    /// Some users find animation distracting.
    var showAudioVisualizer: Bool {
        didSet {
            UserDefaults.standard.set(showAudioVisualizer, forKey: "showAudioVisualizer")
        }
    }

    /// When true, uses monochrome (gray) dots instead of colored (green/yellow/red).
    /// Provides subtler appearance while retaining motion feedback.
    var audioVisualizerMonochrome: Bool {
        didSet {
            UserDefaults.standard.set(audioVisualizerMonochrome, forKey: "audioVisualizerMonochrome")
        }
    }

    // MARK: - Initialization

    /// Private initializer ensures singleton pattern.
    /// Loads initial values from UserDefaults synchronously to prevent
    /// UI flash on first render (settings are available immediately).
    private init() {
        // Load from UserDefaults. Defaults to false if not set.
        self.lowPowerMode = UserDefaults.standard.lowPowerMode
        self.isProUser = UserDefaults.standard.bool(forKey: "isProUser")

        // Audio visualizer settings (default: shown, colored)
        self.showAudioVisualizer = UserDefaults.standard.object(forKey: "showAudioVisualizer") as? Bool ?? true
        self.audioVisualizerMonochrome = UserDefaults.standard.bool(forKey: "audioVisualizerMonochrome")
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
