# Cairn build. Lean builds a static library; the Swift host links it.

export PATH := $(HOME)/.elan/bin:$(PATH)
LEAN_PREFIX = $(shell cd lean && lean --print-prefix)
LIB = build/lib/libcairn_lean.a
VENDOR = host/Sources/CLean/vendor/lean

.PHONY: lean host build check audit ledger kernel lint test corpus bench bench-audio bench-frame selftest demo fixture clean record site site-maps map map-trusted doc doctest site-api conformance fuzz fuzz-quick size fuzz-trusted fuzz-trusted-quick bundle docs-site docs-check

# region: make-apps
# build/lib/libcairn_lean.a: the framework (`Cairn`) and Lean's runtime, linked by every host
# target. Each app gets its own library on top (APPS: library → file), and each executable
# links exactly one: v1 apps all export `cairn_app_init/step/frame` (docs/runtime.md), so two
# in one binary would clash. The check below keeps the shared library free of app exports and
# each app library to one set.
APPS = Counter:counter Basics:basics Todo:todo Clock:clock Tray:tray
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
	cd lean && lake build audit && lake env .lake/build/bin/audit

# Claim ids: every id in claims.lock is still issued (or retired), none is reused, and every
# claim in the code is locked. See docs/claims.md.
ledger: lean
	cd lean && lake exe ledger check

# Replay every declaration through the kernel. Catches proofs that skipped kernel checking
# (debug.skipKernelTC), which #print axioms and the audit cannot see. The sandboxed mode needs
# Linux (bubblewrap); on macOS we run unsandboxed, which is fine for our own code.
kernel: lean
	cd lean && lake check --inadvisably-no-sandbox

# Constructs that bypass the kernel or swap in unchecked code. See research/lean/.
lint:
	@! grep -rnE 'implemented_by|skipKernelTC|native_decide|bv_decide|^\s*axiom ' lean/Cairn lean/Examples \
	  || (echo "lint: forbidden construct (see AGENTS.md, Lean rules)"; exit 1)

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
# Everything a PR must pass.
check: lint audit ledger kernel doctest test selftest fuzz-quick size fuzz-trusted-quick docs-check
# endregion: make-check

bench: lean
	cd lean && lake build bench && .lake/build/bin/bench
	cd host && swift run -c release CairnBasics --bench
	cd host && LEAN_ABORT_ON_NONLINEAR=1 swift run -c release CairnTodo --bench
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
# Drives each app headlessly through the host's real threads and accessibility mirror.
selftest: host
	cd host && swift run CairnCounter --selftest
	cd host && swift run CairnBasics --selftest
	cd host && swift run CairnTodo --selftest
	cd host && swift run CairnClock --selftest
	cd host && swift run CairnTray --selftest
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

# Copy the Counter, Basics and Todo maps, and the trusted base's, into the microsite
# (site/public/map/<app>/, site/public/map/trusted/), building them
# first with fresh evidence: fuzzing for each, and conformance for each app with a generator
# (it shows the app's window while it runs; CONFORMANCE=0 skips it and keeps any earlier run).
# A failing fuzz or conformance run doesn't stop it: the failure is evidence, and the map shows it.
MAP_APPS = Counter Basics Todo
site-maps:
	@for a in $(MAP_APPS); do \
		$(MAKE) fuzz APP=$$a N=1000 || echo "site-maps: fuzzing $$a failed; its map shows it"; \
		if [ "$(CONFORMANCE)" != 0 ] && [ -f tools/conformance/lean/Conformance/Apps/$$a.lean ]; then \
			$(MAKE) conformance APP=$$a || echo "site-maps: conformance on $$a failed; its map shows it"; fi; \
		$(MAKE) map APP=$$a || exit 1; \
	done
	$(MAKE) fuzz-trusted || echo "site-maps: the trusted-base fuzzer failed; its map shows it"
	$(MAKE) map-trusted
	rm -rf site/public/map && mkdir -p site/public/map
	@for a in $(MAP_APPS); do cp -R build/map/$$a/dist site/public/map/$$(echo $$a | tr A-Z a-z); done
	cp -R build/map/Trusted/dist site/public/map/trusted

# The developer docs: site/docs/*.md → site/public/docs/ (tools/docs/build.ts). Code is included
# from source by region; a missing file or region fails the build. The output is committed, and
# docs-check (part of check) fails when it is stale. site/public/docs/api/ is `cairn doc`'s.
docs-site:
	bun tools/docs/build.ts

docs-check:
	bun tools/docs/build.ts --check

# Deploy the microsite (site/) to Cloudflare, once the feed is fresh (site-feed-check, below).
site: site-feed-check
	cd site && npx -y wrangler@4 deploy

clean:
	rm -rf build lean/.lake host/.build .build

# region: make-map
# The map (docs/map.md): claims + evidence → build/map/$(APP)/dist/, Cairn's own pages, with
# headless screenshots pinned from the frame's accessibility rects. `make map APP=Counter`. It
# reads build/fuzz/ and build/conformance/ if `make fuzz` or `make conformance` ran first.
APP ?= Counter
MAPDIR = build/map/$(APP)
map: host
	mkdir -p $(MAPDIR)
	cd lean && lake build claims audit
	cd lean && lake exe claims Examples.$(APP) > ../$(MAPDIR)/claims.json
	cd lean && lake env .lake/build/bin/audit --json ../$(MAPDIR)/audit.json > /dev/null
	bun tools/map/cairn-map.ts script --claims $(MAPDIR)/claims.json > $(MAPDIR)/script.json
	rm -rf $(MAPDIR)/capture
	cd host && swift run Cairn$(APP) --map-capture ../$(MAPDIR)/script.json ../$(MAPDIR)/capture
	bun tools/map/cairn-map.ts build --app $(APP) --dir $(MAPDIR)
# endregion: make-map

# The trusted base's assumptions (Cairn.Fuzz.Trusted.Claims) as a map of their own: no app, so
# no capture; the evidence is build/fuzz/trusted.json from `make fuzz-trusted`.
map-trusted: lean
	mkdir -p build/map/Trusted
	cd lean && lake build claims audit TrustedClaims
	cd lean && lake exe claims Cairn.Fuzz.Trusted.Claims > ../build/map/Trusted/claims.json
	cd lean && lake env .lake/build/bin/audit --json ../build/map/Trusted/audit.json > /dev/null
	bun tools/map/cairn-map.ts build --app Trusted --name "Trusted base" --dir build/map/Trusted

# cairn doc (docs/doc.md): a package's API and claims from its code, rustdoc-style.
# `make doc APP=Todo` documents Examples.Todo and its submodules; `make doc PKG=Cairn` documents
# the framework (DOC_CAIRN), which is the developer docs' API reference. Writes
# build/doc/<name>/dist/. PRIVATE=1 shows private declarations; OPEN=1 opens the index. Claims
# carry the evidence already in build/ (`make fuzz`, `make conformance`, `make map` for the
# screenshots), as on the map. Doc tests (Lean code blocks in doc comments) run first and fail
# the build.
DOC_CAIRN = Cairn Cairn.Claims Cairn.Fuzz Cairn.Fuzz.Trusted.Claims Cairn.Fuzz.Trusted.Export
DOC_NAME = $(or $(PKG),$(APP))
DOCDIR = build/doc/$(DOC_NAME)
DOC_MODULES = $(if $(PKG),$(if $(filter Cairn,$(PKG)),$(DOC_CAIRN),$(PKG)),Examples.$(APP) $(shell cd lean && find Examples/$(APP) -name '*.lean' 2>/dev/null | sed 's/\.lean$$//; s|/|.|g'))
doc:
	@[ -n "$(DOC_NAME)" ] || { echo "doc: APP=<App> or PKG=Cairn"; exit 1; }
	mkdir -p $(DOCDIR)
	cd lean && lake build && lake build doc claims
	cd lean && lake exe doc --check $(DOC_MODULES) > ../$(DOCDIR)/doc.json
	cd lean && lake exe claims $(DOC_MODULES) > ../$(DOCDIR)/claims.json
	bun tools/doc/cairn-doc.ts --name $(DOC_NAME) --dir $(DOCDIR) $(if $(APP),--app $(APP) --link Cairn.=../../Cairn/dist/) \
		$(if $(PRIVATE),--private) $(if $(OPEN),--open)

# Cairn's docs as the developer docs' API reference, site/public/docs/api/ (committed; the
# docs build in tools/docs links to it and never writes it). Deploying is still `make site`.
site-api:
	$(MAKE) doc PKG=Cairn
	rm -rf site/public/docs/api && mkdir -p site/public/docs
	cp -R build/doc/Cairn/dist site/public/docs/api

# Doc tests alone, for `make check`: every Lean code block in a doc comment in Cairn and the
# examples elaborates (docs/doc.md, "Doc tests").
doctest: lean
	cd lean && lake build doc && lake exe doc --check $(DOC_CAIRN) Examples > /dev/null

# region: make-conformance
# Conformance (docs/conformance.md): the Lean model's sequences replayed on the running app
# through its debug socket. `make conformance APP=Basics [N=1000] [LEN=12] [SEED=1]` writes
# build/conformance/$(APP).json (read by the map) and build/conformance/$(APP)/report.md.
# Adding an app takes one file: tools/conformance/lean/Conformance/Apps/<App>.lean.
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
	@[ -f tools/conformance/lean/Conformance/Apps/$(APP).lean ] || { echo "conformance: no tools/conformance/lean/Conformance/Apps/$(APP).lean"; exit 1; }
	cd host && swift build --product Cairn$(APP) && swift build --product CairnMetrics
	cd lean && lake build Conformance.Apps.$(APP) claims
	mkdir -p $(CONFDIR)/$(APP)
	cd lean && lake exe claims Examples.$(APP) > ../$(CONFDIR)/$(APP)/claims.json
	clang -O2 -I$(LEAN_PREFIX)/include -DCAIRN_APP_INIT=runtime_initialize_cairn_Conformance_Apps_$(APP) \
		tools/conformance/gen_main.c \
		$$(cd lean && lake query +Conformance.Gen:c.o +Conformance.Apps.$(APP):c.o 2>/dev/null) \
		build/lib/libcairn_app_$(CONF_LIB).a $(LIB) \
		-Wl,-force_load,$$(cd host && swift build --show-bin-path)/libCairnMetrics.a \
		-L$(SDK)/usr/lib/swift -lc++ -o $(CONFDIR)/$(APP)/gen
	bun tools/conformance/driver.ts --app $(APP) --n $(or $(N),1000) --length $(LEN) --seed $(or $(SEED),1) \
		--bin $$(cd host && swift build --show-bin-path)/Cairn$(APP) --gen $(CONFDIR)/$(APP)/gen \
		--claims $(CONFDIR)/$(APP)/claims.json --out $(CONFDIR)

# region: make-fuzz
# Claim-driven fuzzing (docs/fuzz.md): `make fuzz APP=Basics N=1000` runs N sequences from seed
# SEED (default 0) and writes build/fuzz/$(APP).json, which `make map` reads.
fuzz: lean
	cd lean && lake build fuzz && .lake/build/bin/fuzz $(APP) --seed $(or $(SEED),0) --iterations $(or $(N),200) --out ../build/fuzz
# endregion: make-fuzz

# The quick run in `make check`: every app, 200 sequences of 50 steps (about a second).
# Written to build/fuzz/quick/ so it doesn't replace a longer run's evidence.
FUZZ_APPS = Counter Basics Todo
fuzz-quick: lean
	cd lean && lake build fuzz
	@for a in $(FUZZ_APPS); do (cd lean && .lake/build/bin/fuzz $$a --iterations 200 --out ../build/fuzz/quick) || exit 1; done


# region: make-size
# Binary size (bench/size.md): each app executable built for release with a link map, stripped
# into build/size/, attributed (Lean runtime, Cairn, the app, Swift host, shaders), and checked
# against SIZE_LIMIT bytes. No host app links `Lean` (the compiler, about 100 MB), so each is a
# few MB; crossing the limit almost always means something imported `Lean`.
SIZE_APPS = CairnCounter CairnBasics CairnTodo CairnClock CairnTray
SIZE_LIMIT = 5000000
# endregion: make-size
size: lean
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
	cd lean && lake build claims TrustedClaims && lake exe claims Cairn.Fuzz.Trusted.Claims > ../build/fuzz/trusted-claims.json
	cd host && swift build -c release --product CairnFuzzTrusted
	host/.build/release/CairnFuzzTrusted --n $(or $(N),20000) --seed $(or $(SEED),0) \
		--claims build/fuzz/trusted-claims.json --out build/fuzz/trusted.json

# The quick run in `make check`: 500 cases a suite, debug build (about 2 s).
fuzz-trusted-quick: lean
	mkdir -p build/fuzz/quick
	cd lean && lake build claims TrustedClaims && lake exe claims Cairn.Fuzz.Trusted.Claims > ../build/fuzz/quick/trusted-claims.json
	cd host && swift build --product CairnFuzzTrusted
	host/.build/debug/CairnFuzzTrusted --n 500 --claims build/fuzz/quick/trusted-claims.json --out build/fuzz/quick/trusted.json

# The RSS feed (site/public/feed.xml) and the homepage's links into /milestones/, from the posts in
# site/public/milestones/index.html and the videos in site/public/media.json (tools/site/build.ts).
# Both are committed; site-feed-check fails when either is stale. It is part of check (on its own
# line, so the check: list stays as the docs include it) and runs before every deploy.
.PHONY: site-feed site-feed-check
site-feed:
	bun tools/site/build.ts

site-feed-check:
	bun tools/site/build.ts --check

check: site-feed-check
