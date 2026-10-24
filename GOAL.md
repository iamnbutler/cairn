# Goal: M2, Yap on Cairn

Cairn is research into building user interfaces where every thing a person can do is a
**claim** with a durable id, and every claim carries machine-checked evidence. M1
([docs/goals/m1.md](docs/goals/m1.md)) showed the loop on TodoMVC, a closed app with one window
and no outside world. M2 asks whether it holds up on real software someone uses every day.

The subject is [Yap](https://github.com/iamnbutler/yap) (`~/code/yap`), Nate's dictation app for
the Mac: hold or tap a key, talk, and the transcript is typed into the app in front. It is small
(about 1,500 lines of Swift), but almost all of it is outside the window: a global key, the
microphone, timers, a network request, files, sounds, and typing into another app. Its UI is a
menu bar menu and an overlay that never takes focus. TodoMVC needed none of that.

The existing Yap is the reference. Read it; don't change it.

## The demo

`make yap` builds and installs a signed `Yap (Cairn).app`. Since #75 the app lives in its own
repository, [iamnbutler/yap-cairn](https://github.com/iamnbutler/yap-cairn), and depends on a tagged
Cairn (docs/package.md); `make yap` runs there. Nate uses it instead of Yap for a day
of real work. Its state, its decisions and its menus are Lean; Swift captures audio, hears the
key, makes the request, writes files and types the text, each one an effect Lean asked for.

## Done means

1. **The app.** Everything in Yap's README works: hold to talk and release to send; tap (under
   0.3 s) for hands free and tap again to send; a key used in a shortcut cancels; hands free sends
   on its own after 10 minutes; clips that are too short or silent are dropped; the overlay shows
   a waveform and a live preview from chunks cut at pauses; the dictionary's terms (first 25) and
   fixes; transcripts saved before typing, the recent-transcripts menu, keep-transcripts with
   retention; `config.json` read and live-reloaded; the configurable key; Return after dictating;
   the menu shows missing permissions and errors.
2. **Effects in Cairn.** The framework, not the app, gains:
   - **time:** the runtime gives `update` the clock, and an app can ask for a timer;
   - **requests:** effects the host performs that answer back (transcribe, read and write a file,
     type text, play a sound), with failures as ordinary replies;
   - **subscriptions:** outside inputs an app asks for (a global key, microphone levels);
   - each kind of effect is an `assume` claim with a check, like M1's trusted base.
3. **Surfaces.** A menu bar item whose menu is built from Lean's view, every item a move with an
   id, and a panel that never takes focus or clicks. Both mirrored to accessibility.
4. **Claims and proofs** about the dictation machine, with M1's rules (no `sorry`, standard
   axioms only):
   - a key used in a shortcut never sends;
   - the hold/tap split is exactly the 0.3 s threshold;
   - at most one recording at a time, and every recording ends (released, tapped, cancelled or
     timed out at 10 minutes);
   - a transcript is saved before the effect that types it is issued, and one that fails to type
     stays recoverable and flagged;
   - every send produces at most one typed transcript, and a late reply for an old clip never
     types;
   - dictionary fixes replace whole words only; retention never deletes today's file;
   - menu presence and enablement, as in M1.
5. **Fuzzed.** Random key timings, replies (slow, failed, out of order, duplicated), config edits
   and clock jumps, checking the invariants every step. The host's new effects get trusted-base
   fuzz like M1's codecs.
6. **Measured.** Key-up to text typed, against the original Yap with the same audio; app size;
   idle CPU and memory, in `bench/`.
7. **Mapped and written down.** The map covers Yap; `docs/trusted.md` lists every new
   assumption.

## Not in M2

HTTP or audio processing written in Lean (the host does both; Lean decides what to do with the
results), iOS, other platforms, replacing the original Yap repository, and Ace.

## Order of work

1. **In parallel:** the dictation machine as a headless Lean model with claims, proofs and fuzz
   (no UI, its own command type); the effects design (time, requests, subscriptions) in the
   runtime, ABI and host, shown on a small example.
2. **Surfaces:** the menu bar menu and the non-focusing panel.
3. **Yap on Cairn:** the machine moved onto the framework's effects, with the menu, overlay and
   the host's audio, key, network and typing.
4. **Ship:** signing, install, a day of use, the benchmarks and the map.
