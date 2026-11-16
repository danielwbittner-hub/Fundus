#!/bin/bash
# Fundus als verteilbare .app bauen und als .dmg packen.
# Doppelklick im Finder genügt – oder im Terminal ausführen.
# Ergebnis: dist/Fundus-<Version>.dmg (universal arm64+x86_64).
#
# SIGNIEREN (automatisch erkannt):
#   • Liegt ein "Developer ID Application"-Zertifikat im Schlüsselbund,
#     wird damit signiert (Hardened Runtime + sicherer Zeitstempel).
#   • Sonst Fallback: ad-hoc ("-") – dann meldet Gatekeeper beim ERSTEN
#     Start "nicht verifiziert" (Rechtsklick → Öffnen → Öffnen).
#
# NOTARISIEREN (automatisch, wenn eingerichtet):
#   • Ist ein notarytool-Profil vorhanden (Standard: "fundus-notar"),
#     wird die DMG bei Apple geprüft und das Ticket angeheftet.
#     Danach startet die App auf JEDEM Mac ohne Warnung.
#   • Profil einmalig anlegen (App-spezifisches Passwort von appleid.apple.com):
#       xcrun notarytool store-credentials "fundus-notar" \
#         --apple-id "DEINE-APPLE-ID" --team-id UP525XB6FJ --password "xxxx-xxxx-xxxx-xxxx"
#   • Anderes Profil: Umgebungsvariable FUNDUS_NOTAR_PROFILE setzen.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Projekt aus project.yml erzeugen (falls xcodegen da ist)
command -v xcodegen >/dev/null && xcodegen

BUILD="./build"
STAGE="./build/dmg-stage"
APP="$BUILD/Build/Products/Release/Fundus.app"

# Developer-ID-Signatur automatisch finden
DEVID=$(security find-identity -v -p codesigning \
  | awk -F\" '/Developer ID Application/{print $2; exit}')
NOTARPROFILE="${FUNDUS_NOTAR_PROFILE:-fundus-notar}"

echo "### 1/4  Release-Build (universal) ###"
xcodebuild -scheme Fundus -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build | tail -3

echo "### 2/4  signieren ###"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Fundus.app"
if [ -n "$DEVID" ]; then
  echo "    Developer ID → $DEVID"
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVID" "$STAGE/Fundus.app"
else
  echo "    (kein Developer-ID-Zertifikat gefunden → ad-hoc)"
  codesign --force --deep --sign - "$STAGE/Fundus.app"
fi
codesign --verify --verbose=1 "$STAGE/Fundus.app"

echo "### 3/4  DMG packen ###"
ln -s /Applications "$STAGE/Applications"
VER=$(/usr/bin/defaults read "$PWD/$STAGE/Fundus.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 1.0)
mkdir -p dist
DMG="dist/Fundus-$VER.dmg"
rm -f "$DMG"
hdiutil create -volname "Fundus" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "### 4/4  notarisieren ###"
if [ -z "$DEVID" ]; then
  echo "    übersprungen – ohne Developer-ID-Signatur nicht möglich."
elif xcrun notarytool history --keychain-profile "$NOTARPROFILE" >/dev/null 2>&1; then
  echo "    lade zu Apple hoch (kann 1–3 Min dauern) …"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARPROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "    notarisiert + angeheftet ✓  (startet überall ohne Warnung)"
else
  echo "    kein notarytool-Profil \"$NOTARPROFILE\" → DMG ist signiert, aber NICHT notarisiert."
  echo "    (fremde Macs zeigen weiter die Warnung – einmalig einrichten:)"
  echo "      xcrun notarytool store-credentials \"$NOTARPROFILE\" \\"
  echo "        --apple-id \"DEINE-APPLE-ID\" --team-id UP525XB6FJ --password \"xxxx-xxxx-xxxx-xxxx\""
fi

echo
echo "FERTIG → $DMG"
ls -lh "$DMG" | awk '{print "   Größe:", $5}'
xcrun stapler validate "$DMG" 2>&1 | sed 's/^/   /' || true
