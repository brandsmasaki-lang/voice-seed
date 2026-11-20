import SwiftUI
import UniformTypeIdentifiers

struct DictionaryView: View {
    @EnvironmentObject private var model: DictationModel
    @State private var heard = ""
    @State private var written = ""
    @State private var vocabulary = false
    @State private var preferredEdit: DictionaryEntry?
    @State private var importing = false
    @State private var source = DictionaryImportSource.generic
    @State private var preview: DictionaryImportPreview?
    @State private var exporting = false
    private var exportFile: DictionaryTransferFile { DictionaryTransferFile(entries: model.state.settings.dictionary) }
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
            Section {
                ForEach(model.state.settings.preferredCandidates ?? []) { entry in
                    Button { preferredEdit = entry } label: {
                        VStack(alignment: .leading) {
                            Text(entry.written).font(.title3.bold())
                            Text(entry.heard)
                        }
                    }
                }.onDelete { offsets in
                    let rows = model.state.settings.preferredCandidates ?? []
                    let ids = Set(offsets.map { rows[$0].id })
                    model.updateSettings { $0.preferredCandidates?.removeAll { ids.contains($0.id) } }
                }
                if model.state.settings.preferredCandidates?.isEmpty != false {
                    Text("音声入力のあと、語を直して「登録する」を押すとここに表示されます。")
                }
            } header: { Text("優先する変換候補") } footer: {
                Text("タップして読みや表記を変更できます。左にスワイプすると削除できます。")
            }
            Section("ほかの端末やアプリから辞書を移す") {
                Picker("ファイルの形式", selection: $source) {
                    ForEach(DictionaryImportSource.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("辞書ファイルを選ぶ") { importing = true }
                Text("ATOKやAqua Voiceから自分で書き出したTXT・CSV・TSV・JSONを取り込めます。").font(.caption).foregroundStyle(.secondary)
            }
            Section("ほかの端末へ辞書を渡す") {
                ShareLink(item: exportFile, preview: SharePreview("こえのたね辞書")) {
                    Label("AirDropなどで辞書を共有", systemImage: "square.and.arrow.up")
                }.disabled(model.state.settings.dictionary.isEmpty)
                Button("辞書をファイルに保存") { exporting = true }
                    .disabled(model.state.settings.dictionary.isEmpty)
                Text("読み・表記・認識ヒントを保つJSON形式です。Macでは「単語辞書 → 辞書を取り込む → CSV / TSV / JSON」で開きます。Macから受け取ったファイルは、上の「辞書ファイルを選ぶ」から取り込めます。自動同期はしません。")
                    .font(.caption).foregroundStyle(.secondary)
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
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json, defaultFilename: "こえのたね辞書") { result in
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let value = try DictionaryImporter.read(url: url, source: source, existing: model.state.settings.dictionary)
                guard value.additions.count + model.state.settings.dictionary.count <= 2000 else {
                    model.errorMessage = "このアプリの辞書は2,000件までです。ファイルを分けてください。"; return
                }
                preview = value
            } catch { model.errorMessage = error.localizedDescription }
        }
        .sheet(item: $preferredEdit) { entry in
            PreferredCandidateEditor(entry: entry) { edited in
                model.updateSettings { $0.prefer(edited) }
                preferredEdit = nil
            }
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

private struct PreferredCandidateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: DictionaryEntry
    let save: (DictionaryEntry) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("読み", text: $entry.heard)
                TextField("優先する表記", text: $entry.written)
            }
            .navigationTitle("変換候補を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        entry.heard = entry.heard.trimmingCharacters(in: .whitespacesAndNewlines)
                        entry.written = entry.written.trimmingCharacters(in: .whitespacesAndNewlines)
                        save(entry)
                    }.disabled([entry.heard, entry.written].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.count > 120 })
                }
            }
        }
    }
}

struct DictionaryTransferFile: FileDocument, Transferable {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(entries: [DictionaryEntry]) {
        // String-only JSON is always encodable; do not export settings or input history.
        data = try! DictionaryCorrection.exportData(entries)
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in file.data }
            .suggestedFileName("こえのたね辞書.json")
    }
}
