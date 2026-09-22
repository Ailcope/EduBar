#!/bin/sh
# Construit dist/EduBar.app (signature ad-hoc), dist/EduBar-<version>.zip et dist/EduBar-<version>.dmg.
# Usage : scripts/bundle.sh [version]   (défaut : 0.1.0)
set -eu

VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/EduBar.app"

cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/EduBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EduBar"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

rm -f "$ROOT/dist/EduBar-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/EduBar-$VERSION.zip"

# DMG : l'app + un raccourci vers /Applications pour le glisser-déposer.
DMG="$ROOT/dist/EduBar-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "EduBar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"

echo "OK : $APP"
echo "OK : $ROOT/dist/EduBar-$VERSION.zip"
echo "OK : $DMG"
