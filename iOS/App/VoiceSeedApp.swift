import SwiftUI

@main struct VoiceSeedApp: App {
    @StateObject private var model = DictationModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--keyboard-edit-benchmark") {
                CorrectionBench()
                    #if targetEnvironment(simulator)
                    .task {
                        guard ProcessInfo.processInfo.arguments.contains("--synthetic-dictation") else { return }
                        await model.initialize()
                        await model.activate()
                    }
                    #endif
            } else { application }
            #else
            application
            #endif
        }
    }

    private var application: some View {
        MainView().environmentObject(model)
            .tint(Color(red: 0.13, green: 0.36, blue: 0.28))
            .task { await model.initialize() }
            .onOpenURL { model.handleIncomingURL($0) }
            .onChange(of: scenePhase) { _, phase in model.sceneChanged(phase) }
    }
}

#if DEBUG
/// Isolated, in-memory input fields for comparing keyboard builds on the same device.
private struct CorrectionBench: View {
    @State private var text = ""
    @State private var second = ""
    @State private var status = ""
    @FocusState private var field: Int?
    private var phrase: String {
        let sample = "斎藤の洗濯をまた確認します。"
        return ProcessInfo.processInfo.arguments.contains("--long-correction") ? String(repeating: sample, count: 35) : sample
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("修正の実機テスト").font(.headline)
            TextField("比較用の入力欄", text: $text, axis: .vertical)
                .lineLimit(1...4).focused($field, equals: 1).font(.title2).textFieldStyle(.roundedBorder)
            TextField("別の入力欄", text: $second).focused($field, equals: 2).textFieldStyle(.roundedBorder)
            Button("比較文を準備") {
                do {
                    let store = try AppGroupContainer.open()
                    let prepared = try store.update { state in
                        guard state.retainedDraft == nil, state.request == nil else { return false }
                        state.retainedDraft = .init(id: UUID(), text: phrase, date: Date())
                        return true
                    }
                    field = 1
                    status = prepared ? "「修正する」か「貼り付ける」を選んでください" : "入力待ちの文章があります"
                } catch { status = error.localizedDescription }
            }
            Text(status).font(.footnote)
            Spacer()
        }.padding()
    }
}
#endif
