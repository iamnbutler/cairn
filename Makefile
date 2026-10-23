# Cairn build. Lean builds a static library; the Swift host links it.

export PATH := $(HOME)/.elan/bin:$(PATH)
LEAN_PREFIX = $(shell cd lean && lean --print-prefix)
LIB = build/lib/libcairn_lean.a
VENDOR = host/Sources/CLean/vendor/lean

.PHONY: lean host build check audit ledger kernel lint test corpus bench bench-frame selftest demo fixture clean record site

# build/lib/libcairn_lean.a: the framework (`Cairn`) and Lean's runtime, linked by every host
# target. Each app gets its own library on top (APPS: library → file), and each executable
# links exactly one: v1 apps all export `cairn_app_init/step/frame` (docs/runtime.md), so two
# in one binary would clash. The check below keeps the shared library free of app exports and
# each app library to one set.
APPS = Examples:counter Basics:basics

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
check: lint audit ledger kernel test selftest

bench: lean
	cd lean && lake build bench && .lake/build/bin/bench
	cd host && swift run -c release CairnCounter --bench
	cd host && swift run -c release CairnBasics --bench
	cd host && CAIRN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter RenderBench

# Lean encode and Swift decode times for 1,000- and 10,000-node frames (bench/frame.md).
bench-frame: lean
	cd lean && lake build framecorpus && .lake/build/bin/framecorpus bench ../$(CORPUS)
	cd host && CAIRN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter DecodeBench

# Drives each app headlessly through the host's real threads and accessibility mirror.
selftest: host
	cd host && swift run CairnCounter --selftest
	cd host && swift run CairnBasics --selftest

# Opens an app in a window: `make demo` (Basics), or `make demo DEMO=CairnCounter`.
DEMO ?= CairnBasics
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

# Deploy the microsite (site/) to Cloudflare.
site:
	cd site && npx -y wrangler@4 deploy

clean:
	rm -rf build lean/.lake host/.build $(VENDOR)
