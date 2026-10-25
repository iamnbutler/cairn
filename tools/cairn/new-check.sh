#!/bin/sh
# new-check.sh: `cairn new --bin` makes an app that builds, links and runs (docs/cli.md).
#
#   tools/cairn/new-check.sh [--keep]
#
# Builds the `cairn` CLI and runs its unit tests, makes a new app `demo_app` in a temporary
# directory, points its Lean require and its SwiftPM dependency at this checkout (by path, so it
# tests this tree, not a release), then runs `cairn build`, the app's `--selftest` (headless:
# the Lean side starts, a press on ^2 counts) and the ledger on the template's claims. Then it
# adds a second app, `Second` (its claims ^3 and ^4), to the same package and checks that
# `cairn build` asks which, and that `cairn build --app <App>` links and runs each (cairn#173,
# docs/cli.md, "Several apps"). The name has an underscore so the C declaration of the app's initializer is checked against Lean's
# mangling. `make new-check` runs it, and `make check` runs that. --keep leaves the app behind.
set -eu

repo=$(cd "$(dirname "$0")/../.." && pwd -P)
export PATH="$HOME/.elan/bin:$PATH"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/cairn-new-check.XXXXXX")
[ "${1:-}" = --keep ] || trap 'rm -rf "$tmp"' EXIT

(cd "$repo/tools/cairn" && swift build -c release -q \
	&& { swift test -q >"$tmp/test.log" 2>&1 || { tail -40 "$tmp/test.log" >&2; echo "new-check: cairn's unit tests failed" >&2; exit 1; }; })
cairn="$repo/tools/cairn/.build/release/cairn"

cd "$tmp"
"$cairn" new demo_app --bin >/dev/null
# SwiftPM names a path dependency after its directory, and the template names it `cairn`.
ln -s "$repo" cairn
cd demo_app
sed -i '' "s|^require \"owner\" / \"cairn\" @ .*|require cairn from \"$tmp/cairn/lean\"|" lean/lakefile.lean
sed -i '' "s|.package(url: \"CAIRN_GIT_URL\", from: \"0.1.0\")|.package(path: \"$tmp/cairn\")|" Package.swift
grep -q "require cairn from" lean/lakefile.lean || { echo "new-check: the template's require changed; update this script" >&2; exit 1; }
grep -q ".package(path:" Package.swift || { echo "new-check: the template's Package.swift changed; update this script" >&2; exit 1; }

"$cairn" build >build.log 2>&1 || { tail -40 build.log >&2; echo "new-check: cairn build failed (log above)" >&2; exit 1; }
"$(swift build --show-bin-path)/DemoApp" --selftest

# The template's claims: issue its ids, then check them as an app's CI would. `cairn build` turns
# on Lake's artifact cache, which keeps .olean files out of the build directory on a hit, and the
# ledger imports from there: as `cairn doc` does, turn it off and build again.
export LAKE_ARTIFACT_CACHE=false
(cd lean && lake build -q && lake exe ledger update --scope demo_app --root DemoApp --lock ../claims.lock >/dev/null \
	&& lake exe ledger check --scope demo_app --root DemoApp --lock ../claims.lock)
[ "$(grep -c '^[0-9]' claims.lock)" -eq 2 ] || { cat claims.lock >&2; echo "new-check: expected two claims in claims.lock" >&2; exit 1; }

# A second app in the package: DemoApp's files renamed, with its own claim ids.
unset LAKE_ARTIFACT_CACHE
mkdir -p lean/Second Sources/CSecond/include Sources/Second
second() { sed -e 's/DemoApp/Second/g' -e 's/demo_app\.h/second.h/g' -e 's/\^1/^3/g' -e 's/\^2/^4/g' \
	-e 's/⟨2, 0⟩/⟨4, 0⟩/g' -e 's/\.window 1 /.window 3 /g' "$1" >"$2"; }
second lean/DemoApp.lean lean/Second.lean
second lean/DemoApp/Abi.lean lean/Second/Abi.lean
second Sources/CDemoApp/include/demo_app.h Sources/CSecond/include/second.h
second Sources/CDemoApp/demo_app.c Sources/CSecond/second.c
second Sources/DemoApp/main.swift Sources/Second/main.swift
grep -q '\^4' lean/Second.lean && grep -q '"\^4"' Sources/Second/main.swift \
	|| { echo "new-check: the template's claims changed; update this script" >&2; exit 1; }
printf '\n@[default_target]\nlean_lib Second where\n  roots := #[`Second.Abi, `Second]\n  defaultFacets := #[LeanLib.staticFacet]\n' >>lean/lakefile.lean
sed -i '' 's/^libs = \["DemoApp"\]$/libs = ["DemoApp", "Second"]/' cairn.toml
grep -q '"Second"' cairn.toml || { echo "new-check: cairn.toml's libs changed; update this script" >&2; exit 1; }
# Each executable links its own app's archive, .cairn/lib/libdemo_app_<app>.a.
sed -i '' 's/"-ldemo_app"/"-ldemo_app_demoapp"/' Package.swift
sed -i '' 's|^    \]$|        .target(name: "CSecond", dependencies: [.product(name: "CLean", package: "cairn")]),\
        .executableTarget(name: "Second", dependencies: ["CSecond", .product(name: "CLean", package: "cairn"),\
                          .product(name: "CairnFrame", package: "cairn"), .product(name: "CairnHost", package: "cairn")],\
                          linkerSettings: [.unsafeFlags(["-L" + lib, "-ldemo_app_second"])]),\
    ]|' Package.swift
grep -q '"-ldemo_app_second"' Package.swift && grep -q '"-ldemo_app_demoapp"' Package.swift \
	|| { echo "new-check: the template's Package.swift changed; update this script" >&2; exit 1; }

if "$cairn" build >build2.log 2>&1; then echo "new-check: cairn build linked a package of two apps without --app" >&2; exit 1; fi
grep -q "several apps (DemoApp, Second); pick one with --app" build2.log \
	|| { tail -20 build2.log >&2; echo "new-check: cairn build didn't list the two apps (log above)" >&2; exit 1; }
for app in DemoApp Second; do
	"$cairn" build --app "$app" >build2.log 2>&1 || { tail -40 build2.log >&2; echo "new-check: cairn build --app $app failed (log above)" >&2; exit 1; }
	"$(swift build --show-bin-path)/$app" --selftest
done
[ -f .cairn/lib/libdemo_app_demoapp.a ] && [ -f .cairn/lib/libdemo_app_second.a ] \
	|| { ls .cairn/lib >&2; echo "new-check: expected one archive per app" >&2; exit 1; }

[ "${1:-}" != --keep ] || echo "new-check: kept $tmp/demo_app"
echo "new-check: PASS (cairn new --bin, cairn build, --selftest, ledger, two apps with --app)"
