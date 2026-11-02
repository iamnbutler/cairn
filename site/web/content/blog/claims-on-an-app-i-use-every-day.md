---
title: Claims on an app I use every day
date: 2026-10-23T21:04:46-04:00
milestone: m2
number: 2
status: done
was: second-milestone-yap-on-cairn
summary: I rebuilt Yap, my dictation app, on Cairn. The global key, the microphone, timers and typing into other apps are all effects Lean asks for.
---

Yap is a small dictation app for the Mac: hold a key, talk, and the transcript is typed into the
app in front. I use it every day. TodoMVC lived in one window; almost all of Yap lives outside
its window, in a global key, the microphone, timers, a network request, files, sounds and typing
into another app. The second milestone asked whether claims hold up there.

I rebuilt it on Cairn, signed it, installed it and used it for a day of real work.

## What Cairn gained

- **Effects.** The clock and timers, requests the host performs and answers, and outside inputs
  like a global key and the microphone. Lean decides; Swift captures audio, hears the key, makes
  the request and types the text, each because Lean asked.
- **New surfaces**: a native menu bar menu built from Lean's view, and an overlay that never
  takes focus.
- **Packages.** Moving Yap into its own repository made Cairn a package, with a `cairn` command
  and claim ids scoped by package. Yap's are `yap^N`.

## What's proved about dictation

- A key used in a shortcut never sends.
- A transcript is saved before it's typed.
- A late reply for an old clip never types.
- Every recording ends.

## The catch

Each new effect is an assumption about the host, fuzzed with slow, failed, duplicated and
out-of-order replies, not proved. Audio and HTTP stay in Swift; Lean only decides what to do with
the results.
