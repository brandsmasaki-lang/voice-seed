#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/fetch-sparkle.sh
sparkle="$PWD/.build/dependencies/sparkle-2.10.1"
sources=()
for source in Sources/*.swift; do
    [[ "$source" == Sources/Main.swift ]] || sources+=("$source")
done
swiftc -target arm64-apple-macosx26.0 -swift-version 5 -parse-as-library \
    -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle" \
    -module-cache-path "$PWD/.build/module-cache" "${sources[@]}" \
    Tests/AppStartupIntegrationTests.swift -o .build/AppStartupIntegrationTests
.build/AppStartupIntegrationTests
