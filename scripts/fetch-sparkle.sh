#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version='2.10.1'
digest='1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27'
destination=".build/dependencies/sparkle-$version"
archive=".build/dependencies/Sparkle-$version.tar.xz"
mkdir -p .build/dependencies
if [[ ! -f "$archive" ]]; then
    curl --location --fail --silent --show-error --max-time 120 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
fi
printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c -
if [[ ! -d "$destination/Sparkle.framework" ]]; then
    mkdir -p "$destination"
    tar -xJf "$archive" -C "$destination"
fi
codesign --verify --deep --strict "$destination/Sparkle.framework"
