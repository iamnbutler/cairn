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
