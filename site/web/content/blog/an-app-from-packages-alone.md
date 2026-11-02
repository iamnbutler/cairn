---
title: An app built from packages alone
date: 2026-10-24T20:43:00-04:00
milestone: m3
number: 3
status: done
was: third-milestone-pairs
summary: Pairs is a memory game built only through Cairn's package path, with images, JSON and requests in flight that it doesn't control.
---

Pairs is a memory game: a grid of face-down cards, flip two, keep them if they match. Decks are
theme packs, a JSON manifest and a set of images, loaded from a folder or a URL. It was the
third milestone, small enough to finish, and it needs what a Bluesky client needs: images, JSON
and many requests in flight at once.

It's also the first app built only through the package path, `cairn new pairs --bin`,
`cairn add` and `cairn build`, in a repository of its own. Nothing in it reaches into Cairn's.

## What Cairn gained

- **Images.** An image node whose size Lean knows before the pixels arrive, so the layout never
  jumps, and an effect that loads one. The host decodes and paints; Lean never holds pixels.
- **JSON as its own package**, `cairn_json`, with a proof that decoding what was encoded gives it
  back.
- **Requests in flight**: at most six at once, with the rest queued. Switching packs cancels
  them, and a late reply for an old pack never changes the board.

## What's proved

- The grid follows the window, and for every width no two cards overlap and every card is inside
  it.
- The deal has every face exactly twice, at most two unmatched cards are face up, and every game
  can be won.
- A best score only improves.

## The catch

Decoding images, caching them and the network belong to the host: they're recorded as
assumptions and fuzzed, not proved. The grid always fits the window, so nothing in Pairs
scrolls; scrolling waited for Sky.
