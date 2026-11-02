---
title: Likes that show at once and end up true
date: 2026-10-26T04:18:05-04:00
milestone: m5
number: 5
status: in progress
was: fifth-milestone-sky-acts-on-bluesky
summary: Sky can now like, repost, follow and mute. Each act shows the moment you press it, and a proof says the counts end up matching the server's, whatever order its replies come in.
---

Sky, the Bluesky client I'm building on Cairn, could read a feed. Now it can act on one: like,
repost, follow and mute, with a notifications tab beside Home. This is the fifth milestone, and
it's still in progress.

The hard part of a like button isn't drawing it. The button has to change the instant you press
it, before the server has answered, and the server may refuse, answer late, answer out of order,
or act and lose the reply. Most apps handle that with care and hope. I wanted a claim:

> Once every reply is in, whatever order the replies came in, each post shows what the server
> holds, and its count is the server's.

## What Cairn gained

- **Optimistic values** (`Cairn.Optimistic`): keyed values shown at once, with one write in
  flight per key. A refused write rolls back in the step its answer arrives, and a lost reply is
  read back. The convergence proof is about the framework, so every app gets it, not just Sky.
- **Menus** on controls and on the secondary click, and an app's own items in the menu bar.
- **`scrollTo`, the Dock badge and spoken announcements**, as effects the host runs.
- **A server with a world of its own in `cairn fuzz`.** It keeps the likes and follows, loses
  replies after acting on them, and lets the fuzzer check claims against what it holds.
- **`cairn_atproto` 0.3.0**: record keys, idempotent writes, the authoritative read, viewer state
  and notifications.

## What it looks like

When the server refuses a like, Sky rolls it back, says so in a line and announces it to
VoiceOver. Muting an author takes their posts out of the feed at once without moving the post
you're reading, and the status line offers Undo. Notifications are grouped ("Alice, Bob and 3
others liked your post"), counted on the tab and the Dock, and marked seen once they're on
screen.

## The catch

The proof is about a model of the server: one register per key, with idempotent writes.
Bluesky's real servers lag, so a count other people are changing can be briefly behind; the
count claim holds when no one else has acted since the last view. Posting, replies and quotes
are the next milestone.
