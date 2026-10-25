#!/bin/sh
# new-check.sh: `cairn new --bin` makes an app that builds, links and runs (docs/cli.md).
#
#   tools/cairn/new-check.sh [--keep]
#
# Builds the `cairn` CLI and runs its unit tests, makes a new app `demo_app` in a temporary
# directory, points its Lean require and its SwiftPM dependency at this checkout (by path, so it
# tests this tree, not a release), then runs `cairn build`, the app's `--selftest` (headless:
# the Lean side starts, a press on ^2 counts) and the ledger on the template's claims. The name
# has an underscore so the C declaration of the app's initializer is checked against Lean's
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

[ "${1:-}" != --keep ] || echo "new-check: kept $tmp/demo_app"
echo "new-check: PASS (cairn new --bin, cairn build, --selftest, ledger)"
