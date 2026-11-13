#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -x '/Applications/こえのたね.app/Contents/MacOS/VoiceSeed' ]]; then
    open '/Applications/こえのたね.app'
    exit 0
fi
if [[ ! -x 'dist/こえのたね.app/Contents/MacOS/VoiceSeed' ]]; then bash scripts/build.sh; fi
open 'dist/こえのたね.app'
