import CoreAudio
import Foundation

/// A recording borrows the default output's mute/volume controls. No playback audio is captured.
@MainActor final class RecordingOutputMute {
    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static let defaultOutput = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private struct Change {
        let apply: () -> Bool
        let restore: () -> Void
    }

    private let device: AudioDeviceID
    private let uid: String
    private var changes: [Change] = []
    private var listener: AudioObjectPropertyListenerBlock?

    private init(device: AudioDeviceID, uid: String) {
        self.device = device
        self.uid = uid
    }

    static func begin(onOutputChanged: @escaping @MainActor () -> Void) -> RecordingOutputMute? {
        guard let device = defaultDevice(), let uid = deviceUID(device) else { return nil }
        let mute = RecordingOutputMute(device: device, uid: uid)
        guard mute.silence() else { mute.restore(); return nil }
        let listener: AudioObjectPropertyListenerBlock = { [weak mute] _, _ in
            Task { @MainActor in
                guard let mute, mute.listener != nil, defaultDevice() != device else { return }
                onOutputChanged()
            }
        }
        var address = defaultOutput
        guard AudioObjectAddPropertyListenerBlock(system, &address, .main, listener) == noErr else {
            mute.restore(); return nil
        }
        mute.listener = listener
        guard defaultDevice() == device else { mute.restore(); return nil }
        return mute
    }

    func restore() {
        if let listener {
            self.listener = nil
            var address = Self.defaultOutput
            AudioObjectRemovePropertyListenerBlock(Self.system, &address, .main, listener)
        }
        // The numeric device ID can change after disconnecting hardware.
        if Self.deviceUID(device) == uid { for change in changes.reversed() { change.restore() } }
        changes.removeAll()
    }

    private func silence() -> Bool {
        let main = kAudioObjectPropertyElementMain
        if let change = muteControl(main), apply([change]) { return true }
        if let change = volumeControl(main), apply([change]) { return true }

        var address = outputAddress(kAudioDevicePropertyStreamConfiguration, main)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return false }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return false }
        let channels = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + $1.mNumberChannels }
        guard channels > 0 else { return false }
        let controls = (1...channels).compactMap { muteControl($0) ?? volumeControl($0) }
        return controls.count == Int(channels) && apply(controls)
    }

    private func apply(_ controls: [Change]) -> Bool {
        for control in controls {
            guard control.apply() else {
                restore()
                return false
            }
            changes.append(control)
        }
        return true
    }

    private func muteControl(_ element: UInt32) -> Change? {
        control(address: outputAddress(kAudioDevicePropertyMute, element), initial: UInt32(0), silent: UInt32(1))
    }

    private func volumeControl(_ element: UInt32) -> Change? {
        control(address: outputAddress(kAudioDevicePropertyVolumeScalar, element), initial: Float32(0), silent: Float32(0))
    }

    private func control<T: Equatable>(address: AudioObjectPropertyAddress, initial: T, silent: T) -> Change? {
        let device = self.device
        guard let original = Self.read(device, address, initial) else { return nil }
        if original == silent { return Change(apply: { true }, restore: {}) }
        var currentAddress = address
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &currentAddress, &settable) == noErr, settable.boolValue else { return nil }
        return Change(apply: { Self.write(device, address, silent) }, restore: {
            // Preserve a volume change the user made while dictating.
            guard Self.read(device, address, initial) == silent else { return }
            _ = Self.write(device, address, original)
        })
    }

    private func outputAddress(_ selector: AudioObjectPropertySelector, _ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private static func defaultDevice() -> AudioDeviceID? {
        read(system, defaultOutput, AudioDeviceID(kAudioObjectUnknown)).flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    private static func deviceUID(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: uid))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? value : nil
    }

    private static func write<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var address = address
        return withUnsafeBytes(of: value) {
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32($0.count), $0.baseAddress!) == noErr
        }
    }
}
