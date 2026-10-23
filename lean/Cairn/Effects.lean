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

/-- Something the host does that answers back. Closed: adding a kind is a constructor, its
encoding, a `Reply.answers` case and one host handler (docs/effects.md). -/
inductive Request where
  | readFile (path : String)
  /-- Replace the file atomically, creating missing parent directories. -/
  | writeFile (path : String) (data : ByteArray)
  /-- A named system sound ("Tink", "Pop", "Basso", …). -/
  | playSound (name : String)
  | http (method url : String) (headers : List (String × String)) (body : ByteArray)
      (timeoutMs : Nat)
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
deriving Repr, BEq, Inhabited

/-- The kind of a request, without its payload: what the runtime remembers while it is
pending. -/
inductive Request.Kind where
  | readFile | writeFile | playSound | http
  | appendFile | listDir | deleteFile | frontmostApp | permission
deriving Repr, DecidableEq, Inhabited

def Request.kind : Request → Request.Kind
  | .readFile .. => .readFile | .writeFile .. => .writeFile
  | .playSound .. => .playSound | .http .. => .http
  | .appendFile .. => .appendFile | .listDir .. => .listDir | .deleteFile .. => .deleteFile
  | .frontmostApp => .frontmostApp | .permission .. => .permission

inductive Reply where
  /-- `writeFile`, `appendFile`, `deleteFile` and `playSound` succeeded. -/
  | done
  /-- `readFile`'s contents. -/
  | bytes (data : ByteArray)
  /-- An HTTP response, whatever its status. -/
  | http (status : Nat) (headers : List (String × String)) (body : ByteArray)
  /-- Any request can fail. -/
  | failed (fault : Fault) (message : String)
  /-- `listDir`'s names. -/
  | names (names : List String)
  /-- `frontmostApp`'s process id and name (empty when it has none). -/
  | app (pid : Nat) (name : String)
  /-- `permission`'s answer. -/
  | flag (granted : Bool)
deriving Repr, BEq, Inhabited

/-- Whether a reply has the shape that answers a request of kind `k`. -/
def Reply.answers : Request.Kind → Reply → Bool
  | _, .failed .. => true
  | .readFile, .bytes _ => true
  | .writeFile, .done | .playSound, .done | .appendFile, .done | .deleteFile, .done => true
  | .http, .http .. => true
  | .listDir, .names _ => true
  | .frontmostApp, .app .. => true
  | .permission, .flag _ => true
  | _, _ => false

/-- An outside input an app asks for, as data derived from its state. -/
inductive Sub where
  /-- A tick every `ms` milliseconds (at least 1), from the host. -/
  | every (ms : Nat)
  /-- `changed` whenever the file at `path` changes: written, replaced, created or removed. -/
  | watchFile (path : String)
deriving Repr, DecidableEq, Inhabited

/-- What an active subscription reports. -/
inductive SubEvent where
  /-- `every`'s tick. -/
  | tick
  /-- `watchFile`'s file changed. -/
  | changed
deriving Repr, DecidableEq, Inhabited

/-- Runtime → host: start or stop a subscription, under the runtime's id for it. -/
inductive SubCmd where
  | start (id : Nat) (s : Sub)
  | stop (id : Nat)
deriving Repr, DecidableEq, Inhabited

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

end Cairn
