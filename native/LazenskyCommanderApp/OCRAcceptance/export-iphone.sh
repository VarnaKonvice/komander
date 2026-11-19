#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
  echo "Použití: bash OCRAcceptance/export-iphone.sh /cesta/k/Lazensky-Commander-iPhone-OCR.ipa"
  exit 2
fi
target="$1"
temp="$(mktemp -d /tmp/commander-iphone-ocr.XXXXXX)"
trap 'rm -rf "$temp"' EXIT

xcodebuild -project LazenskyCommanderApp.xcodeproj -scheme LazenskyCommanderApp \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$temp/build" -allowProvisioningUpdates build
app="$temp/build/Build/Products/Release-iphoneos/LazenskyCommanderApp.app"
codesign --verify --deep --strict "$app"
security cms -D -i "$app/embedded.mobileprovision" > "$temp/profile.plist"
python3 - "$temp/profile.plist" <<'PY'
import datetime, plistlib, sys
with open(sys.argv[1], "rb") as f:
    profile = plistlib.load(f)
expires = profile["ExpirationDate"]
if expires <= datetime.datetime.utcnow():
    raise SystemExit("Xcode stále používá prošlý profil. Přihlas se znovu k Apple účtu v Xcode.")
print("Platnost profilu do", expires.isoformat(), "UTC")
PY
mkdir -p "$temp/Payload" "$(dirname "$target")"
ditto "$app" "$temp/Payload/LazenskyCommanderApp.app"
ditto -c -k --keepParent "$temp/Payload" "$temp/signed.ipa"
unzip -tq "$temp/signed.ipa"
cp "$temp/signed.ipa" "$target"
echo "Balíček je uložen v $target. Tento postup nic neinstaluje do telefonu."
