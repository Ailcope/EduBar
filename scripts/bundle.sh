#!/bin/sh
# Construit dist/EduBar.app (signature ad-hoc), dist/EduBar-<version>.zip, sa signature de publication
# dist/EduBar-<version>.zip.sig (si la clé existe) et dist/EduBar-<version>.dmg.
# Usage : scripts/bundle.sh [version]   (défaut : 0.1.0)
# Clé de signature : ~/.config/edubar/release-signing.key, ou EDUBAR_SIGNING_KEY (scripts/sign-release.swift).
# Code de sortie non nul, fichiers produits quand même, si le zip n'est pas signé ou si la clé qui signe
# n'est pas celle épinglée dans Update.swift : une telle version ne doit pas être publiée.
set -eu

VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/EduBar.app"

cd "$ROOT"
swift build -c release -Xswiftc -Osize --arch arm64 --arch x86_64
BIN="$(swift build -c release -Xswiftc -Osize --arch arm64 --arch x86_64 --show-bin-path)/EduBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$ROOT/dist"
# Copie non strippée gardée hors de l'app, du zip et du dmg (pour symboliser les rapports de plantage).
cp "$BIN" "$ROOT/dist/EduBar-$VERSION.symbols"
cp "$BIN" "$APP/Contents/MacOS/EduBar"
# Strip avant la signature (le faire après la casserait).
strip -x "$APP/Contents/MacOS/EduBar"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

ZIP="$ROOT/dist/EduBar-$VERSION.zip"
SIG="$ZIP.sig"
DMG="$ROOT/dist/EduBar-$VERSION.dmg"
# Tout de suite : un arrêt en cours de route ne doit pas laisser un ancien dmg à côté d'un zip neuf.
rm -f "$ZIP" "$SIG" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

# Signature de publication du zip : sans elle, les apps installées refusent la mise à jour.
KEY="${EDUBAR_SIGNING_KEY:-$HOME/.config/edubar/release-signing.key}"
SIGNED=0
if [ -f "$KEY" ]; then
  EDUBAR_SIGNING_KEY="$KEY" swift scripts/sign-release.swift sign "$ZIP" > /dev/null
  SIGNED=1
fi

# DMG : l'app + un raccourci vers /Applications pour le glisser-déposer.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "EduBar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"

echo "OK : $APP"
echo "OK : $ZIP"
if [ "$SIGNED" = 1 ]; then echo "OK : $SIG"; fi
echo "OK : $DMG"

STATUS=0
PINNED="$(sed -n 's/.*releasePublicKey = "\([^"]*\)".*/\1/p' Sources/EduBarCore/Update.swift)"
if [ "$SIGNED" != 1 ]; then
  echo "" >&2
  echo "!!! ATTENTION : zip NON signé : les apps installées refuseront cette mise à jour." >&2
  echo "!!! Aucune clé dans $KEY (docs/deploiement.md, « Publication d'une release »)." >&2
  STATUS=1
elif [ -z "$PINNED" ] || [ "$(EDUBAR_SIGNING_KEY="$KEY" swift scripts/sign-release.swift pubkey)" != "$PINNED" ]; then
  echo "" >&2
  echo "!!! ATTENTION : la clé qui signe n'est pas celle épinglée dans Sources/EduBarCore/Update.swift." >&2
  echo "!!! Cette version ne pourrait plus se mettre à jour toute seule : ne pas la publier." >&2
  STATUS=1
fi
exit "$STATUS"
