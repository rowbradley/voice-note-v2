import SwiftUI
import AVFoundation
import Observation

@MainActor
@Observable
final class AppCoordinator {
    var activeSheet: ActiveSheet?
    var showPermissionAlert = false
    var selectedRecording: Recording?
    
    enum ActiveSheet: Identifiable {
        case library
        case settings
        case templatePicker(Recording?)
        case recordingDetail(Recording)
        
        var id: String {
            switch self {
            case .library: return "library"
            case .settings: return "settings"
            case .templatePicker(let recording): return "templatePicker_\(recording?.id.uuidString ?? "new")"
            case .recordingDetail(let recording): return "recordingDetail_\(recording.id)"
            }
        }
    }
    
    func bootstrap() {
        // Initialize app-wide services
        Task {
            await checkPermissions()
        }
    }
    
    func showLibrary() {
        activeSheet = .library
    }
    
    func showSettings() {
        activeSheet = .settings
    }
    
    func showTemplatePicker(for recording: Recording? = nil) {
        activeSheet = .templatePicker(recording)
    }
    
    func showRecordingDetail(_ recording: Recording) {
        activeSheet = .recordingDetail(recording)
    }
    
    func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }
    
    private func checkPermissions() async {
        // Use AVCaptureDevice for modern, cross-version compatibility
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch authStatus {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                showPermissionAlert = true
            }
        case .denied:
            showPermissionAlert = true
        case .authorized:
            break
        case .restricted:
            showPermissionAlert = true
        @unknown default:
            break
        }
    }
}