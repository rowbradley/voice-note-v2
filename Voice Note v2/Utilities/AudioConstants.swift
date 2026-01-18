import Foundation

/// Centralized audio processing constants.
///
/// Why this exists:
/// - Magic numbers like `-40.0` and `300_000_000` were duplicated across files
/// - When tuning audio sensitivity, developers had to find/replace in multiple places
/// - Low Power Mode needs configurable frame rates in one place
///
/// Usage:
/// ```swift
/// // Instead of:
/// private let voiceThreshold: Float = -40.0
///
/// // Use:
/// private let voiceThreshold = AudioConstants.voiceThreshold
/// ```
enum AudioConstants {

    // MARK: - Voice Detection Thresholds
    //
    // These values are in decibels (dB). More negative = quieter.
    // Typical ranges:
    //   -60 dB: Very quiet room
    //   -40 dB: Normal speech at arm's length
    //   -20 dB: Loud speech
    //    0 dB: Maximum (clipping)

    /// Threshold above which audio is considered speech.
    /// Audio louder than -40 dB triggers voice detection indicator.
    /// Tune lower (e.g., -45) to detect quieter speech.
    /// Tune higher (e.g., -35) to ignore background noise.
    static let voiceThreshold: Float = -40.0

    /// Threshold below which audio is considered silence.
    /// Used for detecting pauses in speech.
    static let silenceThreshold: Float = -55.0

    // MARK: - Audio Level Visualization
    //
    // The audio level bar uses color zones to indicate volume:
    //   Green/Blue (0% - 50%): Normal speech
    //   Yellow (50% - 80%): Moderately loud
    //   Red (80% - 100%): Very loud / potential clipping

    /// Thresholds for color-coding audio level bars.
    enum LevelThreshold {
        /// Position above which bars turn red (very loud).
        /// 0.8 = 80% of the visualizer width.
        static let high: Float = 0.8

        /// Position above which bars turn yellow (moderately loud).
        /// 0.5 = 50% of the visualizer width.
        static let medium: Float = 0.5
    }

    // MARK: - Frame Rates
    //
    // Animation frame rates for UI elements.
    // 60fps = smooth but battery-intensive
    // 30fps = still acceptable, significant battery savings

    /// Frame rate configuration for animations.
    enum FrameRate {
        /// Standard frame rate: 60 frames per second.
        /// Provides buttery-smooth animations.
        static let standard: Double = 60.0

        /// Low power frame rate: 30 frames per second.
        /// Reduces GPU usage by ~50% while remaining visually acceptable.
        static let lowPower: Double = 30.0

        /// Converts frame rate to interval for TimelineView.
        /// - Parameter lowPowerMode: If true, returns 30fps interval; otherwise 60fps.
        /// - Returns: Interval in seconds (e.g., 0.0167 for 60fps).
        static func interval(lowPowerMode: Bool) -> Double {
            1.0 / (lowPowerMode ? lowPower : standard)
        }

        /// Converts frame rate to CFAbsoluteTime for audio callback throttling.
        /// - Parameter lowPowerMode: If true, returns 30fps interval; otherwise 60fps.
        /// - Returns: Interval as CFAbsoluteTime for use in audio tap callbacks.
        static func cfInterval(lowPowerMode: Bool) -> CFAbsoluteTime {
            CFAbsoluteTime(interval(lowPowerMode: lowPowerMode))
        }
    }

    // MARK: - Debounce Intervals
    //
    // Debouncing prevents rapid-fire updates from overwhelming the UI.
    // Values are in nanoseconds for use with Task.sleep(nanoseconds:).
    //
    // Conversion: milliseconds × 1_000_000 = nanoseconds
    //   300ms = 300_000_000 ns
    //   500ms = 500_000_000 ns

    /// Debounce durations in nanoseconds.
    enum Debounce {
        /// Search field debounce: 300ms.
        /// Prevents filtering on every keystroke.
        static let search: UInt64 = 300_000_000

        /// Scroll-to-bottom debounce: 300ms.
        /// Prevents scroll animation spam during rapid transcript updates.
        static let scroll: UInt64 = 300_000_000

        /// Share content recalculation debounce: 500ms.
        /// Prevents expensive string concatenation on every character change.
        static let shareContent: UInt64 = 500_000_000
    }

    // MARK: - File Stabilization
    //
    // When recording stops, AVAudioEngine/AVAudioRecorder may not have finished
    // writing to disk. We poll the file size until it stabilizes.
    //
    // Typical stabilization time: 100-500ms
    // Maximum wait: 2 seconds (20 attempts × 100ms)

    /// Configuration for waiting for audio file to finish writing.
    enum FileStabilization {
        /// Maximum number of polling attempts.
        /// 20 attempts × 100ms = 2 seconds maximum wait.
        static let maxAttempts = 20

        /// Interval between file size checks, in nanoseconds.
        /// 100ms provides good balance between responsiveness and CPU usage.
        static let pollInterval: UInt64 = 100_000_000

        /// Number of consecutive stable readings required.
        /// 2 readings × 100ms = file must be stable for 200ms.
        static let stableThreshold = 2
    }

    // MARK: - Audio Level Bar Visualization
    //
    // The audio level bar displays a row of vertical bars that respond to volume.
    // More bars = finer granularity but more drawing work.

    /// Visual configuration for audio level bars.
    enum LevelBar {
        /// Number of bars in standard mode (60fps).
        /// 20 bars provides good visual feedback.
        static let standardBarCount = 20

        /// Number of bars in low power mode (30fps).
        /// Fewer bars = less drawing work per frame.
        static let lowPowerBarCount = 12

        /// Spacing between bars in points.
        static let barSpacing: CGFloat = 3.0

        /// Returns appropriate bar count based on power mode.
        static func barCount(lowPowerMode: Bool) -> Int {
            lowPowerMode ? lowPowerBarCount : standardBarCount
        }
    }
}
