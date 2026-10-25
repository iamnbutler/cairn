# Cairn build. Lean builds a static library; the Swift host links it.

export PATH := $(HOME)/.elan/bin:$(PATH)
LEAN_PREFIX = $(shell cd lean && lean --print-prefix)
LIB = build/lib/libcairn_lean.a
VENDOR = host/Sources/CLean/vendor/lean

.PHONY: lean host build check audit ledger kernel lint test corpus bench bench-audio bench-frame selftest demo fixture clean record site capture site-try doc doctest conformance fuzz fuzz-quick size fuzz-trusted fuzz-trusted-quick bundle site-build site-dist registry-check new-check cairn-tool fixture-build fixture-ledger examples-check examples-audit examples-doctest examples-selftest examples-fuzz-quick examples-size examples-bench

# region: make-apps
# build/lib/libcairn_lean.a: the framework (`Cairn`) and Lean's runtime, linked by every host
# target. Each app gets its own library on top (APPS: library → file), and each executable
# links exactly one: v1 apps all export `cairn_app_init/step/frame` (docs/runtime.md), so two
# in one binary would clash. The check below keeps the shared library free of app exports and
# each app library to one set.
APPS = Counter:counter Basics:basics Todo:todo Clock:clock Tray:tray Gallery:gallery
# endregion: make-apps

lean:
	cd lean && lake build
	mkdir -p build/lib $(VENDOR)
	cp $(LEAN_PREFIX)/include/lean/*.h $(VENDOR)/
	@git diff --quiet -- $(VENDOR) \
	  || (echo "lean: the toolchain's lean.h differs from the committed $(VENDOR); commit it"; exit 1)
	cd lean && ../bin/cairn-link --out ../$(LIB)
	@for a in $(APPS); do \
		cp lean/.lake/build/lib/libcairn_$${a%%:*}.a build/lib/libcairn_app_$${a##*:}.a; done
	cp lean/.lake/build/lib/libcairn_TrustedFuzz.a build/lib/libcairn_trusted_fuzz.a
	@! nm -gU $(LIB) 2>/dev/null | grep -E ' _cairn_app_' \
	  || (echo "lean: app exports in the shared library $(LIB)"; exit 1)
	@for a in $(APPS); do n=$$(nm -gU build/lib/libcairn_app_$${a##*:}.a 2>/dev/null | grep -c ' _cairn_app_init$$'); \
	  [ "$$n" -le 1 ] || { echo "lean: libcairn_app_$${a##*:}.a defines cairn_app_init $$n times"; exit 1; }; done

host: lean
	cd host && swift build

build: host

audit: lean
	cd lean && lake build audit && lake env .lake/build/bin/audit CairnAll Cairn.Fuzz

# Claim ids: every id in claims.lock is still issued (or retired), none is reused, and every
# claim in the code is locked. See docs/claims.md.
ledger: lean
	cd lean && lake exe ledger check --root CairnAll --root Cairn.Fuzz.Trusted.Claims $(EXAMPLES_LEDGER)

# Replay every declaration through the kernel. Catches proofs that skipped kernel checking
# (debug.skipKernelTC), which #print axioms and the audit cannot see. The sandboxed mode needs
# Linux (bubblewrap); on macOS we run unsandboxed, which is fine for our own code.
kernel: lean
	cd lean && lake check --inadvisably-no-sandbox

# Constructs that bypass the kernel or swap in unchecked code (research/lean/), and import cycles
# between directories of lean/ (docs/packages-and-std.md, "The graph").
lint:
	@! grep -rnE 'implemented_by|skipKernelTC|native_decide|bv_decide|^\s*axiom ' lean/Cairn $(wildcard lean/Examples) $(FIXTURE)/lean/Fixture $(FIXTURE)/lean/*.lean \
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
# Everything a PR must pass. The framework's checks run on test/fixture, Cairn's own app;
# examples-check (at the end of this file) checks the example apps.
check: lint audit ledger kernel doctest test selftest fuzz-quick size fuzz-trusted-quick fixture-ledger site-build registry-check new-check examples-check
# endregion: make-check

# region: make-fixture
# test/fixture: Cairn's own app (test/fixture/README.md), a package of its own that requires this
# checkout by path. The framework's per-app checks (selftest, fuzz-quick, size, bench) run on it
# through the `cairn` CLI, as an app in its own repository runs them (docs/cli.md, "Checks").
FIXTURE = test/fixture
CAIRN = $(CURDIR)/tools/cairn/.build/release/cairn

cairn-tool:
	cd tools/cairn && swift build -c release -q

fixture-build: lean cairn-tool
	cd $(FIXTURE) && $(CAIRN) build
# endregion: make-fixture

# The fixture's claims, scope `fixture`, in test/fixture/claims.lock (none in Cairn's ledger),
# and its theorems' axioms. `cairn build` turns Lake's artifact cache on, which keeps .olean
# files out of the build directory, and the ledger imports from there: turn it off.
fixture-ledger: fixture-build
	cd $(FIXTURE)/lean && export LAKE_ARTIFACT_CACHE=false && lake build -q \
	  && lake exe ledger check --scope fixture --root Checks --lock ../claims.lock && lake exe audit Checks

# The layout bench (bench/layout.md), the fixture's input → frame bench (`cairn bench`), and the
# renderer's. The examples' benches are examples-bench.
bench: lean cairn-tool
	cd lean && lake build bench && .lake/build/bin/bench
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
# mirror; examples-selftest does each example app.
selftest: fixture-build
	cd $(FIXTURE) && $$(swift build --show-bin-path)/Fixture --selftest
# endregion: make-selftest

# region: make-demo
# Opens an app in a window: `make demo` (TodoMVC), or `make demo DEMO=CairnBasics`.
DEMO ?= CairnTodo
demo: host
	cd host && swift run $(DEMO)
# endregion: make-demo

# region: make-bundle
# An app bundle: `make bundle APP=Tray [SIGN=identity]` writes build/apps/Tray.app. Per-app
# Info.plist and entitlements go in host/Bundles/<App>/ (tools/bundle/bundle.sh).
bundle: host
	tools/bundle/bundle.sh $(APP) $$(cd host && swift build --show-bin-path) $(or $(SIGN),-) "$(or $(NAME),$(APP))"
# endregion: make-bundle


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
# (tools/site/llms.ts). bongo empties its own output when a build fails, so it never writes into
# site/public; a file two of them have is an error.
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
	$(MAKE) site-try

# Deploy the microsite (site/) to Cloudflare.
site: site-dist
	cd site && npx -y wrangler@4 deploy

clean:
	rm -rf build lean/.lake host/.build .build $(FIXTURE)/lean/.lake $(FIXTURE)/.build $(FIXTURE)/.cairn $(FIXTURE)/build

# region: make-capture
# Headless screenshots of an app (docs/claim-pages.md): each flow's witness and each move no
# flow presses, from the frame's own pixels, with pins from its accessibility rects. Writes
# build/capture/$(APP)/, and the shots into build/map/$(APP)/capture/, where `make doc APP=…`
# reads them. `make capture APP=Counter`. Kept for a per-claim visual export on the claim pages,
# which doesn't exist yet.
APP ?= Counter
CAPDIR = build/capture/$(APP)
SHOTS = build/map/$(APP)/capture
capture: host
	mkdir -p $(CAPDIR)
	cd lean && lake build claims
	cd lean && lake exe claims Examples.$(APP) > ../$(CAPDIR)/claims.json
	bun tools/map/capture-script.ts --claims $(CAPDIR)/claims.json > $(CAPDIR)/script.json
	rm -rf $(SHOTS) && mkdir -p $(dir $(SHOTS))
	cd host && swift run Cairn$(APP) --map-capture ../$(CAPDIR)/script.json ../$(SHOTS)
# endregion: make-capture

# The "Try it" pages' data (docs/try.md): each app's states, explored headless from its real step
# and frame, → build/site/try/<app>/ (graph.json, img/). Built at deploy by site-dist, not
# committed; about a minute on a built tree.
TRY_APPS = Counter Basics Todo
TRY_OUT ?= build/site/try
site-try: host
	cd lean && lake build claims
	@for a in $(TRY_APPS); do d=build/try/$$a; mkdir -p $$d && \
		(cd lean && lake exe claims Examples.$$a > ../$$d/claims.json) && \
		bun tools/try/try.ts script --app $$a --claims $$d/claims.json > $$d/script.json && \
		rm -rf $$d/capture && (cd host && swift run -q Cairn$$a --try-capture ../$$d/script.json ../$$d/capture) && \
		bun tools/try/try.ts build --app $$a --dir $$d --out $(TRY_OUT)/$$(echo $$a | tr A-Z a-z) && \
		rm -rf $$d/capture || exit 1; done

# cairn doc (docs/doc.md): a package's API and claims from its code, rustdoc-style.
# `make doc APP=Todo` documents Examples.Todo and its submodules; `make doc PKG=Cairn` documents
# the framework (DOC_CAIRN), which is the developer docs' API reference. Writes
# build/doc/<name>/dist/. PRIVATE=1 shows private declarations; OPEN=1 opens the index. Claims
# carry the evidence already in build/ (`make fuzz`, `make conformance`, `make capture` for the
# screenshots). Doc tests (Lean code blocks in doc comments) run first and fail
# the build.
DOC_CAIRN = Cairn CairnAll Cairn.Claims Cairn.Fuzz Cairn.Fuzz.Trusted.Claims Cairn.Fuzz.Trusted.Export
DOC_NAME = $(or $(PKG),$(APP))
DOCDIR = build/doc/$(DOC_NAME)
DOC_MODULES = $(if $(PKG),$(if $(filter Cairn,$(PKG)),$(DOC_CAIRN),$(PKG)),Examples.$(APP) $(shell cd lean && find Examples/$(APP) -name '*.lean' 2>/dev/null | sed 's/\.lean$$//; s|/|.|g'))
doc:
	@[ -n "$(DOC_NAME)" ] || { echo "doc: APP=<App> or PKG=Cairn"; exit 1; }
	mkdir -p $(DOCDIR)
	cd lean && lake build && lake build doc claims
	cd lean && lake exe doc --check $(DOC_MODULES) > ../$(DOCDIR)/doc.json
	cd lean && lake exe claims $(DOC_MODULES) > ../$(DOCDIR)/claims.json
	bun tools/doc/cairn-doc.ts --name $(DOC_NAME) --dir $(DOCDIR) $(if $(PKG),,--app $(APP) --link Cairn.=../../Cairn/dist/) \
		$(if $(PRIVATE),--private) $(if $(OPEN),--open)

# Doc tests alone, for `make check`: every Lean code block in a doc comment in Cairn elaborates
# (docs/doc.md, "Doc tests"). examples-doctest does the examples'.
doctest: lean
	cd lean && lake build doc && lake exe doc --check $(DOC_CAIRN) > /dev/null

# region: make-conformance
# Conformance (docs/conformance.md): the Lean model's sequences replayed on the running app
# through its debug socket. `make conformance APP=Basics [N=1000] [LEN=12] [SEED=1]` writes
# build/conformance/$(APP).json (read by `make doc`) and build/conformance/$(APP)/report.md.
# Adding an example takes one file: lean/Examples/<App>/Conformance.lean. An app package runs
# `cairn conformance` instead (test/fixture: `cd test/fixture && cairn conformance`).
# The generator links with system clang, not Lake: Lake's bundled lld can't read the SDK's
# Swift .tbd files, and the host's Core Text metrics (CairnMetrics) must replace the weak
# fallback in lean/c/text_host.c, hence -force_load.
# endregion: make-conformance
LEN ?= 12
CONFDIR = build/conformance
CONF_LIB = $(patsubst $(APP):%,%,$(filter $(APP):%,$(APPS)))
SDK = $(shell xcrun --show-sdk-path)
conformance: lean
	@[ -n "$(CONF_LIB)" ] || { echo "conformance: $(APP) is not in APPS"; exit 1; }
	@[ -f lean/Examples/$(APP)/Conformance.lean ] || { echo "conformance: no lean/Examples/$(APP)/Conformance.lean"; exit 1; }
	cd host && swift build --product Cairn$(APP) && swift build --product CairnMetrics
	cd lean && lake build Examples.$(APP).Conformance claims
	mkdir -p $(CONFDIR)/$(APP)
	cd lean && lake exe claims Examples.$(APP) > ../$(CONFDIR)/$(APP)/claims.json
	clang -O2 -I$(LEAN_PREFIX)/include -DCAIRN_APP_INIT=runtime_initialize_cairn_Examples_$(APP)_Conformance \
		tools/conformance/gen_main.c \
		$$(cd lean && lake query +Conformance.Gen:c.o +Examples.$(APP).Conformance:c.o 2>/dev/null) \
		build/lib/libcairn_app_$(CONF_LIB).a $(LIB) \
		-Wl,-force_load,$$(cd host && swift build --show-bin-path)/libCairnMetrics.a \
		-L$(SDK)/usr/lib/swift -lc++ -o $(CONFDIR)/$(APP)/gen
	bun tools/conformance/driver.ts --app $(APP) --n $(or $(N),1000) --length $(LEN) --seed $(or $(SEED),1) \
		--bin $$(cd host && swift build --show-bin-path)/Cairn$(APP) --gen $(CONFDIR)/$(APP)/gen \
		--claims $(CONFDIR)/$(APP)/claims.json --out $(CONFDIR)

# region: make-fuzz
# Claim-driven fuzzing (docs/fuzz.md): `make fuzz APP=Basics N=1000` runs N sequences from seed
# SEED (default 0) and writes build/fuzz/$(APP).json, which `make doc` reads.
fuzz: lean
	cd lean && lake build fuzz && .lake/build/bin/fuzz $(APP) --seed $(or $(SEED),0) --iterations $(or $(N),200) --out ../build/fuzz
# endregion: make-fuzz

# The quick run in `make check`: the fixture, 200 sequences of 50 steps (about a second), with
# `cairn fuzz`. Written to test/fixture/build/fuzz/quick/ so it doesn't replace a longer run's
# evidence. examples-fuzz-quick does the examples.
fuzz-quick: lean cairn-tool
	cd $(FIXTURE) && $(CAIRN) fuzz --iterations 200 --out build/fuzz/quick


# region: make-size
# Binary size (bench/size.md): each app executable built for release with a link map, stripped
# into build/size/, attributed (Lean runtime, Cairn, the app, Swift host, shaders), and checked
# against SIZE_LIMIT bytes. No host app links `Lean` (the compiler, about 100 MB), so each is a
# few MB; crossing the limit almost always means something imported `Lean`. `size` is the
# fixture's, with `cairn size` (test/fixture/build/size/); examples-size is the examples'.
SIZE_APPS = CairnCounter CairnBasics CairnTodo CairnClock CairnTray CairnGallery
SIZE_LIMIT = 5000000
# endregion: make-size
size: lean cairn-tool
	cd $(FIXTURE) && $(CAIRN) size --limit $(SIZE_LIMIT)

examples-size: lean
	mkdir -p build/size
	cd host && for a in $(SIZE_APPS); do \
		swift build -c release --product $$a -Xlinker -map -Xlinker $(CURDIR)/build/size/$$a.map || exit 1; done
	bun tools/size/size.ts --bin $$(cd host && swift build -c release --show-bin-path) \
		--maps build/size --out build/size --limit $(SIZE_LIMIT) $(SIZE_APPS)

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

# region: make-examples
# The example apps (lean/Examples, host/Sources/Cairn<App>): checked here until they move to
# their own repository (#137). Nothing above needs them: the framework's checks run on
# test/fixture. Their claims are still in Cairn's ledger (`ledger` reads EXAMPLES_LEDGER).
EXAMPLES_LEDGER = --root Examples
examples-check: examples-audit examples-doctest examples-selftest examples-fuzz-quick examples-size

examples-audit: lean
	cd lean && lake build audit && lake env .lake/build/bin/audit Examples

examples-doctest: lean
	cd lean && lake build doc && lake exe doc --check Examples > /dev/null

# Drives each example headlessly through the host's real threads and accessibility mirror.
examples-selftest: host
	cd host && swift run CairnCounter --selftest
	cd host && swift run CairnBasics --selftest
	cd host && swift run CairnTodo --selftest
	cd host && swift run CairnClock --selftest
	cd host && swift run CairnTray --selftest
	cd host && swift run CairnGallery --selftest

# 200 sequences of 50 steps on each of FUZZ_APPS, into build/fuzz/quick/.
FUZZ_APPS = Counter Basics Todo Clock Tray Gallery
examples-fuzz-quick: lean
	cd lean && lake build fuzz
	@for a in $(FUZZ_APPS); do (cd lean && .lake/build/bin/fuzz $$a --iterations 200 --out ../build/fuzz/quick) || exit 1; done

# Basics' and TodoMVC's input → frame benches (bench/basics.md, bench/todo.md).
examples-bench: host
	cd host && swift run -c release CairnBasics --bench
	cd host && LEAN_ABORT_ON_NONLINEAR=1 swift run -c release CairnTodo --bench
# endregion: make-examples
