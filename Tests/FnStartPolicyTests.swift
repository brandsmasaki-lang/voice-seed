import Foundation

@main struct FnStartPolicyTests {
    static func main() {
        var checks = 0
        func expect(_ actual: FnStartPolicy.Action, _ expected: FnStartPolicy.Action, _ message: String) {
            precondition(actual == expected, message); checks += 1
        }
        func action(model: Bool = true, paste: Bool = true, automatic: Bool = true,
                    enabled: Bool = true, busy: Bool = false, installing: Bool = false,
                    settings: Bool = false) -> FnStartPolicy.Action {
            FnStartPolicy.action(enabled: enabled, busy: busy, installing: installing,
                                 ownSettingsFrontmost: settings, modelReady: model,
                                 pasteAllowed: paste, autoPasteEnabled: automatic)
        }
        expect(action(), .record(automaticallyPaste: true), "Prepared Fn input records and pastes")
        expect(action(paste: false), .record(automaticallyPaste: false), "First installation without accessibility still records")
        expect(action(automatic: false), .record(automaticallyPaste: false), "Turning auto-paste off must not disable Fn recording")
        expect(action(paste: false, automatic: false), .record(automaticallyPaste: false), "Neither paste condition sends the user to settings")
        expect(action(model: false), .prepareSpeechModel, "Missing speech model requires an actionable preparation step")
        expect(action(model: false, paste: false), .prepareSpeechModel, "Fresh install identifies the speech model first")
        expect(action(model: false, paste: false, automatic: false), .prepareSpeechModel, "Initial setup does not mislabel paste preferences as missing permissions")
        expect(action(enabled: false), .ignore, "Disabled Fn remains disabled")
        expect(action(busy: true), .ignore, "Do not start a concurrent recording or update")
        expect(action(installing: true), .ignore, "Do not record while the speech model is installing")
        expect(action(settings: true), .ignore, "Settings key detection must not open the microphone")
        expect(action(model: false, busy: true), .ignore, "Busy takes precedence over model setup")
        expect(action(model: false, settings: true), .ignore, "Settings stays safe before initial setup")
        expect(action(paste: false), .record(automaticallyPaste: false), "Repeated Fn attempts with denied paste permission still record")
        expect(action(paste: true), .record(automaticallyPaste: true), "A later permission grant enables automatic paste")
        expect(action(automatic: false), .record(automaticallyPaste: false), "Changing paste preference never forces navigation")
        print("PASS: \(checks) fresh-install and Fn startup regression checks")
    }
}
