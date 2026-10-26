# Cairn build. Lean builds a static library; the Swift host links it.

export PATH := $(HOME)/.elan/bin:$(PATH)
LEAN_PREFIX = $(shell cd lean && lean --print-prefix)
LIB = build/lib/libcairn_lean.a
VENDOR = host/Sources/CLean/vendor/lean

.PHONY: try lean host build check audit ledger kernel lint test corpus bench bench-audio bench-frame selftest fixture clean record site doc doctest fuzz-quick fuzz-scope size fuzz-trusted fuzz-trusted-quick site-build site-dist site-nexthub registry-check new-check cairn-tool cairn-tool-test fixture-build fixture-ledger

lean:
	cd lean && lake build
	mkdir -p build/lib $(VENDOR)
	cp $(LEAN_PREFIX)/include/lean/*.h $(VENDOR)/
	@git diff --quiet -- $(VENDOR) \
	  || (echo "lean: the toolchain's lean.h differs from the committed $(VENDOR); commit it"; exit 1)
	cd lean && ../bin/cairn-link --out ../$(LIB)
	cp lean/.lake/build/lib/libcairn_TrustedFuzz.a build/lib/libcairn_trusted_fuzz.a
	@! nm -gU $(LIB) 2>/dev/null | grep -E ' _cairn_app_' \
	  || (echo "lean: app exports in the shared library $(LIB)"; exit 1)

host: lean
	cd host && swift build

build: host

audit: lean
	cd lean && lake build audit && lake env .lake/build/bin/audit CairnAll Cairn.Fuzz

# Claim ids: every id in claims.lock is still issued (or retired, or moved to another package),
# none is reused, and every claim in the code is locked; first, the ledger's own tests
# (Cairn.Claims.LedgerTests). See docs/claims.md.
ledger: lean
	cd lean && lake build Cairn.Claims.LedgerTests
	cd lean && lake exe ledger check --root CairnAll --root Cairn.Fuzz.Trusted.Claims

# Replay every declaration through the kernel. Catches proofs that skipped kernel checking
# (debug.skipKernelTC), which #print axioms and the audit cannot see. The sandboxed mode needs
# Linux (bubblewrap); on macOS we run unsandboxed, which is fine for our own code.
kernel: lean
	cd lean && lake check --inadvisably-no-sandbox

# Constructs that bypass the kernel or swap in unchecked code (research/lean/), and import cycles
# between directories of lean/ (docs/packages-and-std.md, "The graph").
lint:
	@! grep -rnE 'implemented_by|skipKernelTC|native_decide|bv_decide|^\s*axiom ' lean/Cairn $(FIXTURE)/lean/Fixture $(FIXTURE)/lean/*.lean \
	  || (echo "lint: forbidden construct (see AGENTS.md, Lean rules)"; exit 1)
	@bun tools/lint/dircycles.ts lean

# Swift tests: renderer goldens, pixel probes, text metrics (offscreen; needs a Metal device),
# and the host's unit tests (index conversion, text-input shadow, input mapping, NSTextInputClient).
# CairnRenderTests run one at a time: Core Text's synchronous calls to fontd, made from many test
# threads at once, sometimes never get a reply, and the whole run hangs. The rest stay parallel.
test: lean corpus
	cd host && swift test --skip CairnRenderTests
	cd host && swift test --filter CairnRenderTests --no-parallel
	cd lean && .lake/build/bin/framecorpus verify ../build/corpus

# The frame/event corpus (docs/frame.md): Lean writes frames, event batches and their canonical
# dumps; the Swift tests decode and encode against them and write Swift-encoded batches, which
# `test` then decodes with Lean's proved decoder.
CORPUS = build/corpus
corpus: lean
	cd lean && lake build framecorpus
	rm -rf $(CORPUS)
	cd lean && .lake/build/bin/framecorpus gen ../$(CORPUS)

# region: make-check
# Everything a PR must pass. The per-app checks run on test/fixture, Cairn's own app; the
# example apps are in their own repository, iamnbutler/cairn_examples.
check: lint audit ledger kernel doctest test selftest fuzz-quick fuzz-scope size fuzz-trusted-quick fixture-ledger site-build registry-check new-check cairn-tool-test
# endregion: make-check

# region: make-fixture
# test/fixture: Cairn's own app (test/fixture/README.md), a package of its own that requires this
# checkout by path. The framework's per-app checks (selftest, fuzz-quick, size, bench) run on it
# through the `cairn` CLI, as an app in its own repository runs them (docs/cli.md, "Checks").
FIXTURE = test/fixture
CAIRN = $(CURDIR)/tools/cairn/.build/release/cairn

cairn-tool:
	cd tools/cairn && swift build -c release -q

# The CLI's unit tests, and #196's stale checkout on a localhost dumb-HTTP server (needs python3).
cairn-tool-test:
	cd tools/cairn && swift test -q

fixture-build: lean cairn-tool
	cd $(FIXTURE) && $(CAIRN) build
# endregion: make-fixture

# The fixture's claims, scope `fixture`, in test/fixture/claims.lock (none in Cairn's ledger),
# and its theorems' axioms. `cairn build` turns Lake's artifact cache on, which keeps .olean
# files out of the build directory, and the ledger imports from there: turn it off.
fixture-ledger: fixture-build
	cd $(FIXTURE)/lean && export LAKE_ARTIFACT_CACHE=false && lake build -q \
	  && lake exe ledger check --scope fixture --root Checks --lock ../claims.lock && lake exe audit Checks Fixture

# The layout bench (bench/layout.md), the virtual-list bench (bench/vlist.md), the fixture's input → frame bench (`cairn bench`), and the
# renderer's.
bench: lean cairn-tool
	cd lean && lake build bench && .lake/build/bin/bench && .lake/build/bin/bench --vlist && LEAN_ABORT_ON_NONLINEAR=1 .lake/build/bin/bench --optimistic
	cd $(FIXTURE) && $(CAIRN) bench
	cd host && CAIRN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter RenderBench

# What recording costs: the level stream in Lean and the host, and WAV extraction
# (bench/effects.md, "Recording"). Synthetic audio only.
bench-audio: lean
	cd lean && lake build framecorpus && .lake/build/bin/framecorpus bench-audio
	cd host && swift build -c release --product CairnFuzzTrusted && .build/release/CairnFuzzTrusted --bench-audio


# Lean encode and Swift decode times for 1,000- and 10,000-node frames (bench/frame.md).
bench-frame: lean
	cd lean && lake build framecorpus && .lake/build/bin/framecorpus bench ../$(CORPUS)
	cd host && CAIRN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter DecodeBench

# region: make-selftest
# Drives the fixture headlessly through the host's real threads, timers and accessibility
# mirror. Then --close-test: the real app's window
# (shown without focus) closed with work in flight; it must quit cleanly.
selftest: fixture-build
	cd $(FIXTURE) && $$(swift build --show-bin-path)/Fixture --selftest
	cd $(FIXTURE) && $$(swift build --show-bin-path)/Fixture --close-test
# endregion: make-selftest


# The Swift stand-in app with a text field, for checking IME and accessibility by hand.
fixture: host
	cd host && swift run CairnFixture

# Window-only screen recorder for demo videos (see docs/media.md).
record: build/bin/record
build/bin/record: tools/record/main.swift
	mkdir -p build/bin
	swiftc -O $< -o $@

# The site's pages, built by bongo (site/web/bongo.config.ts) into site/web/public/: the developer
# docs (content/docs/*.md), the homepage, /milestones/ and /feed.xml, each page with a link
# preview card. Docs code is included from source by region; a missing file or region, a fenced
# code block or a broken link fails the build. The feed and the homepage's latest milestone come
# from content/milestones/index.hbs and site/public/media.json (lib/site.ts). The output isn't
# committed: site-dist merges it with site/public. site/public/docs/docs.css is shared with the
# package pages. --fresh: bongo
# rebuilds a page when its Markdown changes, not when a file it includes does.
site-build:
	cd site/web && bun install --frozen-lockfile --silent && bun --bun ./node_modules/.bin/bongo build --fresh

# The package pages (site/registry.js) against the registry fixture and a fake registry. The
# fixture comes from the release tags: `bun tools/registry/fixture.ts` rewrites it, `--check` diffs it.
registry-check:
	bun tools/registry/fixture.ts --check
	bun test site/registry.test.js

# `cairn new --bin` + `cairn build` against this checkout: the template app builds, links (its
# `import Cairn` is the linked library), passes its `--selftest` and its ledger. About a minute.
new-check: lean
	tools/cairn/new-check.sh

# The microsite's files, build/site/: site/public, bongo's pages, and Cairn's API reference
# (`make doc PKG=Cairn`, built fresh each time) at /docs/api/, with the copied pages' link preview
# tags stamped in (tools/site/pages.ts), and the docs as Markdown for language models
# (tools/site/llms.ts), then every internal link checked, the package pages rendered from the
# registry the Worker reads (tools/site/links.ts). bongo empties its own output when a build
# fails, so it never writes into site/public; a file two of them have is an error.
site-dist: site-build
	$(MAKE) doc PKG=Cairn
	rm -rf build/site && mkdir -p build && cp -R site/public build/site
	@clash=$$(cd site/web/public && find . -type f -exec test -e ../../public/{} \; -print); \
		if [ -n "$$clash" ]; then echo "site-dist: site/public and the docs build both have $$clash"; exit 1; fi
	cp -R site/web/public/. build/site/
	@if [ -e build/site/docs/api ]; then echo "site-dist: something else wrote docs/api/"; exit 1; fi
	cp -R build/doc/Cairn/dist build/site/docs/api
	bun tools/site/pages.ts build/site
	bun site/icons.ts build/site
	bun tools/site/llms.ts build/site
	mkdir -p build/site/fonts && for w in 400 600 700; do cp site/web/node_modules/@fontsource/pixelify-sans/files/pixelify-sans-latin-$$w-normal.woff2 build/site/fonts/; done
	bun tools/site/links.ts build/site

# Deploy the microsite (site/) to Cloudflare.
site: site-dist
	cd site && npx -y wrangler@4 deploy
	bun tools/site/nexthub.ts build/site

# The same build on Nexthub Pages alone (https://cairn.iamnbutler.pages.nexthub.sh); the token
# comes from the Keychain (nexthub.sh).
site-nexthub: site-dist
	bun tools/site/nexthub.ts build/site

# region: make-try
# The "Try it" pages' data (docs/try.md): Counter, Basics and Todo from iamnbutler/cairn_examples
# at TRY_REV, each walked headless with `--try-capture` (offscreen, no window), into
# build/try/out/<app>/ (graph.json, img/*.webp). `bun tools/try/put.ts --examples $(EXAMPLES)`
# then publishes them to the media bucket and writes site/public/try/apps.json, which is committed
# as media.json is; `make site` builds none of it. EXAMPLES=<dir> uses a checkout already there.
# A few minutes the first time, for the examples' Lean and Swift builds.
TRY_APPS = Counter Basics Todo
TRY_REV = df45306
EXAMPLES ?= build/try/cairn_examples
# Bounds other than try.ts's default (depth 8, 200 states), as <App>=<option>.
TRY_BOUNDS = Counter=--depth=20 Todo=--states=400
XCAIRN = $(abspath $(EXAMPLES))/lean/.lake/packages/cairn/tools/cairn/.build/release/cairn
try:
	@command -v cwebp >/dev/null || { echo "try: cwebp is needed (brew install webp)"; exit 1; }
	@if [ "$(EXAMPLES)" = build/try/cairn_examples ]; then \
		[ -d $(EXAMPLES) ] || git clone -q https://github.com/iamnbutler/cairn_examples $(EXAMPLES); \
		git -C $(EXAMPLES) checkout -q $(TRY_REV) 2>/dev/null || { git -C $(EXAMPLES) fetch -q && git -C $(EXAMPLES) checkout -q $(TRY_REV); }; fi
	$(MAKE) -C $(EXAMPLES) cairn-tool
	@for a in $(TRY_APPS); do d=$(CURDIR)/build/try/$$a; rm -rf $$d && mkdir -p $$d && \
		b=; for x in $(TRY_BOUNDS); do [ "$${x%%=*}" = $$a ] && b=$${x#*=}; done; \
		(cd $(EXAMPLES) && $(XCAIRN) build --app $$a && $(XCAIRN) claims $$a --out $$d/claims.json) && \
		bun tools/try/try.ts script --claims $$d/claims.json $$b > $$d/script.json && \
		(cd $(EXAMPLES) && swift run -q Cairn$$a --try-capture $$d/script.json $$d/capture) && \
		bun tools/try/try.ts build --app $$a --dir $$d --root $(EXAMPLES) --scope cairn_examples \
			--out build/try/out/$$(echo $$a | tr A-Z a-z) && \
		rm -rf $$d/capture || exit 1; done
# endregion: make-try

clean:
	rm -rf build lean/.lake host/.build .build $(FIXTURE)/lean/.lake $(FIXTURE)/.build $(FIXTURE)/.cairn $(FIXTURE)/build

# Cairn's API reference (docs/doc.md), rustdoc-style: `make doc PKG=Cairn` documents the framework
# (DOC_CAIRN), which is the developer docs' API reference; an app package runs `cairn doc`.
# Writes build/doc/<name>/dist/. PRIVATE=1 shows private declarations; OPEN=1 opens the index.
# Doc tests (Lean code blocks in doc comments) run first and fail the build.
DOC_CAIRN = Cairn CairnAll Cairn.Claims Cairn.Fuzz Cairn.Fuzz.Trusted.Claims Cairn.Fuzz.Trusted.Export
DOC_NAME = $(PKG)
DOCDIR = build/doc/$(DOC_NAME)
DOC_MODULES = $(if $(filter Cairn,$(PKG)),$(DOC_CAIRN),$(PKG))
doc:
	@[ -n "$(DOC_NAME)" ] || { echo "doc: PKG=Cairn"; exit 1; }
	mkdir -p $(DOCDIR)
	cd lean && lake build && lake build doc claims
	cd lean && lake exe doc --check $(DOC_MODULES) > ../$(DOCDIR)/doc.json
	cd lean && lake exe claims $(DOC_MODULES) > ../$(DOCDIR)/claims.json
	bun tools/doc/cairn-doc.ts --name $(DOC_NAME) --dir $(DOCDIR) \
		$(if $(PRIVATE),--private) $(if $(OPEN),--open)

# Doc tests alone, for `make check`: every Lean code block in a doc comment in Cairn elaborates
# (docs/doc.md, "Doc tests").
doctest: lean
	cd lean && lake build doc && lake exe doc --check $(DOC_CAIRN) > /dev/null

# The quick run in `make check`: the fixture, 200 sequences of 50 steps (a few seconds), with
# `cairn fuzz`. Written to test/fixture/build/fuzz/quick/ so it doesn't replace a longer run's
# evidence. `LEAN_ABORT_ON_NONLINEAR=1`: the fixture's fake server marks its posts linear, so a
# copy of the server's world aborts the run. Then the likes' mutant, which the server must catch
# (test/fixture/lean/Fixture/LikeMutant.lean).
fuzz-quick: lean cairn-tool
	cd $(FIXTURE) && LEAN_ABORT_ON_NONLINEAR=1 $(CAIRN) fuzz --iterations 200 --out build/fuzz/quick
	cd $(FIXTURE)/lean && lake build -q likeMutant && LEAN_ABORT_ON_NONLINEAR=1 .lake/build/bin/likeMutant > /dev/null

# Whose machines a fuzz executable runs (cairn#221, test/fuzz-scope/README.md): an app and a
# dependency each with a machine in a module ending in `Claims`. The app lists only its own,
# `Claims`; `--deps` adds the dependency's as `fuzzdep/Claims`; building `Clash` checks that two
# of the app's own machines with one name are a compile error. Both are fuzzed briefly.
FUZZ_SCOPE = test/fuzz-scope/app
fuzz-scope: lean
	cd $(FUZZ_SCOPE) && lake build -q && lake build -q fuzz
	test "$$($(FUZZ_SCOPE)/.lake/build/bin/fuzz --list)" = "$$(printf 'Claims\tApp.Claims')"
	test "$$($(FUZZ_SCOPE)/.lake/build/bin/fuzz --list --deps)" = "$$(printf 'Claims\tApp.Claims\nfuzzdep/Claims\tDep.Claims')"
	cd $(FUZZ_SCOPE) && for t in Claims fuzzdep/Claims; do .lake/build/bin/fuzz $$t --iterations 20 --steps 10 --out build/fuzz > /dev/null || exit 1; done
	test -f $(FUZZ_SCOPE)/build/fuzz/Claims.json && test -f $(FUZZ_SCOPE)/build/fuzz/fuzzdep/Claims.json


# region: make-size
# Binary size (bench/size.md): the fixture's executable built for release with a link map,
# stripped, attributed (Lean runtime, Cairn, the app, Swift host, shaders), and checked against
# SIZE_LIMIT bytes, with `cairn size` (test/fixture/build/size/). No app links `Lean` (the
# compiler, about 100 MB), so it is a few MB; crossing the limit almost always means something
# imported `Lean`.
SIZE_LIMIT = 5000000
# endregion: make-size
size: lean cairn-tool
	cd $(FIXTURE) && $(CAIRN) size --limit $(SIZE_LIMIT)

# The trusted base's fuzzer (docs/fuzz.md, "Trusted base"): the Swift frame decoder and event
# encoder against Lean's proved codecs, TextIndex, the NSTextInputClient and the text-input
# shadow against a Lean field, and Core Text metrics against TextMetrics.Valid. `make
# fuzz-trusted [N=20000] [SEED=0]` writes build/fuzz/trusted.json, with the evidence for each
# `assume` claim in Cairn.Fuzz.Trusted.Claims that names a check; repros go to build/fuzz/trusted/.
fuzz-trusted: lean
	mkdir -p build/fuzz
	cd lean && lake build claims CairnTrusted && lake exe claims Cairn.Fuzz.Trusted.Claims > ../build/fuzz/trusted-claims.json
	cd host && swift build -c release --product CairnFuzzTrusted
	host/.build/release/CairnFuzzTrusted --n $(or $(N),20000) --seed $(or $(SEED),0) \
		--claims build/fuzz/trusted-claims.json --out build/fuzz/trusted.json

# The quick run in `make check`: 500 cases a suite, debug build (about 2 s).
fuzz-trusted-quick: lean
	mkdir -p build/fuzz/quick
	cd lean && lake build claims CairnTrusted && lake exe claims Cairn.Fuzz.Trusted.Claims > ../build/fuzz/quick/trusted-claims.json
	cd host && swift build --product CairnFuzzTrusted
	host/.build/debug/CairnFuzzTrusted --n 500 --claims build/fuzz/quick/trusted-claims.json --out build/fuzz/quick/trusted.json

.PHONY: og-scene
# The background of every link preview card, site/web/assets/og/scene.png (tools/og/scene.ts):
# the homepage's scene, screenshotted by Google Chrome. Redraw it after a change to the scene and
# commit it. The cards themselves are drawn by satori when bongo builds (tools/og/card.ts).
og-scene:
	bun tools/og/scene.ts
