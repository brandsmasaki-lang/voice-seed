# リリース手順

## ソース公開とアプリ配布を分ける

ソースコードはMITライセンスで公開します。正式な署名・公証版には、同じ開発元のDeveloper ID Application署名・Hardened Runtime・Apple公証・公証チケットを付けます。これとは別に、利用者の指示に基づき、初回起動の個別許可手順を同梱してアプリを配布します。

参考：[Apple Developer ID](https://developer.apple.com/developer-id/) / [公証](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## 公開用ソース

1. `Resources/Info.plist` のバージョンとビルド番号、`CHANGELOG.md` を更新します。
2. `Resources/PublicAppInfo.json` の5つのURLを確認します。画面のバージョンはInfo.plistから表示されます。
3. `python3 scripts/check-release.py`、`bash scripts/test.sh`、`bash scripts/build.sh` を実行します。
4. `python3 scripts/export-source.py` で `dist/voice-seed-バージョン-source.zip` を作成します。
5. ZIPの全ファイルと `SOURCE_MANIFEST.json` を確認します。公開内容は `scripts/public_source.py` の明示的な一覧に限ります。個人の設定・辞書・音声・開発用qa・既存のGit履歴は含みません。
6. 初回公開は、このZIPを新しい作業フォルダへ展開して新しいGit履歴を作ります。開発用履歴をそのままpushしないでください。以後の更新は公開リポジトリの既存履歴を維持します。
7. GitHub Actionsの成功を確認します。CIは `macos-26` のarm64ランナーで、純粋ロジックのテスト・ビルド・ソース書き出しを実施します。マイク・Fn・他アプリへの入力は実機検証です。

CIのチェックは公開用ファイル一覧・一部の偶発的な認証情報・ローカルパスを確認しますが、秘密情報の不在を保証するものではありません。公開前の内容確認は必須です。

## 現在のアプリ配布

`bash scripts/build.sh` の後に `bash scripts/package-app.sh` を実行します。続いて `bash scripts/package-dmg.sh` を実行すると、アプリとアプリケーションへの移動先を並べたDMGを作ります。ZIPにはアプリ本体だけを入れ、初回起動・Fn許可の説明はLPとdocs/INSTALL.mdで案内します。`docs/INSTALL.md` はApple公式のアプリ単位の許可手順を説明し、システム全体のセキュリティ無効化は案内しません。通常のGitHub CIでのビルド成功と、別のMacでの実操作検証は分けて記録してください。

公式LPはLINEの案内を入口にし、LINEHarnessの専用キーワード応答からアプリのダウンロードURLを届けます。

## 署名・公証済みアプリ

配布者は有効なApple Developer ProgramのDeveloper ID Application証明書と、`notarytool` / `stapler` を含むXcode環境を用意します。新規契約・購入・証明書発行はこのスクリプトでは行いません。秘密鍵やパスワードをリポジトリへ保存しないでください。公証用認証情報はApple公式手順に従い、ご本人がキーチェーンに登録します。

```sh
export CODESIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export NOTARY_PROFILE='your-existing-keychain-profile'
bash scripts/release.sh
```

このスクリプトは署名用の公開識別名と、設定済みのキーチェーンプロファイル名を使います。パスワードを引数へ書く必要はありません。アプリだけをAppleへ公証提出します。個人の辞書・設定・録音は含めません。

`release.sh` は次を確認し、途中で失敗した場合は一般向けZIPを新規生成しません。

- 公開メタデータとライセンス、テスト、ビルド
- Developer ID Application署名、Hardened Runtime、マイク入力用entitlement
- Apple公証のAccepted結果、チケットの添付と検証
- 署名の検証、Gatekeeperの実行アセスメント

成果物は `dist/voice-seed-バージョン-macos-arm64.zip`、ソースZIP、`SHA256SUMS.txt` です。同じバージョン名の既存成果物は公開前の再実行で更新されます。公開済みリリースのファイルを差し替えるときは、バージョン・ビルドを上げてください。バイナリの署名にはタイムスタンプが入るため、バイト単位の再現可能ビルドを保証するものではありません。

## 追加の実機確認

開発Mac以外の、以前の許可・モデル・辞書がないAppleシリコンMacでも次を確認し、未実施の項目はそのまま記録します。

- ブラウザからZIPを取得し、Finderで展開・アプリケーションへコピー・初回起動できる。
- 現在の配布物では、LPのアプリ個別の許可手順で起動できる。Developer ID署名・公証を付けた配布物では、その状態も確認する。
- マイク許可、モデルダウンロード、入力監視、アクセシビリティの説明と導線が機能する。
- Fn長押しから認識、離してTextEditの空欄への貼り付けまで完了する。通常のキー操作だけでは録音しない。
- 拒否した許可を勝手に再要求し続けない。Fnの準備中の解放・検知中断・スリープで録音が止まる。
- Apple Intelligenceの利用不可／オフでも音声認識とルールのフィラー除去が動く。
- 架空の辞書の取り込み確認・追加・重複の扱いを確認する。実際の個人辞書は公開しない。
- 元と異なる入力欄やパスワード欄へ自動貼り付けしない。Enterなどの送信操作をしない。
- 全5リンクが意図した公開先を開く。バージョン・ライセンス・プライバシー文が正しい。
- 既存版からの更新で辞書と設定が残る。

完了した環境・バージョン・結果を `docs/VALIDATION.md` へ記載します。未実施を成功として扱わないでください。

## GitHub Releases

実際の配布物と検証範囲を明示します。Developer ID署名・公証の有無は、LPの初回起動の案内に正確に記載します。該当コミットへバージョンタグを付け、変更内容・対応OS・既知の制約・チェックサムと3つの成果物を添付します。初回導入は固定名の `voice-seed-macos-arm64.dmg` を案内します。既存利用者のリンクとアプリ内更新を保つため、`voice-seed-macos-arm64.zip` も各リリースへ含めます。

リポジトリではPrivate vulnerability reportingを有効にします。公開Issueへ機密情報を誘導する設定や、認証情報を含むCIログを作らないでください。リポジトリの既定ブランチと保護設定、Issueの受付窓口も確認してください。
