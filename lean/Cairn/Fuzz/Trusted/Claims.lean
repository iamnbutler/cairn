module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab

/-! The trusted base's assumptions (docs/trusted.md), each naming the check of the trusted-base
fuzzer that gathers its evidence (`make fuzz-trusted`, `build/fuzz/trusted.json`, docs/fuzz.md
"Trusted base"). Evidence, not proof: these stay assumptions.

Ids 901–999 and 1000 on are for framework-level assumptions; apps' own assumptions use their apps' ranges.
^7 and ^214 are framework-level too, kept from the examples that first declared them.
Not imported by `Cairn` (the host links that); the ledger reads this module as a root. -/

namespace Cairn.Fuzz.Trusted.Claims

assume ^901 swiftFrameDecoder "The Swift frame decoder agrees with Lean's" where
  does "For every byte buffer, the host's Frame(bytes:) accepts exactly when Lean's proved decodeFrame does, and then decodes the same frame."
  check "frame.decode"

assume ^902 swiftEventEncoder "Lean decodes what the Swift event encoder writes" where
  does "For every batch of events, Lean's proved decodeEvents decodes the host's encodeEvents bytes to the same events, and Lean's encoder gives back the same bytes."
  check "events.encode"

assume ^903 textIndex "UTF-16 offsets and scalar indices convert exactly" where
  does "TextIndex maps between AppKit's UTF-16 offsets and Lean's scalar indices exactly on boundaries, rounds offsets inside a surrogate pair to a whole scalar, and clamps AppKit ranges (NSNotFound, negative, past the end) to whole scalars."
  check "text.index"

assume ^904 textShadow "The text-input shadow predicts Lean's field" where
  does "Between an input-method call and the frame that reflects it, the host's copy of the focused field has the text, selection and marked range Lean's field will show."
  check "text.shadow"

assume ^905 inputClientGeometry "Input-method geometry agrees with Lean's caret" where
  does "selectedRange and markedRange are Lean's, firstRect at the selection is Lean's caret, and characterIndex(for:) maps points back to scalar boundaries of the field."
  check "text.input-client"

assume ^906 textMetricsHost "The host's text metrics are what layout assumes" where
  does "cairn_text_metrics gives one offset per scalar boundary, from 0 and nondecreasing, with nonnegative ascent and descent, and Lean's TextMetrics.host sees those numbers unchanged."
  check "text.metrics"

assume ^907 textCaretsPainted "Carets follow the painted glyphs" where
  does "On left-to-right text, the caret offset after each grapheme is at or right of every glyph painted for the text before it."
  check "text.metrics.carets"

assume ^908 hostClock "The host's clock is monotonic milliseconds" where
  does "Every batch the host sends Lean starts with exactly one clock event; its monotonic milliseconds never decrease from batch to batch and are not ahead of the system's monotonic clock, its wall time is the wall clock and its zone the current UTC offset."
  check "clock.monotonic"

assume ^909 hostWake "The host wakes Lean by wake" where
  does "When a frame carries a wake deadline, the host sends a clock-only batch whose time is at or past the deadline, soon after it, and sends none for a deadline that a later frame cleared or met."
  check "clock.wake"

assume ^910 hostReadFile "readFile replies with the file's bytes, or failed" where
  does "readFile answers with exactly the bytes the file holds, notFound for a missing file, a failure for a directory or an unreadable file, and invalid for a path that can't name a file."
  check "effects.read-file"

assume ^911 hostWriteFile "writeFile is atomic, and replies done only when the bytes are there" where
  does "writeFile answers done only when the file then holds exactly the bytes, creating missing directories; a reader alongside sees the old bytes or the new ones, never a mix; a failed write leaves the old file unchanged; a path that can't name a file is invalid."
  check "effects.write-file"

assume ^912 hostPlaySound "playSound starts a known sound and refuses an unknown one" where
  does "playSound finds every system sound by its name and answers done once it starts; any other name is answered notFound, once, without playing anything."
  check "effects.sound"

retire ^913 assume "http sends the request as given and returns the response as received" because "Reissued as ^974: http gained a secret header and captured reply fields (#205), so a request with them is no longer sent and answered exactly as given; a published claim keeps its statement."

assume ^914 hostReplyOnce "The host answers every request exactly once, with its id" where
  does "Every request the host runs is answered at most once and, when its handler answers, exactly once, under its own id with the handler's first answer; a kind with no handler is answered invalid; after the app starts over no answer to an earlier request is sent."
  check "effects.reply-once"

assume ^915 hostEvery "every ms ticks while started and never after it is stopped" where
  does "An every subscription ticks under its id only while it is started and not yet stopped, at most once per period, and the host's running subscriptions are exactly those the frames started and did not stop."
  check "subs.every"

/-! Yap's host effects (workstream T, docs/effects.md "What Yap needs"), ids 960–989. -/

assume ^960 hostAppendFile "appendFile adds exactly the bytes at the end, or fails and adds nothing" where
  does "appendFile answers done only when the file then holds its old bytes followed by exactly the new ones, creating the file with mode 600 and missing directories; appends from several threads each land whole; a directory, a path under a file, a read-only file and a path that can't name a file fail and leave the file unchanged."
  check "effects.append-file"

assume ^961 hostListDir "listDir lists exactly the directory's names, sorted" where
  does "listDir answers with exactly the names in the directory, without . and .., sorted by their UTF-8 bytes; a missing directory is notFound, a file invalid, an unreadable directory denied."
  check "effects.list-dir"

assume ^962 hostDeleteFile "deleteFile removes a file or a link, never a directory" where
  does "deleteFile answers done only when the file or link (not its target) is gone, notFound when there is none, invalid for a directory, which stays, and denied when its directory is read-only, leaving the file."
  check "effects.delete-file"

assume ^963 hostWatchFile "watchFile reports every change to its file, and nothing after its stop" where
  does "While a watchFile subscription runs, every write, replacement, append, creation, removal, touch or mode change of its file is followed by a changed event within a few polls, an untouched file brings none, and after its stop has been handled none is sent."
  check "subs.watch-file"

assume ^964 hostFrontmostApp "frontmostApp answers the app in front" where
  does "frontmostApp answers with the process id and name of the app the system reports in front, notFound when there is none; the pid names a running process."
  check "effects.frontmost-app"

assume ^965 hostPermission "permission answers whether the app holds it, and prompts only when asked" where
  does "permission answers flag true exactly when the app holds Accessibility (AXIsProcessTrusted) or the microphone (authorized); the system is asked to prompt only when prompt is set, the microphone only while undecided, answering with the person's choice; each request is answered once."
  check "effects.permission"

assume ^966 hostRecord "record streams the levels of exactly the samples it keeps, and nothing after its stop" where
  does "While a record subscription runs, its audio events count every sample the clip keeps, in order, and their windows are the 20 ms levels (sum of squares and peak of each 320 samples) of those samples from the start of the clip, however the microphone split them; after its stop has been handled none is sent and the clip is finished; a microphone that can't start (no permission, no device) is one failed event and an empty clip, and the microphone is never started without the permission."
  check "subs.record"

assume ^1005 hostRecordStarted "record reports started once its microphone is running, before any audio, or fails without it" where
  does "A record subscription's first event is started, sent once, only after the microphone's start has returned (the engine is running), and before every audio event of it, with the host's monotonic milliseconds (the clock of key events) read after the return; a microphone that can't start sends failed and never started. So an app that waits for started shows nothing for a microphone that fails, as Yap shows its overlay only once AudioCapture.start has returned."
  check "subs.record-start"

assume ^967 hostClipWav "A clip's WAV for a range of windows holds exactly those samples" where
  does "An upload's wav part for clip c and windows s to e is a 16 kHz mono 16-bit RIFF/WAVE file of exactly samples 320 s to 320 e of the clip (to the end of the clip when e is none, waiting for a clip whose recording is being stopped); a range past the end or backwards is invalid, an unknown or forgotten clip notFound, and forgetClip answers done once and notFound after."
  check "effects.clip-wav"

assume ^968 hostGlobalKey "globalKey reports the hotkey's press and release, and other keys while it is held" where
  does "A globalKey subscription reports keyDown and keyUp of the hotkey and otherKey for any other key pressed while it is down, as Yap's PushToTalk does (a modifier by its flag in flagsChanged, an ordinary key by key down without repeats and key up, no repeated state), with monotonic times; without Accessibility it reports failed denied and installs nothing; after its stop has been handled none is sent."
  check "subs.global-key"

assume ^969 hostTypeText "typeText types exactly the text into that app, or nothing" where
  does "typeText posts the text as key events whose payloads, in order, are exactly its UTF-16 units, at most 20 per event and never splitting a character, then Return only when asked, and only after the app with that pid is in front; empty text is invalid, no Accessibility denied, no such app notFound and an app that won't come forward failed, and then nothing is posted."
  check "effects.type-text"

assume ^970 hostUpload "upload sends the body assembled from its parts, with the secret in its header" where
  does "upload sends one request whose body is its parts in order, each wav part replaced by the clip's WAV, with its headers and, for a secret, the header scheme ++ value; a missing clip, bad range or missing secret fails before anything is sent; otherwise it answers as http does."
  check "effects.upload"

retire ^971 assume "A secret is read from the environment or its file, and never shown" because "Reissued as ^975 for environment secrets: a secret can now also be a Keychain item (^972, #205); a published claim keeps its statement."

/-! Secrets in the Keychain (M4, #205, docs/effects.md "Secrets in the Keychain"), ids 972–975. -/

assume ^972 hostKeychain "The Keychain keeps what it was given for this app" where
  does "The host's Keychain store keeps one generic password item per account, under the app's service (its bundle identifier), in the login keychain (file-based, not synchronized to iCloud, no access group): reading an account gives the value last written to it, exactly, until it is deleted; writing one account changes no other; forgetSecret deletes the item and answers done, also when there was none; a Keychain secret whose item is missing answers failed notFound. Values never appear in a reply, failure message, frame, dump or debug description."
  check "effects.secret.keychain"

assume ^973 hostCapture "Captured reply fields go to the Keychain and never to Lean" where
  does "For an http request with captures, a 2xx reply whose body is a JSON object with each listed top-level field present once as a string has each value written exactly to its account's Keychain item, and Lean receives the body with each of those values written as an empty string and every other byte as the server sent it; a body that is not a JSON object, or a listed field that is missing, repeated or not a string, answers failed invalid and writes nothing, and a failed write leaves every item as it was. Any other reply passes through unchanged. A captured value appears in no reply, failure message, frame, dump or debug description."
  check "effects.http.capture"

assume ^974 hostHttpSecret "http sends the request as given, with its secret header, and returns the response as received" where
  does "http sends the method, URL, headers and body as given, plus for a secret the header scheme ++ value, and answers with the response's status, headers sorted by name and body exactly (captured fields aside, ^973); a missing secret is notFound and sends nothing; a request with a secret never follows a redirect, answering the 3xx; a connection failure is network, no answer in time is timeout, and a non-http URL, a bad method, a header (the secret's too) that could inject another, or an empty account is invalid and sends nothing."
  check "effects.http"

assume ^975 hostEnvSecret "An environment secret is read from the environment or its file, and never shown" where
  does "An environment secret's value is the environment variable if set and not empty, else its line in the KEY=value file as Yap's Secrets.parseDotEnv reads it (comments, export, quotes, a later line wins); a missing one is failed notFound; the value appears in the request's header and in no reply, failure message or debug description."
  check "effects.secret"

/-! Wrapped text (workstream V, docs/layout.md "Wrapped text"), ids 990–999. -/

assume ^990 wrapPainted "Wrapped lines paint as wide as Lean measured them" where
  does "On left-to-right text without controls or tabs, each line Lean's wrapping chose, shaped again on its own by the host, is within 1 + ceil(0.15 em) points of the width Lean took from the whole string's carets, and so fits the width up to that slack; laid lines sit at x 0, one line height apart."
  check "text.wrap.painted"

assume ^991 wrapCoreText "Lean breaks lines where Core Text would" where
  does "On left-to-right letters, digits and spaces, Lean's lines are Core Text's (CTTypesetterSuggestLineBreak, trailing spaces trimmed) except where a line is within one point of the width or a word is cut, where the cut is within two scalars of Core Text's."
  check "text.wrap.coretext"

/-! Surfaces (workstream S, docs/surfaces.md): menus and overlay panels, ids 940–959. -/

assume ^940 hostMenuRender "The native menu shows exactly the frame's menu records" where
  does "After each frame, a status item's NSMenu tree holds the frame's menu records in order: each item's title, enabled state, checkmark, key equivalent and ref, separators where they are, each submenu under its item with its own records, and status lines shown but not actionable; updating it in place or rebuilding it gives the same tree."
  check "menu.render"

assume ^941 hostMenuSelect "Choosing a menu item reports that item's ref" where
  does "When AppKit performs a menu item's action, the host sends exactly one menuSelect with the status item's place and that item's ref, and nothing for a status line, separator or submenu; Lean checks the ref against the menu it is showing (menu_select_stale)."
  check "menu.select"

assume ^942 hostMenuOpenClose "Opening and closing the menu are reported once each" where
  does "When the status item's menu opens the host sends one menuOpen with its place, and one menuClose when it closes; submenus opening and closing send nothing."
  check "menu.open-close"

assume ^943 hostPanelInert "An overlay panel never takes focus or clicks" where
  does "Every overlay panel is a non-activating panel that cannot become key or main, ignores the mouse, sits at status-bar level on every Space and over full-screen apps, is not hidden when the app deactivates and is transparent, whatever frames it is given."
  check "panel.inert"

assume ^944 hostPanelPlace "An overlay panel is where its anchor says" where
  does "A shown panel's frame has its canvas's size, horizontally centred in the chosen screen's visible frame and the anchor's offset above its bottom, on whole points; the screen is chosen when it appears and kept until it is hidden."
  check "panel.place"

assume ^945 hostControlMenuRender "A control's menu shows exactly the frame's menu records" where
  does "While the window's frame record shows a control's menu (its status: the owner and the menu records), the host's native menu for it holds those records as a status item's does (^940), for that owner, at the window's place; a frame with no menu records shows none."
  check "control-menu.render"

assume ^946 hostControlMenuSelect "Choosing a control menu's item reports its ref, then the close" where
  does "When AppKit performs an item's action in a control's menu, the host sends exactly one menuSelect with the window's place and that item's ref, and nothing for a status line, separator or submenu; when the menu closes, chosen from or not, it sends one menuClose with the window's place, after any menuSelect."
  check "control-menu.select"

assume ^947 hostControlMenuDismiss "The host shows a control menu only while Lean has it open" where
  does "The host shows a control's menu exactly when the last frame shows one, except that after the host closed it, a frame that does not yet account for that close (its events are numbered below the close) does not open it again; a frame without the menu, or without a window, dismisses one that is open."
  check "control-menu.dismiss"

assume ^948 hostAxShowMenu "AXShowMenu opens a control's menu as a right click does" where
  does "An assistive app may perform AXShowMenu on exactly the AX elements of controls with a menu, and doing so sends a secondary click (move, down, up) at the node's centre, then puts the pointer back; a control that is a menu button is an AXMenuButton."
  check "ax.show-menu"

assume ^949 hostMenuBarRender "The menu bar shows the app's menu items" where
  does "After each frame with a menuBar surface, each of its top-level submenus is a menu in the main menu before the host's Window menu, with its records as a status item's menu has them (^940), and every other top-level entry is at the top of the app menu, in order, followed by a separator and the host's own Hide and Quit, unchanged; Edit and Window stay where they are."
  check "menubar.render"

assume ^950 hostMenuBarSelect "A menu bar item, by click or key equivalent, reports that item's ref" where
  does "When AppKit performs an enabled menu bar item's action, chosen with the pointer or by its key equivalent (NSMenu.performKeyEquivalent with the keys a keyboard gives, a capital for a shifted letter), the host sends exactly one menuSelect with the menuBar surface's place and that item's ref; the key equivalent of a greyed item sends nothing."
  check "menubar.select"

/-! Yap on Cairn (workstream W): opening files and URLs, other apps, other domains' defaults, ids 1000–. -/

assume ^1000 hostOpenItem "openItem opens exactly the URL or existing file it names" where
  does "openItem with a target that has a URL scheme asks the system to open that URL; with a path (a leading ~/ is the home folder) it opens that file or folder with its default app only when it exists, and answers notFound otherwise; it answers done exactly when the system took it, and an empty target or one with NUL is invalid and opens nothing."
  check "effects.open-item"

assume ^1001 hostAppRunning "appRunning answers whether an app with that bundle id runs" where
  does "appRunning answers flag true exactly when the system lists a running, not terminated app with that bundle identifier; an empty identifier is invalid."
  check "effects.app-running"

assume ^1002 hostReadDefault "readDefault answers the default's value as text" where
  does "readDefault answers the value CFPreferences holds for the key in the domain as UTF-8 bytes: a string as it is, a boolean as 1 or 0, a number as its decimal text; a missing value is notFound, any other type and an empty domain or key invalid. It never writes a default."
  check "effects.read-default"

assume ^1003 hostMakeDir "makeDir makes a private directory and its parents" where
  does "makeDir answers done only when the path is then a directory, each directory it made mode 700 whatever the umask, one already there done and left as it was; a file in the way, a path under a file, a read-only parent, NUL and the empty path fail."
  check "effects.make-dir"

/-! Host-drawn content (workstream Y, docs/frame.md "Draw records"): ids 1004–1019 (^1003 is the trusted makeDir claim). -/

assume ^1004 hostPaintBounds "A painter's pixels stay inside its box" where
  does "A paint draw changes no pixel outside its rect (snapped to device pixels as rects are) within the clip in force, whatever its painter draws and whatever data, time or scale it is given; a paint naming no registered painter changes nothing. Checked offscreen against the same frame without its paint draws, with Yap's tape painter and painters whose triangles cover the whole target or land anywhere."
  check "render.paint.bounds"

/-! Images (docs/effects.md "Images", docs/frame.md `image` draws). -/

assume ^1006 hostLoadImage "loadImage answers the image's pixel size, or the fault" where
  does "loadImage of a file path (~/ is home, relative to the working directory) or an http(s) URL decodes the first image with ImageIO, applying its EXIF orientation, keeps it for image draws naming the same source and answers image with the oriented pixel size, exactly once; a missing file is notFound, an unreadable one denied, a directory, an empty source, NUL or bytes that are no image invalid; HTTP 404 and 410 notFound, 401 and 403 denied, any other status outside 2xx other, a failed connection network, a timeout timeout. Without reload a kept source is answered from the store without reading; with reload it is read again, and a failure removes it."
  check "effects.load-image"

assume ^1007 hostImageBounds "An image's pixels stay inside its box" where
  does "An image draw changes no pixel outside its rect (snapped to device pixels as rects are) within the clip in force, whatever its destination rect and scale; a draw naming a source the host holds no image for changes nothing."
  check "render.image.bounds"

assume ^1008 hostImagePixels "An image is drawn where its oriented pixels are" where
  does "An image draw scales the oriented image to its destination rect: each quadrant of the image lands in the same quadrant of the destination, in its colour (within 8 per channel, 40 for JPEG and HEIC), whatever the EXIF orientation, format and scale."
  check "render.image.pixels"

/-! Requests in flight (docs/effects.md "Requests in flight"). -/

assume ^1009 hostCancelRequest "cancelRequest stops a running request's work; it is still answered once" where
  does "On cancelRequest for a request still running, the host stops its work where it can (an http, upload or loadImage download's URLSession task is cancelled) and still answers it exactly once, failed if the work was stopped, at once if its handler had not started; a cancelled loadImage leaves the image store as it was; a cancel of an id already answered or never requested does nothing."
  check "effects.cancel"

/-! The window's size (docs/surfaces.md, `App.minSize`). -/

assume ^1010 hostWindowMinSize "The window is never smaller than the app's minimum size" where
  does "The host sets the window's contentMinSize to the minimum size of the frame's window record (a negative side as 0), so a person can't drag it smaller, clamps every live resize AppKit proposes to it, and grows a window already smaller to it, keeping its top-left corner; a minimum the window meets leaves it alone. So every resize Lean hears is at least the minimum the app asked for, from the first frame that asks for it."
  check "window.min-size"

/-! Pointer input (`HostView`'s mouse handlers). Every app relies on these, so they are Cairn's,
not an app's; they keep the ids the Counter and TodoMVC examples first gave them. -/

-- region: trusted-host-clicks
assume ^7 hostClicks "The host reports clicks where they happen" where
  does "The host sends a pointer down and up at the logical point the person clicked, in order."
  check "pointer.click"
-- endregion: trusted-host-clicks

-- region: trusted-double-click
assume ^214 doubleClick "The host reports a double click as a second click" where
  does "The host sends the second click of a double click as a pointer down with a click count of 2, at the same point, within the system's double-click interval; the runtime turns its release into a double press. (T20)"
  check "pointer.double-click"
-- endregion: trusted-double-click

-- region: trusted-host-scroll
assume ^1012 hostScroll "The host reports scrolls where they happen, toward the end positive" where
  does "The host sends each wheel or trackpad scroll as a scroll event at the logical point under the pointer, with positive dy toward the end of the content (AppKit's deltas negated, natural scrolling already applied) and 16 points to a wheel line; fractions carry, so the total stays within a point of AppKit's. The runtime moves the scroll box under that point by it (Runtime.wheel)."
  check "pointer.scroll"
-- endregion: trusted-host-scroll

/-! The image cache's budget (docs/effects.md, "Images"; `Sub.imageCache`). -/

assume ^1011 hostImageCache "The image cache reports every image it drops, after it is gone" where
  does "While an imageCache subscription runs, the host keeps its decoded images within the smallest running budget: past it, it drops the images used least recently, never one the latest published frame draws nor the one just loaded, and sends evicted for every image it drops (a failed reload's removal too) after the pixels are gone. It answers loadImage ready only after it held the pixels for that load. With Images.evicted on the Lean side, an image the app takes for ready has its pixels with the host once every message is heard (Images.Cache.ready_held_quiet)."
  check "images.cache"

/-! Secure fields (docs/text.md, "Secure fields"). -/

assume ^1020 hostSecureInput "Secure event input is on exactly while a secure field has focus" where
  does "The host turns the system's secure event input on (EnableSecureEventInput) when the applied frame's text input is a secure field, its window is key and the view is live, and off (DisableSecureEventInput) when any of those stops, the view is shut down or released; it calls them in pairs, never twice the same way in a row, so it never leaves secure input on. While it is on, no other process can read the keystrokes."
  check "text.secure-input"

/-! The accessibility mirror under scroll areas and on secure fields (docs/host.md, "Accessibility"). -/

assume ^1021 hostAxScroll "Assistive apps reach only what a scroll area shows" where
  does "The host's accessibility tree holds exactly the frame's AX nodes that are not scrolled out, each under its frame parent in frame order: a node is scrolled out when it or a node above it has an empty rect with a scroll area above that (the frame gives each node its visible rect, Frame.ofLaid). A scroll area is an AXScrollArea; a hit test answers only elements in the tree; the focused element is the focused node's even when it is scrolled out."
  check "ax.scroll"

assume ^1022 hostAxSecure "A secure field shows assistive apps nothing typed" where
  does "A frame node marked secure is an AXTextField with subrole AXSecureTextField, no value, no characters, no selected text and an empty string for every range, whatever its node or the text input holds; no other element shows its text. The debug socket's description of an http request shows no header value, body or secret, and no URL when the request is redact."
  check "ax.secure"

/-! The Dock badge and announcements (docs/effects.md, "The Dock badge and announcements"). -/

assume ^1030 hostBadge "The badge the host shows is the label of the last badge effect, or none" where
  does "The host sets the Dock tile's badge label (NSApp.dockTile.badgeLabel) to exactly the label of each badge effect, as it is, in the order the frames hand them over, and clears it for badge none; it never sets the badge otherwise. So the badge shown is the label of the last badge effect, or none."
  check "dock.badge"

assume ^1031 hostAnnounce "An announcement is posted once, with exactly its text" where
  does "For each announce effect the host posts one announcementRequested accessibility notification (NSAccessibility.post) for its window, carrying exactly the effect's text and its priority (low or high), in order, and posts none otherwise. Its text is the app's: the fuzzer checks that text typed into a secure field never reaches an effect's dump, announcements included."
  check "ax.announce"

/-! Conformance's held world (docs/conformance.md, "The world"; the debug socket's `holdWorld`). -/

assume ^1032 hostHoldWorld "Under holdWorld the host sends no clock, wake or reply of its own" where
  does "Once Engine.holdClock and World.holdRequests have returned, every batch Lean hears is exactly the events the caller sent, in order (the driver's clock and reply events among them): the host adds no clock, sends no wake whatever the frame's wake deadline, and runs and answers no request handed over afterwards; a request from before the hold is answered at most once. Lean never hears an empty batch."
  check "world.hold"

end Cairn.Fuzz.Trusted.Claims
