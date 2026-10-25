module

/-! The outside world as data (docs/effects.md): the time the host reports, the requests an app
can make and the replies they get, and the subscriptions an app can ask for. `Cairn.Input`
builds `Effect` and `Event` on these; the runtime's handling is `Cairn.Runtime.World`. -/

@[expose] public section

/-- Byte payloads print as their size. (Core has no `Repr ByteArray`.) -/
instance : Repr ByteArray := ⟨fun b _ => s!"<{b.size} bytes>"⟩

namespace Cairn

/-- The host's clock. `mono` is monotonic milliseconds (timers and durations use it); `wall`
is milliseconds since the Unix epoch, UTC, and `zone` the local offset from UTC in seconds
(for dates). -/
structure Time where
  mono : Nat := 0
  wall : Int := 0
  zone : Int := 0
deriving Repr, DecidableEq, Inhabited

/-- Why a request failed. Failure is an ordinary reply. -/
inductive Fault where
  | notFound | denied | timeout | network | invalid | other
deriving Repr, DecidableEq, Inhabited

/-- A permission the person grants the app in System Settings (TCC). -/
inductive Permission where
  /-- Privacy & Security › Accessibility: typing into other apps, hearing a global key. -/
  | accessibility
  /-- Privacy & Security › Microphone: recording. -/
  | microphone
deriving Repr, DecidableEq, Inhabited

/-- A part of an `upload` body: bytes Lean built, or audio the host holds. -/
inductive Part where
  | bytes (b : ByteArray)
  /-- The recording of `clip`, 20 ms windows `[start, stop)` (320 samples each; to the end of
  the recording, with any partial last window, for `none`), as a WAV file: 16 kHz, mono,
  16-bit PCM. Lean never sees the samples. -/
  | wav (clip start : Nat) (stop : Option Nat)
deriving Repr, BEq, Inhabited

/-- Where the host reads a secret's value as it sends a request. -/
inductive Secret.Source where
  /-- The environment variable `name` if set and not empty, else `name`'s line in the
  `KEY=value` file `file` (Yap's API key). -/
  | env (file name : String)
  /-- The generic password item `account` in the login keychain, under the app's bundle
  identifier as its service (docs/effects.md, "Secrets in the Keychain"). -/
  | keychain (account : String)
deriving Repr, DecidableEq, Inhabited

/-- A header whose value comes from a secret the host reads when it sends the request, so the
secret never reaches Lean, a frame or a log: `header: scheme ++ value`, where `value` is read
from `source`. -/
structure Secret where
  header : String
  scheme : String
  source : Secret.Source
deriving Repr, DecidableEq, Inhabited

/-- `Authorization: Bearer <value of the Keychain item account>`. -/
def Secret.bearer (account : String) : Secret :=
  { header := "Authorization", scheme := "Bearer ", source := .keychain account }

-- region: effects-request
/-- Something the host does that answers back. Closed: adding a kind is a constructor, its
encoding, a `Reply.answers` case and one host handler (docs/effects.md). -/
inductive Request where
  | readFile (path : String)
  /-- Replace the file atomically, creating missing parent directories. -/
  | writeFile (path : String) (data : ByteArray)
  /-- A named system sound ("Tink", "Pop", "Basso", …). -/
  | playSound (name : String)
  /-- An HTTP request. With a `secret`, the host adds its header as it sends (a missing secret
  answers `failed notFound` and sends nothing). With a non-empty `capture`, a 2xx reply whose
  body is a JSON object has each listed top-level string field (`(field, account)`) written to
  the Keychain item `account` and its value replaced by `""` in the body Lean receives; all or
  nothing: a body that isn't a JSON object, or a listed field that is missing, repeated or not
  a string, answers `failed invalid` and writes nothing. Other replies pass through as they
  came. -/
  | http (method url : String) (headers : List (String × String)) (body : ByteArray)
      (timeoutMs : Nat) (secret : Option Secret := none)
      (capture : List (String × String) := [])
  /-- Append to the file, creating it (mode 600) and missing parent directories. -/
  | appendFile (path : String) (data : ByteArray)
  /-- The names in a directory (not `.` and `..`), sorted by their UTF-8 bytes. -/
  | listDir (path : String)
  /-- Remove a file or a symbolic link; never a directory. -/
  | deleteFile (path : String)
  /-- The app in front: its process id and name. -/
  | frontmostApp
  /-- Whether the app holds `p`; with `prompt`, the system also asks the person if it doesn't. -/
  | permission (p : Permission) (prompt : Bool)
  /-- Bring process `pid` to the front and type `text` into it as key events, then Return if
  `pressReturn`. Needs Accessibility. -/
  | typeText (pid : Nat) (text : String) (pressReturn : Bool)
  /-- `http` with a body of parts the host assembles and an optional secret header (OpenAI's
  transcription request: multipart framing from Lean, the clip's WAV and the key from the
  host). -/
  | upload (method url : String) (headers : List (String × String)) (secret : Option Secret)
      (body : List Part) (timeoutMs : Nat)
  /-- The host may drop the clip's samples. -/
  | forgetClip (clip : Nat)
  /-- Open `target` with its default app (the Finder for a folder, the default editor for a
  text file, System Settings for its URLs): a path (`~/` is the home folder) or a URL with a
  scheme. -/
  | openItem (target : String)
  /-- Whether an app with this bundle identifier is running. -/
  | appRunning (bundleId : String)
  /-- The value of `key` in the defaults domain `domain` (`defaults read domain key`), as UTF-8
  text: a string as it is, a number or a boolean as its text (booleans as `1` or `0`). -/
  | readDefault (domain key : String)
  /-- Create the directory and its missing parents, each private (mode 700); `done` if it is
  already a directory. -/
  | makeDir (path : String)
  /-- Load the image at `source` (a file path, `~/` for the home folder, or an `http`/`https`
  URL) and answer its size in pixels (`Reply.image`); the host keeps the decoded pixels under
  `source` and paints them for `Style.image`s that name it. Lean never sees the pixels. An image
  the host already holds is answered from what it holds, unless `reload`, which reads `source`
  again. -/
  | loadImage (source : String) (reload : Bool)
  /-- Delete the Keychain item `account` (`Secret.Source.keychain`): `done`, also when there is
  none. -/
  | forgetSecret (account : String)
deriving Repr, BEq, Inhabited
-- endregion: effects-request

/-- The kind of a request, without its payload: what the runtime remembers while it is
pending. -/
inductive Request.Kind where
  | readFile | writeFile | playSound | http
  | appendFile | listDir | deleteFile | frontmostApp | permission
  | typeText | upload | forgetClip | openItem | appRunning | readDefault | makeDir | loadImage
  | forgetSecret
deriving Repr, DecidableEq, Inhabited

def Request.kind : Request → Request.Kind
  | .readFile .. => .readFile | .writeFile .. => .writeFile
  | .playSound .. => .playSound | .http .. => .http
  | .appendFile .. => .appendFile | .listDir .. => .listDir | .deleteFile .. => .deleteFile
  | .frontmostApp => .frontmostApp | .permission .. => .permission
  | .typeText .. => .typeText | .upload .. => .upload | .forgetClip .. => .forgetClip
  | .openItem .. => .openItem | .appRunning .. => .appRunning | .readDefault .. => .readDefault
  | .makeDir .. => .makeDir | .loadImage .. => .loadImage | .forgetSecret .. => .forgetSecret

/-- The kinds that count toward the cap on requests in flight (`App.maxInFlight`, docs/effects.md
"Requests in flight"): the ones that can take seconds on the network. The others (files, sounds,
permissions, typing) are sent at once. -/
def Request.Kind.capped : Request.Kind → Bool
  | .http | .upload | .loadImage => true
  | _ => false

-- region: effects-reply
inductive Reply where
  /-- `writeFile`, `appendFile`, `deleteFile`, `makeDir`, `forgetSecret` and `playSound`
  succeeded. -/
  | done
  /-- `readFile`'s contents, or `readDefault`'s value. -/
  | bytes (data : ByteArray)
  /-- An HTTP response, whatever its status. -/
  | http (status : Nat) (headers : List (String × String)) (body : ByteArray)
  /-- Any request can fail. -/
  | failed (fault : Fault) (message : String)
  /-- `listDir`'s names. -/
  | names (names : List String)
  /-- `frontmostApp`'s process id and name (empty when it has none). -/
  | app (pid : Nat) (name : String)
  /-- `permission`'s or `appRunning`'s answer. -/
  | flag (granted : Bool)
  /-- `loadImage`'s answer: the image's size in pixels (after its orientation is applied). -/
  | image (width height : Nat)
deriving Repr, BEq, Inhabited

/-- Whether a reply has the shape that answers a request of kind `k`. -/
def Reply.answers : Request.Kind → Reply → Bool
  | _, .failed .. => true
  | .readFile, .bytes _ => true
  | .writeFile, .done | .playSound, .done | .appendFile, .done | .deleteFile, .done => true
  | .typeText, .done | .forgetClip, .done | .openItem, .done | .makeDir, .done => true
  | .forgetSecret, .done => true
  | .readDefault, .bytes _ => true
  | .http, .http .. | .upload, .http .. => true
  | .listDir, .names _ => true
  | .frontmostApp, .app .. => true
  | .permission, .flag _ | .appRunning, .flag _ => true
  | .loadImage, .image .. => true
  | _, _ => false
-- endregion: effects-reply

-- region: effects-sub
/-- An outside input an app asks for, as data derived from its state. -/
inductive Sub where
  /-- A tick every `ms` milliseconds (at least 1), from the host. -/
  | every (ms : Nat)
  /-- `changed` whenever the file at `path` changes: written, replaced, created or removed. -/
  | watchFile (path : String)
  /-- Record `clip` from the microphone while active: `started` once the microphone is running,
  then `audio`; or `failed` if it can't start. Stopping it stops the microphone. The host keeps
  the samples for `Part.wav`. Needs Microphone. -/
  | record (clip : Nat)
  /-- The key with virtual key code `code` (with `modifier`, the `NSEvent.ModifierFlags` bit
  that tells a modifier key's press from its release): `keyDown`, `keyUp`, and `otherKey` for
  any other key pressed while it is down. Needs Accessibility. -/
  | globalKey (code : Nat) (modifier : Option Nat)
  /-- Keep the host's decoded images (`Request.loadImage`) within about `bytes` bytes of pixels
  while active: past it the host drops the images used least recently, never one the latest
  frame draws nor the one it just loaded, and reports each with `evicted` (^1011). Without it
  the host keeps every image. The smallest budget of those active wins. -/
  | imageCache (bytes : Nat)
deriving Repr, DecidableEq, Inhabited
-- endregion: effects-sub

/-- One 20 ms window of a recording (320 samples at 16 kHz), as integers. -/
structure Level where
  /-- The sum of its samples' squares. -/
  sumSq : Nat
  /-- Its largest absolute sample (`Int16.min` counts as `Int16.max`). -/
  peak : Nat
deriving Repr, DecidableEq, Inhabited

/-- What an active subscription reports. -/
inductive SubEvent where
  /-- `every`'s tick. -/
  | tick
  /-- `watchFile`'s file changed. -/
  | changed
  /-- `record`: `frames` more samples, their largest absolute value `peak`, and the 20 ms
  windows they complete, in order from the start of the clip. -/
  | audio (frames peak : Nat) (windows : List Level)
  /-- `record`: the microphone is running, since monotonic milliseconds `t` (when its start
  returned). Sent once, before any `audio`, and never after a `failed` that says it could not
  start. -/
  | started (t : Nat)
  /-- `globalKey`: the key went down or up, or another key went down while it was held, at
  monotonic milliseconds `t` (the clock of `Time.mono`). -/
  | keyDown (t : Nat)
  | keyUp (t : Nat)
  | otherKey (t : Nat)
  /-- The subscription could not run (a permission missing, no microphone). It may still be
  running; an app stops it by not asking for it. -/
  | failed (fault : Fault) (message : String)
  /-- `imageCache`: the host dropped `source`'s pixels; sent after they are gone. An app that
  forgets the image when it hears this (`Images.evicted`, which also stops waiting for its
  loads) never takes an image for ready while the host has no pixels for it
  (`Images.Cache.ready_held`). -/
  | evicted (source : String)
deriving Repr, DecidableEq, Inhabited

/-- Runtime → host: start or stop a subscription, under the runtime's id for it. -/
inductive SubCmd where
  | start (id : Nat) (s : Sub)
  | stop (id : Nat)
deriving Repr, DecidableEq, Inhabited

-- region: effects-msg
/-- Runtime → app, through `App.receive`: the outside world. -/
inductive Msg where
  /-- The current time, delivered before anything else whenever it changed. -/
  | clock (t : Time)
  /-- A timer the app set has come due. -/
  | timer (name : String)
  /-- The answer to request `id`. -/
  | reply (id : Nat) (r : Reply)
  /-- An event from an active subscription. -/
  | sub (s : Sub) (e : SubEvent)
deriving Repr, BEq, Inhabited
-- endregion: effects-msg

end Cairn
