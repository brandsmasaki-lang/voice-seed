import SwiftUI
import UniformTypeIdentifiers

struct DictionaryView: View {
    @EnvironmentObject private var model: DictationModel
    @State private var heard = ""
    @State private var written = ""
    @State private var vocabulary = false
    @State private var importing = false
    @State private var source = DictionaryImportSource.generic
    @State private var preview: DictionaryImportPreview?
    var body: some View {
        Form {
            Section {
                TextField("読み・認識された表記", text: $heard).textInputAutocapitalization(.never)
                TextField("入力したい表記", text: $written).textInputAutocapitalization(.never)
                Toggle("認識ヒントとして登録", isOn: $vocabulary)
                Button("追加") {
                    let entry = DictionaryEntry(heard: heard.trimmingCharacters(in: .whitespacesAndNewlines),
                        written: written.trimmingCharacters(in: .whitespacesAndNewlines), kind: vocabulary ? .vocabulary : nil)
                    model.updateSettings { $0.dictionary.append(entry) }; heard = ""; written = ""
                }.disabled(heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || heard.count > 120 || written.count > 120 || model.state.settings.dictionary.count >= 2000)
            } header: { Text("名前・用語を登録") } footer: { Text("認識ヒントは聞き取りに使い、表記の一律置換はしません。置換辞書の読みは、日本語テンキーの変換候補にも使います。") }
            Section("Macや他アプリから辞書を移す") {
                Picker("ファイルの形式", selection: $source) {
                    ForEach(DictionaryImportSource.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("辞書ファイルを選ぶ") { importing = true }
                Text("ATOKやAqua Voiceから自分で書き出したTXT・CSV・TSV・JSONを取り込めます。").font(.caption).foregroundStyle(.secondary)
            }
            Section("登録済み \(model.state.settings.dictionary.count)件") {
                ForEach(model.state.settings.dictionary) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.written)
                        Text(entry.isVocabulary ? "認識ヒント" : entry.heard + " → " + entry.written).font(.caption).foregroundStyle(.secondary)
                    }
                }.onDelete { indices in model.updateSettings { $0.dictionary.remove(atOffsets: indices) } }
            }
        }.navigationTitle("単語辞書")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let value = try DictionaryImporter.read(url: url, source: source, existing: model.state.settings.dictionary)
                guard value.additions.count + model.state.settings.dictionary.count <= 2000 else {
                    model.errorMessage = "iPhone版の辞書は2,000件までです。ファイルを分けてください。"; return
                }
                preview = value
            } catch { model.errorMessage = error.localizedDescription }
        }
        .sheet(item: $preview) { value in
            NavigationStack {
                List {
                    Section {
                        Text("追加予定 \(value.additions.count)件・重複 \(value.duplicates)件・表記違い \(value.conflicts)件")
                        ForEach(value.warnings, id: \.self) { Text($0).font(.footnote) }
                    }
                    ForEach(value.additions.prefix(100)) { entry in Text(entry.heard + " → " + entry.written) }
                }.navigationTitle("辞書の取り込み確認").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { preview = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("追加する") { model.updateSettings { $0.dictionary.append(contentsOf: value.additions) }; preview = nil }
                            .disabled(value.additions.isEmpty)
                    }
                }
            }
        }
    }
}
