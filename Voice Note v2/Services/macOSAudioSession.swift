//
//  macOSAudioSession.swift
//  Voice Note
//
//  macOS implementation of AudioSessionProvider using CoreAudio.
//  macOS does not have AVAudioSession; AVAudioEngine auto-configures.
//

#if os(macOS)

import AVFoundation
import CoreAudio
import Foundation
import os.log

/// macOS audio session provider using CoreAudio for device detection
final class macOSAudioSession: AudioSessionProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.voicenote", category: "macOSAudioSession")

    private var deviceChangeHandler: (@Sendable () -> Void)?
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        logger.debug("macOSAudioSession initialized")
    }

    deinit {
        stopObservingRouteChanges()
        stopObservingInterruptions()
    }

    // MARK: - AudioSessionProvider

    func configure() async throws {
        // macOS: AVAudioEngine auto-configures, no session setup needed
        logger.debug("macOS audio session configure (no-op)")
    }

    func activate() async throws {
        // macOS: No explicit activation needed
        logger.debug("macOS audio session activate (no-op)")
    }

    func deactivate() throws {
        // macOS: No explicit deactivation needed
        logger.debug("macOS audio session deactivate (no-op)")
    }

    var currentInputDevice: String {
        get async {
            await getDefaultInputDeviceName()
        }
    }

    var isExternalInputConnected: Bool {
        get async {
            // Check if default input is not built-in
            let deviceName = await getDefaultInputDeviceName()
            return !deviceName.lowercased().contains("built-in") &&
                   !deviceName.lowercased().contains("macbook")
        }
    }

    func observeRouteChanges(_ handler: @escaping @Sendable () -> Void) {
        deviceChangeHandler = handler

        // Listen for default input device changes
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Create block as local variable first, then store it
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.logger.info("macOS audio input device changed")
            handler()
        }
        listenerBlock = block

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block  // Use local variable, not force unwrap
        )

        if status != noErr {
            logger.error("Failed to add audio device listener: \(status)")
        }
    }

    func stopObservingRouteChanges() {
        // Capture block in local variable to avoid race condition
        guard let block = listenerBlock else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block  // Use captured local, not force unwrap
        )

        listenerBlock = nil
        deviceChangeHandler = nil
    }

    func observeInterruptions(
        began: @escaping @Sendable () -> Void,
        ended: @escaping @Sendable (Bool) -> Void
    ) {
        // macOS doesn't have iOS-style audio interruptions (phone calls, Siri, etc.)
        // Audio is managed at the app level, not system level
        logger.debug("macOS audio interruption observer (no-op)")
    }

    func stopObservingInterruptions() {
        // No-op on macOS
    }

    // MARK: - Private CoreAudio

    private func getDefaultInputDeviceName() async -> String {
        var deviceID = AudioDeviceID()
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            logger.warning("Failed to get default input device")
            return "Microphone"
        }

        return getDeviceName(deviceID: deviceID)
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0,
            nil,
            &propertySize,
            &name
        )

        guard status == noErr else {
            return "Microphone"
        }

        return name as String
    }
}

#endif
