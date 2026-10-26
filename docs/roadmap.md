# Roadmap

Each milestone is an app that someone uses, chosen for what it forces the framework to gain. The
current one is in [GOAL.md](../GOAL.md); finished ones are in [goals/](goals/).

| Milestone | App | What Cairn gains |
|---|---|---|
| M1 (done) | [TodoMVC](goals/m1.md) | the loop: claims, proofs, layout, text input, a Metal host |
| M2 (done) | [Yap](goals/m2.md), dictation | time, requests, subscriptions, menu bar and panel surfaces |
| M3 (done) | [Pairs](goals/m3.md), a memory game | images, JSON (`cairn_json`), requests in flight with cancellation, a grid that follows the window, apps built only from packages |
| M4 (done) | [Sky](goals/m4.md), Bluesky: read | login and a session in the Keychain, the home feed, scrolling that lays out only what's on screen, paging, refresh racing "load more" |
| M5 (now) | [Bluesky: act](goals/m5.md) | like, repost, follow and mute shown at once and rolled back on failure, with the count proved to match the server's after any order of replies; notifications |
| M6 | Bluesky: write | the post editor: mentions, links and tags as facets over UTF-8 byte ranges, counting by grapheme cluster, replies and quotes |
| M7 | Bluesky: everywhere | one or several columns by window width, several windows, live updates over a websocket |

Bluesky is the subject from M4 on because nearly every gap left after M3 shows up in it: long
lists, many requests at once, authentication, rich text, optimistic updates and streams. Its
actions (like, repost, reply, follow, mute) are moves with clear rules, such as "a muted account's
posts appear nowhere".

Work that runs alongside the milestones: host capabilities an app declares (#84), the docs
builder (#94), artifacts only from CI (#95). Done: examples in their own scope (#88), in
iamnbutler/cairn_examples since 0.3.0.

## Planned `cairn` commands

Not in `cairn` yet (site/web/content/docs/reference/cairn-tool.md documents the plan):

| Command | What it will do | Today |
|---|---|---|
| `cairn run` | open the app in a window | `cairn build`, then `swift run <App>` |
| `cairn check` | everything a change must pass | `make check` |
| `cairn doctor` | check the toolchain | none |
