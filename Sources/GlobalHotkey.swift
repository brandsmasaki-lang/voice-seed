import Carbon
import AppKit
import SwiftUI
import ApplicationServices

@MainActor final class FnKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var state = FnKeyState()
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var running: Bool { tap != nil }

    @discardableResult func start() -> Bool {
        if let tap { return CGEvent.tapIsEnabled(tap: tap) }
        // Do not trigger an OS permission prompt on launch; the setup button does that.
        guard CGPreflightListenEventAccess() || AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.receive(type: type, event: event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if state.reset() { onInterrupted?() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }
        let flags = event.flags
        let other = !flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]).isEmpty
        switch state.update(keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                            fnDown: flags.contains(.maskSecondaryFn), otherModifiers: other) {
        case .pressed: onPress?()
        case .released: onRelease?()
        case nil: break
        }
    }

    func stop() {
        if state.reset() { onInterrupted?() }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
    }
}

@MainActor final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotkey.onPress?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(choice: Int) -> Bool {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        let modifiers = [controlKey | optionKey, cmdKey | shiftKey, controlKey | shiftKey]
        let id = EventHotKeyID(signature: 0x4B4F454E, id: 1)
        return RegisterEventHotKey(UInt32(kVK_Space), UInt32(modifiers[min(max(choice, 0), 2)]), id,
                                  GetApplicationEventTarget(), 0, &reference) == noErr
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil; handler = nil
    }
}

@MainActor final class RecordingHUD {
    private let panel: NSPanel
    init(model: AppModel) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 66),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }
    func show() {
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 140, y: screen.visibleFrame.minY + 32))
        }
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
}

struct HUDView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            if model.phase == .recording {
                Image(systemName: "waveform").foregroundStyle(Color.mint)
            } else { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.phase == .recording ? "録音中  \(model.duration)" : model.phase.title).font(.system(size: 13, weight: .semibold))
                Text(model.phase == .recording ? (model.recordingFromFn ? "Fn を離すと入力します" : "\(model.shortcutLabel) で終了") : "Macの中で処理しています").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.phase == .recording {
                Button { model.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 12)) }
                    .buttonStyle(.borderless).help("録音を終了")
            }
        }
        .padding(16).frame(width: 280, height: 66)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15)))
    }
}
