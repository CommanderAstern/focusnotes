#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/build-app.sh" "${1:-debug}"
while IFS='=' read -r key value; do
    case "$key" in
        APPNAME) APPNAME="$value" ;;
        BUNDLE_PREFIX) BUNDLE_PREFIX="$value" ;;
    esac
done < "$ROOT_DIR/Config/app.env"

APPNAME_LOWER="$(printf '%s' "$APPNAME" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9-]/-/g')"
BUNDLE_ID="$BUNDLE_PREFIX.$APPNAME_LOWER"
BUNDLE_PATH="$ROOT_DIR/build/$APPNAME.app"

pkill -x "$APPNAME" 2>/dev/null || true
open "$BUNDLE_PATH"
printf "Tail logs with: log stream --predicate 'subsystem == \"%s\"'\n" "$BUNDLE_ID"
