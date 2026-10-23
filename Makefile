# Cairn build. Lean builds a static library; the Swift host links it.

export PATH := $(HOME)/.elan/bin:$(PATH)
LEAN_PREFIX = $(shell cd lean && lean --print-prefix)
LIB = build/lib/libcairn_lean.a
VENDOR = host/Sources/CLean/vendor/lean

.PHONY: lean host build check audit ledger kernel lint test corpus bench bench-frame selftest demo fixture clean record site site-maps map conformance fuzz fuzz-quick

# build/lib/libcairn_lean.a: the framework (`Cairn`) and Lean's runtime, linked by every host
# target. Each app gets its own library on top (APPS: library → file), and each executable
# links exactly one: v1 apps all export `cairn_app_init/step/frame` (docs/runtime.md), so two
# in one binary would clash. The check below keeps the shared library free of app exports and
# each app library to one set.
APPS = Counter:counter Basics:basics Todo:todo

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
	@! nm -gU $(LIB) 2>/dev/null | grep -E ' _cairn_(app|counter)_' \
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
test: lean corpus
	cd host && swift test
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
check: lint audit ledger kernel test selftest fuzz-quick

bench: lean
	cd lean && lake build bench && .lake/build/bin/bench
	cd host && swift run -c release CairnCounter --bench
	cd host && swift run -c release CairnBasics --bench
	cd host && LEAN_ABORT_ON_NONLINEAR=1 swift run -c release CairnTodo --bench
	cd host && CAIRN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter RenderBench

# Lean encode and Swift decode times for 1,000- and 10,000-node frames (bench/frame.md).
bench-frame: lean
	cd lean && lake build framecorpus && .lake/build/bin/framecorpus bench ../$(CORPUS)
	cd host && CAIRN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter DecodeBench

# Drives each app headlessly through the host's real threads and accessibility mirror.
selftest: host
	cd host && swift run CairnCounter --selftest
	cd host && swift run CairnBasics --selftest
	cd host && swift run CairnTodo --selftest

# Opens an app in a window: `make demo` (TodoMVC), or `make demo DEMO=CairnBasics`.
DEMO ?= CairnTodo
demo: host
	cd host && swift run $(DEMO)

# The Swift stand-in app with a text field, for checking IME and accessibility by hand.
fixture: host
	cd host && swift run CairnFixture

# Window-only screen recorder for demo videos (see docs/media.md).
record: build/bin/record
build/bin/record: tools/record/main.swift
	mkdir -p build/bin
	swiftc -O $< -o $@

# Copy the Counter and Basics maps into the microsite (site/public/map/<app>/), building them first.
site-maps:
	$(MAKE) map APP=Counter
	$(MAKE) map APP=Basics
	rm -rf site/public/map && mkdir -p site/public/map
	cp -R build/map/Counter/dist site/public/map/counter
	cp -R build/map/Basics/dist site/public/map/basics

# Deploy the microsite (site/) to Cloudflare.
site:
	cd site && npx -y wrangler@4 deploy

clean:
	rm -rf build lean/.lake host/.build $(VENDOR)

# The map (docs/map.md): claims + evidence → build/map/$(APP)/ in the map skill's format, with
# headless screenshots pinned from the frame's accessibility rects. `make map APP=Counter`.
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
		--claims $(CONFDIR)/$(APP)/claims.json --out $(CONFDIR)

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
