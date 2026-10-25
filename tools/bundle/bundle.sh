#!/bin/sh
# Wraps an app's host executable in an .app bundle.
#
#   make bundle APP=<App> [NAME=<name>]   Cairn's examples: Cairn<App> into build/apps/<name>.app
#   cairn bundle                          an app package's executable (docs/cli.md)
#
# bundle.sh <App> <bin dir> [<sign identity>] [<name>], with, from the environment:
#   EXE      the executable's name in <bin dir> (default Cairn<App>)
#   HOOK     the per-app folder (default host/Bundles/<App>):
#              Info.plist          used as the bundle's Info.plist (CFBundleExecutable is set to
#                                  EXE); without one, a minimal plist is written. An accessory app
#                                  (no window) sets LSUIElement there (docs/surfaces.md).
#              entitlements.plist  signed in with the hardened runtime (e.g. Yap's audio input).
#   OUT_DIR  where <name>.app goes (default build/apps)
#   ID       the bundle id of a generated plist (default dev.cairn.<app>)
#
# The SwiftPM resource bundles the executable uses (<package>_<target>.bundle in <bin dir>, the
# ones whose name the executable's `Bundle.module` accessor holds) are copied into
# Contents/Resources, where that accessor looks first in an app.
#
# The sign identity's default `-` signs ad hoc, which is not a stable signature (TCC grants such
# as the microphone's don't survive a rebuild). Pass a real identity for that.
set -eu
APP=$1; BIN=$2; SIGN=${3:--}; NAME=${4:-$APP}
EXE=${EXE:-Cairn$APP}
HOOK=${HOOK:-host/Bundles/$APP}
OUT_DIR=${OUT_DIR:-build/apps}
ID=${ID:-dev.cairn.$(echo "$APP" | tr '[:upper:]' '[:lower:]')}
OUT="$OUT_DIR/$NAME.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN/$EXE" "$OUT/Contents/MacOS/$EXE"
for b in "$BIN"/*.bundle; do
	[ -d "$b" ] || continue
	name=$(basename "$b" .bundle)
	if LC_ALL=C grep -q -a -F "$name" "$BIN/$EXE"; then
		cp -R "$b" "$OUT/Contents/Resources/"
		echo "bundle: resources $name.bundle"
	fi
done
if [ -f "$HOOK/Info.plist" ]; then
	cp "$HOOK/Info.plist" "$OUT/Contents/Info.plist"
else
	cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleIdentifier</key><string>$ID</string>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
fi
plutil -replace CFBundleExecutable -string "$EXE" "$OUT/Contents/Info.plist"
plutil -lint -s "$OUT/Contents/Info.plist"
if [ -f "$HOOK/entitlements.plist" ]; then
	codesign --force --options runtime --entitlements "$HOOK/entitlements.plist" -s "$SIGN" "$OUT"
else
	codesign --force -s "$SIGN" "$OUT"
fi
codesign --verify --strict "$OUT"
echo "bundle: $OUT ($( [ "$SIGN" = "-" ] && echo "signed ad hoc" || echo "signed by $SIGN"))"
