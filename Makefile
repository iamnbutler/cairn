# Cairn build. Lean builds a static library; the Swift host links it.

export PATH := $(HOME)/.elan/bin:$(PATH)
LEAN_PREFIX = $(shell cd lean && lean --print-prefix)
LIB = build/lib/libcairn_lean.a
VENDOR = host/Sources/CLean/vendor/lean

.PHONY: lean host build check audit kernel lint bench spike selftest test clean record site

lean:
	cd lean && lake build
	mkdir -p build/lib $(VENDOR)
	cp $(LEAN_PREFIX)/include/lean/*.h $(VENDOR)/
	libtool -static -o $(LIB) \
		lean/.lake/build/lib/libcairn_Examples.a \
		lean/.lake/build/lib/libcairn_Cairn.a \
		$(LEAN_PREFIX)/lib/lean/libInit.a \
		$(LEAN_PREFIX)/lib/lean/libleanrt.a \
		$(LEAN_PREFIX)/lib/libuv.a \
		$(LEAN_PREFIX)/lib/libgmp.a 2>&1 | grep -v "has no symbols" || true

host: lean
	cd host && swift build

build: host

audit: lean
	cd lean && lake build audit && lake env .lake/build/bin/audit

# Replay every declaration through the kernel. Catches proofs that skipped kernel checking
# (debug.skipKernelTC), which #print axioms and the audit cannot see. The sandboxed mode needs
# Linux (bubblewrap); on macOS we run unsandboxed, which is fine for our own code.
kernel: lean
	cd lean && lake check --inadvisably-no-sandbox

# Constructs that bypass the kernel or swap in unchecked code. See research/lean/.
lint:
	@! grep -rnE 'implemented_by|skipKernelTC|native_decide|bv_decide|^\s*axiom ' lean/Cairn lean/Examples \
	  || (echo "lint: forbidden construct (see AGENTS.md, Lean rules)"; exit 1)

# Swift tests: renderer goldens, pixel probes, text metrics (offscreen; needs a Metal device).
test: lean
	cd host && swift test

# Everything a PR must pass.
check: lint audit kernel selftest test

bench: lean
	cd lean && lake build bench && .lake/build/bin/bench
	cd host && swift run -c release CairnSpike --bench
	cd host && CAIRN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter RenderBench

selftest: host
	cd host && swift run CairnSpike --selftest

spike: host
	cd host && swift run CairnSpike

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
