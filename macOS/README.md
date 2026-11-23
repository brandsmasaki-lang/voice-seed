# Mac App Store用ターゲット

従来の直接配布版と同じSourcesを使用し、`APP_STORE`条件でストア用の処理を選びます。直接配布版のビルドは引き続き`bash scripts/build.sh`です。

ストア用はSandbox、マイク、利用者が選択したファイルへの読み書きだけをentitlementsに指定します。Sparkle、自己インストール処理、他アプリのAXUIElement取得、Accessibilityの信頼API、tccutilによる権限リセットはストア版に含めません。外部の公開設定の定期取得も停止します。

入力監視を許可したMacでは、Fnを押した瞬間と離した瞬間をキーイベントで検知します。自動貼り付けだけを許可したMacでは、修飾キーの状態からFn長押しを検知します。録音開始時と同じアプリが前面にあり、OSの保護入力状態が無効なときだけCommand-Vを送り、結果はアプリ内に保持します。Sandboxでは他アプリの入力欄を検査できないため、同じ入力欄への配信成功や全てのパスワード欄の判別は保証しません。実機でのFn・貼り付け確認とAppleの審査は別に必要です。未確認の候補を審査承認済みとは扱いません。

法人チームはBRANS BANK SYSTEMS, K.K.（NRX77TLPW7）。App Store Connectの既存アプリにmacOSプラットフォームを追加し、Appleの複数プラットフォーム配布に従ってiOS版と同じBundle ID `jp.ainotane.koenotane.ios`を使用します。末尾の`.ios`は内部識別子であり、Mac版の表示名を意味しません。直接配布版の`jp.ainotane.voice-seed`とは保存領域が異なります。

```sh
python3 macOS/Scripts/generate-project.py --check
xcodebuild -project macOS/VoiceSeedStore.xcodeproj -scheme VoiceSeed-Mac-AppStore \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath macOS/.build/DerivedData \
  -archivePath macOS/.build/VoiceSeed.xcarchive CODE_SIGNING_ALLOWED=NO archive
codesign --force --sign - --entitlements macOS/Config/App.entitlements \
  macOS/.build/VoiceSeed.xcarchive/Products/Applications/こえのたね.app
python3 macOS/Scripts/check-build.py macOS/.build/VoiceSeed.xcarchive/Products/Applications/こえのたね.app
```

この段階のアドホック署名は配布署名ではありません。App Store Connect向けのautomatic exportを法人チームで実行し、Appleの配布証明書・Mac用プロファイルで再署名したパッケージを作成します。証明書や認証情報をリポジトリへ保存しません。

2026-11-17の確認：0.7.5（18）の法人署名パッケージ生成とアップロードに成功。Sandbox有効の候補で日本語モデルの準備と架空の合成音声ファイルからの認識を確認。これはマイク・Fn・貼り付けの実機受入完了ではありません。

ストア用の許可案内を調整した0.7.5（19）もアップロード済みです。Fn・貼り付けの実機受入は引き続き未確認です。

提出候補は0.7.5（20）へ更新しました。入力監視とイベント送信を別々に案内し、ストア版で行わない権限記録の削除を説明する誤った文言を修正しています。Mac Studioでマイク許可、入力監視・イベント送信許可、再起動後の準備完了表示、UIからの架空音声ファイルの認識を確認しました。実際のFn長押しから別アプリへの貼り付けまでの一連の受入は未確認です。

0.7.7（21）は、直接配布版0.7.7と同じ録音処理を使用します。Fnを押すとマイクを先に動かし、キーを離した直後まで語尾の音を受け取ります。録音中は対応する出力先をミュートし、録音終了時に音を戻します。審査承認後の公開は手動です。
