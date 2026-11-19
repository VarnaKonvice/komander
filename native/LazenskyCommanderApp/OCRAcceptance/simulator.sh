#!/bin/bash
# Run on a dedicated iPhone simulator. Reads only synthetic fixtures.
set -euo pipefail
cd "$(dirname "$0")"
sim="$1"
app="$2"
fixtures="$3"
out="$4"
bundle=com.varnakonvice.lazenskycommander
mkdir -p "$out"
xcrun simctl install "$sim" "$app"
container="$(xcrun simctl get_app_container "$sim" "$bundle" data)"
mkdir -p "$container/Documents/ocr-qa"
cp "$fixtures"/*.png "$container/Documents/ocr-qa/"
swiftc -parse-as-library ScreenshotText.swift -o "$out/read-screenshot"

inspect() {
  local name="$1" paths="$2" expected="$3"
  xcrun simctl terminate "$sim" "$bundle" 2>/dev/null || true
  SIMCTL_CHILD_LC_OCR_QA_PHOTOS="$paths" xcrun simctl launch "$sim" "$bundle" \
    -lazensky.commander.terms.acceptedVersion 1
  for attempt in {1..12}; do
    xcrun simctl io "$sim" screenshot "$out/$name.png" >/dev/null 2>&1
    "$out/read-screenshot" "$out/$name.png" > "$out/$name.txt"
    if grep -q "$expected" "$out/$name.txt"; then
      cat "$out/$name.txt"
      return 0
    fi
    sleep 1
  done
  cat "$out/$name.txt"
  return 1
}

base="$container/Documents/ocr-qa"
inspect rovny "$base/01-rovny.png" '3 položky.*0 ke kontrole'
grep -q 'Procedura ABC-17' "$out/rovny.txt"
inspect casti "$base/09-cast-a.png|$base/10-cast-b.png" '3 položky.*0 ke kontrole'
inspect nejasny "$base/11-nejasny-cas.png" '1 položka.*1 ke kontrole'
! grep -q 'Použít rozpis' "$out/nejasny.txt"
echo 'PASS iPhone review, overlapping sheets, ambiguous time'
