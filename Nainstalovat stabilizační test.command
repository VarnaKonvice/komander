#!/bin/bash

set -u
set -o pipefail
umask 077

TARGET_BRANCH="lc/native-stabilization-v2"
EXPECTED_REPOSITORY="VarnaKonvice/komander"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"
REFRESH_TOOL="$REPO_ROOT/Obnovit Lázeňský Commander.command"
TEMP_XCCONFIG=""

cleanup() {
  if [[ -n "$TEMP_XCCONFIG" && -f "$TEMP_XCCONFIG" ]]; then
    /bin/rm -f "$TEMP_XCCONFIG"
  fi
}
trap cleanup EXIT INT TERM

fail() {
  printf 'CHYBA: %s\n' "$1"
  exit 1
}

if [[ ! -x /usr/bin/git || ! -d "$REPO_ROOT/.git" && ! -f "$REPO_ROOT/.git" ]]; then
  fail "Spouštěč není v repozitáři Lázeňského Commanderu."
fi
if [[ ! -x "$REFRESH_TOOL" ]]; then
  fail "Chybí běžný nástroj Obnovit Lázeňský Commander.command."
fi

ORIGIN_URL="$(/usr/bin/git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
case "$ORIGIN_URL" in
  "https://github.com/$EXPECTED_REPOSITORY"|"https://github.com/$EXPECTED_REPOSITORY.git"|"git@github.com:$EXPECTED_REPOSITORY.git"|"ssh://git@github.com/$EXPECTED_REPOSITORY.git") ;;
  *) fail "Git origin neukazuje na ověřený repozitář VarnaKonvice/komander." ;;
esac

printf 'Připravuji přesnou stabilizační verzi z GitHubu...\n'
if ! /usr/bin/git -C "$REPO_ROOT" fetch --quiet --no-tags origin \
  "+refs/heads/$TARGET_BRANCH:refs/remotes/origin/$TARGET_BRANCH"; then
  fail "Stabilizační větev se nepodařilo stáhnout."
fi

REMOTE_COMMIT="$(/usr/bin/git -C "$REPO_ROOT" rev-parse --verify "refs/remotes/origin/$TARGET_BRANCH^{commit}" 2>/dev/null || true)"
if [[ ! "$REMOTE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  fail "Nelze určit přesný commit stabilizační větve."
fi
REMOTE_COMMIT_SHORT="${REMOTE_COMMIT:0:8}"

TEMP_XCCONFIG="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lazensky-commander-build-identity.XXXXXX")" || fail "Nelze připravit identitu sestavy."
{
  printf 'LC_BUILD_BRANCH = %s\n' "$TARGET_BRANCH"
  printf 'LC_BUILD_COMMIT = %s\n' "$REMOTE_COMMIT"
} > "$TEMP_XCCONFIG"

printf 'Instaluji: %s @ %s\n' "$TARGET_BRANCH" "$REMOTE_COMMIT_SHORT"
printf 'Po instalaci musí stejná identita být vidět v Commanderu v Diagnostice.\n\n'

XCODE_XCCONFIG_FILE="$TEMP_XCCONFIG" \
LC_REFRESH_TARGET_BRANCH="$TARGET_BRANCH" \
"$REFRESH_TOOL"
RESULT=$?

if [[ "$RESULT" -ne 0 ]]; then
  exit "$RESULT"
fi

printf '\nHOTOVO – očekávaná identita v Diagnostice: %s @ %s\n' "$TARGET_BRANCH" "$REMOTE_COMMIT_SHORT"
printf 'Pokud Diagnostika ukáže jinou identitu nebo že identita není vložena, fyzický test nezačínej.\n'
