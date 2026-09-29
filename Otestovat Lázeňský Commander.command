#!/bin/bash

set -u
set -o pipefail
umask 077

APP_BUNDLE_ID="com.varnakonvice.lazenskycommander"
WATCH_BUNDLE_ID="com.varnakonvice.lazenskycommander.watchkitapp"
IPHONE_UDID="${LC_ACCEPTANCE_IPHONE_UDID:-00008140-0019586A3607001C}"
WATCH_UDID="${LC_ACCEPTANCE_WATCH_UDID:-00008310-001C09693CE0E01E}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"
PROJECT="$REPO_ROOT/native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj"
DERIVED="/private/tmp/lc-commander-acceptance"
RESULTS_ROOT="$HOME/Desktop/LazenskyCommander-Acceptance"
RESULTS="$RESULTS_ROOT/$(/bin/date '+%Y%m%d-%H%M%S')-$$"
LOG="$RESULTS/acceptance.log"
MODE="${1:---run}"
if [[ "$MODE" == "--help" ]]; then
  printf '%s\n' 'Commander: --run | --cleanup | --doctor | --service | --capture-watch | --build-normal | --install-normal'
  printf '%s\n' 'Vždy aktuální worktree; bez fetch/checkout/reset. --run je plný test produkční cesty; plánuje a spouští testovací alarmy.'
  exit 0
fi
LOCK_DIR="/private/tmp/commander-acceptance.lock"

fail() {
  printf 'CHYBA: %s\n' "$1"
  printf 'Log: %s\n' "$LOG"
  exit 1
}

status() {
  printf '%s\n' "$*"
  printf '%s %s\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG"
}
free_gb() {
  /bin/df -Pk /System/Volumes/Data | /usr/bin/awk 'NR==2 {printf "%.0f", $4/1024/1024}'
}

acquire_lock() {
  if /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    trap '/bin/rm -rf "$LOCK_DIR"' EXIT INT TERM
    return 0
  fi

  local owner=""
  [[ -f "$LOCK_DIR/pid" ]] && owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -n "$owner" ]] && /bin/kill -0 "$owner" 2>/dev/null; then
    fail "Acceptance test už běží v procesu $owner. Druhý souběžný test nespouštím."
  fi

  /bin/rm -rf "$LOCK_DIR"
  /bin/mkdir "$LOCK_DIR" || fail "Nelze vytvořit zámek acceptance testu."
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  trap '/bin/rm -rf "$LOCK_DIR"' EXIT INT TERM
}

cleanup_test_artifacts() {
  # Delete only this launcher's named build directory; never other work or evidence.
  [[ "$DERIVED" == "/private/tmp/lc-commander-acceptance" ]] || return 1
  /bin/rm -rf -- "$DERIVED"
}

wait_for_watch_connected() {
  local attempt
  /usr/bin/open -a Xcode >/dev/null 2>&1 || true
  for attempt in $(/usr/bin/seq 1 36); do
    if /usr/bin/xcrun devicectl device info apps       --device "$WATCH_UDID" --timeout 5 >/dev/null 2>&1; then
      status "Apple Watch odpovídají přes CoreDevice."
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      status "Čekám na skutečný CoreDevice handshake s Apple Watch…"
    fi
    /bin/sleep 2
  done
  return 1
}

watch_is_unlocked() {
  /usr/bin/xcrun devicectl device info lockState --device "$WATCH_UDID" --timeout 8 2>/dev/null |
    /usr/bin/grep -q 'passcodeRequired: false'
}

wait_for_watch_unlock() {
  local attempt
  for attempt in $(/usr/bin/seq 1 1800); do
    if wait_for_watch_connected && watch_is_unlocked; then
      status "Apple Watch jsou připojené a odemčené."
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      status "Apple Watch jsou zamčené nebo dočasně nedostupné; čekám až 30 minut a pokračuji po odemčení…"
    fi
    /bin/sleep 1
  done
  return 1
}

watch_handshake() {
  wait_for_watch_connected
}

watch_install_with_retry() {
  local app="$1"
  local attempt
  for attempt in 1 2 3; do
    wait_for_watch_connected || return 1
    status "Watch instalace – pokus $attempt/3"
    if /usr/bin/xcrun devicectl device install app --device "$WATCH_UDID" --timeout 60 "$app" >> "$LOG" 2>&1; then
      return 0
    fi
    /bin/sleep 2
  done
  return 1
}
iphone_is_unlocked() {
  /usr/bin/xcrun devicectl device info lockState --device "$IPHONE_UDID" --timeout 8 2>/dev/null |
    /usr/bin/grep -q 'passcodeRequired: false'
}

wait_for_iphone_unlock() {
  local attempt
  for attempt in $(/usr/bin/seq 1 1800); do
    if iphone_is_unlocked; then
      status "iPhone je odemčený."
      return 0
    fi
    if [[ "$attempt" -eq 1 ]]; then
      status "iPhone je zamčený; čekám až 30 minut a po nejbližším odemčení pokračuji automaticky…"
    fi
    /bin/sleep 1
  done
  return 1
}

iphone_pid() {
  /usr/bin/xcrun devicectl device info processes --device "$IPHONE_UDID" --timeout 10 2>/dev/null |
    /usr/bin/awk '/LazenskyCommanderApp\.app\/LazenskyCommanderApp/{print $1; exit}'
}

terminate_iphone_app() {
  local pid
  pid="$(iphone_pid)"
  if [[ -n "$pid" ]]; then
    /usr/bin/xcrun devicectl device process terminate --device "$IPHONE_UDID" --pid "$pid" >/dev/null 2>&1 || true
  fi
}

watch_pid() {
  /usr/bin/xcrun devicectl device info processes --device "$WATCH_UDID" --timeout 20 2>/dev/null |
    /usr/bin/awk '/LazenskyCommanderWatchApp\.app\/LazenskyCommanderWatchApp/{print $1; exit}'
}

launch_watch_companion() {
  local attempt
  for attempt in 1 2 3; do
    wait_for_watch_unlock || return 1
    if /usr/bin/xcrun devicectl device process launch       --device "$WATCH_UDID" --timeout 60 --terminate-existing       "$WATCH_BUNDLE_ID" >> "$LOG" 2>&1; then
      return 0
    fi
    /bin/sleep 2
  done
  return 1
}

terminate_watch_app() {
  local pid
  pid="$(watch_pid)"
  if [[ -n "$pid" ]]; then
    /usr/bin/xcrun devicectl device process terminate       --device "$WATCH_UDID" --pid "$pid" --timeout 30 >/dev/null 2>&1 || true
  fi
}

launch_iphone_mode() {
  local flag="$1"
  /usr/bin/xcrun devicectl device process launch     --device "$IPHONE_UDID"     --terminate-existing     "$APP_BUNDLE_ID" -- "$flag" >> "$LOG" 2>&1
}

capture_optional() {
  local device="$1"
  local path="$2"
  if [[ "$device" == "$WATCH_UDID" ]]; then
    wait_for_watch_connected || return 0
  fi
  /usr/bin/xcrun devicectl device capture screenshot     --device "$device" --destination "$path" --timeout 60 >> "$LOG" 2>&1 || true
}

pull_acceptance_status() {
  local destination="$1"
  /bin/rm -f "$destination"
  /usr/bin/xcrun devicectl device copy from     --device "$IPHONE_UDID"     --domain-type appDataContainer     --domain-identifier "$APP_BUNDLE_ID"     --source Documents/commander-acceptance-status.json     --destination "$destination"     --timeout 15 >> "$LOG" 2>&1
}

acceptance_status_field() {
  local file="$1"
  local field="$2"
  /usr/bin/python3 - "$file" "$field" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        value = json.load(handle).get(sys.argv[2], "")
    print(value if value is not None else "")
except Exception:
    print("")
PY
}

acceptance_status_epoch() {
  local file="$1"
  /usr/bin/python3 - "$file" <<'PY'
import json, sys
from datetime import datetime
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        value = json.load(handle).get("timestamp", "")
    print(int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()))
except Exception:
    print(0)
PY
}

wait_for_acceptance_success() {
  local launched_epoch="$1"
  local status_file="$RESULTS/acceptance-status.json"
  local attempt phase observed expected stamp message

  for attempt in $(/usr/bin/seq 1 90); do
    if pull_acceptance_status "$status_file"; then
      phase="$(acceptance_status_field "$status_file" phase)"
      stamp="$(acceptance_status_epoch "$status_file")"
      if [[ "$stamp" =~ ^[0-9]+$ && "$stamp" -ge "$launched_epoch" ]]; then
        case "$phase" in
          watch-acknowledged)
            expected="$(acceptance_status_field "$status_file" expectedToken)"
            observed="$(acceptance_status_field "$status_file" observedToken)"
            if [[ -n "$expected" && "$expected" == "$observed" ]]; then
              status "Watch potvrdily přesně stejný acceptance stav: $observed"
              return 0
            fi
            ;;
          failed-alarm-sync|failed-live-activity|failed-watch-ack)
            message="$(acceptance_status_field "$status_file" message)"
            status "Acceptance aplikace nahlásila $phase: ${message:-bez detailu}"
            return 1
            ;;
        esac
      fi
    fi
    /bin/sleep 0.5
  done
  status "Acceptance status se včas nepotvrdil."
  return 1
}

wait_for_activity_active() {
  local launched_epoch="$1"
  local status_file="$RESULTS/activity-status.json"
  local attempt phase stamp message

  for attempt in $(/usr/bin/seq 1 150); do
    if pull_acceptance_status "$status_file"; then
      phase="$(acceptance_status_field "$status_file" phase)"
      stamp="$(acceptance_status_epoch "$status_file")"
      if [[ "$stamp" =~ ^[0-9]+$ && "$stamp" -ge "$launched_epoch" ]]; then
        case "$phase" in
          activity-active)
            status "iPhone ActivityKit read-back potvrzuje aktivní Commander Live Activity."
            return 0
            ;;
          failed-alarm-sync|failed-live-activity|failed-watch-ack|activity-not-active)
            message="$(acceptance_status_field "$status_file" message)"
            status "iPhone ActivityKit read-back není active: ${message:-bez detailu}"
            return 1
            ;;
        esac
      fi
    fi
    /bin/sleep 0.25
  done
  status "iPhone ActivityKit read-back se včas nepotvrdil."
  return 1
}

wait_until_epoch() {
  local target="$1"
  local now
  while :; do
    now="$(/bin/date '+%s')"
    [[ "$now" -ge "$target" ]] && return 0
    /bin/sleep 0.5
  done
}

build_normal_pair() {
  cleanup_test_artifacts || return 1
  local build_number build_branch build_commit
  build_number="$(/bin/date '+%y%m%d%H%M')"
  build_branch="$(/usr/bin/git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
  build_commit="$(/usr/bin/git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$build_branch" && "$build_commit" =~ ^[0-9a-f]{40}$ ]] || return 1
  status "Sestavuji normální Commander z $build_branch @ ${build_commit:0:8}…"
  /usr/bin/xcodebuild -quiet -project "$PROJECT" -scheme LazenskyCommanderApp \
    -configuration Debug -destination "generic/platform=iOS" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$build_number" \
    LC_BUILD_BRANCH="$build_branch" LC_BUILD_COMMIT="$build_commit" \
    COMPILER_INDEX_STORE_ENABLE=NO 'OTHER_SWIFT_FLAGS=$(inherited)' build >> "$LOG" 2>&1 || return 1
  local iphone_app="$DERIVED/Build/Products/Debug-iphoneos/LazenskyCommanderApp.app"
  local watch_app="$DERIVED/Build/Products/Debug-watchos/LazenskyCommanderWatchApp.app"
  [[ -d "$iphone_app" && -d "$watch_app" ]] || return 1
  /usr/bin/codesign --verify --deep --strict "$iphone_app" >> "$LOG" 2>&1 || return 1
  /usr/bin/codesign --verify --deep --strict "$watch_app" >> "$LOG" 2>&1 || return 1
  status "Podepsaný iPhone + Watch build připraven: $DERIVED"
}

restore_normal_build() {
  build_normal_pair || return 1
  local iphone_app="$DERIVED/Build/Products/Debug-iphoneos/LazenskyCommanderApp.app"
  local watch_app="$DERIVED/Build/Products/Debug-watchos/LazenskyCommanderWatchApp.app"
  wait_for_iphone_unlock || return 1
  /usr/bin/xcrun devicectl device install app --device "$IPHONE_UDID" --timeout 60 "$iphone_app" >> "$LOG" 2>&1 || return 1
  watch_install_with_retry "$watch_app" || return 1
  launch_watch_companion || return 1
  /usr/bin/xcrun devicectl device process launch --device "$IPHONE_UDID" \
    --terminate-existing "$APP_BUNDLE_ID" >> "$LOG" 2>&1 || return 1
  status "Normální iPhone + Watch build nainstalován; spuštěn produkční bootstrap pro obnovení rozpisu a alarmů."
  status "Prodloužení provisioning platnosti tímto není potvrzeno; termín určuje profil v aplikaci."
}

wait_for_cleanup_success() {
  local launched_epoch="$1"
  local status_file="$RESULTS/cleanup-status.json"
  local attempt phase stamp
  for attempt in $(/usr/bin/seq 1 90); do
    if pull_acceptance_status "$status_file"; then
      phase="$(acceptance_status_field "$status_file" phase)"
      stamp="$(acceptance_status_epoch "$status_file")"
      if [[ "$stamp" =~ ^[0-9]+$ && "$stamp" -ge "$launched_epoch" ]]; then
        [[ "$phase" == "cleaned" ]] && return 0
        [[ "$phase" == failed-* || "$phase" == "cleanup-watch-failed" ]] && return 1
      fi
    fi
    /bin/sleep 0.5
  done
  return 1
}

abort_acceptance_run() {
  local reason="$1"
  status "Acceptance test neprošel: $reason"
  local cleanup_started
  cleanup_started="$(/bin/date '+%s')"
  if ! launch_iphone_mode "--acceptance-cleanup" || ! wait_for_cleanup_success "$cleanup_started"; then
    status "POZOR: cleanup nebyl potvrzen; netvrdím, že testovací aktivity zmizely."
  fi
  terminate_iphone_app
  terminate_watch_app
  /bin/rm -rf "$DERIVED"
  if restore_normal_build; then
    cleanup_test_artifacts
    fail "$reason Normální Commander byl automaticky obnoven."
  fi
  cleanup_test_artifacts
  fail "$reason Navíc se nepodařilo automaticky obnovit normální build."
}

mkdir -p "$RESULTS"
: > "$LOG"

if [[ "$MODE" != "--doctor" && "$MODE" != "--capture-watch" ]]; then
  acquire_lock
fi

case "$MODE" in
  --doctor)
    status "=== Commander acceptance doctor ==="
    status "Repo: $REPO_ROOT"
    status "Branch: $(/usr/bin/git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
    status "HEAD: $(/usr/bin/git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
    status "Volné místo: $(free_gb) GB"
    /usr/bin/xcrun devicectl list devices | /usr/bin/grep -E "$IPHONE_UDID|$WATCH_UDID" || true
    exit 0
    ;;

  --capture-watch)
    mkdir -p "$RESULTS"
    status "Fotím aktuální obrazovku Watch po klepnutí na Live Activity…"
    watch_handshake || true
    capture_optional "$WATCH_UDID" "$RESULTS/watch-opened.png"
    [[ -f "$RESULTS/watch-opened.png" ]] ||
      fail "Watch screenshot se nepodařilo zachytit."
    status "Watch detail uložen: $RESULTS/watch-opened.png"
    exit 0
    ;;

  --service)
    status "Provádím bezpečný servis Commander testovacích artefaktů…"
    cleanup_test_artifacts
    status "Servis dokončen. Volné místo: $(free_gb) GB"
    exit 0
    ;;

  --cleanup)
    status "Uklízím integrovaný acceptance test…"
    wait_for_iphone_unlock ||
      fail "iPhone zůstal zamčený. Odemkni ho; cleanup pak lze spustit znovu."
    launch_watch_companion || true
    /bin/sleep 2
    CLEANUP_STARTED="$(/bin/date '+%s')"
    if launch_iphone_mode "--acceptance-cleanup" && wait_for_cleanup_success "$CLEANUP_STARTED"; then
      terminate_iphone_app
      status "Testovací alarmy, Live Activity a Watch snapshot byly uklizeny."
    else
      fail "Commander se nepodařilo spustit v cleanup režimu."
    fi
    cleanup_test_artifacts
    restore_normal_build ||
      fail "Acceptance stav je uklizený, ale normální Commander se nepodařilo obnovit."
    cleanup_test_artifacts
    status "Volné místo po úklidu: $(free_gb) GB"
    exit 0
    ;;

  --build-normal)
    build_normal_pair || fail "Normální podepsaný build selhal."
    exit 0
    ;;
  --install-normal)
    restore_normal_build || fail "Normální iPhone + Watch sestava nebyla kompletně nainstalována."
    exit 0
    ;;
  --run) ;;
  *) fail "Neznámý režim; použij --help." ;;
esac
status "=== Integrovaný Commander acceptance test ==="
status "Branch: $(/usr/bin/git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
status "HEAD: $(/usr/bin/git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
/usr/bin/git -C "$REPO_ROOT" status --short >> "$LOG" 2>&1 || true

cleanup_test_artifacts
# Keep this run's log and all prior evidence.

FREE="$(free_gb)"
status "Volné místo před buildem: $FREE GB"
if [[ ! "$FREE" =~ ^[0-9]+$ || "$FREE" -lt 12 ]]; then
  fail "Po bezpečném úklidu je stále méně než 12 GB volného místa."
fi

[[ -d "$PROJECT" ]] || fail "Chybí Xcode projekt."
/usr/bin/xcodebuild -version >> "$LOG" 2>&1 || fail "Xcode není připravený."

# Build je záměrně nezávislý na okamžité dostupnosti zařízení.
# iPhone se ověří až před instalací a Watch skutečným CoreDevice handshakem.
BUILD_NUMBER="$(/bin/date '+%y%m%d%H%M')"
BUILD_BRANCH="$(/usr/bin/git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
BUILD_COMMIT="$(/usr/bin/git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$BUILD_BRANCH" && "$BUILD_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
  fail "Nelze určit identitu aktuálního worktree."
status "Sestavuji plný Commander s injektovaným rozpisem z $BUILD_BRANCH @ ${BUILD_COMMIT:0:8}, build ${BUILD_NUMBER}…"

/usr/bin/xcodebuild -quiet   -project "$PROJECT"   -scheme LazenskyCommanderApp   -configuration Debug   -destination "generic/platform=iOS"   -derivedDataPath "$DERIVED"   -allowProvisioningUpdates   CURRENT_PROJECT_VERSION="$BUILD_NUMBER"   LC_BUILD_BRANCH="$BUILD_BRANCH"   LC_BUILD_COMMIT="$BUILD_COMMIT"   COMPILER_INDEX_STORE_ENABLE=NO   'OTHER_SWIFT_FLAGS=$(inherited) -DCOMMANDER_ACCEPTANCE_FIXTURES'   build >> "$LOG" 2>&1 || {
    /usr/bin/tail -100 "$LOG"
    fail "Podepsaný iPhone+Watch build selhal."
  }

IPHONE_APP="$DERIVED/Build/Products/Debug-iphoneos/LazenskyCommanderApp.app"
WATCH_APP="$DERIVED/Build/Products/Debug-watchos/LazenskyCommanderWatchApp.app"
[[ -d "$IPHONE_APP" ]] || fail "Chybí sestavená iPhone aplikace."
[[ -d "$WATCH_APP" ]] || fail "Chybí sestavená Watch aplikace."

wait_for_iphone_unlock ||
  fail "iPhone zůstal zamčený po buildu. Odemkni ho a skript bude pokračovat."
status "Instaluji iPhone Commander…"
/usr/bin/xcrun devicectl device install app --device "$IPHONE_UDID" --timeout 60 "$IPHONE_APP" >> "$LOG" 2>&1 ||
  fail "Instalace iPhone aplikace selhala."

watch_install_with_retry "$WATCH_APP" ||
  fail "Watch app se nepodařilo nainstalovat ani po čtyřech handshacích."

wait_for_iphone_unlock ||
  fail "iPhone zůstal zamčený po buildu. Odemkni ho a spusť test znovu."
status "Aktivuji skutečnou Watch app kvůli potvrzení WatchConnectivity…"
launch_watch_companion || fail "Watch app se nepodařilo spustit pro acceptance handshake."
/bin/sleep 2

status "Nejdřív uklízím případný starý acceptance stav…"
CLEANUP_STARTED="$(/bin/date '+%s')"
launch_iphone_mode "--acceptance-cleanup" || abort_acceptance_run "Cleanup před testem selhal."
wait_for_cleanup_success "$CLEANUP_STARTED" || abort_acceptance_run "Watch cleanup nebyl potvrzen."

wait_for_iphone_unlock ||
  fail "iPhone se před ostrým acceptance během znovu zamkl."
status "Spouštím společný Live Activity + Watch acceptance stav…"
ACCEPTANCE_LAUNCHED_EPOCH="$(/bin/date '+%s')"
launch_iphone_mode "--acceptance-visual" || abort_acceptance_run "Acceptance režim se nespustil."

if ! wait_for_acceptance_success "$ACCEPTANCE_LAUNCHED_EPOCH"; then
  abort_acceptance_run "Watch nepotvrdily stejný acceptance stav jako iPhone."
fi

# Watch potvrdily canonical projekci skutečně uloženou ve společné app/widget cache.
capture_optional "$WATCH_UDID" "$RESULTS/watch-handshake.png"
terminate_watch_app
terminate_iphone_app

# Krátký odstup před read-backem produkčního activity plánu.
# Jeho skutečný stav se ověří v aplikaci, nikoli odhadem z času.
wait_until_epoch "$((ACCEPTANCE_LAUNCHED_EPOCH + 23))"

ACTIVITY_READBACK_EPOCH="$(/bin/date '+%s')"
launch_iphone_mode "--acceptance-readback" || abort_acceptance_run "ActivityKit read-back se nespustil."
wait_for_activity_active "$ACTIVITY_READBACK_EPOCH" || abort_acceptance_run "Naplánovaná iPhone Live Activity nepřešla do active."
terminate_iphone_app
/bin/sleep 1

capture_optional "$IPHONE_UDID" "$RESULTS/iphone-expanded.png"
/bin/sleep 4
capture_optional "$IPHONE_UDID" "$RESULTS/iphone-compact.png"
capture_optional "$WATCH_UDID" "$RESULTS/watch-summary.png"

{
  printf 'branch=%s\n' "$(/usr/bin/git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
  printf 'head=%s\n' "$(/usr/bin/git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
  printf 'build=%s\n' "$BUILD_NUMBER"
  printf 'iphone=%s\n' "$IPHONE_UDID"
  printf 'watch=%s\n' "$WATCH_UDID"
} > "$RESULTS/manifest.txt"

/bin/rm -rf "$DERIVED"
status "Build artefakty po instalaci odstraněny."
status "Volné místo: $(free_gb) GB"
status "TEST BĚŽÍ."
status "Výstupy: $RESULTS"
status "Teď ověř Lock Screen, Dynamic Island, alarmy a Watch app/widget během celého 24minutového rozpisu."
status "Po klepnutí na Watch kartu použij --capture-watch."
status "Po skončení použij --cleanup; ten vrátí normální iPhone + Watch build a smaže testovací buildy."
