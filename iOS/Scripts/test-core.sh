#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
for file in TextPipeline.swift TranscriptBuffer.swift DictionaryImporter.swift; do
  cmp "Core/$file" "../Sources/$file"
done
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
  -parse-as-library Core/*.swift Tests/PortableCoreTests.swift -o .build/PortableCoreTests
.build/PortableCoreTests
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
  -parse-as-library -typecheck Core/*.swift App/AudioStreamPump.swift App/OnDeviceSpeech.swift
swiftc -target arm64-apple-macosx26.0 -module-cache-path "$PWD/.build/module-cache" \
  -parse-as-library Core/*.swift App/AudioStreamPump.swift App/OnDeviceSpeech.swift \
  Tests/AudioStreamPumpTests.swift -o .build/AudioStreamPumpTests
.build/AudioStreamPumpTests
