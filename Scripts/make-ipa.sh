#!/bin/zsh
# Сборка IPA для GBox/ESign: релизная сборка без подписи, Info.plist → XML
# (подписывающие инструменты на телефоне не читают бинарный plist и выдают
# "unable to locate info.plist inside app bundle"), без xattr/ресурс-форков.
set -e
cd "$(dirname "$0")/.."

SYM=/tmp/turno-ipa-build
rm -rf "$SYM"
xcodebuild -project Turno.xcodeproj -target Turno -configuration Release -sdk iphoneos build \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    OTHER_LDFLAGS="-Wl,-no_fixup_chains" \
    SYMROOT="$SYM" | grep -E "error:|BUILD" | tail -3

APP="$SYM/Release-iphoneos/Turno.app"
VER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")

# XML вместо бинарного plist + снятие системных атрибутов (иначе zip кладёт мусор)
plutil -convert xml1 "$APP/Info.plist"
xattr -cr "$APP" 2>/dev/null || true

STAGE=$(mktemp -d)
mkdir "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
(cd "$STAGE" && zip -qry Turno.ipa Payload)

OUT="Turno-$VER.ipa"
cp "$STAGE/Turno.ipa" "$OUT"
cp "$STAGE/Turno.ipa" "$HOME/Desktop/$OUT"
rm -rf "$STAGE"
echo "==> готово: $OUT (и копия на Рабочем столе)"
