import SwiftUI
import UIKit

struct MainView: View {
    @EnvironmentObject private var model: DictationModel
    @AppStorage("completedInitialSetup") private var completedSetup = false
    var body: some View {
        Group {
            if model.showKeyboardReturn {
                KeyboardReturnView()
            } else {
                applicationTabs
            }
        }
        .alert("こえのたね", isPresented: Binding(get: { !model.errorMessage.isEmpty }, set: { if !$0 { model.errorMessage = "" } })) {
            Button("閉じる") { model.errorMessage = "" }
        } message: { Text(model.errorMessage) }
    }
    private var applicationTabs: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { DictationHome() }.tabItem { Label("入力", systemImage: "mic") }.tag(0)
            NavigationStack { DictionaryView() }.tabItem { Label("辞書", systemImage: "text.book.closed") }.tag(1)
            NavigationStack { HistoryView() }.tabItem { Label("履歴", systemImage: "clock") }.tag(2)
            NavigationStack { BenchmarkView() }.tabItem { Label("精度・速度", systemImage: "gauge.with.dots.needle.50percent") }.tag(3)
            NavigationStack { VoiceSeedSettings() }.tabItem { Label("設定", systemImage: "slider.horizontal.3") }.tag(4)
        }
        .onAppear { if !completedSetup { model.showSetup = true } }
        .fullScreenCover(isPresented: $model.showSetup) {
            SetupFlow { completedSetup = true; model.showSetup = false }
        }
    }
}

private struct DictationHome: View {
    @EnvironmentObject private var model: DictationModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("BrandIcon").resizable().frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("声で、いつもの入力欄へ。").font(.title2.bold())
                        Text("日本語・端末内で音声認識").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !model.modelReady {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("はじめに日本語モデルを準備").font(.headline)
                            Text("初回のモデル取得に通信します。音声や文章をクラウドAIへ送る処理はありません。").font(.subheadline)
                            Button(model.downloading ? "ダウンロード中…" : "日本語モデルを準備") { Task { await model.installModel() } }
                                .buttonStyle(.borderedProminent).disabled(model.downloading)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(spacing: 14) {
                    Text(model.state.phase.label).font(.headline)
                    Button {
                        switch model.state.phase {
                        case .inactive, .failed: Task { await model.activate() }
                        case .ready: model.startLocal()
                        case .listening: model.finish()
                        case .processing: Task { await model.cancel() }
                        case .preparing: break
                        }
                    } label: {
                        Label(buttonTitle, systemImage: model.state.phase == .listening ? "stop.fill" : "mic.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 20)
                    }.buttonStyle(.borderedProminent).disabled(!model.modelReady || model.state.phase == .preparing)
                    .accessibilityIdentifier("dictation-main-button")
                    if model.state.sessionID != nil {
                        Button("マイクを終了") { model.disconnect() }.foregroundStyle(.secondary)
                    }
                    if let end = model.state.expiresAt { Text("マイク待機は \(end, style: .time) まで").font(.caption).foregroundStyle(.secondary) }
                }
                if !model.state.preview.isEmpty {
                    GroupBox("聞き取り中") { Text(model.state.preview).frame(maxWidth: .infinity, alignment: .leading) }
                } else if let result = model.state.history.first {
                    GroupBox("直近の入力") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(result.text).textSelection(.enabled)
                            Button("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = result.text }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("ほかのアプリで使う").font(.headline)
                    Text("① 本体でマイクを有効にします。\n② LINEやメールの入力欄に戻ります。\n③ 🌐で「こえのたね」に切り替え、マイクをタップ。\n④ 話し終えてもう一度タップすると、文章が入ります。")
                        .font(.subheadline).lineSpacing(6)
                    Text("待機中もiPhoneのマイク使用表示が出ます。「マイクを終了」か、最後の入力から待機時間が経つと止まります。話している途中では終了しません。待機中の音声は認識・保存しません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("最初の設定・入力練習を開く") { model.showSetup = true }
                }
                if !model.state.message.isEmpty { Text(model.state.message).font(.footnote).foregroundStyle(.secondary) }
            }.padding(22)
        }.navigationTitle("こえのたね")
    }
    private var buttonTitle: String {
        switch model.state.phase {
        case .inactive, .failed: "マイクを有効にする"
        case .ready: "この画面で音声入力"
        case .listening: "話し終えたらタップ"
        case .processing: "確定中…タップでキャンセル"
        case .preparing: "準備中…"
        }
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var model: DictationModel
    var body: some View {
        List {
            Section {
                Toggle("直近5件をこのiPhoneに保存", isOn: Binding(
                    get: { model.state.settings.saveHistory }, set: { value in model.updateSettings { $0.saveHistory = value } }))
            } footer: { Text("コピーし直せるように保存します。オフにしても既存の履歴は残ります。") }
            ForEach(model.state.history) { entry in
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.text).textSelection(.enabled)
                    HStack {
                        Text(entry.date, style: .time).foregroundStyle(.secondary)
                        Spacer()
                        Button("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.text }
                    }.font(.caption)
                    Text("認識確定 \(Int(entry.metrics.finalizationMilliseconds)) ms  ·  整形 \(Int(entry.metrics.refinementMilliseconds)) ms")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let value = entry.metrics.insertionMilliseconds {
                        Text("話し終えた操作から入力操作まで \(Int(value)) ms").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            if !model.state.history.isEmpty {
                Button("このiPhoneの入力履歴を削除", role: .destructive) { model.clearHistory() }
            }
        }.navigationTitle("入力履歴")
    }
}

private struct BenchmarkView: View {
    @EnvironmentObject private var model: DictationModel
    @State private var selected = BenchmarkPhrase.corpus[0].id
    var body: some View {
        List {
            Section {
                Picker("確認する文章", selection: $selected) {
                    ForEach(BenchmarkPhrase.corpus) { Text($0.label).tag($0.id) }
                }
                Text(phrase.text).font(.title3).textSelection(.enabled)
                if !model.state.isLive(at: Date()) {
                    Button("マイクを有効にする") { Task { await model.activate() } }.disabled(!model.modelReady)
                } else {
                    Button(model.state.phase == .listening ? "話し終えたらタップ" : "この文章を読む") {
                        if model.state.phase == .listening { model.finish() } else { model.startLocal(benchmark: phrase) }
                    }.disabled(![.ready, .listening].contains(model.state.phase))
                }
            } header: { Text("同じ文章で、精度と速さを確認") } footer: {
                Text("認識処理は通常の音声入力と共通です。この画面では認識精度と確定までの時間を測ります。他アプリへの入力時間は、キーボードで入力した履歴に表示します。")
            }
            ForEach(model.state.benchmarks) { result in
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.reference).font(.caption).foregroundStyle(.secondary)
                    Text(result.finalText).textSelection(.enabled)
                    Text(String(format: "文字誤り率  認識 %.1f%% → 整形後 %.1f%%", result.rawCharacterErrorRate * 100, result.finalCharacterErrorRate * 100))
                        .font(.caption)
                    Text("認識確定 \(Int(result.metrics.finalizationMilliseconds)) ms・整形 \(Int(result.metrics.refinementMilliseconds)) ms")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.state.benchmarks.isEmpty {
                Section {
                    ShareLink(item: model.exportBenchmarkReport()) { Label("計測結果を共有", systemImage: "square.and.arrow.up") }
                    Button("計測結果を削除", role: .destructive) { model.clearBenchmarks() }
                } footer: { Text("共有するデータには、実際に話した認識結果が含まれます。共有する前に内容を確認してください。") }
            }
        }.navigationTitle("精度・速度")
    }
    private var phrase: BenchmarkPhrase { BenchmarkPhrase.corpus.first { $0.id == selected }! }
}

struct VoiceSeedSettings: View {
    @EnvironmentObject private var model: DictationModel
    var body: some View {
        Form {
            Section {
                Toggle("フィラー除去（ルール）", isOn: binding(\.removeFillers))
                Toggle("文章整形（Apple Intelligence）", isOn: binding(\.refineWithAppleIntelligence))
                    .disabled(!OnDeviceRefiner.available)
                Text(OnDeviceRefiner.status).font(.caption).foregroundStyle(.secondary)
                Picker("マイクの待機時間", selection: Binding(get: { model.state.settings.sessionMinutes }, set: { value in model.updateSettings { $0.sessionMinutes = value } })) {
                    Text("1分").tag(1); Text("5分").tag(5); Text("10分").tag(10)
                }
                if model.state.sessionID != nil { Button("マイクを終了") { model.disconnect() } }
            } header: { Text("音声入力") } footer: { Text("音声認識・フィラー除去・任意の文章整形は、このiPhone内で行います。文章整形を使うと、その処理時間が加わります。") }
            Section("最初の設定") {
                Button("設定と入力練習をやり直す") { model.showSetup = true }
                Button("iPhoneの設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Text("キーボードのフルアクセスは、本体アプリとの共有に使います。入力した文字や音声をクラウドAIへ送るための設定ではありません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("開発者・サポート") {
                Link("株式会社ブランズバンクシステムズ", destination: URL(string: "https://brands-bank.com/")!)
                Link("服部雅樹のX", destination: URL(string: "https://x.com/masakihattori")!)
                Link("AIの導入サポート及びビジネス相談はこちら", destination: URL(string: "https://line.me/R/ti/p/%40833ciyeu")!)
                Link("Github ※こえのたねはオープンソース（MIT）です", destination: URL(string: "https://github.com/brandsmasaki-lang/voice-seed")!)
                Link("AIのたね、AIのまどはこちら", destination: URL(string: "https://ai-no-tane.com/lp/003-2/")!)
                Link("AIのたねシリーズ｜質問と活用相談", destination: URL(string: "https://line.me/ti/g2/ZN76A-QiLrufOzTLufF9DqKkteDhChw8j7uGrw?utm_source=invitation&utm_medium=link_copy&utm_campaign=default")!)
            }
            Section {
                NavigationLink("データの扱い・権利表示") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("音声認識はApple SpeechAnalyzer、任意の整形はSystemLanguageModelを使い、クラウド認識へ切り替えません。マイク音声はファイル保存しません。")
                            Text("履歴5件、辞書、設定、計測結果はアプリとキーボードの共有領域に保存し、バックアップ対象から除外します。入力先の本文や、手入力した文字列を開発者へ送信する処理はありません。")
                            Text("かな漢字変換はAzooKeyKanaKanjiConverterの辞書変換を端末内で実行します。変換学習の保存とニューラル変換は使用しません。")
                            Text("コピーした文章はiPhoneのクリップボードに入ります。共有と外部リンクは、利用者が操作した場合だけ開きます。")
                            Text(licenses)
                                .font(.caption)
                        }.padding()
                    }.navigationTitle("データ・権利表示")
                }
                LabeledContent("バージョン", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"))
            }
        }.navigationTitle("設定")
    }
    private func binding(_ key: WritableKeyPath<LocalSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.state.settings[keyPath: key] }, set: { value in model.updateSettings { $0[keyPath: key] = value } })
    }
    private var licenses: String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "権利表示はソースのiOS/THIRD_PARTY_NOTICES.txtをご確認ください。"
        }
        return text
    }
}

private struct KeyboardReturnView: View {
    @EnvironmentObject private var model: DictationModel
    @State private var swipe = false
    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 10) {
                Image("BrandIcon").resizable().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7))
                Text("こえのたね").font(.headline)
                Spacer()
            }
            Spacer()
            if model.state.phase == .ready || model.state.phase == .listening {
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.3)).frame(height: 30)
                            }
                        }
                    }
                    RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.3)).frame(width: 130, height: 30)
                    ZStack {
                        Capsule().fill(Color.primary).frame(width: 110, height: 5)
                        Circle().fill(Color.primary.opacity(0.25)).frame(width: 48, height: 48)
                            .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 2))
                            .offset(x: swipe ? 85 : -85, y: 5)
                    }.frame(height: 54)
                }.padding(26).background(.quaternary, in: RoundedRectangle(cornerRadius: 28))
                    .accessibilityHidden(true)
                    .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { swipe = true } }
                Text("スワイプしてアプリに戻る").font(.title.bold()).multilineTextAlignment(.center)
                Text("お手数ですが、画面下のバーを横にスワイプして、\n使っていたアプリへ戻ってください。")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text("戻ったら、そのまま話せます。")
                    .font(.headline).multilineTextAlignment(.center)
            } else if !model.errorMessage.isEmpty {
                Text(model.errorMessage).multilineTextAlignment(.center)
            } else {
                ProgressView().controlSize(.large)
                Text("マイクに接続しています…").font(.title2.bold())
            }
            Spacer()
            Button("音声入力をやめる") { model.disconnect() }.padding(.bottom, 40)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .accessibilityIdentifier("keyboard-return-screen")
    }
}
