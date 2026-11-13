import SwiftUI

private let ink = Color(red: 0.12, green: 0.19, blue: 0.18)
private let green = Color(red: 0.16, green: 0.44, blue: 0.34)
private let paper = Color(red: 0.97, green: 0.97, blue: 0.95)

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var publicInfo: PublicInfoStore
    @ObservedObject var updater: AppUpdateController

    init(model: AppModel) {
        self.model = model
        self.publicInfo = model.publicInfo
        self.updater = model.updater
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.selectedTab == "入力" ? "VOICE WORKSPACE" : model.selectedTab == "入力履歴" ? "RECENT INPUTS" : model.selectedTab == "統計" ? "YOUR ACTIVITY" : model.selectedTab == "単語辞書" ? "YOUR VOCABULARY" : model.selectedTab == "アプリについて" ? "ABOUT & SUPPORT" : "PREFERENCES")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                    Spacer()
                    if publicInfo.updateAvailable {
                        Button("更新があります") { model.selectedTab = "アプリについて" }
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(green)
                    }
                    Label("ローカル処理", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(green)
                }.padding(.horizontal, 32).padding(.top, 30).padding(.bottom, 22)
                Group {
                    switch model.selectedTab {
                    case "単語辞書": DictionaryView(model: model)
                    case "入力履歴": RecentInputsView(model: model)
                    case "統計": UsageView(model: model)
                    case "設定": SettingsView(model: model)
                    case "アプリについて": AboutView(model: model, publicInfo: publicInfo, updater: updater)
                    default: input
                    }
                }
                Spacer(minLength: 0)
                if !model.notice.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").padding(.top, 1)
                        Text(model.notice).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { model.notice = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("通知を閉じる")
                    }.font(.system(size: 11)).foregroundStyle(ink.opacity(0.8))
                        .padding(14).background(green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 28).padding(.bottom, 16)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(paper)
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 710, idealHeight: 760)
        .foregroundStyle(ink).preferredColorScheme(.light)
        .task { await model.refresh() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon).resizable().frame(width: 31, height: 31)
                } else { Image(systemName: "waveform").font(.system(size: 22, weight: .semibold)).foregroundStyle(green) }
                Text("こえのたね").font(.system(size: 19, weight: .bold))
            }.padding(.top, 32).padding(.bottom, 8)
            Text("ことばを、もっと自由に。").font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 36)
            ForEach(Array(zip(["入力", "入力履歴", "統計", "単語辞書", "設定", "アプリについて"], ["mic", "clock.arrow.circlepath", "chart.bar", "character.book.closed", "slider.horizontal.3", "info.circle"])), id: \.0) { title, icon in
                Button { model.selectedTab = title } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon).frame(width: 18)
                        Text(title).font(.system(size: 13, weight: model.selectedTab == title ? .semibold : .regular))
                        Spacer()
                        if model.selectedTab == title { Circle().fill(green).frame(width: 5, height: 5) }
                    }.padding(.horizontal, 14).padding(.vertical, 13)
                        .foregroundStyle(model.selectedTab == title ? green : ink.opacity(0.6))
                        .background(model.selectedTab == title ? green.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain).padding(.bottom, 6)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Label("あなたの声は、Macの中に。", systemImage: "leaf").font(.system(size: 10, weight: .medium)).foregroundStyle(green)
                Text("音声を外部に送らずに文字起こし。\n録音ファイルは保存しません。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(paper, in: RoundedRectangle(cornerRadius: 12))
            Button { model.selectedTab = "アプリについて" } label: {
                Text("\(AppMetadata.name)  /  \(AppMetadata.version)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).help(AppMetadata.versionDescription).padding(.top, 18).padding(.bottom, 24)
        }.padding(.horizontal, 20).frame(width: 220).background(Color.white)
    }

    private var input: some View {
        VStack(spacing: 0) {
            Text(model.phase.title).font(.system(size: 27, weight: .semibold)).tracking(-0.6)
            Text(model.phase == .idle ? (model.needsInputSetup ? "下の準備状況を確認してください。設定画面へ移動せずに準備できます。" : model.fnEnabled ? "入力先で Fn を押しながら話し、離すと入力できます。" : "思いついたことを、そのまま話してください。") : model.phase == .recording ? (model.recordingFromFn ? (model.canAutomaticallyPaste ? "Fn を離すと、文字起こしして元の入力欄に貼り付けます。" : "Fn を離すと、認識結果をこのアプリに表示します。") : "もう一度ボタンを押すと、録音を終了します。") : "音声は外部に送信せず、このMacで処理しています。")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
            if model.needsInputSetup && model.phase == .idle {
                InputSetupView(model: model).padding(.top, 15)
            }
            ZStack {
                if !model.needsInputSetup || model.phase != .idle {
                    Circle().fill(green.opacity(0.035)).frame(width: 166, height: 166)
                    Circle().stroke(green.opacity(0.10), lineWidth: 1).frame(width: 142, height: 142)
                    Circle().stroke(green.opacity(0.14), lineWidth: 1).frame(width: 118, height: 118)
                        .scaleEffect(model.phase == .recording ? 1 + model.level * 0.15 : 1)
                }
                Button { model.toggle() } label: {
                    ZStack {
                        Circle().fill((model.phase == .recording ? Color(red: 0.71, green: 0.28, blue: 0.23) : green).gradient)
                        if model.phase == .transcribing || model.phase == .refining || model.phase == .preparing {
                            ProgressView().tint(.white).controlSize(.large)
                        } else {
                            Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: model.phase == .recording ? 24 : 32, weight: .medium)).foregroundStyle(.white)
                        }
                    }.frame(width: model.needsInputSetup && model.phase == .idle ? 62 : 94, height: model.needsInputSetup && model.phase == .idle ? 62 : 94).shadow(color: green.opacity(0.2), radius: 18, y: 7)
                }.buttonStyle(.plain).disabled((model.busy && model.phase != .recording) || model.installing || !model.modelReady)
                    .help(model.phase == .recording ? "録音を終了" : "録音を開始").accessibilityLabel(model.phase == .recording ? "録音を終了" : "録音を開始")
            }.padding(.top, 17).padding(.bottom, 8)
            if model.phase == .recording {
                HStack(spacing: 4) {
                    ForEach(0..<25, id: \.self) { n in
                        Capsule().fill(green.opacity(0.7)).frame(width: 3, height: 4 + model.level * (n % 3 == 0 ? 21 : 12))
                    }
                    Text(model.duration).font(.system(size: 11, design: .monospaced)).padding(.leading, 8)
                    Button("キャンセル") { model.cancel() }.font(.system(size: 10)).buttonStyle(.plain).padding(.leading, 8)
                }.frame(height: 26).animation(.easeOut(duration: 0.1), value: model.level)
            } else {
                HStack(spacing: 8) {
                    Text(model.fnEnabled ? "入力先で長押し" : "クリック、または").foregroundStyle(.secondary)
                    Text(model.fnEnabled ? "Fn / 🌐" : model.shortcutLabel).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 5).background(.white, in: RoundedRectangle(cornerRadius: 6))
                }.font(.system(size: 11)).frame(height: 26)
            }
            HStack {
                Label("認識結果", systemImage: "text.alignleft").font(.system(size: 12, weight: .semibold))
                Spacer()
                if let elapsed = model.lastFinalizeSeconds {
                    Text(String(format: "確定 %.2f秒", elapsed)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text("\(model.displayedOutput.count) 文字").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Button { model.importAudio() } label: { Label("音声ファイル", systemImage: "arrow.up.doc") }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(green).disabled(model.busy || !model.modelReady)
            }.padding(.top, 27).padding(.bottom, 12)
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: { model.displayedOutput }, set: { if !model.busy { model.output = $0 } })).font(.system(size: 14)).lineSpacing(6).scrollContentBackground(.hidden)
                    .padding(14).disabled(model.busy).accessibilityLabel("認識結果の編集")
                if model.displayedOutput.isEmpty {
                    Text("話したことばが、ここに表示されます。\n文字起こしのあとで、自由に編集できます。")
                        .font(.system(size: 13)).lineSpacing(7).foregroundStyle(.tertiary).padding(20).allowsHitTesting(false)
                }
            }.frame(minHeight: 100, maxHeight: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.07)))
            if !model.original.isEmpty && model.original != model.output {
                DisclosureGroup("元の認識結果を確認") {
                    ScrollView { Text(model.original).font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8) }.frame(maxHeight: 75)
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 9)
            }
            HStack {
                Toggle("フィラー除去（ルール）", isOn: $model.removeFillers).toggleStyle(.switch).controlSize(.mini)
                    .font(.system(size: 10)).disabled(model.busy)
                Toggle("文章整形（Apple Intelligence）", isOn: $model.refineText).toggleStyle(.switch).controlSize(.mini)
                    .font(.system(size: 10)).disabled(model.busy || !SpeechService.canRefine)
                Spacer()
                Button { model.copy() } label: { Label("コピー", systemImage: "doc.on.doc").font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 9) }
                    .buttonStyle(.plain).foregroundStyle(.white).background(green, in: RoundedRectangle(cornerRadius: 9))
                    .disabled(model.output.isEmpty || model.busy)
            }.padding(.top, 14)
            Text("フィラーはルールで除去。文章整形をオンにすると、Apple Intelligenceが句読点・改行も整えます。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
            Button("最近の入力履歴（\(model.activity.history.count)件）を開く") { model.selectedTab = "入力履歴" }
                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(green).padding(.top, 9)
        }.padding(.horizontal, 32).padding(.bottom, 22)
    }
}

struct InputSetupView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("音声入力の準備", systemImage: "checklist").font(.system(size: 12, weight: .semibold))
            if !model.modelReady {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("日本語モデル").fontWeight(.medium)
                        Text(model.modelStatus).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.installing ? "ダウンロード中…" : "日本語モデルを準備") { model.installModel() }
                        .disabled(model.installing || model.busy)
                    if model.installing { ProgressView().controlSize(.small) }
                }
                Text("初回はモデルのダウンロードが必要です。「準備完了」まで待ってください。Apple Intelligenceの設定とは別です。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if model.microphoneStatus != .authorized {
                HStack {
                    Text("マイク：\(model.microphoneStatus == .notDetermined ? "初回の許可が必要" : "許可が必要")")
                    Spacer()
                    Button("マイクを許可する") { model.requestMicrophonePermission() }
                }
            }
            if model.fnEnabled && !model.fnReady {
                HStack {
                    Text("Fnキーの検知：入力監視の許可が必要")
                    Spacer()
                    Button("入力監視を設定する") { model.requestFnPermission() }
                }
            }
            if model.autoPaste && !model.pasteReady {
                HStack {
                    Text("自動貼り付け：アクセシビリティの許可が必要")
                    Spacer()
                    Button("貼り付けを許可する") { model.requestAccessibility() }
                }
                Text("この許可がなくても録音と文字起こしはできます。結果はこのアプリに表示します。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Button("準備状況を再確認") { Task { await model.refresh(); model.refreshInputPermissions() } }
                    .disabled(model.installing || model.busy)
                Spacer()
                Link("設定で困ったとき", destination: URL(string: "https://ai-no-tane.com/lp/koenotane/#troubleshooting")!)
            }
        }.font(.system(size: 11)).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AboutView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var publicInfo: PublicInfoStore
    @ObservedObject var updater: AppUpdateController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                        Image(nsImage: icon).resizable().frame(width: 76, height: 76)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(AppMetadata.name).font(.system(size: 28, weight: .semibold))
                        Text(AppMetadata.versionDescription).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        Text("日本語の声を、Macの中でことばに。").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("アプリの更新", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(publicInfo.updateAvailable ? "更新する" : "更新を確認") { updater.checkForUpdates() }
                            .disabled(model.phase != .idle || !updater.canCheckForUpdates)
                    }
                    if publicInfo.updateAvailable {
                        Text("バージョン \(publicInfo.info.latest.version) が利用できます。")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(green)
                        Text(publicInfo.info.latest.notes).font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text("現在のバージョン：\(AppMetadata.version)（ビルド \(AppMetadata.build)）")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("更新する場合は、案内に従ってインストール・再起動してください。辞書と設定は引き継ぎます。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 10) {
                    Label("無料で使える音声入力", systemImage: "leaf").font(.system(size: 13, weight: .semibold)).foregroundStyle(green)
                    Text(publicInfo.info.intro)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                    Text("対応環境：Appleシリコン搭載Mac / macOS 26以降 / 日本語")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(publicInfo.info.supportTitle).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("案内を再読込") { Task { await publicInfo.refresh(force: true) } }
                            .font(.system(size: 10)).disabled(publicInfo.refreshing)
                    }
                    ForEach(publicInfo.info.links) { link in
                        if let url = link.url {
                            Link(destination: url) { linkContent(link, available: true) }
                                .buttonStyle(.plain).help(url.absoluteString)
                                .accessibilityLabel(link.title + "（外部サイトを開く）")
                        } else {
                            linkContent(link, available: false)
                        }
                    }
                    Text("リンクは標準ブラウザで開きます。音声や認識結果をリンク先へ送ることはありません。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if !publicInfo.status.isEmpty {
                        Text(publicInfo.status).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup("プライバシーとデータの扱い") {
                    Text(AppMetadata.bundledText("PRIVACY")).font(.system(size: 11)).textSelection(.enabled).padding(.top, 10)
                }.font(.system(size: 12))
                DisclosureGroup("ライセンス・クレジット") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(AppMetadata.bundledText("LICENSE", extension: "txt"))
                        Text(AppMetadata.bundledText("THIRD_PARTY_NOTICES"))
                        Text(AppMetadata.bundledText("SparkleLicense", extension: "txt"))
                    }.font(.system(size: 10)).textSelection(.enabled).padding(.top, 10)
                }.font(.system(size: 12))
            }.padding(.horizontal, 32).padding(.bottom, 28)
        }
        .task { await publicInfo.refresh() }
    }

    private func linkContent(_ link: AppLink, available: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: link.symbol).font(.system(size: 18)).frame(width: 26).foregroundStyle(green)
            VStack(alignment: .leading, spacing: 4) {
                Text(link.title).font(.system(size: 13, weight: .medium))
                Text(link.detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if available { Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(green) }
            else { Text("準備中").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct UpdateMenuItem: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdateController
    @ObservedObject var publicInfo: PublicInfoStore
    init(model: AppModel, updater: AppUpdateController) {
        self.model = model; self.updater = updater; self.publicInfo = model.publicInfo
    }
    var body: some View {
        Button(publicInfo.updateAvailable ? "新しいバージョンに更新…" : "更新を確認…") { updater.checkForUpdates() }
            .disabled(model.phase != .idle || !updater.canCheckForUpdates)
    }
}

@MainActor final class DictionaryForm: ObservableObject {
    @Published var heard = ""
    @Published var written = ""
}

struct DictionaryView: View {
    @ObservedObject var model: AppModel
    @StateObject private var form = DictionaryForm()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("いつもの言葉を、正しく。").font(.system(size: 25, weight: .semibold))
                Spacer()
                if model.readingDictionary { ProgressView().controlSize(.small) }
                Menu("辞書を取り込む") {
                    ForEach(DictionaryImportSource.allCases) { source in
                        Button(source.rawValue + "から…") { model.chooseDictionary(source: source) }
                    }
                }.disabled(model.busy || model.readingDictionary)
            }
            Text("名前や専門用語の表記を登録できます。認識のヒントと、認識後の置換に使います。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                TextField("認識される言葉", text: $form.heard)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("正しい表記", text: $form.written)
                Button("追加") {
                    model.dictionary.append(DictionaryEntry(heard: form.heard.trimmingCharacters(in: .whitespacesAndNewlines), written: form.written.trimmingCharacters(in: .whitespacesAndNewlines)))
                    form.heard = ""; form.written = ""
                }.disabled(form.heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || form.written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.dictionary.contains(where: { $0.heard == form.heard.trimmingCharacters(in: .whitespacesAndNewlines) }))
            }.textFieldStyle(.roundedBorder)
            Text("例：ぷろんぷとばんく → PromptBank").font(.system(size: 10)).foregroundStyle(.secondary)
            DisclosureGroup("ATOK Pro / Aqua Voiceからの取り込み方") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ATOK：辞書ユーティリティの「単語・用例の一覧出力」からテキストで書き出し、「ATOKから…」で選びます。Unicode出力を推奨します。.dicファイルは取り込めません。")
                    Text("Aqua Voice：公式CLIで書き出した単語辞書と置換辞書を、それぞれ取り込めます。単語だけの辞書は認識ヒントとして登録します。")
                    Text("aqua dict export > dictionary.json\naqua replacements export > replacements.json")
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Link("ATOK公式の書き出し手順", destination: URL(string: "https://support.justsystems.com/faq/1032/app/servlet/qadoc?QID=056108")!)
                        Link("Aqua公式CLIの手順", destination: URL(string: "https://aquavoice.com/docs/cli#import-and-export")!)
                    }
                    Text("ファイルは追加前に確認できます。重複は除外し、既存の単語は上書きしません。")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.system(size: 11))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.dictionary) { entry in
                        HStack {
                            Text(entry.isVocabulary ? "認識ヒント" : entry.heard).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: entry.isVocabulary ? "sparkle" : "arrow.right").foregroundStyle(.tertiary)
                            Text(entry.written).frame(maxWidth: .infinity, alignment: .leading)
                            Button { model.dictionary.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("この単語を削除")
                        }.font(.system(size: 13)).padding(16).background(.white)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
                if model.dictionary.isEmpty {
                    ContentUnavailableView("単語を登録しましょう", systemImage: "character.book.closed", description: Text("登録した単語は、このMacだけに保存されます。"))
                }
            }
            Text("部分一致で置き換えます。短すぎる単語は意図しない置換につながるため、固有名詞などを登録してください。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.horizontal, 32).padding(.bottom, 24)
            .sheet(item: $model.pendingDictionaryImport) { preview in DictionaryImportView(model: model, preview: preview) }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("心地よい入力のために。").font(.system(size: 25, weight: .semibold))
                card("Fnを押して話す → 離して入力", icon: "keyboard") {
                    Toggle("Fn / 🌐 キーを押している間だけ録音する", isOn: $model.fnEnabled).font(.system(size: 12)).disabled(model.busy)
                    Text("入力したい欄をクリックし、Fnを押しながら話してください。離すと文字起こしして、その欄へ自動で貼り付けます。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    HStack {
                        Label(model.fnReady ? "① Fnキーの検知：準備完了" : "① Fnキーの検知：許可が必要", systemImage: model.fnReady ? "checkmark.circle.fill" : "circle")
                        Spacer()
                        Button("入力監視の設定を開く") { model.requestFnPermission() }
                    }.font(.system(size: 11))
                    HStack {
                        Label(model.pasteReady ? "② 自動貼り付け：許可済み" : "② 自動貼り付け：許可が必要", systemImage: model.pasteReady ? "checkmark.circle.fill" : "circle")
                        Spacer()
                        Button("貼り付けの許可を設定") { model.requestAccessibility() }
                    }.font(.system(size: 11))
                    Text("開いた設定で「こえのたね」をオンにしてください。許可しても反映されない場合はアプリを終了して開き直してください。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Toggle("Fnを離したら、元の入力欄へ貼り付ける", isOn: $model.autoPaste).font(.system(size: 12)).disabled(model.busy)
                    Divider()
                    Text("Macのキーボード設定で「🌐キーを押して実行する操作」を「何もしない」にしてください。同じFnキーを使うAqua Voiceは、試す間は終了してください。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    Button("Macのキーボード設定を開く") { model.openKeyboardSettings() }
                    Text(model.fnLastEvent).font(.system(size: 11, weight: .medium)).foregroundStyle(green)
                    Text("この設定画面ではFnを押しても録音しません。キーの検出だけを確認できます。通常の文字キーは監視・保存しません。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("入力画面で試す") { model.selectedTab = "入力"; model.refreshInputPermissions() }
                }
                card("音声認識", icon: "waveform") {
                    Text("日本語 / Apple SpeechAnalyzer").font(.system(size: 13, weight: .medium))
                    Text(model.modelStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Button(model.installing ? "モデルを準備中…" : model.modelReady ? "準備完了" : "日本語モデルを準備") { model.installModel() }
                            .disabled(model.installing || model.modelReady || model.busy)
                        if model.installing { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("再確認") { Task { await model.refresh() } }.disabled(model.installing)
                    }
                    Text("初回のモデル取得にインターネットを使います。認識は端末内で実行します。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                card("文章を整える", icon: "sparkles") {
                    Toggle("フィラー除去（ルール処理・高速）", isOn: $model.removeFillers)
                        .font(.system(size: 12)).disabled(model.busy)
                    Text("端末内の軽いルールで、明らかなフィラーを除きます。「あの店」「ええ、賛成です」、引用した言葉、辞書に登録した語は残します。元の認識結果も確認できます。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Toggle("文章整形（Apple Intelligence）", isOn: $model.refineText)
                        .font(.system(size: 12)).disabled(!SpeechService.canRefine || model.busy)
                    Text(model.llmStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Apple Intelligenceの端末内LLMが、フィラー・句読点・改行を文章全体から整えます。オンにすると、その分の処理時間が加わります。元の認識結果も確認できます。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if !SpeechService.canRefine {
                        Button("Apple Intelligenceの設定を開く") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences.AppleIntelligence")!) }
                    }
                }
                card("予備のショートカット", icon: "keyboard") {
                    Picker("録音の開始 / 終了", selection: $model.shortcut) {
                        Text("⌃ ⌥ Space").tag(0); Text("⌘ ⇧ Space").tag(1); Text("⌃ ⇧ Space").tag(2)
                    }.disabled(model.busy)
                    if !model.hotkeyStatus.isEmpty { Text(model.hotkeyStatus).font(.system(size: 10)).foregroundStyle(.red) }
                    Toggle("ショートカット録音後、元のアプリに自動で貼り付ける", isOn: $model.autoPaste).font(.system(size: 12)).disabled(model.busy)
                    Text("クリップボードに結果を入れ、⌘Vを送ります。送信キーは押しません。アプリの録音ボタンでは結果を表示します。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("アクセシビリティの許可を設定") { model.requestAccessibility() }
                }
                card("データについて", icon: "lock.shield") {
                    Text("マイク音声はメモリ上で認識し、録音ファイルは保存しません。入力履歴は直近5件をこのMacに保存し、履歴画面で保存のオン・オフと削除ができます。統計は文字数・回数・所要時間・開始時のアプリ名をこのMacに保存します。単語辞書と設定もこのMacに保存します。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
                    Text("録音は1回5分まで。処理中は新しい録音を開始できません。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 32).padding(.bottom, 24)
        }
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(green)
            content()
        }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RecentInputsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("最近の入力").font(.system(size: 25, weight: .semibold))
                    Spacer()
                    Button("履歴を削除") { model.confirmingHistoryDeletion = true }.disabled(model.activity.history.isEmpty)
                }
                Text("直近5件をこのMacに保存します。アプリを開き直してもコピーできます。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Toggle("入力履歴をこのMacに保存する", isOn: Binding(get: { model.activity.savesHistory }, set: model.setHistoryEnabled))
                    .font(.system(size: 12))
                if model.activity.history.isEmpty {
                    Text("音声入力すると、ここに履歴が表示されます。")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 30)
                }
                ForEach(model.activity.history) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Text(entry.application)
                            Spacer()
                            Button("コピー") { model.copyHistory(entry) }
                                .accessibilityLabel("\(entry.createdAt.formatted(date: .omitted, time: .shortened))の履歴をコピー")
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(entry.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 13))
                }
                Text("保存をオフにしても既存の履歴は残ります。不要な履歴は「履歴を削除」で消せます。音声ファイル自体は保存しません。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 32).padding(.bottom, 24)
        }.confirmationDialog("入力履歴をすべて削除しますか？", isPresented: $model.confirmingHistoryDeletion) {
            Button("5件までの入力履歴を削除", role: .destructive) { model.clearHistory() }
        } message: { Text("辞書・設定・統計は残ります。") }
    }
}

struct UsageView: View {
    @ObservedObject var model: AppModel
    private var usage: UsageTotals { model.activity.usage }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("あなたの音声入力").font(.system(size: 25, weight: .semibold))
                Text("声から作ったことばと、手入力との時間の比較。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 15) {
                    Text("累計入力文字数").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(usage.characters.formatted()).font(.system(size: 48, weight: .medium, design: .rounded))
                    Divider()
                    Text("推定短縮時間").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(duration(usage.estimatedSavedSeconds(typingCharactersPerMinute: model.activity.typingCharactersPerMinute)))
                        .font(.system(size: 31, weight: .semibold)).foregroundStyle(green)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    metric("利用回数", "\(usage.sessions)回")
                    metric("連続利用", "\(usage.currentStreak(on: Date()))日")
                    metric("音声入力の速度", "\(Int(usage.charactersPerMinute.rounded()))文字/分")
                    metric("開始時のアプリ（最多）", usage.topApplication ?? "まだありません")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("手入力の速度：\(model.activity.typingCharactersPerMinute)文字/分", value: Binding(get: { model.activity.typingCharactersPerMinute }, set: model.setTypingSpeed), in: 20...1000, step: 10)
                        .font(.system(size: 12))
                    Text("初期値の100文字/分は計算用の仮の値です。ご自身の速度に変更してください。推定短縮時間＝文字数÷手入力速度－音声入力にかかった時間。修正やコピーの時間は含みません。")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                    Toggle("利用統計をこのMacに保存する", isOn: Binding(get: { model.activity.collectsUsage }, set: model.setUsageEnabled))
                        .font(.system(size: 12))
                    Button("統計をリセット") { model.confirmingUsageReset = true }.font(.system(size: 11))
                }
                Text("文字数・回数・所要時間・開始時のアプリ名のみをMac内で集計します。音声ファイルの取り込みは、速度と短縮時間に含めません。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 32).padding(.bottom, 24)
        }.confirmationDialog("利用統計をリセットしますか？", isPresented: $model.confirmingUsageReset) {
            Button("統計だけをリセット", role: .destructive) { model.clearUsage() }
        } message: { Text("入力履歴・辞書・設定は残ります。") }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)時間\(minutes % 60)分" : minutes > 0 ? "\(minutes)分\(Int(seconds) % 60)秒" : "\(Int(seconds))秒"
    }
}
