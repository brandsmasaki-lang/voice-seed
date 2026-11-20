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
    -parse-as-library Sources/MicrophoneTail.swift Tests/MicrophoneTailTests.swift -o .build/MicrophoneTailTests
.build/MicrophoneTailTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/FnStartPolicy.swift Tests/FnStartPolicyTests.swift -o .build/FnStartPolicyTests
.build/FnStartPolicyTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/TextPipeline.swift Sources/DictionaryImporter.swift Tests/DictionaryImporterTests.swift -o .build/DictionaryImporterTests
.build/DictionaryImporterTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/TranscriptBuffer.swift Tests/TranscriptBufferTests.swift -o .build/TranscriptBufferTests
.build/TranscriptBufferTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/ModifierShortcutState.swift Tests/ModifierShortcutStateTests.swift -o .build/ModifierShortcutStateTests
.build/ModifierShortcutStateTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/JapaneseSentenceEnding.swift Tests/JapaneseSentenceEndingTests.swift -o .build/JapaneseSentenceEndingTests
.build/JapaneseSentenceEndingTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/DeveloperTermCorrection.swift Tests/DeveloperTermCorrectionTests.swift -o .build/DeveloperTermCorrectionTests
.build/DeveloperTermCorrectionTests
plutil -lint Resources/Info.plist
python3 Tests/PublicSourceTests.py
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/PublicAppInfo.swift Tests/PublicAppInfoTests.swift -o .build/PublicAppInfoTests
.build/PublicAppInfoTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/LocalActivity.swift Sources/RecordingPresentation.swift Tests/LocalActivityTests.swift -o .build/LocalActivityTests
.build/LocalActivityTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
    -parse-as-library Sources/ApplicationInstallService.swift Tests/ApplicationInstallTests.swift -o .build/ApplicationInstallTests
.build/ApplicationInstallTests
bash scripts/test-startup.sh
