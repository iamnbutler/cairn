---
title: A proved TodoMVC
date: 2026-10-23T10:57:34-04:00
milestone: m1
number: 1
status: done
was: first-milestone-a-proved-todomvc
summary: TodoMVC on the Mac, written in Lean, with every action a claim and proofs that each control is on screen exactly when it should be and can be pressed.
---

The first milestone was TodoMVC, running natively on the Mac. TodoMVC is small, completely
specified and has text input, and formal UI testing already uses it as a benchmark. It needs
every layer of a UI framework and is small enough to finish.

Its state, view, layout, hit testing, focus and text editing are written in Lean. A thin Swift
host passes events in and paints Lean's frames with Metal. The text fields do typing, selection,
copy and paste, and input methods.

## What's proved

- Every action is a claim with an id, and the build won't let an id drift.
- Each action does what its claim says, and the counts and filters stay right in every state.
- **Presence**: a control is on screen exactly when its action is enabled.
- **Pressable**: at any window size from the minimum up, a click at an enabled control's centre
  reaches that control, so it's visible, unclipped and on top.

## Checked another way

The real app is driven through a thousand generated sequences of real pointer and key events,
and must agree with the model after every step. A map of the app is generated from the claims,
with the evidence behind each one, and everything the proofs trust about the host is written
down in the trusted base.
