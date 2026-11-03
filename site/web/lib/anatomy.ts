// The claim anatomy figure: Counter's ^2 Reset, every part of it called out ({{{ $utils.anatomy() }}}).
// It is on the homepage and on /claims/. annotate.js draws the leaders from each note to the code
// it is about (data-for names the id); without it the numbered markers pair them up.
export const anatomy = () => `<figure class="claim anatomy">
<pre class="px"><code><span class="ln"><span class="kw">move</span> <span class="id br" id="c-id">^2</span> reset <span class="op">(</span>s <span class="op">:</span> State<span class="op">)</span> <span class="str">"Reset"</span> <span class="br" id="c-place"><span class="kw">in</span> <span class="id">^3</span></span> <span class="kw">where</span><i class="mk">1</i><i class="mk">2</i></span><span class="ln people" id="c-people">  <span class="kw">does</span> <span class="str">"Press Reset."</span><i class="mk">3</i></span><span class="ln people">  <span class="kw">sees</span> <span class="str">"The count is zero, and Reset disappears."</span></span><span class="ln checker" id="c-checker">  <span class="kw">enabled</span> <span class="op">:=</span> <span class="br" id="c-enabled">resetEnabled s</span><i class="mk">4</i><i class="mk">5</i></span><span class="ln checker">  <span class="kw">on</span> press</span><span class="ln checker">    <span class="kw">apply</span> <span class="op">:=</span> <span class="br" id="c-apply"><span class="op">{</span> s <span class="kw">with</span> count <span class="op">:=</span> <span class="lit">0</span> <span class="op">}</span></span><i class="mk">6</i></span><span class="ln checker">    <span class="kw">post</span> s' <span class="op">:=</span> <span class="br" id="c-post">s'.count <span class="op">=</span> <span class="lit">0</span> <span class="op">∧</span> resetEnabled s' <span class="op">=</span> <span class="lit">false</span></span><i class="mk">7</i></span><span class="ln checker">    <span class="kw">sound</span> <span class="op">:=</span> <span class="br" id="c-sound"><span class="tac">by</span> <span class="tac">intro</span> s _<span class="op">;</span> <span class="tac">exact</span> <span class="op">⟨</span><span class="tac">rfl</span>, <span class="tac">rfl</span><span class="op">⟩</span></span><i class="mk">8</i></span></code></pre>
    <ol class="callouts">
      <li class="l" data-for="c-id"><b>The id</b> Permanent: never renumbered or reused, and what reviews,
        docs and agents cite. <i>Like a data-testid that can't drift.</i></li>
      <li class="r" data-for="c-place"><b>Where it lives</b> <code>^3</code> is a claim too, a place: Counter's window.</li>
      <li class="l people" data-for="c-people"><b>For people</b> <code>does</code> and <code>sees</code>, in plain
        English for reviewers and the claim's page. Lean doesn't check them.</li>
      <li class="l" data-for="c-enabled"><b>When it's offered</b> The button is proved on screen exactly when
        this holds, in every state. <i>Playwright's toBeVisible() checks one page load.</i></li>
      <li class="l checker" data-for="c-checker"><b>For the checker</b> Everything below. Lean checks it when the app builds.</li>
      <li class="r" data-for="c-apply"><b>What it does</b> A pure copy of <code>s</code> with the count at 0.</li>
      <li class="r" data-for="c-post"><b>The promise</b> Afterwards the count is zero and Reset is gone.
        <i>An expect() stated for every state, not asserted on one run.</i></li>
      <li class="r" data-for="c-sound"><b>The proof</b> <i>Like assert_eq!, except the compiler settles it for
        every s.</i> No proof, no build.</li>
    </ol>
  </figure>`;

// The Claims page's version: the same claim taken apart further, fourteen notes after the ones in
// the Next Cloud post's diagram. Each marker sits just after the span it is about; the notes follow
// the code in reading order, two columns on a wide page.
const m = (n: number) => `<i class="mk">${n}</i>`;
const NOTES: [string, string, string?, string?][] = [
	["A move", "Something a person can do. Cairn's other claims are flows (a path through moves), invariants (always true) and places (where things show).", "Like a test step, except it's declared with the app instead of written after it."],
	["The id, ^2", "Permanent: never renumbered or reused. Reviews, docs and agents cite it.", "A data-testid that can't drift, kept in a ledger (claims.lock)."],
	["The input, s", "The app's whole state at the moment of the press. It's a variable, so everything below holds for any s."],
	["The title", "The button's label, as people see it."],
	["The place, ^3", "Where the button lives. ^3 is a claim too, a place: Counter's window. The build checks that ^3 exists and is a place."],
	["What it does, in words", "does says what you do, sees what you'll see next: plain English for reviewers, shown on the claim's page. Lean checks the lines below, not these.", "Like the name in test('…').", "people"],
	["When it's offered", "Reset exists only while this is true. Cairn proves the button is on screen exactly then, in every state.", "Playwright's toBeVisible() checks one page load."],
	["A plain function", "The same Lean function the view calls to decide whether to draw the button, so the claim and the screen can't disagree.", "No selector to keep in sync."],
	["On press", "The contract for one press, as given, when, then: enabled is the given, apply the when, post the then.", "Given-When-Then, with a proof in place of a test run."],
	["The new state", "A copy of s with the count set to 0. Pure: nothing changes in place, and nothing is asked of the host.", "Like a Redux reducer."],
	["The promise", "About the new state s′: the count is 0, and (∧) Reset is gone.", "An expect(), stated for every state instead of asserted on one run."],
	["A proof begins", "by switches from stating to proving. sound is the claim that post always follows from apply."],
	["For any state", "Take any s where Reset is enabled: any s, not only the ones a test tried."],
	["Both halves hold", "rfl: true by computing, one for each side of the ∧. If either fails, the app doesn't build.", "Like Rust's assert_eq!, except the compiler settles it for every s instead of running it on one value."],
];

export const anatomyFull = () => `<figure class="claim anatomy full">
<pre class="px"><code><span class="ln"><span class="kw">move</span>${m(1)} <span class="id br">^2</span>${m(2)} reset <span class="br"><span class="op">(</span>s <span class="op">:</span> State<span class="op">)</span></span>${m(3)} <span class="str br">"Reset"</span>${m(4)} <span class="br"><span class="kw">in</span> <span class="id">^3</span></span>${m(5)} <span class="kw">where</span></span><span class="ln people">  <span class="kw">does</span> <span class="str">"Press Reset."</span>${m(6)}</span><span class="ln people">  <span class="kw">sees</span> <span class="str">"The count is zero, and Reset disappears."</span></span><span class="ln checker">  <span class="kw">enabled</span>${m(7)} <span class="op">:=</span> <span class="br">resetEnabled s</span>${m(8)}</span><span class="ln checker">  <span class="kw">on</span> press${m(9)}</span><span class="ln checker">    <span class="kw">apply</span> <span class="op">:=</span> <span class="br"><span class="op">{</span> s <span class="kw">with</span> count <span class="op">:=</span> <span class="lit">0</span> <span class="op">}</span></span>${m(10)}</span><span class="ln checker">    <span class="kw">post</span> s' <span class="op">:=</span> <span class="br">s'.count <span class="op">=</span> <span class="lit">0</span> <span class="op">∧</span> resetEnabled s' <span class="op">=</span> <span class="lit">false</span></span>${m(11)}</span><span class="ln checker">    <span class="kw">sound</span> <span class="op">:=</span> <span class="br"><span class="tac">by</span></span>${m(12)} <span class="br"><span class="tac">intro</span> s _</span>${m(13)}<span class="op">;</span> <span class="br"><span class="tac">exact</span> <span class="op">⟨</span><span class="tac">rfl</span>, <span class="tac">rfl</span><span class="op">⟩</span></span>${m(14)}</span></code></pre>
<ol class="callouts">
${NOTES.map(([b, t, like, cls]) => `<li${cls ? ` class="${cls}"` : ""}><b>${b}</b> ${t}${like ? ` <i>${like}</i>` : ""}</li>`).join("\n")}
</ol>
<figcaption>Counter's Reset button, exactly as written in Counter.lean. Every line under <code>sees</code> is checked when the app builds.</figcaption>
</figure>`;
