import SwiftUI
import UIKit

struct SetupFlow: View {
    @EnvironmentObject private var model: DictationModel
    @State private var step = 0
    @State private var practiceText = ""
    @FocusState private var fieldFocused: Bool
    let complete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { fieldFocused = false; step = max(0, step - 1) } label: { Image(systemName: "chevron.left").font(.title3) }
                    .disabled(step == 0).accessibilityLabel("前の手順")
                HStack(spacing: 5) {
                    ForEach(0..<3) { index in
                        GeometryReader { geometry in
                            Capsule().fill(Color.secondary.opacity(0.25))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.primary)
                                        .frame(width: geometry.size.width * min(1, max(0, (Double(step) + 1) / 2.67 - Double(index))))
                                }
                        }.frame(height: 3)
                    }
                }
                Button("スキップ") { fieldFocused = false; complete() }.font(.subheadline.weight(.semibold))
            }.padding(.horizontal, 22).padding(.vertical, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                    if !model.errorMessage.isEmpty {
                        Text(model.errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom) {
            Button { Task { await advance() } } label: {
                if model.downloading || model.state.phase == .preparing {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(18)
                        .contentShape(Rectangle())
                } else {
                    Text(buttonTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 18)
                        .contentShape(Rectangle())
                }
            }.buttonStyle(.plain).foregroundStyle(Color(uiColor: .systemBackground)).background(Color.primary, in: RoundedRectangle(cornerRadius: 15))
                .disabled(model.downloading || model.state.phase == .preparing || ((4...6).contains(step) && practiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .padding(.horizontal, 22).padding(.bottom, 12).background(.background)
                .accessibilityIdentifier("setup-continue")
        }
        .onChange(of: step) { _, _ in practiceText = ""; fieldFocused = (4...6).contains(step) }
        .accessibilityIdentifier("setup-flow")
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            VStack(spacing: 24) {
                Image("BrandIcon").resizable().frame(width: 112, height: 112).clipShape(RoundedRectangle(cornerRadius: 27)).padding(.top, 40)
                Text("話したことばを、\nいつもの入力欄へ。").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("オトナの音声入力 こえのたね").font(.headline)
                Text("音声入力も、テンキーでの修正も。\nこの端末で、日本語を文字にします。")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Label(model.modelReady ? "日本語モデル：準備完了" : "最初に日本語モデルを準備します", systemImage: model.modelReady ? "checkmark.circle.fill" : "arrow.down.circle")
                Text("初回のモデル取得にだけ通信します。音声や文章をクラウドAIへ送りません。").font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        case 1:
            title("キーボードを追加", subtitle: "端末の設定で、次の2つをオンにします。")
            GroupBox {
                VStack(alignment: .leading, spacing: 18) {
                    Label("オトナの音声入力 こえのたね", systemImage: "keyboard")
                    Divider()
                    Label("フルアクセスを許可", systemImage: "checkmark.shield")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Text("設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 → オトナの音声入力 こえのたね")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("端末の設定を開く", systemImage: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }.buttonStyle(.bordered)
            Text("フルアクセスは、本体とキーボードが端末内で連携するために使います。入力した文章や音声を開発者へ送信する機能はありません。")
                .font(.footnote).foregroundStyle(.secondary)
        case 2:
            VStack(spacing: 28) {
                Image(systemName: "mic.badge.plus").font(.system(size: 58)).padding(38)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                Text("音声入力とマイク").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("音声入力では、話した内容をこの端末で文字にするためにマイクを使います。")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text("待機中は端末のマイク使用表示が出ます。\n設定した時間で終了し、本体からいつでも止められます。")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.top, 70)
        case 3:
            title("キーボードを使いこなす", subtitle: "声で入力し、同じキーボードで修正できます。")
            if UIDevice.current.userInterfaceIdiom == .pad {
                guide("マイクをタップして話す", "話し終えたら「録音を終了」を押し、「修正する」か「貼り付ける」を選びます。", label: "🎙 タップして話す")
                guide("確定を待つ間に貼り付けを予約", "「確定後に貼り付け」を押すと、文が整ったときに今の入力欄に入ります。そのまま待つと、貼り付ける前に文を見直せます。", label: "確定後に貼り付け")
                guide("直す範囲を矢印で調整", "語をタップすると黄色になります。←で末尾を1文字短く、→で長くできます。「先頭」「全体」に切り替えると、矢印で動かす部分が変わります。", label: "←　→")
            } else {
                guide("もう一度タップして貼り付ける", "話し終わったら「終了して貼り付け」をタップ。文章が整うと、話し始めた入力欄に入ります。", label: "終了して貼り付け")
                guide("前のかなに戻す", "「あ」を押しすぎて「う」になったら、丸い矢印をタップすると「い」に戻ります。", label: "前のかなに戻す", symbol: "arrow.counterclockwise")
            }
            guide("スペース長押しでカーソル移動", "押したまま左右に動かして、修正したい場所へ移動します。", label: "←　空白を長押し　→")
        case 4:
            title("何か話して、文を貼り付けましょう。", subtitle: "🌐で「オトナの音声入力 こえのたね」を選び、下の入力欄で試します。")
            prompt("みなさん、こんにちは。")
            practice(title: "入力してみよう")
        case 5:
            title("メールを声で書いてみよう", subtitle: "宛名や日時も、そのまま話せます。")
            prompt("佐藤さん、金曜日の16時に打ち合わせできますか。ご都合を教えてください。")
            practice(title: "メール")
        case 6:
            title("思いついたことを、すぐ文字に。", subtitle: UIDevice.current.userInterfaceIdiom == .pad ? "貼り付ける前に直すときは「修正する」を押し、プレビューで語をタップします。" : "「空白」を長押しして指を左右に動かすと、貼り付けた文章の直したい位置にカーソルを移せます。")
            prompt("今週末は、まず郵便局で荷物を受け取る。次に、19時に友人へ電話する。")
            practice(title: "メモ")
        default:
            VStack(spacing: 26) {
                Image("BrandIcon").resizable().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 24))
                Text("準備できました。").font(.largeTitle.bold())
                Text("LINEやメールでも、このキーボードを使えます。").multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text("マイクの待機が終了したら、キーボードの「マイクを準備」から再開できます。").font(.footnote).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.top, 70)
        }
    }
    private var buttonTitle: String {
        if step == 0 && !model.modelReady { return "日本語モデルを準備" }
        return step >= 7 ? "入力をはじめる" : "続ける"
    }
    private func advance() async {
        if step == 0 && !model.modelReady {
            await model.installModel()
            if !model.modelReady { return }
        }
        if step == 2 && model.state.sessionID == nil {
            await model.activate()
            if model.state.phase != .ready { return }
        }
        if step >= 7 { complete() } else { fieldFocused = false; step += 1 }
    }
    private func title(_ text: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(.system(size: 27, weight: .bold))
            Text(subtitle).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }
    private func prompt(_ text: String) -> some View {
        Label(text, systemImage: "person.wave.2").font(.subheadline)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    private func practice(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: title == "メール" ? "envelope" : "note.text").font(.headline)
            Divider()
            TextEditor(text: $practiceText).font(.system(size: 20)).scrollContentBackground(.hidden)
                .frame(minHeight: 170).focused($fieldFocused).accessibilityIdentifier("setup-practice")
        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private func guide(_ title: String, _ text: String, label: String, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).accessibilityLabel(label)
                } else {
                    Text(label).font(.system(size: 14, weight: .semibold))
                }
            }
                .padding(.vertical, 16).frame(maxWidth: .infinity)
                .background(Color(uiColor: .systemGray4), in: RoundedRectangle(cornerRadius: 12))
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
