import SwiftUI

/// Environment key for AppSettings.
///
/// Why use Environment instead of accessing AppSettings.shared directly:
/// 1. Testability — previews/tests can inject mock settings
/// 2. SwiftUI convention — matches patterns like \.dismiss, \.colorScheme
/// 3. Explicit dependencies — views declare what they need
///
/// The default value points to the shared singleton, so views work
/// without explicit injection. But you CAN override it:
///
/// ```swift
/// // In previews:
/// MyView()
///     .environment(\.appSettings, MockAppSettings())
/// ```
private struct AppSettingsKey: EnvironmentKey {
    static let defaultValue = AppSettings.shared
}

extension EnvironmentValues {
    /// App-wide settings (low power mode, etc.).
    ///
    /// Usage:
    /// ```swift
    /// struct MyView: View {
    ///     @Environment(\.appSettings) private var appSettings
    ///
    ///     var body: some View {
    ///         if appSettings.lowPowerMode {
    ///             Text("Battery saver on")
    ///         }
    ///     }
    /// }
    /// ```
    var appSettings: AppSettings {
        get { self[AppSettingsKey.self] }
        set { self[AppSettingsKey.self] = newValue }
    }
}
