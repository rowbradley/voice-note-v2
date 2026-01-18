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
/// Note: Not `@MainActor` because:
/// 1. @Observable provides thread-safe observation
/// 2. UserDefaults access is thread-safe
/// 3. Allows EnvironmentKey to reference `shared` without concurrency warnings
/// SwiftUI will access this on the main thread anyway.
@Observable
final class AppSettings: @unchecked Sendable {

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

    // MARK: - Initialization

    /// Private initializer ensures singleton pattern.
    /// Loads initial values from UserDefaults synchronously to prevent
    /// UI flash on first render (settings are available immediately).
    private init() {
        // Load from UserDefaults. Defaults to false if not set.
        self.lowPowerMode = UserDefaults.standard.lowPowerMode
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
