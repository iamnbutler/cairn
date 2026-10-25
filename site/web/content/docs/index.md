---
title: Cairn docs
nav: Docs
eyebrow: Developer docs
lede: How to build a Mac app in Cairn, where everything a person can do is a claim with a durable id and machine-checked evidence.
---

Cairn apps are written in Lean 4. The app's state, its view, its layout, its hit testing and its
text editing are pure Lean functions, and every thing a person can do is a **claim**: an id like
`^2`, a sentence saying what happens, a formal statement, and a proof that the code meets it. A
thin Swift host runs the app on macOS and paints it with Metal.

These docs are young. Pages that today's code supports are written; the one that isn't says what
it will cover and what has to land first. Every code sample is included from a source file that
`make check` compiles, so a sample can't drift from the code it shows.

<bongo:note label="What works today">
Cairn is research, and its API has no stability promise before 1.0. It is a package, though: an
app lives in its own repository and depends on a tagged release (the latest is `v0.2.0`), and
the `cairn` tool starts, builds and documents it. Yap is the first app built that way. Checking,
fuzzing, mapping and bundling an app are still the Cairn repository's `make` targets; see
[the cairn tool](/docs/reference/cairn-tool/).
</bongo:note>

## Guides

<div class="shelf">
<a href="/docs/guide/"><b>Building an app</b><span>From a counter to effects and shipping, one chapter at a time.</span></a>
<a href="/docs/examples/"><b>Example apps</b><span>Counter, Basics, TodoMVC and Yap, read through their source.</span></a>
<a href="/try/"><b>Try an app</b><span>Counter, Basics and TodoMVC in the browser, every control with its claim id and evidence.</span></a>
</div>

## Reference

<div class="shelf">
<a href="/docs/api/"><b>API reference</b><span>Every module, declaration and claim in Cairn, generated from the code by <code>cairn doc</code>.</span></a>
<a href="/docs/reference/cairn-tool/"><b>The cairn tool</b><span>Starting, building, documenting and publishing a package, and the make targets for the rest.</span></a>
<a href="/docs/reference/claims/"><b>Claims</b><span>Every claim kind, what each generates, and what the build checks.</span></a>
<a href="/docs/reference/evidence/"><b>The evidence ladder</b><span>Proved, fuzzed, tested, seen, assumed: how sure we are of each claim.</span></a>
<a href="/docs/reference/trust/"><b>How much to trust a claim</b><span>What each kind of evidence rules out, what it still trusts, and a bug the tests miss.</span></a>
<a href="/docs/internals/trusted-base/"><b>The trusted base</b><span>What the proofs rely on but can't prove, and how each piece is checked.</span></a>
<a href="/docs/reference/releases/"><b>Release notes</b><span>What changed in each version, and what an app can rely on across them.</span></a>
</div>

## Evidence

<div class="shelf">
<a href="/docs/evidence/"><b>Claim pages</b><span>Every claim each package makes, grouped by place, with its proofs, generated from what it published.</span></a>
</div>

## Contributing

<div class="shelf">
<a href="/docs/internals/host-protocol/"><b>The host protocol</b><span>The two byte buffers between Lean and Swift, and the threads around them.</span></a>
<a href="/docs/internals/host-effects/"><b>Writing host effects</b><span>Adding something the host does for an app, with its assumption and fuzz check.</span></a>
<a href="/docs/internals/profiling/"><b>Profiling against a reference</b><span>Measuring an app against the one it replaces, with Apple's own tools.</span></a>
<a href="/docs/internals/contributing/"><b>Contributing</b><span>The rules every change follows.</span></a>
</div>
