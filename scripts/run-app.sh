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

# Install to /Applications, or ~/Applications when /Applications is not writable.
INSTALL_DIR="/Applications"
if [[ ! -w "$INSTALL_DIR" ]]; then
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
fi
INSTALL_PATH="$INSTALL_DIR/$APPNAME.app"

pkill -x "$APPNAME" 2>/dev/null || true
rm -rf "$INSTALL_PATH"
ditto "$BUNDLE_PATH" "$INSTALL_PATH"
open "$INSTALL_PATH"
printf 'Installed %s\n' "$INSTALL_PATH"

# SwiftPM's .build grows to several GB; drop it and the staged bundle once installed.
# KEEP_BUILD=1 keeps them for faster incremental rebuilds.
if [[ "${KEEP_BUILD:-0}" != "1" ]]; then
    rm -rf "$ROOT_DIR/.build" "$BUNDLE_PATH"
    printf 'Removed build artifacts (set KEEP_BUILD=1 to keep them)\n'
fi

printf "Tail logs with: log stream --predicate 'subsystem == \"%s\"'\n" "$BUNDLE_ID"
