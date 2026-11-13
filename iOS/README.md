# こえのたね iPhone版

日本語の音声入力と、その場で修正できる日本語テンキーを組み合わせたiPhoneアプリの開発コードです。公開中のMac版とは別のターゲットです。PC版と同じアイコン画像を使用します。

## 構成

- iOS 26以降。実機確認の指定対象はiPhone 16 Pro Max / iOS 27.2.1。
- 本体アプリで日本語モデルを取得し、マイクを有効にする。
- 他アプリの入力欄で、こえのたねキーボードのマイクをタップして開始・終了する。
- 音声認識はSpeechAnalyzer / SpeechTranscriber。クラウド認識への代替処理はない。
- Mac版と同一の辞書パーサー・フィラー除去・逐次認識の確定処理を使用。テストでファイルの一致を確認する。
- 任意の整形はApple IntelligenceのSystemLanguageModelのみ。初期状態はオフ。
- キーボード内で、かなフリック・漢字候補・濁点／半濁点／小文字・英字・数字・絵文字・削除・改行を操作できる。
- スペースの長押しと左右移動でカーソルを動かす。
- かな漢字変換はAzooKeyKanaKanjiConverter v0.11.2の辞書変換。ニューラル変換のTraitsは有効にせず、学習保存も無効にする。
- セットアップは、モデル準備 → キーボード追加 → マイク許可 → 使い方 → 短文・メール・メモの入力練習の順。
- 直近5件の履歴、辞書の手動追加・ファイル取り込み、指定文での精度／処理時間の計測。

キーボードからの本体起動は公開App Intents APIで行います。独自のURLスキームを他アプリへ送る処理、非公開セレクター、ホストアプリの探索はありません。最初のマイク有効化後は、元の入力欄へ戻って使用します。

## データとマイク

音声をファイルに保存しません。待機中もマイクを維持するためiPhoneの使用表示が出ますが、音声入力を開始していない間の音声は認識器へ渡さず、保存もしません。待機は1・5・10分から選べ、初期値5分。本体から終了できます。通話・音声経路変更・期限切れでは終了します。

アプリとキーボードはApp Groupの専用領域で連携します。フルアクセスはこの連携に必要です。音声・辞書・履歴・手入力した文字列をネットワークへ送る実装はありません。日本語モデルの取得はAppleのAssetInventoryが行います。外部サポートリンクや結果の共有は利用者の操作で開きます。

共有ファイルは0600・原子的な更新・排他ロックを使用し、バックアップ対象から除外します。履歴は5件、計測結果は50件まで。履歴保存のオフは既存データを削除しません。削除は画面のボタンで行います。手入力のかな漢字変換はメモリ内で処理し、学習履歴を保存しません。

入力先・キーボードの表示回・リクエストを照合し、異なる欄や古い要求へ結果を挿入しません。挿入を先に一度だけ予約してからUIKitへ渡します。予約直後のクラッシュなどで入力されなかった場合は、履歴からコピーできます。自動的な再挿入はしません。

## ビルド

Xcode 26以降とiOS SDKが必要です。Command Line ToolsだけではiPhoneアプリをビルドできません。

1. iOS/VoiceSeed.xcodeprojをXcodeで開く。
2. VoiceSeed-iOSスキームを選ぶ。
3. 実機で動かす場合は、自分の開発チーム・アプリ識別子・App Groupに対応するプロビジョニングを設定する。識別子はConfig/Project.xcconfigで変更でき、App Groupは本体とキーボードで同じ値を使用する。
4. iPhoneを選んでRunする。

証明書・プロビジョニングファイル・個人アカウント情報はリポジトリに含めません。署名なしのSimulatorビルドを、iPhoneにそのまま入る配布物とは扱いません。

~~~sh
python3 iOS/Scripts/generate-project.py --check
bash iOS/Scripts/test-core.sh
swift test --package-path iOS
xcodebuild -project iOS/VoiceSeed.xcodeproj -scheme VoiceSeed-iOS \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath iOS/.build/DerivedData CODE_SIGNING_ALLOWED=NO build
~~~

test-core.shはiOS SDKやXCTestを持たないAppleシリコンMacでも、合成データだけで共有プロトコル・保存・フィラー除去などを検証します。swift testはXCTestを含むXcode環境で実行します。App Groups・マイク・キーボードからの本体起動・背景動作・実際の他アプリへの入力は、実機で確認する別の項目です。

プロジェクトはScripts/generate-project.pyで決定的に生成します。新しいソースを追加した場合は再生成します。

## 精度と時間の測り方

「精度・速度」で、Macと比較できる同じ指定文を読みます。認識結果と整形後の文字誤り率（空白を除いたUnicode文字単位の編集距離）、終了操作から認識確定までの時間、任意の整形時間を別々に表示します。計測結果は明示操作で共有できます。

キーボード入力の履歴には、終了操作からUIKitへの挿入操作までの時間も記録します。実際に入力欄へ文字が入ったことは実機で確認します。数値だけから、認識精度や操作感がMac版や他製品と同等であるとは扱いません。

## 現在の検証状態

共有処理36項目、XCTest、かな漢字変換辞書の検証と、アプリ本体・埋め込みキーボードのiOS Simulatorビルドが成功しています。iPhone 16 Pro Maxの独立したシミュレータで初期画面の起動も確認しました。[検証実行](https://github.com/brandsmasaki-lang/voice-seed/actions/runs/43526141966)。iPhone実機の精度・速度・キーボード連携は未確認です。App Storeで配布済みのiPhone版ではありません。

コードはルートのMITライセンスに従います。変換エンジン・辞書・依存ライブラリはTHIRD_PARTY_NOTICES.txtに権利表示を含めます。
