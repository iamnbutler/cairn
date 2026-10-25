# Demo videos and the site

The microsite at https://cairn.iamnbutler.workers.dev shows what Cairn is and a dated log of demo
videos. Record a video whenever something new works on screen.

- `site/`: a Cloudflare Worker. `public/` holds the static files and `web/` the pages bongo builds
  (the homepage, `/milestones/`, the docs and the feed); `/m/<key>` is served from the
  `cairn-media` R2 bucket with range requests (video seeking, Safari) and immutable caching.
  `public/media.json` lists the videos and notes, newest first; the homepage shows the featured one and
  `/milestones/` renders each milestone's progress log from it.
- `/feed.xml` is the RSS feed: one item per milestone (from the `article.post`s in
  `web/content/milestones/index.hbs`) and one per video or note (from `media.json`).
  `site/web/lib/site.ts` builds it when bongo builds the site (`make site-build`, run by `make
  site`), along with the homepage's pointer to the latest milestone and its list of ids that
  moved to `/milestones/`. None of them is committed.
- `make record` builds `build/bin/record`, which records **one window only** through
  ScreenCaptureKit's desktop-independent window filter. Never record the screen or a region:
  other apps' windows hold private content.

  ```sh
  build/bin/record --pid <pid> --out /tmp/take.mov --seconds 10   # or stop with Ctrl-C
  ```

  Drive the app during the take with real input or accessibility presses on `^N` ids.

  A panel (a non-activating window above layer 0, like Yap's overlay) is taken by its window
  id, still only if the app owns it: `--window <id> --wait 2` waits for it to come on screen,
  and `--size WxH` (points) fixes the output for a panel that grows. Yap's overlay take:
  `CairnYap --bench-demo` (yap-cairn's host/Sources/CairnYap/Bench.swift) plays a synthetic dictation with
  no microphone, key, network or typing, and prints `demo: panel window <id>`; then
  `build/bin/record --pid <pid> --window <id> --wait 2 --size 556x214 --out take.mov --seconds 14`
  (it stops when the panel closes).
- `tools/media/put.sh <take.mov> <title> <caption> [--feature] [--milestone m1|m2]` encodes to H.264, uploads the video
  and a poster under content-hashed keys, and adds an entry to `media.json` (with the date, the time it was published, which the feed
  uses, and the commit). `--feature` makes it the video at the top of the page, and `--milestone` (default `m2`, the current goal) picks which milestone's progress log it appears in. The featured video is whichever best represents the project as it is now (not simply the newest); each time a video lands, decide whether it beats the current one.
- **Notes** are log entries with no video, for work that has nothing new to show on screen (a
  release, docs, a measurement). Add one by hand at its place in `media.json` (newest first):
  `title`, `text` (a list of plain-text paragraphs), `date`, `published` (when the work landed:
  the merge time from git, as UTC), `commit` and `milestone`. The milestones page shows it with
  its date and commit, and the feed makes it an item. Write it like the captions: plain,
  concrete and short, with every number taken from the PR or the repository. Never dress a note
  up as a video.
- Commit `media.json` in a lane and merge it. Then deploy **only from an up-to-date main**:
  `git pull --ff-only` in the main checkout, then `make site`. Never deploy from a lane: the live
  site must always match main, or one session's deploy overwrites another's work (the site's
  design and the video list are edited by different sessions).

The recorder must run inside an `NSApplication` (`NSApplication.shared.run()`), because
ScreenCaptureKit creates its menu-bar recording indicator on its own queue and asserts that
CoreGraphics and AppKit are initialised; `dispatchMain()` crashes.
