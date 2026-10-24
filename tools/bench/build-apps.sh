#!/bin/sh
# Builds the two apps the Yap Instruments bench compares (bench/yap-instruments.md):
#   build/bench/YapCairn.app   CairnYap from this tree, release (as `make yap`), ad hoc signed
#                              with get-task-allow, bundle id dev.yap.cairn.bench
#   build/bench/YapRef.app     the original Yap at $YAP_REF_COMMIT, cloned from $YAP_SRC to
#                              /tmp/yap-ref, tools/bench/yap-ref.patch applied (its bench mode),
#                              Release, like for like with CairnYap's release build
#   build/bench/YapRef-Debug.app  the same, Debug, as the original's Makefile builds the app
#                              people run (Yap.debug.dylib); skip with CONFIGS=Release
# The original's repository is only read (git clone); it is never modified.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
YAP_SRC=${YAP_SRC:-$HOME/code/yap}
YAP_REF_COMMIT=${YAP_REF_COMMIT:-96ab494}
CONFIGS=${CONFIGS:-Release Debug}
OUT=build/bench
mkdir -p "$OUT"

# Cairn
export PATH="$HOME/.elan/bin:$PATH"
make lean >/dev/null
(cd host && swift build -c release --product CairnYap 2>&1 | grep -E "error|Compiling|Build" | tail -3)
BIN=$(cd host && swift build -c release --show-bin-path)
APP="$OUT/YapCairn.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/CairnYap" "$APP/Contents/MacOS/CairnYap"
cp host/Bundles/Yap/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string dev.yap.cairn.bench "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string YapCairn "$APP/Contents/Info.plist"
codesign --force --entitlements tools/bench/bench.entitlements -s - "$APP"
echo "built $APP"

# The original, in a copy
REF=/tmp/yap-ref
rm -rf "$REF"
git clone -q "$YAP_SRC" "$REF"
git -C "$REF" checkout -q "$YAP_REF_COMMIT"
git -C "$REF" apply "$ROOT/tools/bench/yap-ref.patch"
(cd "$REF" && xcodegen generate --quiet)
for CONFIG in $CONFIGS; do
	(cd "$REF" && xcodebuild -project Yap.xcodeproj -scheme Yap -configuration "$CONFIG" \
		-destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode -quiet build 2>&1 | grep -E "error" || true)
	NAME=YapRef.app
	[ "$CONFIG" = Release ] || NAME=YapRef-$CONFIG.app
	rm -rf "$OUT/$NAME"
	cp -R "$REF/.build/xcode/Build/Products/$CONFIG/YapRef.app" "$OUT/$NAME"
	# get-task-allow, as CairnYap, so Instruments may attach to either without root
	codesign --force --deep --entitlements tools/bench/bench.entitlements -s - "$OUT/$NAME"
	echo "built $OUT/$NAME ($CONFIG, $(git -C "$REF" rev-parse --short HEAD) + yap-ref.patch)"
done
