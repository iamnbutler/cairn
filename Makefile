# Cairn build. Lean builds a static library; the Swift host links it.

export PATH := $(HOME)/.elan/bin:$(PATH)
LEAN_PREFIX = $(shell cd lean && lean --print-prefix)
LIB = build/lib/libcairn_lean.a
VENDOR = host/Sources/CLean/vendor/lean

.PHONY: lean host build check audit bench spike selftest clean

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

# Everything a PR must pass.
check: audit selftest

bench: lean
	cd lean && lake build bench && .lake/build/bin/bench
	cd host && swift run -c release CairnSpike --bench

selftest: host
	cd host && swift run CairnSpike --selftest

spike: host
	cd host && swift run CairnSpike

clean:
	rm -rf build lean/.lake host/.build $(VENDOR)
