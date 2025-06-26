import Foundation

class TranscriptionSettings: ObservableObject {
    static let shared = TranscriptionSettings()
    
    @Published var useCloudMode: Bool {
        didSet {
            UserDefaults.standard.set(useCloudMode, forKey: "useCloudMode")
        }
    }
    
    private init() {
        self.useCloudMode = UserDefaults.standard.bool(forKey: "useCloudMode")
    }
}