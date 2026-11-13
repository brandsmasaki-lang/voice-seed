import SwiftUI

struct DictionaryImportView: View {
    @ObservedObject var model: AppModel
    let preview: DictionaryImportPreview
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("辞書の取り込みを確認").font(.system(size: 23, weight: .semibold))
            Text("\(preview.fileName) · \(preview.encoding)").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 25) {
                metric("追加", preview.additions.count)
                metric("重複を除外", preview.duplicates)
                metric("表記違いをヒント化", preview.conflicts)
                metric("形式外を除外", preview.skipped)
            }
            ForEach(preview.warnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("置換は「認識される言葉 → 表記」、認識ヒントは正しい単語だけを登録します。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(preview.additions.prefix(200)) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Text(entry.isVocabulary ? "認識ヒント" : entry.heard).frame(width: 170, alignment: .leading).foregroundStyle(.secondary)
                            Image(systemName: entry.isVocabulary ? "sparkle" : "arrow.right").foregroundStyle(.tertiary)
                            Text(entry.written).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.font(.system(size: 12)).padding(.vertical, 9)
                        Divider()
                    }
                }.padding(.horizontal, 12)
            }.frame(minHeight: 200, maxHeight: 300).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            if preview.additions.count > 200 {
                Text("先頭200件を表示しています。追加対象は全\(preview.additions.count)件です。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("この画面ではまだ登録していません。取り込むと、こえのたねの辞書へ追加します。元の辞書ファイルや既存の登録は変更しません。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("キャンセル") { model.pendingDictionaryImport = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("\(preview.additions.count)件を追加") { model.confirmDictionaryImport() }
                    .keyboardShortcut(.defaultAction).disabled(preview.additions.isEmpty)
            }
        }.padding(28).frame(width: 650).preferredColorScheme(.light)
    }
    private func metric(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(count)").font(.system(size: 23, weight: .semibold, design: .rounded))
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
