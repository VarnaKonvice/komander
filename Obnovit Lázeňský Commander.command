#!/bin/bash

set -u
set -o pipefail
umask 077

APP_NAME="Lázeňský Commander"
SCHEME="LazenskyCommanderApp"
CONFIGURATION="Debug"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"
PROJECT_PATH="$REPO_ROOT/native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj"
MODE="refresh"
TEMP_DIR=""

if [[ $# -gt 1 ]]; then
  printf 'Neplatné parametry. Použij pouze --check.\n'
  exit 2
fi

if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
elif [[ -n "${1:-}" ]]; then
  printf 'Neplatný parametr: %s\n' "$1"
  exit 2
fi

LOG_DIR="$HOME/Library/Logs/LazenskyCommanderRefresh"
if ! /bin/mkdir -p "$LOG_DIR" 2>/dev/null; then
  LOG_DIR="${TMPDIR:-/tmp}/LazenskyCommanderRefreshLogs"
  /bin/mkdir -p "$LOG_DIR" || {
    printf 'Nelze vytvořit bezpečný provozní log.\n'
    exit 1
  }
fi

RUN_ID="$(/bin/date '+%Y%m%d-%H%M%S')-$$"
LOG_FILE="$LOG_DIR/refresh-$RUN_ID.log"
/usr/bin/touch "$LOG_FILE" || {
  printf 'Nelze vytvořit provozní log.\n'
  exit 1
}

log() {
  printf '%s %s\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE"
}

status() {
  printf '%s\n' "$*"
  log "$*"
}

show_dialog() {
  local icon="$1"
  local message="$2"
  if [[ "${LC_REFRESH_NO_DIALOG:-0}" == "1" ]]; then
    return
  fi
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display dialog (item 2 of argv) with title "Lázeňský Commander" buttons {"OK"} default button "OK" with icon ((item 1 of argv) as integer)' \
    -e 'end run' \
    "$icon" "$message" >/dev/null 2>&1 || true
}

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    /bin/rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT INT TERM

fail() {
  local reason="$1"
  status "CHYBA: $reason"
  status "Technický log: $LOG_FILE"
  show_dialog "0" "$reason\n\nTechnický log je uložen v:\n$LOG_FILE"
  exit 1
}

plist_raw() {
  local keypath="$1"
  local file="$2"
  /usr/bin/plutil -extract "$keypath" raw -n "$file" 2>/dev/null || true
}

log "Start; mode=$MODE; repo=$REPO_ROOT"

if [[ "$(/usr/bin/uname -s 2>/dev/null)" != "Darwin" ]]; then
  fail "Tento spouštěč funguje pouze na Macu."
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  fail "Spouštěč není u kompletního projektu Lázeňského Commanderu."
fi

if [[ ! -x /usr/bin/xcode-select || ! -x /usr/bin/xcrun || ! -x /usr/bin/xcodebuild ]]; then
  fail "Na Macu chybí plný Xcode. Nainstaluj nebo dokonči první spuštění Xcode."
fi

DEVELOPER_DIR_PATH="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
case "$DEVELOPER_DIR_PATH" in
  *.app/Contents/Developer) ;;
  *) fail "Mac nepoužívá plný Xcode. Otevři jednou Xcode a dokonči jeho nastavení." ;;
esac

if ! /usr/bin/xcodebuild -version >> "$LOG_FILE" 2>&1; then
  fail "Xcode není připravený k sestavení aplikace."
fi

if ! /usr/bin/xcodebuild -checkFirstLaunchStatus >> "$LOG_FILE" 2>&1; then
  fail "Xcode vyžaduje dokončit první spuštění a instalaci komponent."
fi

DEVICECTL="$(/usr/bin/xcrun --find devicectl 2>/dev/null || true)"
if [[ -z "$DEVICECTL" || ! -x "$DEVICECTL" ]]; then
  fail "Xcode neobsahuje nástroj pro bezpečnou instalaci na iPhone."
fi

TEMP_ROOT="${TMPDIR:-/tmp}"
TEMP_DIR="$(/usr/bin/mktemp -d "${TEMP_ROOT%/}/lazensky-commander-refresh.XXXXXX" 2>/dev/null || true)"
if [[ -z "$TEMP_DIR" || ! -d "$TEMP_DIR" ]]; then
  fail "Nelze vytvořit dočasnou složku pro kontrolu a sestavení."
fi

SCHEMES_JSON="$TEMP_DIR/schemes.json"
if ! /usr/bin/xcodebuild -project "$PROJECT_PATH" -list -json > "$SCHEMES_JSON" 2>> "$LOG_FILE"; then
  fail "Projekt Lázeňského Commanderu nelze načíst v Xcode."
fi

SCHEME_COUNT="$(plist_raw project.schemes "$SCHEMES_JSON")"
SCHEME_FOUND=0
if [[ "$SCHEME_COUNT" =~ ^[0-9]+$ ]]; then
  for ((index = 0; index < SCHEME_COUNT; index++)); do
    if [[ "$(plist_raw "project.schemes.$index" "$SCHEMES_JSON")" == "$SCHEME" ]]; then
      SCHEME_FOUND=1
      break
    fi
  done
fi
if [[ "$SCHEME_FOUND" -ne 1 ]]; then
  fail "Projekt neobsahuje očekávané schéma LazenskyCommanderApp."
fi

if [[ ! -x /usr/bin/git || ! -d "$REPO_ROOT/.git" && ! -f "$REPO_ROOT/.git" ]]; then
  fail "Nelze určit ověřenou verzi zdrojového kódu."
fi

GIT_BRANCH="$(/usr/bin/git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
GIT_COMMIT="$(/usr/bin/git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
if [[ -z "$GIT_COMMIT" ]]; then
  fail "Nelze určit commit, ze kterého se má aplikace nainstalovat."
fi
if [[ -z "$GIT_BRANCH" ]]; then
  GIT_BRANCH="detached HEAD"
fi
status "Instalovaná verze: $GIT_BRANCH @ $GIT_COMMIT"

HTTP_CODE="$(/usr/bin/curl --head --location --silent --show-error --max-time 8 --output /dev/null --write-out '%{http_code}' https://developer.apple.com 2>> "$LOG_FILE" || true)"
if [[ -z "$HTTP_CODE" || "$HTTP_CODE" == "000" ]]; then
  fail "Mac nemá přístup k internetu potřebný pro podpis. Zapni Wi-Fi, hotspot nebo USB internet z iPhonu."
fi

DEVICES_JSON="$TEMP_DIR/devices.json"
if ! "$DEVICECTL" list devices --quiet --timeout 15 --json-output "$DEVICES_JSON" >> "$LOG_FILE" 2>&1; then
  fail "Připoj iPhone kabelem, odemkni ho a potvrď důvěru tomuto Macu."
fi

DEVICE_COUNT="$(plist_raw result.devices "$DEVICES_JSON")"
if [[ ! "$DEVICE_COUNT" =~ ^[0-9]+$ ]]; then
  fail "Xcode nedokázal přečíst seznam připojených zařízení."
fi

IPHONE_SEEN=0
UNPAIRED_SEEN=0
DEV_MODE_DISABLED_SEEN=0
LOCKED_SEEN=0
READY_COUNT=0
DEVICE_IDENTIFIER=""
DEVICE_UDID=""
DEVICE_NAME=""
DEVICE_MODEL=""
DEVICE_OS=""

for ((index = 0; index < DEVICE_COUNT; index++)); do
  prefix="result.devices.$index"
  platform="$(plist_raw "$prefix.hardwareProperties.platform" "$DEVICES_JSON")"
  reality="$(plist_raw "$prefix.hardwareProperties.reality" "$DEVICES_JSON")"
  device_type="$(plist_raw "$prefix.hardwareProperties.deviceType" "$DEVICES_JSON")"
  if [[ "$platform" != "iOS" || "$reality" != "physical" || "$device_type" != "iPhone" ]]; then
    continue
  fi

  IPHONE_SEEN=$((IPHONE_SEEN + 1))
  pairing_state="$(plist_raw "$prefix.connectionProperties.pairingState" "$DEVICES_JSON")"
  if [[ "$pairing_state" != "paired" ]]; then
    UNPAIRED_SEEN=1
    continue
  fi

  developer_mode="$(plist_raw "$prefix.deviceProperties.developerModeStatus" "$DEVICES_JSON")"
  if [[ "$developer_mode" != "enabled" ]]; then
    DEV_MODE_DISABLED_SEEN=1
    continue
  fi

  identifier="$(plist_raw "$prefix.identifier" "$DEVICES_JSON")"
  udid="$(plist_raw "$prefix.hardwareProperties.udid" "$DEVICES_JSON")"
  if [[ -z "$identifier" || -z "$udid" ]]; then
    continue
  fi

  LOCK_JSON="$TEMP_DIR/lock-$index.json"
  if ! "$DEVICECTL" device info lockState --device "$identifier" --quiet --timeout 15 --json-output "$LOCK_JSON" >> "$LOG_FILE" 2>&1; then
    continue
  fi

  passcode_required="$(plist_raw result.passcodeRequired "$LOCK_JSON")"
  unlocked_since_boot="$(plist_raw result.unlockedSinceBoot "$LOCK_JSON")"
  if [[ "$passcode_required" != "false" || "$unlocked_since_boot" != "true" ]]; then
    LOCKED_SEEN=1
    continue
  fi

  READY_COUNT=$((READY_COUNT + 1))
  DEVICE_IDENTIFIER="$identifier"
  DEVICE_UDID="$udid"
  DEVICE_NAME="$(plist_raw "$prefix.deviceProperties.name" "$DEVICES_JSON")"
  DEVICE_MODEL="$(plist_raw "$prefix.hardwareProperties.marketingName" "$DEVICES_JSON")"
  DEVICE_OS="$(plist_raw "$prefix.deviceProperties.osVersionNumber" "$DEVICES_JSON")"
done

if [[ "$READY_COUNT" -eq 0 ]]; then
  if [[ "$IPHONE_SEEN" -eq 0 ]]; then
    fail "Připoj iPhone k MacBooku Air kabelem."
  elif [[ "$UNPAIRED_SEEN" -eq 1 ]]; then
    fail "Na iPhonu potvrď důvěru tomuto Macu."
  elif [[ "$DEV_MODE_DISABLED_SEEN" -eq 1 ]]; then
    fail "Na iPhonu zapni Režim vývojáře a potom ho znovu odemkni."
  elif [[ "$LOCKED_SEEN" -eq 1 ]]; then
    fail "Odemkni iPhone a spusť obnovu znovu."
  else
    fail "Připoj iPhone kabelem, odemkni ho a potvrď důvěru tomuto Macu."
  fi
fi

if [[ "$READY_COUNT" -gt 1 ]]; then
  fail "Je připojeno více vhodných iPhonů. Nech připojený pouze ten, který chceš obnovit."
fi

status "Nalezen iPhone: ${DEVICE_NAME:-iPhone} (${DEVICE_MODEL:-model neuveden}, iOS ${DEVICE_OS:-neuvedeno})"

DESTINATIONS_FILE="$TEMP_DIR/destinations.txt"
if ! /usr/bin/xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showdestinations > "$DESTINATIONS_FILE" 2>> "$LOG_FILE"; then
  fail "Xcode nedokázal ověřit připojený iPhone pro sestavení."
fi
if ! /usr/bin/grep -Fq "platform:iOS" "$DESTINATIONS_FILE" || ! /usr/bin/grep -Fq "id:$DEVICE_UDID" "$DESTINATIONS_FILE"; then
  fail "Připojený iPhone není v Xcode dostupný jako fyzické cílové zařízení."
fi

if [[ "$MODE" == "check" ]]; then
  status "PŘIPRAVENO – Mac a iPhone jsou připravené k obnově."
  status "Kontrolní režim nic nesestavil, nepodepsal ani nenainstaloval."
  status "Technický log: $LOG_FILE"
  show_dialog "1" "PŘIPRAVENO – Mac a iPhone jsou připravené k obnově.\n\nKontrolní režim nic nenainstaloval."
  exit 0
fi

DERIVED_DATA="$TEMP_DIR/DerivedData"
status "Obnovuji podpis a sestavuji aplikaci. Může to několik minut trvat..."
if ! /usr/bin/xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build >> "$LOG_FILE" 2>&1; then
  log "Build result: failure"
  if /usr/bin/grep -Eqi 'internet connection|network connection|could not resolve host|offline|NSURLError' "$LOG_FILE"; then
    fail "Mac nemá přístup k internetu potřebný pro podpis."
  elif /usr/bin/grep -Eqi 'provisioning|no profiles|signing certificate|developer account|no accounts|communication with Apple' "$LOG_FILE"; then
    fail "Apple provisioning se nepodařilo obnovit. Zkontroluj v Xcode jednou přihlášený Apple účet Personal Team."
  else
    fail "Sestavení Commanderu selhalo."
  fi
fi
log "Build result: success"

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/LazenskyCommanderApp.app"
if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/embedded.mobileprovision" ]]; then
  fail "Sestavená aplikace nemá platný vývojářský podpis."
fi
if ! /usr/bin/codesign --verify --deep --strict "$APP_PATH" >> "$LOG_FILE" 2>&1; then
  fail "Kontrola podpisu sestavené aplikace selhala."
fi

INSTALL_JSON="$TEMP_DIR/install.json"
status "Instaluji aktualizovanou aplikaci na iPhone..."
if ! "$DEVICECTL" device install app \
  --device "$DEVICE_IDENTIFIER" \
  "$APP_PATH" \
  --quiet \
  --timeout 180 \
  --json-output "$INSTALL_JSON" >> "$LOG_FILE" 2>&1; then
  log "Install result: failure"
  fail "Instalace na iPhone selhala. Odemkni iPhone, nech ho připojený a spusť obnovu znovu."
fi

if [[ "$(plist_raw info.outcome "$INSTALL_JSON")" != "success" ]]; then
  log "Install result: unconfirmed"
  fail "Xcode nepotvrdil úspěšnou instalaci na iPhone."
fi
log "Install result: success"

status "HOTOVO – $APP_NAME byl obnoven."
status "Zdrojová verze zůstala beze změny: $GIT_BRANCH @ $GIT_COMMIT"
status "Technický log: $LOG_FILE"
show_dialog "1" "HOTOVO – Lázeňský Commander byl obnoven."
