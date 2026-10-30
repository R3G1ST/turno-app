#!/bin/bash
# Создаёт Turno-<версия>.dmg: классический установщик — Turno.app + ссылка на Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Turno.app"
STAGE="$ROOT/build/dmg-stage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/Turno-$VERSION.dmg"

[ -d "$APP" ] || { echo "Сначала Scripts/build-app.sh"; exit 1; }

echo "==> подготовка сцены"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> создание DMG"
hdiutil create -volname "Turno $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> готово: $DMG"
