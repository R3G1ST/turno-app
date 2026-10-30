#!/bin/bash
# Собирает Turno.app из исходников (Release).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Turno.app"

echo "==> swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/Turno"

echo "==> собираем $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Turno"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/Turno.icns" ] && cp "$ROOT/Resources/Turno.icns" "$APP/Contents/Resources/"

echo "==> ad-hoc подпись"
codesign --force --deep --sign - "$APP"

echo "==> готово: $APP"
