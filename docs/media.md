# Demo videos and the site

The microsite at https://cairn.iamnbutler.workers.dev shows what Cairn is and a dated log of demo
videos. Record a video whenever something new works on screen.

- `site/`: a Cloudflare Worker. `public/` is the static page; `/m/<key>` is served from the
  `cairn-media` R2 bucket with range requests (video seeking, Safari) and immutable caching.
  `public/media.json` lists the videos, newest first; the page renders from it.
- `make record` builds `build/bin/record`, which records **one window only** through
  ScreenCaptureKit's desktop-independent window filter. Never record the screen or a region:
  other apps' windows hold private content.

  ```sh
  build/bin/record --pid <pid> --out /tmp/take.mov --seconds 10   # or stop with Ctrl-C
  ```

  Drive the app during the take with real input or accessibility presses on `^N` ids.
- `tools/media/put.sh <take.mov> <title> <caption> [--feature] [--milestone m1|m2]` encodes to H.264, uploads the video
  and a poster under content-hashed keys, and adds an entry to `media.json` (with the date and
  commit). `--feature` makes it the video at the top of the page, and `--milestone` (default `m2`, the current goal) picks which milestone's progress log it appears in. The featured video is whichever best represents the project as it is now (not simply the newest); each time a video lands, decide whether it beats the current one.
- Commit `media.json` in a lane and merge it. Then deploy **only from an up-to-date main**:
  `git pull --ff-only` in the main checkout, then `make site`. Never deploy from a lane: the live
  site must always match main, or one session's deploy overwrites another's work (the site's
  design and the video list are edited by different sessions).

The recorder must run inside an `NSApplication` (`NSApplication.shared.run()`), because
ScreenCaptureKit creates its menu-bar recording indicator on its own queue and asserts that
CoreGraphics and AppKit are initialised; `dispatchMain()` crashes.
