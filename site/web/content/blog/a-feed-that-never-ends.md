---
title: A feed that never ends
date: 2026-10-25T16:57:29-04:00
milestone: m4
number: 4
status: done
was: fourth-milestone-sky-reads-bluesky
summary: Sky signs in to Bluesky, keeps the session in the Keychain and reads the home feed however long it gets. It's built only from registry packages.
---

Sky is the reading half of a Bluesky client, built on Cairn: sign in with an app password, keep
the session, and read the home feed for as long as you scroll. It was the fourth milestone and
the first of four on Bluesky, which needs nearly everything a small app doesn't: long lists,
authentication, paging and requests that race.

Sky lives in its own repository, [iamnbutler/sky](https://github.com/iamnbutler/sky), as the
package `sky`, built only from registry packages. Its [claims are on the
registry](/packages/sky/claims/).

## What Cairn gained

- **Scrolling owned by the runtime.** Every scroll offset belongs to Cairn, not the app, and is
  clamped after every step. A virtual list builds and lays out only the rows on screen: a step
  costs about 0.17 ms at 1,000 rows and at 100,000.
- **Secrets.** The host captures the session's tokens from the server's replies straight into
  the Keychain, so they never reach Lean. The password goes in a secure field that shows
  bullets, keeps no undo and copies nothing.
- **`cairn_atproto`**, a package for XRPC, the session calls and the timeline, with proofs that
  only one token refresh runs at a time and each call is sent at most twice.

## What's proved about the feed

- No duplicates and no gaps.
- A late page for an old cursor never changes the feed.
- A refresh racing a load-more ends as one of the two would have, in order.

Refresh puts new posts above without moving the post you're reading, and offers a way back to
the top. Flinging through 1,102 posts with images, Sky's Lean thread takes a median of 1.5 to
1.7 ms a frame.

## The catch

Everything the host is trusted with, from the Keychain to what VoiceOver sees of a scrolled
list, is an assumption with a fuzz check of its own rather than a proof. Every path runs against
a fake server with no account and no network; reading a real timeline is something I do by hand
with the installed app.
