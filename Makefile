# Cairn build. Lean builds a static library; the Swift host links it.

export PATH := $(HOME)/.elan/bin:$(PATH)
LEAN_PREFIX = $(shell cd lean && lean --print-prefix)
LIB = build/lib/libcairn_lean.a
VENDOR = host/Sources/CLean/vendor/lean

.PHONY: lean host build check audit ledger kernel lint test corpus bench bench-audio bench-frame selftest demo fixture clean record site site-maps map map-trusted conformance fuzz fuzz-quick fuzz-yap size fuzz-trusted fuzz-trusted-quick bundle yap yap-install bench-yap-apps bench-yap-overlay bench-yap

# build/lib/libcairn_lean.a: the framework (`Cairn`) and Lean's runtime, linked by every host
# target. Each app gets its own library on top (APPS: library → file), and each executable
# links exactly one: v1 apps all export `cairn_app_init/step/frame` (docs/runtime.md), so two
# in one binary would clash. The check below keeps the shared library free of app exports and
# each app library to one set.
APPS = Counter:counter Basics:basics Todo:todo Clock:clock Tray:tray Yap:yap

lean:
	cd lean && lake build
	mkdir -p build/lib $(VENDOR)
	cp $(LEAN_PREFIX)/include/lean/*.h $(VENDOR)/
	libtool -static -o $(LIB) \
		lean/.lake/build/lib/libcairn_Cairn.a \
		$(LEAN_PREFIX)/lib/lean/libInit.a \
		$(LEAN_PREFIX)/lib/lean/libleanrt.a \
		$(LEAN_PREFIX)/lib/libuv.a \
		$(LEAN_PREFIX)/lib/libgmp.a 2>&1 | grep -v "has no symbols" || true
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

# Everything a PR must pass.
check: lint audit ledger kernel test selftest fuzz-quick size fuzz-trusted-quick

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

# Yap (Cairn) against the original Yap under Apple's Instruments (bench/yap-instruments.md).
# Builds both bench apps, records each suite with xctrace and summarises the traces into
# bench/out/yap-instruments/. bench-yap-overlay is the frame pacing suite alone (~15 min);
# bench-yap is every suite (~2 h). Set SCREEN=1 for the second display, BUFFER_MS=100 for
# coarser microphone buffers, RUNS, SECS; see tools/bench/yap-instruments.sh.
bench-yap-apps: lean
	tools/bench/build-apps.sh

bench-yap-overlay: bench-yap-apps
	tools/bench/yap-instruments.sh overlay

bench-yap: bench-yap-apps
	tools/bench/yap-instruments.sh overlay hitches latency idle menu launch

# Lean encode and Swift decode times for 1,000- and 10,000-node frames (bench/frame.md).
bench-frame: lean
	cd lean && lake build framecorpus && .lake/build/bin/framecorpus bench ../$(CORPUS)
	cd host && CAIRN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter DecodeBench

# Drives each app headlessly through the host's real threads and accessibility mirror.
selftest: host
	cd host && swift run CairnCounter --selftest
	cd host && swift run CairnBasics --selftest
	cd host && swift run CairnTodo --selftest
	cd host && swift run CairnClock --selftest
	cd host && swift run CairnTray --selftest
	cd host && swift run CairnYap --selftest

# Opens an app in a window: `make demo` (TodoMVC), or `make demo DEMO=CairnBasics`.
DEMO ?= CairnTodo
demo: host
	cd host && swift run $(DEMO)

# An app bundle: `make bundle APP=Tray [SIGN=identity]` writes build/apps/Tray.app. Per-app
# Info.plist and entitlements go in host/Bundles/<App>/ (tools/bundle/bundle.sh).
bundle: host
	tools/bundle/bundle.sh $(APP) $$(cd host && swift build --show-bin-path) $(or $(SIGN),-) "$(or $(NAME),$(APP))"

# Yap on Cairn (docs/yap.md): `make yap` builds build/apps/Yap (Cairn).app, release, signed with
# the first valid Apple Development identity (Yap's own project.yml signs with team 8S43JJMN6B's
# "Apple Development"), so TCC grants survive rebuilds. YAP_SIGN=<identity or hash> overrides it.
# `make yap-install` copies it to /Applications, beside (never over) the original Yap.app.
YAP_SIGN ?= $(shell security find-identity -v -p codesigning | grep '"Apple Development' | grep -v CSSMERR | head -1 | awk '{print $$2}')
yap: lean
	cd host && swift build -c release --product CairnYap
	@[ -n "$(YAP_SIGN)" ] || { echo "yap: no Apple Development identity; pass YAP_SIGN=<identity>"; exit 1; }
	tools/bundle/bundle.sh Yap $$(cd host && swift build -c release --show-bin-path) $(YAP_SIGN) "Yap (Cairn)"

yap-install: yap
	rm -rf "/Applications/Yap (Cairn).app"
	cp -R "build/apps/Yap (Cairn).app" "/Applications/Yap (Cairn).app"
	@echo "installed /Applications/Yap (Cairn).app"

# The Swift stand-in app with a text field, for checking IME and accessibility by hand.
fixture: host
	cd host && swift run CairnFixture

# Window-only screen recorder for demo videos (see docs/media.md).
record: build/bin/record
build/bin/record: tools/record/main.swift
	mkdir -p build/bin
	swiftc -O $< -o $@

# Copy the Counter, Basics, Todo and Yap maps, and the trusted base's, into the microsite
# (site/public/map/<app>/, site/public/map/trusted/), building them
# first with fresh evidence: fuzzing for each (and Yap's random host, `make fuzz-yap`), and
# conformance for each app with a generator (it shows the app's window while it runs; Yap has
# none and runs detached; CONFORMANCE=0 skips it and keeps any earlier run).
# A failing fuzz or conformance run doesn't stop it: the failure is evidence, and the map shows it.
MAP_APPS = Counter Basics Todo Yap
site-maps:
	@for a in $(MAP_APPS); do \
		$(MAKE) fuzz APP=$$a N=1000 || echo "site-maps: fuzzing $$a failed; its map shows it"; \
		if [ $$a = Yap ]; then $(MAKE) fuzz-yap || echo "site-maps: Yap's random-host fuzzer failed; its map shows it"; fi; \
		if [ "$(CONFORMANCE)" != 0 ] && [ -f tools/conformance/lean/Conformance/Apps/$$a.lean ]; then \
			$(MAKE) conformance APP=$$a || echo "site-maps: conformance on $$a failed; its map shows it"; fi; \
		$(MAKE) map APP=$$a || exit 1; \
	done
	$(MAKE) fuzz-trusted || echo "site-maps: the trusted-base fuzzer failed; its map shows it"
	$(MAKE) map-trusted
	rm -rf site/public/map && mkdir -p site/public/map
	@for a in $(MAP_APPS); do cp -R build/map/$$a/dist site/public/map/$$(echo $$a | tr A-Z a-z); done
	cp -R build/map/Trusted/dist site/public/map/trusted

# Deploy the microsite (site/) to Cloudflare.
site:
	cd site && npx -y wrangler@4 deploy

clean:
	rm -rf build lean/.lake host/.build $(VENDOR)

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

# The trusted base's assumptions (Cairn.Fuzz.Trusted.Claims) as a map of their own: no app, so
# no capture; the evidence is build/fuzz/trusted.json from `make fuzz-trusted`.
map-trusted: lean
	mkdir -p build/map/Trusted
	cd lean && lake build claims audit TrustedClaims
	cd lean && lake exe claims Cairn.Fuzz.Trusted.Claims > ../build/map/Trusted/claims.json
	cd lean && lake env .lake/build/bin/audit --json ../build/map/Trusted/audit.json > /dev/null
	bun tools/map/cairn-map.ts build --app Trusted --name "Trusted base" --dir build/map/Trusted

# Conformance (docs/conformance.md): the Lean model's sequences replayed on the running app
# through its debug socket. `make conformance APP=Basics [N=1000] [LEN=12] [SEED=1]` writes
# build/conformance/$(APP).json (read by the map) and build/conformance/$(APP)/report.md.
# Adding an app takes one file: tools/conformance/lean/Conformance/Apps/<App>.lean.
# The generator links with system clang, not Lake: Lake's bundled lld can't read the SDK's
# Swift .tbd files, and the host's Core Text metrics (CairnMetrics) must replace the weak
# fallback in lean/c/text_host.c, hence -force_load.
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
		--claims $(CONFDIR)/$(APP)/claims.json --out $(CONFDIR) $(CONF_ARGS_$(APP))

# Yap under the socket has a silent world (no key, microphone or reply), so its walks stay in
# the menu and never reach a state its dictation invariants are about: the map says so.
CONF_ARGS_Yap = --invariants-unreached "under the debug socket Yap's world is silent (no key, microphone or reply reaches it), so every walk stays in the menu and no state reached exercises a dictation invariant; the invariants are checked by the proofs, \`make fuzz-yap\` and \`CairnYap --selftest\`"

# Claim-driven fuzzing (docs/fuzz.md): `make fuzz APP=Basics N=1000` runs N sequences from seed
# SEED (default 0) and writes build/fuzz/$(APP).json, which `make map` reads.
fuzz: lean
	cd lean && lake build fuzz && .lake/build/bin/fuzz $(APP) --seed $(or $(SEED),0) --iterations $(or $(N),200) --out ../build/fuzz

# The quick run in `make check`: every app, 200 sequences of 50 steps (about a second).
# Written to build/fuzz/quick/ so it doesn't replace a longer run's evidence.
FUZZ_APPS = Counter Basics Todo
fuzz-quick: lean
	cd lean && lake build fuzz
	@for a in $(FUZZ_APPS); do (cd lean && .lake/build/bin/fuzz $$a --iterations 200 --out ../build/fuzz/quick) || exit 1; done
	cd lean && lake build yapfuzz && .lake/build/bin/yapfuzz --iterations 200 --steps 200 --out ../build/fuzz/quick

# Yap's dictation machine against a random host (lean/Examples/Yap/Fuzz.lean): keys, ticks,
# audio, replies late, failed, duplicated and out of order; then the app itself (`receive` and
# the menu, lean/Examples/Yap/AppFuzz.lean) against one. `make fuzz-yap [N=5000] [SEED=0]`
# writes build/fuzz/host/Yap.json, which `make map APP=Yap` reads beside build/fuzz/Yap.json
# from the generic `make fuzz APP=Yap` (the menu's moves, through the runtime).
fuzz-yap: lean
	cd lean && lake build yapfuzz && .lake/build/bin/yapfuzz --seed $(or $(SEED),0) --iterations $(or $(N),5000) --steps 300 --out ../build/fuzz/host

# Binary size (bench/size.md): each app executable built for release with a link map, stripped
# into build/size/, attributed (Lean runtime, Cairn, the app, Swift host, shaders), and checked
# against SIZE_LIMIT bytes. No host app links `Lean` (the compiler, about 100 MB), so each is a
# few MB; crossing the limit almost always means something imported `Lean`.
SIZE_APPS = CairnCounter CairnBasics CairnTodo CairnClock CairnTray CairnYap
SIZE_LIMIT = 5000000
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
