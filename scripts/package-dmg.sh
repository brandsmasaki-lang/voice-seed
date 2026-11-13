#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${VOICE_SEED_BUILD_DIR:-dist}/こえのたね.app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
stage=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/こえのたね.app"
ln -s /Applications "$stage/アプリケーション"
cat > "$stage/はじめに.txt" <<'EOF'
こえのたねのインストール

「こえのたね」を、隣の「アプリケーション」へドラッグしてください。
コピー後はアプリケーションフォルダのこえのたねを開いてください。
直接アプリを開いた場合も「インストールして開く」から配置できます。
管理者の許可が必要な場合はmacOSの認証画面に従ってください。

以降の更新は、アプリ内の「更新する」から行えます。
初回の開き方・日本語モデル・Fnの設定：
https://ai-no-tane.com/lp/koenotane/#setup

無料・オープンソース（MIT）
開発・配布：株式会社ブランズバンクシステムズ
EOF
hdiutil create -ov -fs HFS+ -volname 'こえのたね' -srcfolder "$stage" -format UDZO "dist/voice-seed-${version}-macos-arm64.dmg"
cp "dist/voice-seed-${version}-macos-arm64.dmg" dist/voice-seed-macos-arm64.dmg
(
    cd dist
    shasum -a 256 "voice-seed-${version}-macos-arm64.zip" voice-seed-macos-arm64.zip \
        "voice-seed-${version}-macos-arm64.dmg" voice-seed-macos-arm64.dmg \
        "voice-seed-${version}-source.zip" > "voice-seed-${version}-SHA256SUMS.txt"
)
