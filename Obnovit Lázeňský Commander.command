#!/bin/bash

set -u
set -o pipefail
umask 077

APP_NAME="Lázeňský Commander"
SCHEME="LazenskyCommanderApp"
APP_BUNDLE_ID="com.varnakonvice.lazenskycommander"
WATCH_SCHEME="LazenskyCommanderWatchApp"
WATCH_BUNDLE_ID="com.varnakonvice.lazenskycommander.watchkitapp"
CONFIGURATION="Debug"
TARGET_BRANCH="${LC_REFRESH_TARGET_BRANCH:-main}"
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

read_profile_refresh_dates() {
  local profile="$1"
  local decoded="$2"
  local creation expiration creation_epoch expiration_epoch
  /usr/bin/security cms -D -i "$profile" -o "$decoded" >> "$LOG_FILE" 2>&1 || return 1
  creation="$(plist_raw CreationDate "$decoded")"
  expiration="$(plist_raw ExpirationDate "$decoded")"
  [[ "$creation" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  [[ "$expiration" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  creation_epoch="$(LC_ALL=C /bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$creation" '+%s' 2>> "$LOG_FILE")" || return 1
  expiration_epoch="$(LC_ALL=C /bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s' 2>> "$LOG_FILE")" || return 1
  [[ "$(/bin/date -u -r "$creation_epoch" '+%Y-%m-%dT%H:%M:%SZ')" == "$creation" ]] || return 1
  [[ "$(/bin/date -u -r "$expiration_epoch" '+%Y-%m-%dT%H:%M:%SZ')" == "$expiration" ]] || return 1
  [[ "$creation_epoch" -lt "$expiration_epoch" ]] || return 1
  PROFILE_EXPIRATION_EPOCH="$expiration_epoch"
  PROFILE_EXPIRATION_DATE="$(TZ=Europe/Prague /bin/date -r "$expiration_epoch" '+%d.%m.%Y %H:%M')" || return 1
  NEXT_REFRESH_DATE="$(TZ=Europe/Prague /bin/date -r "$expiration_epoch" -v-1d '+%d.%m.%Y')" || return 1
  log "Provisioning dates: creation=$creation; expiration=$expiration; next=$NEXT_REFRESH_DATE; source=embedded.mobileprovision"
  return 0
}

set_refresh_deadline_after_install() {
  if [[ "$PROFILE_DATES_AVAILABLE" == "1" ]]; then
    REFRESH_PROFILE_SUMMARY="Platnost iPhone aplikace do: $PROFILE_EXPIRATION_DATE"
  else
    NEXT_REFRESH_DATE="$(TZ=Europe/Prague /bin/date -v+6d '+%d.%m.%Y' 2>> "$LOG_FILE" || true)"
    log "WARNING: provisioning dates unavailable; next refresh uses installation +6 calendar days."
    REFRESH_PROFILE_SUMMARY="Termín obnovy je pouze odhad; platnost profilu se nepodařilo přečíst."
  fi
  status "$REFRESH_PROFILE_SUMMARY"
  if [[ -z "$NEXT_REFRESH_DATE" ]]; then
    NEXT_REFRESH_DATE="nelze určit"
    log "WARNING: recommended next refresh date could not be calculated."
  fi
}

WATCH_STATUS="přeskočeno"
WATCH_REASON="nativní Watch aplikace nebyla obnovena"
WATCH_ELIGIBLE=0

skip_watch() {
  WATCH_STATUS="přeskočeno"
  WATCH_REASON="$1"
  log "WATCH: skipped; reason=$WATCH_REASON"
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

if ! /usr/bin/git check-ref-format "refs/heads/$TARGET_BRANCH" >/dev/null 2>&1; then
  fail "Cílová větev obnovy má neplatný název."
fi

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
  LC_REFRESH_RELAUNCH_COUNT=1 /usr/bin/env LC_REFRESH_TARGET_BRANCH="$TARGET_BRANCH" LC_REFRESH_NO_DIALOG="${LC_REFRESH_NO_DIALOG:-0}" "$TARGET_LAUNCHER" "$@"
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
WATCH_SCHEME_FOUND=0
if [[ "$SCHEME_COUNT" =~ ^[0-9]+$ ]]; then
  for ((index = 0; index < SCHEME_COUNT; index++)); do
    scheme_name="$(plist_raw "project.schemes.$index" "$SCHEMES_JSON")"
    [[ "$scheme_name" == "$SCHEME" ]] && SCHEME_FOUND=1
    [[ "$scheme_name" == "$WATCH_SCHEME" ]] && WATCH_SCHEME_FOUND=1
  done
fi
if [[ "$SCHEME_FOUND" -ne 1 ]]; then
  fail "Projekt neobsahuje sdílené schéma LazenskyCommanderApp."
fi
if [[ "$WATCH_SCHEME_FOUND" -ne 1 ]]; then
  skip_watch "projekt neobsahuje sdílené schéma LazenskyCommanderWatchApp"
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

WATCH_SEEN=0
WATCH_UNPAIRED_SEEN=0
WATCH_LOCKED_SEEN=0
WATCH_UNREACHABLE_SEEN=0
WATCH_READY_COUNT=0
WATCH_LOCK_STATE_UNKNOWN=0
WATCH_IDENTIFIER=""
WATCH_UDID=""
WATCH_NAME=""
WATCH_MODEL=""
WATCH_OS=""
WATCH_DEVELOPER_MODE=""

for ((index = 0; index < DEVICE_COUNT; index++)); do
  prefix="result.devices.$index"
  platform="$(plist_raw "$prefix.hardwareProperties.platform" "$DEVICES_JSON")"
  reality="$(plist_raw "$prefix.hardwareProperties.reality" "$DEVICES_JSON")"
  device_type="$(plist_raw "$prefix.hardwareProperties.deviceType" "$DEVICES_JSON")"
  if [[ "$reality" != "physical" ]]; then
    continue
  fi

  pairing_state="$(plist_raw "$prefix.connectionProperties.pairingState" "$DEVICES_JSON")"
  developer_mode="$(plist_raw "$prefix.deviceProperties.developerModeStatus" "$DEVICES_JSON")"
  identifier="$(plist_raw "$prefix.identifier" "$DEVICES_JSON")"
  udid="$(plist_raw "$prefix.hardwareProperties.udid" "$DEVICES_JSON")"

  if [[ "$platform" == "iOS" && "$device_type" == "iPhone" ]]; then
    IPHONE_SEEN=$((IPHONE_SEEN + 1))
    if [[ "$pairing_state" != "paired" ]]; then
      UNPAIRED_SEEN=1
      continue
    fi
    if [[ "$developer_mode" != "enabled" ]]; then
      DEV_MODE_DISABLED_SEEN=1
      continue
    fi
    if [[ -z "$identifier" || -z "$udid" ]]; then
      continue
    fi

    LOCK_JSON="$TEMP_DIR/iphone-lock-$index.json"
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
  elif [[ "$platform" == "watchOS" && "$device_type" == "appleWatch" ]]; then
    WATCH_SEEN=$((WATCH_SEEN + 1))
    if [[ "$pairing_state" != "paired" ]]; then
      WATCH_UNPAIRED_SEEN=1
      continue
    fi
    if [[ -z "$identifier" || -z "$udid" ]]; then
      WATCH_UNREACHABLE_SEEN=1
      continue
    fi

    WATCH_READY_COUNT=$((WATCH_READY_COUNT + 1))
    WATCH_IDENTIFIER="$identifier"
    WATCH_UDID="$udid"
    WATCH_NAME="$(plist_raw "$prefix.deviceProperties.name" "$DEVICES_JSON")"
    WATCH_MODEL="$(plist_raw "$prefix.hardwareProperties.marketingName" "$DEVICES_JSON")"
    WATCH_OS="$(plist_raw "$prefix.deviceProperties.osVersionNumber" "$DEVICES_JSON")"
    WATCH_DEVELOPER_MODE="$developer_mode"

    WATCH_LOCK_JSON="$TEMP_DIR/watch-lock-$index.json"
    if ! "$DEVICECTL" device info lockState --device "$identifier" --quiet --timeout 15 --json-output "$WATCH_LOCK_JSON" >> "$LOG_FILE" 2>&1; then
      WATCH_LOCK_STATE_UNKNOWN=1
      continue
    fi
    watch_passcode_required="$(plist_raw result.passcodeRequired "$WATCH_LOCK_JSON")"
    watch_unlocked_since_boot="$(plist_raw result.unlockedSinceBoot "$WATCH_LOCK_JSON")"
    if [[ "$watch_passcode_required" != "false" || "$watch_unlocked_since_boot" != "true" ]]; then
      WATCH_LOCKED_SEEN=1
    fi
  fi
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

probe_watch_eligibility() {
  WATCH_ELIGIBLE=0
  if [[ "$WATCH_SCHEME_FOUND" -ne 1 ]]; then
    skip_watch "chybí sdílené schéma LazenskyCommanderWatchApp"
    return
  fi
  if [[ "$WATCH_READY_COUNT" -eq 0 ]]; then
    if [[ "$WATCH_SEEN" -eq 0 ]]; then
      skip_watch "Apple Watch nejsou dostupné"
    elif [[ "$WATCH_UNPAIRED_SEEN" -eq 1 ]]; then
      skip_watch "Apple Watch nejsou spárované s tímto Macem"
    elif [[ "$WATCH_UNREACHABLE_SEEN" -eq 1 ]]; then
      skip_watch "Apple Watch nemají platný identifier nebo UDID"
    else
      skip_watch "Apple Watch nejsou připravené"
    fi
    return
  fi
  if [[ "$WATCH_READY_COUNT" -gt 1 ]]; then
    skip_watch "je dostupných více Apple Watch"
    return
  fi

  log "Watch candidate: ${WATCH_NAME:-Apple Watch}; udid=$WATCH_UDID; watchOS=${WATCH_OS:-unknown}"
  WATCH_DESTINATIONS_FILE="$TEMP_DIR/watch-destinations.txt"
  if ! /usr/bin/xcodebuild -project "$PROJECT_PATH" -scheme "$WATCH_SCHEME" -showdestinations > "$WATCH_DESTINATIONS_FILE" 2>> "$LOG_FILE"; then
    skip_watch "Xcode nedokázal ověřit Watch destination"
    return
  fi
  if ! /usr/bin/grep -Fq "platform:watchOS" "$WATCH_DESTINATIONS_FILE" || ! /usr/bin/grep -Fq "id:$WATCH_UDID" "$WATCH_DESTINATIONS_FILE"; then
    skip_watch "Apple Watch nejsou způsobilá Xcode destination"
    return
  fi

  WATCH_BUILD_SETTINGS_JSON="$TEMP_DIR/watch-build-settings.json"
  if ! /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$WATCH_SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=watchOS,id=$WATCH_UDID" \
    -showBuildSettings -json > "$WATCH_BUILD_SETTINGS_JSON" 2>> "$LOG_FILE"; then
    skip_watch "Xcode odmítl fyzickou Watch destination"
    return
  fi

  if [[ "$WATCH_DEVELOPER_MODE" != "enabled" ]]; then
    log "WARNING: CoreDevice reported Apple Watch developerModeStatus=${WATCH_DEVELOPER_MODE:-unknown}, but Xcode accepted destination $WATCH_UDID; continuing."
  fi
  if [[ "$WATCH_LOCK_STATE_UNKNOWN" -eq 1 ]]; then
    log "WARNING: CoreDevice could not confirm Apple Watch lock state, but Xcode accepted destination $WATCH_UDID; continuing."
  fi
  if [[ "$WATCH_LOCKED_SEEN" -eq 1 ]]; then
    skip_watch "Apple Watch jsou zamčené"
    return
  fi

  WATCH_ELIGIBLE=1
  WATCH_REASON="Apple Watch jsou připravené"
}

if [[ "$MODE" == "check" ]]; then
  probe_watch_eligibility
  status "PŘIPRAVENO – Mac a iPhone jsou připravené k obnově."
  if [[ "$WATCH_ELIGIBLE" -eq 1 ]]; then
    status "WATCH: volitelná aplikace je nyní připravená."
  else
    status "WATCH: volitelná aplikace bude přeskočena – $WATCH_REASON."
  fi
  status "Kontrolní režim nic nesestavil, nepodepsal ani nenainstaloval."
  status "Technický log: $LOG_FILE"
  show_dialog "1" "PŘIPRAVENO – Mac a iPhone jsou připravené k obnově.\n\nWatch aplikace je volitelná. Kontrolní režim nic nenainstaloval."
  exit 0
fi

DERIVED_DATA="$TEMP_DIR/DerivedData"
status "Obnovuji podpis a sestavuji iPhone aplikaci. Může to několik minut trvat..."
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
  log "iPhone build result: failure"
  if /usr/bin/grep -Eqi 'internet connection|network connection|could not resolve host|offline|NSURLError' "$LOG_FILE"; then
    fail "Mac nemá přístup k internetu potřebný pro podpis."
  elif /usr/bin/grep -Eqi 'provisioning|no profiles|signing certificate|developer account|no accounts|communication with Apple' "$LOG_FILE"; then
    fail "Apple provisioning se nepodařilo obnovit. Zkontroluj v Xcode jednou přihlášený Apple účet Personal Team."
  else
    fail "Sestavení Commanderu selhalo."
  fi
fi
log "iPhone build result: success"

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/LazenskyCommanderApp.app"
if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/embedded.mobileprovision" ]]; then
  fail "Sestavená aplikace nemá platný vývojářský podpis."
fi
EMBEDDED_WATCH_APP_PATH="$APP_PATH/Watch/LazenskyCommanderWatchApp.app"
if [[ ! -d "$EMBEDDED_WATCH_APP_PATH" ]]; then
  log "WARNING: iPhone build does not contain an embedded Watch app; iPhone refresh continues."
fi
if ! /usr/bin/codesign --verify --strict "$APP_PATH" >> "$LOG_FILE" 2>&1; then
  fail "Kontrola podpisu sestavené iPhone aplikace selhala."
fi

PROFILE_DATES_AVAILABLE=0
PROFILE_EXPIRATION_EPOCH=""
PROFILE_EXPIRATION_DATE=""
NEXT_REFRESH_DATE=""
if read_profile_refresh_dates "$APP_PATH/embedded.mobileprovision" "$TEMP_DIR/iphone-profile.plist"; then
  PROFILE_DATES_AVAILABLE=1
  if [[ "$PROFILE_EXPIRATION_EPOCH" -le "$(/bin/date '+%s')" ]]; then
    fail "Xcode vytvořil aplikaci s již prošlým provisioning profilem. Ověř Personal Team v Xcode."
  fi
fi

APP_VERSION="$(plist_raw CFBundleShortVersionString "$APP_PATH/Info.plist")"
APP_BUILD="$(plist_raw CFBundleVersion "$APP_PATH/Info.plist")"
status "Ověřená iPhone aplikace: verze ${APP_VERSION:-neuvedena} (${APP_BUILD:-bez čísla})."

INSTALL_JSON="$TEMP_DIR/iphone-install.json"
status "Instaluji aktualizovanou aplikaci na iPhone..."
if ! "$DEVICECTL" device install app \
  --device "$DEVICE_IDENTIFIER" \
  "$APP_PATH" \
  --quiet \
  --timeout 180 \
  --json-output "$INSTALL_JSON" >> "$LOG_FILE" 2>&1; then
  log "iPhone install result: failure"
  fail "Instalace na iPhone selhala. Odemkni iPhone, nech ho připojený a spusť obnovu znovu."
fi

if [[ "$(plist_raw info.outcome "$INSTALL_JSON")" != "success" ]]; then
  log "iPhone install result: unconfirmed"
  fail "Xcode nepotvrdil úspěšnou instalaci na iPhone."
fi
log "iPhone install result: success"

IPHONE_APPS_JSON="$TEMP_DIR/iphone-apps.json"
if ! "$DEVICECTL" device info apps \
  --device "$DEVICE_IDENTIFIER" \
  --bundle-id "$APP_BUNDLE_ID" \
  --quiet \
  --timeout 30 \
  --json-output "$IPHONE_APPS_JSON" >> "$LOG_FILE" 2>&1; then
  fail "Instalace na iPhone proběhla, ale její výsledek se nepodařilo ověřit."
fi
IPHONE_APP_COUNT="$(plist_raw result.apps "$IPHONE_APPS_JSON")"
if [[ ! "$IPHONE_APP_COUNT" =~ ^[0-9]+$ || "$IPHONE_APP_COUNT" -lt 1 ]]; then
  fail "Po instalaci nebyl Lázeňský Commander na iPhonu nalezen."
fi
log "iPhone post-install verification: success; bundleID=$APP_BUNDLE_ID"

set_refresh_deadline_after_install

IPHONE_LAUNCH_JSON="$TEMP_DIR/iphone-launch.json"
status "Otevírám Commander pro automatickou aktualizaci připomenutí obnovy..."
if ! "$DEVICECTL" device process launch \
  --device "$DEVICE_IDENTIFIER" \
  --quiet --timeout 30 --json-output "$IPHONE_LAUNCH_JSON" \
  "$APP_BUNDLE_ID" >> "$LOG_FILE" 2>&1; then
  fail "Aplikace je nainstalovaná, ale nejde otevřít. Odemkni iPhone a otevři Commander, aby se aktualizovalo připomenutí obnovy."
fi
if [[ "$(plist_raw info.outcome "$IPHONE_LAUNCH_JSON")" != "success" ]]; then
  fail "Instalace je ověřená, ale spuštění Commanderu nebylo potvrzeno. Otevři jej na iPhonu pro aktualizaci připomenutí."
fi
log "iPhone post-install launch: success"

attempt_watch_refresh() {
  probe_watch_eligibility
  if [[ "$WATCH_ELIGIBLE" -ne 1 ]]; then
    return
  fi

  status "WATCH: zkouším obnovit volitelnou nativní aplikaci..."
  if ! /usr/bin/xcodebuild \
    -quiet \
    -project "$PROJECT_PATH" \
    -scheme "$WATCH_SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=watchOS,id=$WATCH_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build >> "$LOG_FILE" 2>&1; then
    skip_watch "Watch build nebo provisioning selhal"
    return
  fi
  log "Watch build result: success"

  WATCH_PRODUCT_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-watchos/LazenskyCommanderWatchApp.app"
  if [[ ! -d "$WATCH_PRODUCT_PATH" || ! -f "$WATCH_PRODUCT_PATH/embedded.mobileprovision" ]]; then
    skip_watch "Watch build nemá platný vývojářský profil"
    return
  fi
  if ! /usr/bin/codesign --verify --deep --strict "$WATCH_PRODUCT_PATH" >> "$LOG_FILE" 2>&1; then
    skip_watch "kontrola podpisu Watch aplikace selhala"
    return
  fi

  WATCH_INSTALL_JSON="$TEMP_DIR/watch-install.json"
  if ! "$DEVICECTL" device install app \
    --device "$WATCH_IDENTIFIER" \
    "$WATCH_PRODUCT_PATH" \
    --quiet \
    --timeout 180 \
    --json-output "$WATCH_INSTALL_JSON" >> "$LOG_FILE" 2>&1; then
    skip_watch "instalace Watch aplikace selhala"
    return
  fi
  if [[ "$(plist_raw info.outcome "$WATCH_INSTALL_JSON")" != "success" ]]; then
    skip_watch "Xcode nepotvrdil instalaci Watch aplikace"
    return
  fi
  log "Watch install result: success"

  WATCH_APPS_JSON="$TEMP_DIR/watch-apps.json"
  if ! "$DEVICECTL" device info apps \
    --device "$WATCH_IDENTIFIER" \
    --bundle-id "$WATCH_BUNDLE_ID" \
    --quiet \
    --timeout 30 \
    --json-output "$WATCH_APPS_JSON" >> "$LOG_FILE" 2>&1; then
    skip_watch "instalaci Watch aplikace se nepodařilo ověřit"
    return
  fi
  WATCH_APP_COUNT="$(plist_raw result.apps "$WATCH_APPS_JSON")"
  if [[ ! "$WATCH_APP_COUNT" =~ ^[0-9]+$ || "$WATCH_APP_COUNT" -lt 1 ]]; then
    skip_watch "Watch aplikace po instalaci nebyla nalezena"
    return
  fi

  WATCH_STATUS="OK"
  WATCH_REASON="nativní Watch aplikace byla obnovena"
  log "Watch post-install verification: success; bundleID=$WATCH_BUNDLE_ID"
}

attempt_watch_refresh

REFRESH_RESULT="HOTOVO – $APP_NAME na iPhonu byl obnoven."
REFRESH_DIALOG_ICON=1
REFRESH_EXIT_CODE=0
if [[ "$PROFILE_DATES_AVAILABLE" == "1" ]]; then
  PROFILE_REFRESH_DAY="$(TZ=Europe/Prague /bin/date -r "$PROFILE_EXPIRATION_EPOCH" -v-1d '+%Y%m%d' 2>> "$LOG_FILE" || true)"
  CURRENT_REFRESH_DAY="$(TZ=Europe/Prague /bin/date '+%Y%m%d' 2>> "$LOG_FILE" || true)"
  if [[ ! "$PROFILE_REFRESH_DAY" =~ ^[0-9]{8}$ || ! "$CURRENT_REFRESH_DAY" =~ ^[0-9]{8}$ ]]; then
    REFRESH_RESULT="NAINSTALOVÁNO – $APP_NAME je na iPhonu nainstalován, ale termín obnovy nelze bezpečně ověřit. Obnova není potvrzena."
    REFRESH_DIALOG_ICON=2
    REFRESH_EXIT_CODE=2
  elif [[ "$PROFILE_REFRESH_DAY" -le "$CURRENT_REFRESH_DAY" ]]; then
    REFRESH_RESULT="NAINSTALOVÁNO – $APP_NAME je na iPhonu nainstalován, ale provisioning platnost se neprodloužila. Obnova je stále nutná."
    REFRESH_DIALOG_ICON=2
    REFRESH_EXIT_CODE=2
  fi
fi

status "$REFRESH_RESULT"
status "Nainstalovaná větev + commit: $TARGET_BRANCH @ $GIT_COMMIT_SHORT"
status "iPhone: OK"
if [[ "$WATCH_STATUS" == "OK" ]]; then
  WATCH_SUMMARY="WATCH: OK – nativní Watch aplikace byla obnovena."
else
  WATCH_SUMMARY="WATCH: přeskočeno – nativní Watch aplikace nebyla obnovena. Důvod: $WATCH_REASON."
fi
status "$WATCH_SUMMARY"
status "DALŠÍ OBNOVA NEJPOZDĚJI: $NEXT_REFRESH_DATE"
status "Technický log: $LOG_FILE"
show_dialog "$REFRESH_DIALOG_ICON" "$REFRESH_RESULT\n\nVětev + commit: $TARGET_BRANCH @ $GIT_COMMIT_SHORT\niPhone: OK\n$WATCH_SUMMARY\n$REFRESH_PROFILE_SUMMARY\nDALŠÍ OBNOVA NEJPOZDĚJI: $NEXT_REFRESH_DATE\n\nTechnický log:\n$LOG_FILE"
exit "$REFRESH_EXIT_CODE"
