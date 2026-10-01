import AppKit
import CoreAudio
import CoreMediaIO
import Foundation
import Intents
import OSLog
import SalahCore

private let log = Logger(subsystem: SalahInfo.appBundleIdentifier, category: "prayer-mode.busy")

/// Reports whether the user is on a call or has a Focus on, so Prayer Mode can stand aside.
/// Salah never opens the mic or camera itself — it only reads whether hardware already in use
/// by some other process is running, which needs no privacy permission.
protocol BusyMonitoring: AnyObject {
    var onChange: ((BusyState) -> Void)? { get set }
    func currentState() -> BusyState
    func start()
    func stop()
}

@MainActor
final class SystemBusyMonitor: BusyMonitoring {
    var onChange: ((BusyState) -> Void)?

    /// Debounces the busy→free transition only; a new call is reported immediately.
    private static let endDebounce: TimeInterval = 10

    private var reportedBusy = false
    private var endTimer: Timer?
    private var cameraPollTimer: Timer?

    private var micListeners: [(AudioObjectID, AudioObjectPropertyListenerBlock)] = []
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var cameraListeners: [(CMIOObjectID, CMIOObjectPropertyListenerBlock)] = []
    private var cameraListListener: CMIOObjectPropertyListenerBlock?

    func start() {
        installDeviceListListeners()
        attachMicListeners()
        attachCameraListeners()
        // A light fallback poll: CMIO's "is running somewhere" isn't guaranteed to post a
        // change notification on every driver, so don't rely solely on the listener for camera.
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(t, forMode: .common)
        cameraPollTimer = t
        evaluate(force: true)
    }

    func stop() {
        detachMicListeners()
        detachCameraListeners()
        removeDeviceListListeners()
        cameraPollTimer?.invalidate()
        endTimer?.invalidate()
    }

    func currentState() -> BusyState {
        isRawBusy() ? .onCall(appName: callAppName()) : .free
    }

    // MARK: - Debounced reporting

    private func isRawBusy() -> Bool { micIsRunning() || cameraIsRunning() }

    private func evaluate(force: Bool = false) {
        let raw = isRawBusy()
        if raw {
            endTimer?.invalidate(); endTimer = nil
            guard !reportedBusy || force else { return }
            reportedBusy = true
            onChange?(.onCall(appName: callAppName()))
        } else if reportedBusy {
            guard endTimer == nil else { return }
            let t = Timer(timeInterval: Self.endDebounce, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isRawBusy() else { return }
                    self.reportedBusy = false
                    self.onChange?(.free)
                }
            }
            RunLoop.main.add(t, forMode: .common)
            endTimer = t
        } else if force {
            onChange?(.free)
        }
    }

    // MARK: - Microphone (CoreAudio)

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
    )
    private static var micRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain
    )
    private static var streamConfigAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain
    )

    private func installDeviceListListeners() {
        var addr = Self.devicesAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachMicListeners(); self?.evaluate() }
        }
        deviceListListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
    }

    private func removeDeviceListListeners() {
        guard let block = deviceListListener else { return }
        var addr = Self.devicesAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        deviceListListener = nil
    }

    private func inputDevices() -> [AudioObjectID] {
        var addr = Self.devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter(hasInputChannels)
    }

    private func hasInputChannels(_ device: AudioObjectID) -> Bool {
        var addr = Self.streamConfigAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private func attachMicListeners() {
        detachMicListeners()
        var addr = Self.micRunningAddress
        for device in inputDevices() {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &addr, .main, block) == noErr {
                micListeners.append((device, block))
            }
        }
    }

    private func detachMicListeners() {
        var addr = Self.micRunningAddress
        for (device, block) in micListeners { AudioObjectRemovePropertyListenerBlock(device, &addr, .main, block) }
        micListeners.removeAll()
    }

    private func micIsRunning() -> Bool {
        var addr = Self.micRunningAddress
        for device in inputDevices() {
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    // MARK: - Camera (CoreMediaIO)

    private static var cmioDevicesAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    private static var cmioRunningAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )

    private func cameraDevices() -> [CMIOObjectID] {
        var addr = Self.cmioDevicesAddress
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &devices) == noErr else { return [] }
        return devices
    }

    private func attachCameraListeners() {
        detachCameraListeners()
        var addr = Self.cmioRunningAddress
        for device in cameraDevices() {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            if CMIOObjectAddPropertyListenerBlock(device, &addr, .main, block) == noErr {
                cameraListeners.append((device, block))
            }
        }
        // Re-scan when a camera is added or removed (e.g. an external webcam plugged in).
        var devicesAddr = Self.cmioDevicesAddress
        let listBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachCameraListeners(); self?.evaluate() }
        }
        cameraListListener = listBlock
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devicesAddr, .main, listBlock)
    }

    private func detachCameraListeners() {
        var addr = Self.cmioRunningAddress
        for (device, block) in cameraListeners { CMIOObjectRemovePropertyListenerBlock(device, &addr, .main, block) }
        cameraListeners.removeAll()
        if let block = cameraListListener {
            var devicesAddr = Self.cmioDevicesAddress
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devicesAddr, .main, block)
            cameraListListener = nil
        }
    }

    private func cameraIsRunning() -> Bool {
        var addr = Self.cmioRunningAddress
        for device in cameraDevices() {
            var running: UInt32 = 0
            var used: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    // MARK: - Naming the call app (macOS 14.2+, CoreAudio AudioProcess API)

    /// Bundle IDs never counted as "the call app", even while their mic/camera is briefly active.
    static var excludedBundleIDs: Set<String> = [
        SalahInfo.appBundleIdentifier, "com.apple.dictation", "com.apple.assistant.backgroundassets",
        "com.apple.SpeechRecognitionCore", "com.apple.AssistiveControl",
    ]

    private func callAppName() -> String? {
        guard #available(macOS 14.2, *) else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processes = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &processes) == noErr else { return nil }

        var names = Set<String>()
        for process in processes where isProcessRunningInput(process) {
            guard let pid = processPID(process), let url = runningAppURL(for: pid), let bundleID = Bundle(url: url)?.bundleIdentifier,
                  !Self.excludedBundleIDs.contains(bundleID) else { continue }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            names.insert(name)
        }
        return names.count == 1 ? names.first : nil
    }

    private func isProcessRunningInput(_ process: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &running) == noErr && running != 0
    }

    private func processPID(_ process: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &pid) == noErr, pid > 0 else { return nil }
        return pid
    }

    /// The outermost `.app` for a PID, so a browser's helper process (e.g. "Google Chrome
    /// Helper.app" inside "Google Chrome.app/Contents/Frameworks/…") resolves to the browser.
    private func runningAppURL(for pid: pid_t) -> URL? {
        guard let running = NSRunningApplication(processIdentifier: pid), var url = running.bundleURL else { return nil }
        var path = url.path
        while let range = path.range(of: ".app/", options: .backwards) {
            let outer = String(path[..<range.lowerBound]) + ".app"
            if outer == path { break }
            path = outer
        }
        url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : running.bundleURL
    }
}

// MARK: - Focus Status

/// Whether a Focus is currently on, via `INFocusStatusCenter`. Needs the Focus Status
/// capability and `NSFocusStatusUsageDescription`; see roadmap/prayer-mode.md open question 2 —
/// unverified in a Developer ID (non-App Store) build.
@MainActor
enum FocusStatusMonitor {
    static func authorizationStatus() -> INFocusStatusAuthorizationStatus {
        INFocusStatusCenter.default.authorizationStatus
    }

    static func requestAuthorization() async -> INFocusStatusAuthorizationStatus {
        await withCheckedContinuation { c in
            INFocusStatusCenter.default.requestAuthorization { status in c.resume(returning: status) }
        }
    }

    /// `nil` when not authorized or the capability isn't available, so callers treat it as "not busy".
    static func isFocused() -> Bool? {
        guard authorizationStatus() == .authorized else { return nil }
        return INFocusStatusCenter.default.focusStatus.isFocused
    }
}
