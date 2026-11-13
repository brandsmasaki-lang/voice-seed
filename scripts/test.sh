#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/TextPipeline.swift Tests/TextPipelineTests.swift -o .build/TextPipelineTests
.build/TextPipelineTests
swiftc -O -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/TextPipeline.swift Tests/FillerCleanupTests.swift -o .build/FillerCleanupTests
.build/FillerCleanupTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/FnKeyState.swift Tests/FnKeyStateTests.swift -o .build/FnKeyStateTests
.build/FnKeyStateTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/TextPipeline.swift Sources/DictionaryImporter.swift Tests/DictionaryImporterTests.swift -o .build/DictionaryImporterTests
.build/DictionaryImporterTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/TranscriptBuffer.swift Tests/TranscriptBufferTests.swift -o .build/TranscriptBufferTests
.build/TranscriptBufferTests
plutil -lint Resources/Info.plist
python3 Tests/PublicSourceTests.py
