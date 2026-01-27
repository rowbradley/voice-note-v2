import SwiftUI

struct RecordButton: View {
    // RecordingState is now defined in Models/RecordingState.swift for cross-platform use

    let state: RecordingState
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var pulseAnimation = false
    
    var body: some View {
        Button(action: {
            // Haptic feedback handled by onChange when state transitions
            action()
        }) {
            Circle()
                .fill(buttonGradient)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )
                .overlay(
                    iconView
                        .foregroundColor(.white)
                        .font(.system(size: iconSize, weight: .medium))
                )
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        }
        .buttonStyle(PressableButtonStyle { pressed in
            isPressed = pressed
        })
        .disabled(state == .processing)
        .onAppear {
            if state == .recording {
                pulseAnimation = true
            }
        }
        .onChange(of: state) { oldState, newState in
            pulseAnimation = newState == .recording
            triggerHapticFeedback(for: newState, from: oldState)
        }
    }
    
    private var diameter: CGFloat {
        return 120 // Always the same size
    }
    
    private var buttonGradient: LinearGradient {
        switch state {
        case .idle:
            return LinearGradient(
                colors: [.red.opacity(0.9), .red.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
        case .recording:
            return LinearGradient(
                colors: [.red, .red.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )
        case .processing:
            return LinearGradient(
                colors: [.gray.opacity(0.8), .gray.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
    
    private var shadowColor: Color {
        switch state {
        case .idle: return .red.opacity(0.3)
        case .recording: return .red.opacity(0.4)
        case .processing: return .gray.opacity(0.2)
        }
    }
    
    private var shadowRadius: CGFloat {
        return 4 // Always the same
    }
    
    private var shadowY: CGFloat {
        return 2 // Always the same
    }
    
    private var strokeColor: Color {
        switch state {
        case .idle: return .red.opacity(0.3)
        case .recording: return .red.opacity(0.5)
        case .processing: return .gray.opacity(0.3)
        }
    }
    
    private var strokeWidth: CGFloat {
        return 4 // Always the same
    }
    
    private var iconSize: CGFloat {
        return 40 // Always the same size
    }
    
    @ViewBuilder
    private var iconView: some View {
        switch state {
        case .idle:
            Image(systemName: "mic.fill")  // Always show mic icon in idle
        case .recording:
            Image(systemName: "stop.fill")
        case .processing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
        }
    }
    
    private func triggerHapticFeedback(for newState: RecordingState, from previousState: RecordingState) {
        switch (previousState, newState) {
        case (.idle, .recording):
            // Starting recording - medium impact
            PlatformFeedback.shared.mediumTap()

        case (.recording, .processing), (.recording, .idle):
            // Stopping recording - light impact
            PlatformFeedback.shared.lightTap()

        case (.processing, .idle):
            // Processing complete - soft notification
            PlatformFeedback.shared.success()

        default:
            break
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    let onPressedChange: (Bool) -> Void
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressedChange(isPressed)
            }
    }
}

#Preview {
    VStack(spacing: 40) {
        RecordButton(state: .idle) { }
        RecordButton(state: .recording) { }
        RecordButton(state: .processing) { }
    }
    .padding()
}