#!/bin/bash
#
# Packages a built Chronos.app into a compressed disk image with the usual
# drag-to-Applications layout. No create-dmg dependency: hdiutil is enough.
#
#   Scripts/make-dmg.sh /path/to/Chronos.app dist/Chronos-v0.1.0.dmg
#
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $(basename "$0") <path/to/Chronos.app> <path/to/output.dmg>" >&2
    exit 2
fi

APP_PATH="$1"
DMG_PATH="$2"
VOLUME_NAME="Chronos"

if [ ! -d "$APP_PATH" ]; then
    echo "error: no app bundle at $APP_PATH" >&2
    exit 1
fi

mkdir -p "$(dirname "$DMG_PATH")"

# Stage the contents of the image: the app plus a symlink people can drag it
# onto. The staging folder is temporary and is removed however this exits.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "Created $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
