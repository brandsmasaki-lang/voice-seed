import Foundation

/// Receiving a physical Fn event already proves the key monitor is active.
/// Paste permission and the user's paste preference must never block recording.
enum FnStartPolicy {
    enum Action: Equatable {
        case ignore
        case prepareSpeechModel
        case record(automaticallyPaste: Bool)
    }

    static func action(enabled: Bool, busy: Bool, installing: Bool, ownSettingsFrontmost: Bool,
                       modelReady: Bool, pasteAllowed: Bool, autoPasteEnabled: Bool) -> Action {
        guard enabled, !busy, !installing, !ownSettingsFrontmost else { return .ignore }
        guard modelReady else { return .prepareSpeechModel }
        return .record(automaticallyPaste: pasteAllowed && autoPasteEnabled)
    }
}
