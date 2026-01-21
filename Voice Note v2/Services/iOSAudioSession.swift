//
//  iOSAudioSession.swift
//  Voice Note
//
//  iOS implementation of AudioSessionProvider using AVAudioSession.
//

#if os(iOS)

import AVFoundation
import Foundation
import os.log

/// iOS audio session provider using AVAudioSession
final class iOSAudioSession: AudioSessionProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.voicenote", category: "iOSAudioSession")
    private let session = AVAudioSession.sharedInstance()

    private var routeChangeObserver: Any?
    private var interruptionObserver: Any?

    init() {
        logger.debug("iOSAudioSession initialized")
    }

    deinit {
        stopObservingRouteChanges()
        stopObservingInterruptions()
    }

    // MARK: - AudioSessionProvider

    func configure() async throws {
        // Configure for recording with playback capability
        // .allowBluetoothHFP enables Bluetooth input - iOS routes automatically
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            logger.debug("Audio session category configured")
        } catch {
            throw AudioSessionError.configurationFailed(error.localizedDescription)
        }
    }

    func activate() async throws {
        do {
            try session.setActive(true)

            // Wait for Bluetooth HFP negotiation to complete
            // When AirPods are connected, iOS needs time to switch from A2DP to HFP
            try await Task.sleep(nanoseconds: AudioConstants.Timing.hfpNegotiation)

            logger.debug("Audio session activated, route: \(self.session.currentRoute.inputs.first?.portType.rawValue ?? "none")")
        } catch {
            throw AudioSessionError.activationFailed(error.localizedDescription)
        }
    }

    func deactivate() throws {
        try session.setActive(false)
        logger.debug("Audio session deactivated")
    }

    var currentInputDevice: String {
        get async {
            if let input = session.currentRoute.inputs.first {
                return getReadableDeviceName(for: input)
            }
            return "Microphone"
        }
    }

    var isExternalInputConnected: Bool {
        get async {
            guard let input = session.currentRoute.inputs.first else { return false }
            return input.portType != .builtInMic
        }
    }

    func observeRouteChanges(_ handler: @escaping @Sendable () -> Void) {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }

            // Only notify for significant route changes
            if reason == .newDeviceAvailable ||
               reason == .oldDeviceUnavailable ||
               reason == .routeConfigurationChange {
                self.logger.info("Audio route changed: \(reason.rawValue)")
                handler()
            }
        }
    }

    func stopObservingRouteChanges() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    func observeInterruptions(
        began: @escaping @Sendable () -> Void,
        ended: @escaping @Sendable (Bool) -> Void
    ) {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            switch type {
            case .began:
                self.logInterruptionReason(userInfo)
                began()

            case .ended:
                let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options)
                    .contains(.shouldResume)
                self.logger.info("Audio interruption ended, shouldResume: \(shouldResume)")
                ended(shouldResume)

            @unknown default:
                break
            }
        }
    }

    func stopObservingInterruptions() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    // MARK: - Private

    private func getReadableDeviceName(for input: AVAudioSessionPortDescription) -> String {
        switch input.portType {
        case .builtInMic:
            return "Built-in Microphone"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            let deviceName = input.portName.isEmpty ? "Bluetooth" : input.portName
            return deviceName
        case .headsetMic:
            return "Wired Headset"
        case .airPlay:
            return "AirPlay Device"
        case .carAudio:
            return "Car Audio"
        case .usbAudio:
            return "USB Microphone"
        default:
            return input.portName.isEmpty ? "External Microphone" : input.portName
        }
    }

    private func logInterruptionReason(_ userInfo: [AnyHashable: Any]) {
        if let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt,
           let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
            switch reason {
            case .appWasSuspended:
                logger.info("Audio interrupted - app was suspended")
            case .builtInMicMuted:
                logger.info("Audio interrupted - mic muted (iPad)")
            case .routeDisconnected:
                logger.info("Audio interrupted - route disconnected")
            default:
                logger.info("Audio interrupted - another app took focus")
            }
        }
    }
}

#endif
