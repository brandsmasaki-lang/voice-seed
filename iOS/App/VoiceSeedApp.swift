import SwiftUI

@main struct VoiceSeedApp: App {
    @StateObject private var model = DictationModel()
    var body: some Scene {
        WindowGroup {
            MainView().environmentObject(model)
                .tint(Color(red: 0.13, green: 0.36, blue: 0.28))
                .task { await model.initialize() }
        }
    }
}
