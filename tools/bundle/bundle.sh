#!/bin/sh
# make bundle APP=<App> [NAME=<name>]: wraps the host executable Cairn<App> in
# build/apps/<name>.app (<App>.app by default).
#
# The per-app hook is host/Bundles/<App>/:
#   Info.plist          used as the bundle's Info.plist (CFBundleExecutable is set to Cairn<App>);
#                       without one, a minimal plist is written. An accessory app (no window)
#                       sets LSUIElement there (docs/surfaces.md, "Accessory apps").
#   entitlements.plist  signed in with the hardened runtime (e.g. Yap's audio input).
# SIGN is the codesign identity; the default `-` signs ad hoc, which is not a stable signature
# (TCC grants such as the microphone's don't survive a rebuild). Pass a real identity for that.
set -eu
APP=$1; BIN=$2; SIGN=${3:--}; NAME=${4:-$APP}
HOOK=host/Bundles/$APP
OUT="build/apps/$NAME.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
cp "$BIN/Cairn$APP" "$OUT/Contents/MacOS/Cairn$APP"
if [ -f "$HOOK/Info.plist" ]; then
	cp "$HOOK/Info.plist" "$OUT/Contents/Info.plist"
else
	cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleIdentifier</key><string>dev.cairn.$(echo "$APP" | tr '[:upper:]' '[:lower:]')</string>
	<key>CFBundleName</key><string>$APP</string>
	<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
fi
plutil -replace CFBundleExecutable -string "Cairn$APP" "$OUT/Contents/Info.plist"
plutil -lint -s "$OUT/Contents/Info.plist"
if [ -f "$HOOK/entitlements.plist" ]; then
	codesign --force --options runtime --entitlements "$HOOK/entitlements.plist" -s "$SIGN" "$OUT"
else
	codesign --force -s "$SIGN" "$OUT"
fi
echo "bundle: $OUT"
