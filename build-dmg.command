#!/bin/bash
# Fundus als verteilbare .app bauen und als .dmg packen.
# Doppelklick im Finder genügt – oder im Terminal ausführen.
# Ergebnis: dist/Fundus-<Version>.dmg (universal, ad-hoc signiert).
#
# Mit freier Apple-ID signiert → Gatekeeper meldet beim ERSTEN Start
# "nicht verifiziert": Rechtsklick auf Fundus → Öffnen → Öffnen (danach nie wieder).
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Projekt aus project.yml erzeugen (falls xcodegen da ist)
command -v xcodegen >/dev/null && xcodegen

BUILD="./build"
STAGE="./build/dmg-stage"
APP="$BUILD/Build/Products/Release/Fundus.app"

echo "### 1/3  Release-Build (universal) ###"
xcodebuild -scheme Fundus -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build | tail -3

echo "### 2/3  ad-hoc signieren ###"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Fundus.app"
codesign --force --deep --sign - "$STAGE/Fundus.app"
codesign --verify --verbose=1 "$STAGE/Fundus.app"

echo "### 3/3  DMG packen ###"
ln -s /Applications "$STAGE/Applications"
VER=$(/usr/bin/defaults read "$PWD/$STAGE/Fundus.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 1.0)
mkdir -p dist
DMG="dist/Fundus-$VER.dmg"
rm -f "$DMG"
hdiutil create -volname "Fundus" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo
echo "FERTIG → $DMG"
ls -lh "$DMG" | awk '{print "   Größe:", $5}'
