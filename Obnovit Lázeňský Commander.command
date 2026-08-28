#!/bin/bash

set -u
set -o pipefail
umask 077

APP_NAME="Lázeňský Commander"
SCHEME="LazenskyCommanderApp"
CONFIGURATION="Debug"
TARGET_BRANCH="lc/stability-pass-v1"
EXPECTED_REPOSITORY="VarnaKonvice/komander"
LAUNCHER_FILENAME="Obnovit Lázeňský Commander.command"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"
PROJECT_PATH="$REPO_ROOT/native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj"
MODE="refresh"
TEMP_DIR=""
RELAUNCH_COUNT="${LC_REFRESH_RELAUNCH_COUNT:-0}"
START_LAUNCHER_HASH="$(/usr/bin/shasum -a 256 "$0" 2>/dev/null | /usr/bin/awk '{print $1}')"

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

if [[ ! -x /usr/bin/git || ! -d "$REPO_ROOT/.git" && ! -f "$REPO_ROOT/.git" ]]; then
  fail "Spouštěč není v platném Git repozitáři Lázeňského Commanderu."
fi

ORIGIN_URL="$(/usr/bin/git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
case "$ORIGIN_URL" in
  "https://github.com/$EXPECTED_REPOSITORY"|"https://github.com/$EXPECTED_REPOSITORY.git"|"git@github.com:$EXPECTED_REPOSITORY.git"|"ssh://git@github.com/$EXPECTED_REPOSITORY.git") ;;
  *) fail "Git origin neukazuje na ověřený repozitář VarnaKonvice/komander. Nic nebylo změněno ani nainstalováno." ;;
esac

INITIAL_DIRTY="$(/usr/bin/git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all 2>> "$LOG_FILE" || true)"
if [[ -n "$INITIAL_DIRTY" ]]; then
  fail "Pracovní složka obsahuje neuložené změny. Obnova je z bezpečnostních důvodů nepřepíše."
fi

status "Kontroluji aktuální ověřenou verzi $TARGET_BRANCH na GitHubu..."
if ! /usr/bin/git -C "$REPO_ROOT" fetch --quiet --no-tags origin \
  "+refs/heads/$TARGET_BRANCH:refs/remotes/origin/$TARGET_BRANCH" >> "$LOG_FILE" 2>&1; then
  fail "Aktuální verzi se nepodařilo stáhnout z GitHubu. Zkontroluj internet a spusť obnovu znovu."
fi

REMOTE_COMMIT="$(/usr/bin/git -C "$REPO_ROOT" rev-parse --verify "refs/remotes/origin/$TARGET_BRANCH^{commit}" 2>/dev/null || true)"
if [[ -z "$REMOTE_COMMIT" ]]; then
  fail "Na GitHubu chybí cílová větev $TARGET_BRANCH. Nic nebylo nainstalováno."
fi

LOCAL_COMMIT="$(/usr/bin/git -C "$REPO_ROOT" rev-parse --verify "refs/heads/$TARGET_BRANCH^{commit}" 2>/dev/null || true)"
if [[ -n "$LOCAL_COMMIT" && "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]]; then
  if ! /usr/bin/git -C "$REPO_ROOT" merge-base --is-ancestor "$LOCAL_COMMIT" "$REMOTE_COMMIT"; then
    fail "Lokální cílová větev obsahuje vlastní nebo odlišné commity. Obnova je nepřepíše; repozitář musí zkontrolovat vývojář."
  fi
fi

CURRENT_BRANCH="$(/usr/bin/git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
if [[ -z "$LOCAL_COMMIT" ]]; then
  if ! /usr/bin/git -C "$REPO_ROOT" switch --quiet --create "$TARGET_BRANCH" --track "origin/$TARGET_BRANCH" >> "$LOG_FILE" 2>&1; then
    fail "Nepodařilo se přepnout na ověřenou cílovou větev. Nic nebylo nainstalováno."
  fi
else
  if [[ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]]; then
    if [[ "$CURRENT_BRANCH" == "$TARGET_BRANCH" ]]; then
      if ! /usr/bin/git -C "$REPO_ROOT" switch --quiet --detach >> "$LOG_FILE" 2>&1; then
        fail "Příprava bezpečné aktualizace cílové větve selhala."
      fi
    fi
    if ! /usr/bin/git -C "$REPO_ROOT" branch --force "$TARGET_BRANCH" "$REMOTE_COMMIT" >> "$LOG_FILE" 2>&1; then
      fail "Cílovou větev nelze bezpečně posunout na aktuální GitHub verzi."
    fi
  fi
  if ! /usr/bin/git -C "$REPO_ROOT" switch --quiet "$TARGET_BRANCH" >> "$LOG_FILE" 2>&1; then
    fail "Nepodařilo se přepnout na ověřenou cílovou větev. Nic nebylo nainstalováno."
  fi
fi

GIT_BRANCH="$(/usr/bin/git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
GIT_COMMIT="$(/usr/bin/git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
FINAL_DIRTY="$(/usr/bin/git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all 2>> "$LOG_FILE" || true)"
if [[ "$GIT_BRANCH" != "$TARGET_BRANCH" || "$GIT_COMMIT" != "$REMOTE_COMMIT" || -n "$FINAL_DIRTY" ]]; then
  fail "Po aktualizaci nelze potvrdit čistou a přesnou GitHub verzi $TARGET_BRANCH. Nic nebylo nainstalováno."
fi

GIT_COMMIT_SHORT="$(/usr/bin/git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
status "Ověřená zdrojová verze: $TARGET_BRANCH @ $GIT_COMMIT_SHORT"

TARGET_LAUNCHER="$REPO_ROOT/$LAUNCHER_FILENAME"
TARGET_LAUNCHER_HASH="$(/usr/bin/shasum -a 256 "$TARGET_LAUNCHER" 2>/dev/null | /usr/bin/awk '{print $1}')"
if [[ -z "$START_LAUNCHER_HASH" || -z "$TARGET_LAUNCHER_HASH" || ! -x "$TARGET_LAUNCHER" ]]; then
  fail "Cílová větev neobsahuje platný spouštěč obnovy. Nic nebylo nainstalováno."
fi
if [[ "$START_LAUNCHER_HASH" != "$TARGET_LAUNCHER_HASH" ]]; then
  if [[ "$RELAUNCH_COUNT" -ge 1 ]]; then
    fail "Cílová větev se během obnovy znovu změnila. Spusť obnovu ještě jednou."
  fi
  status "Spouštím právě staženou verzi obnovovacího nástroje..."
  LC_REFRESH_RELAUNCH_COUNT=1 /usr/bin/env LC_REFRESH_NO_DIALOG="${LC_REFRESH_NO_DIALOG:-0}" "$TARGET_LAUNCHER" "$@"
  exit $?
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  fail "Cílová větev neobsahuje kompletní Xcode projekt Lázeňského Commanderu."
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
WATCH_APP_PATH="$APP_PATH/Watch/LazenskyCommanderWatchApp.app"
if [[ ! -d "$WATCH_APP_PATH" ]]; then
  fail "Sestavení neobsahuje zabalenou aplikaci pro Apple Watch. Nic nebylo nainstalováno."
fi
if ! /usr/bin/codesign --verify --deep --strict "$APP_PATH" >> "$LOG_FILE" 2>&1; then
  fail "Kontrola podpisu sestavené aplikace selhala."
fi

APP_VERSION="$(plist_raw CFBundleShortVersionString "$APP_PATH/Info.plist")"
APP_BUILD="$(plist_raw CFBundleVersion "$APP_PATH/Info.plist")"
status "Ověřená aplikace: verze ${APP_VERSION:-neuvedena} (${APP_BUILD:-bez čísla}), včetně Apple Watch."

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
status "Nainstalovaná zdrojová verze: $TARGET_BRANCH @ $GIT_COMMIT_SHORT"
status "Technický log: $LOG_FILE"
show_dialog "1" "HOTOVO – Lázeňský Commander byl obnoven."
