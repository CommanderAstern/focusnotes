#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [debug|release]\n' "$0" >&2
    exit 2
fi

CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in
    debug|release) ;;
    *)
        printf 'Invalid configuration: %s (expected debug or release)\n' "$CONFIGURATION" >&2
        exit 2
        ;;
esac

while IFS='=' read -r key value; do
    case "$key" in
        APPNAME) APPNAME="$value" ;;
        BUNDLE_PREFIX) BUNDLE_PREFIX="$value" ;;
        VERSION) VERSION="$value" ;;
        BUILD) BUILD="$value" ;;
        MIN_MACOS) MIN_MACOS="$value" ;;
    esac
done < "$ROOT_DIR/Config/app.env"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

APPNAME_LOWER="$(printf '%s' "$APPNAME" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9-]/-/g')"
BUNDLE_ID="$BUNDLE_PREFIX.$APPNAME_LOWER"
BUNDLE_PATH="$ROOT_DIR/build/$APPNAME.app"
CONTENTS_PATH="$BUNDLE_PATH/Contents"
PLIST_PATH="$CONTENTS_PATH/Info.plist"

python3 - "$BUNDLE_PATH" <<'PY'
from pathlib import Path
import shutil
import sys

bundle = Path(sys.argv[1])
if bundle.is_symlink() or bundle.is_file():
    bundle.unlink()
elif bundle.exists():
    shutil.rmtree(bundle)
PY

mkdir -p "$CONTENTS_PATH/MacOS"
cp "$BIN_DIR/App" "$CONTENTS_PATH/MacOS/$APPNAME"
chmod 755 "$CONTENTS_PATH/MacOS/$APPNAME"
cp "$BIN_DIR/EmbedHelper" "$CONTENTS_PATH/MacOS/EmbedHelper"
chmod 755 "$CONTENTS_PATH/MacOS/EmbedHelper"

plutil -create xml1 "$PLIST_PATH"
plutil -insert CFBundleName -string "$APPNAME" "$PLIST_PATH"
plutil -insert CFBundleDisplayName -string "$APPNAME" "$PLIST_PATH"
plutil -insert CFBundleExecutable -string "$APPNAME" "$PLIST_PATH"
plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST_PATH"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST_PATH"
plutil -insert CFBundleVersion -string "$BUILD" "$PLIST_PATH"
plutil -insert LSMinimumSystemVersion -string "$MIN_MACOS" "$PLIST_PATH"
plutil -insert LSUIElement -bool true "$PLIST_PATH"
plutil -insert NSHighResolutionCapable -bool true "$PLIST_PATH"
plutil -insert CFBundlePackageType -string APPL "$PLIST_PATH"

# Local stable dev identity (see README) keeps macOS privacy permissions across rebuilds.
DEV_SIGNING_DIR="$HOME/.config/local-dev-signing"
DEV_KEYCHAIN="$DEV_SIGNING_DIR/dev-signing.keychain-db"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$CONTENTS_PATH/MacOS/EmbedHelper"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$BUNDLE_PATH"
elif [[ -f "$DEV_KEYCHAIN" && -f "$DEV_SIGNING_DIR/keychain.pass" ]]; then
    security unlock-keychain -p "$(cat "$DEV_SIGNING_DIR/keychain.pass")" "$DEV_KEYCHAIN"
    codesign --force --sign "Local Dev Code Signing" --keychain "$DEV_KEYCHAIN" --timestamp=none "$CONTENTS_PATH/MacOS/EmbedHelper"
    codesign --force --sign "Local Dev Code Signing" --keychain "$DEV_KEYCHAIN" --timestamp=none "$BUNDLE_PATH"
else
    codesign --force --sign - --timestamp=none "$CONTENTS_PATH/MacOS/EmbedHelper"
    codesign --force --sign - --timestamp=none "$BUNDLE_PATH"
fi

printf '%s\n' "$BUNDLE_PATH"
