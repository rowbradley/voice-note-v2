import Foundation
import Observation

@MainActor
@Observable
final class TranscriptionSettings {
    static let shared = TranscriptionSettings()

    var useCloudMode: Bool {
        didSet {
            UserDefaults.standard.set(useCloudMode, forKey: "useCloudMode")
        }
    }

    private init() {
        self.useCloudMode = UserDefaults.standard.bool(forKey: "useCloudMode")
    }
}