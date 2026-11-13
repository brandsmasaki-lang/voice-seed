# 運営側で案内と更新を管理する

## 会社名・文言・リンクを変える

公開元はAIのたねサイトの `landing-pages/public/lp/koenotane/app-info.json` です。こえのたねのアプリ本体をビルドし直す必要はありません。

- `intro`：アプリについての説明文。
- `supportTitle`：リンク一覧の見出し。
- `links`：表示名・補足・アイコン・HTTPSのURL。IDは重複させません。
- `revision`：運営側で変更を識別する文字列。
- `latest`：実際に公開したアプリのバージョン・ビルド・変更内容。案内文の変更だけでは増やしません。

公開LPリポジトリの設定ファイルを変更し、そのリポジトリの通常の確認・Git保存・既存LPへの配備を行います。既存ページやASSETSのマニフェストを置き換えず、確認した公開元を基点に配備してください。

アプリは起動時と6時間ごとに取得し、「アプリについて → 案内を再読込」でも取得できます。取得に失敗した場合や形式が壊れていた場合は、直前の有効な内容を残します。取得できない初回は、アプリに同梱した内容を使います。

この設定で録音・キー監視・貼り付け・macOSの権限は変更できません。アプリが表示するインストール済みバージョンも、公開設定からは変更しません。

## アプリ本体を更新する

1. Info.plistのバージョンとビルド番号を上げ、変更内容と検証結果を記録します。
2. `bash scripts/test.sh`、`bash scripts/build.sh`、`bash scripts/package-app.sh` を実行します。
3. `python3 scripts/generate-appcast.py` で更新ZIPのEdDSA署名を検証し、`dist/appcast.xml` を作ります。秘密鍵は専用のキーチェーン項目に保持し、Gitへ保存しません。
4. ソース・アプリZIP・SHA-256をGitHub Releasesへ公開し、実際にダウンロードできることとチェックサムを確認します。
5. 公開LP側へappcast.xmlを反映し、app-info.jsonのlatestを公開済みの版と一致させます。配備後、アプリの更新通知・更新ボタン・インストール・再起動を確認します。

EdDSAは更新ファイルを認証する署名です。AppleのDeveloper ID署名とは別のものです。法人名のDeveloper ID署名には、法人としてのApple Developer Program登録と証明書が必要です。

起動済みの開発版と別の候補を作るときは `VOICE_SEED_BUILD_DIR=dist/候補名 bash scripts/build.sh` を使います。許可登録の参照先になっているアプリを、文言変更や試験のたびに置き換えないでください。
