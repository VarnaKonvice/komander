#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
root="$(cd .. && pwd)"
scratch="$(mktemp -d /tmp/lc-ocr-check.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
core="$root/../LazenskyCommander"
swift build --build-system native --package-path "$core" --scratch-path "$scratch/core"
products="$(swift build --build-system native --package-path "$core" --scratch-path "$scratch/core" --show-bin-path)"
swiftc -I "$products/Modules" \
  "$root/LazenskyCommanderApp/CommanderDocumentIntelligence.swift" \
  "$root/LazenskyCommanderApp/CommanderOnDeviceOCR.swift" \
  "$PWD/Check.swift" "$products"/LazenskyCommanderCore.build/*.swift.o -o "$scratch/check"
"$scratch/check" "$PWD/offline-ocr.json" "$root/LazenskyCommanderApp/commander-ocr-lexicon-v1.json" "$@"
