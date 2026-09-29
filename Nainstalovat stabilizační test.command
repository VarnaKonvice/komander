#!/bin/bash
# Compatibility entry only. One acceptance owner; no branch selection or fetch.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
exec /bin/bash "$SCRIPT_DIR/Otestovat Lázeňský Commander.command" "$@"
