import Fixture
import Cairn.Fuzz.Rng

/-! # The fixture's fuzz setup: a server for the likes

`cairn fuzz` finds `Fixture.fuzz` (Cairn's docs/fuzz.md, "A server"). Its server keeps each
post's like as the server would: a register per post, set by an idempotent `PUT` and read by a
`GET`, with a view of each post's count and the viewer's like at `/view/k`. It refuses a write
now and then (429, the world unchanged), and answers 503 after acting now and then (which the
app takes for a lost reply). Other accounts like and unlike between steps
(`tick`), which never touches the viewer's like. The fuzz host adds the two faults: failed
before (the world unchanged) and lost after (the world changed).

^22 is checked against it after every step and once every reply is in: a post with nothing in
flight shows what the server holds. So is ^24: such a post's count is the server's, the other
accounts' likes when its view was served (`served`) plus the viewer's like the server holds. Fixture/LikeMutant.lean runs the same fuzz on the
mutant that takes a lost write for a refused one, and checks that it fails.

Not linked into the app: `Checks` imports it, and the fuzz executable imports `Checks`. -/

namespace Fixture
open Cairn Cairn.Fuzz

/-- One post on the server. -/
structure Post where
  /-- The viewer's like. -/
  liked : Bool := false
  /-- Other accounts' likes. -/
  others : Nat := 0
deriving Repr, Inhabited

/-- What the fake server holds: post `k` at index `k - 1`. -/
structure Server where
  posts : Array Post
  /-- Writes it applied, retransmissions included. -/
  writes : Nat := 0
  /-- For each view it served, by request id: the other accounts' likes then. -/
  served : Std.TreeMap Nat Nat := {}
deriving Inhabited

/-- The post a URL under `prefix` names. -/
def postAt (pre url : String) : Option Nat :=
  if url.startsWith pre then
    ((url.splitOn "/").getLast?.bind String.toNat?).filter fun k => 1 ≤ k && k ≤ Like.posts
  else none

def postOf (url : String) : Option Nat := postAt "http://127.0.0.1:9/like/" url
def viewOf (url : String) : Option Nat := postAt "http://127.0.0.1:9/view/" url

def isLike : Request → Bool
  | .http _ url .. => (postOf url).isSome || (viewOf url).isSome
  | _ => false

def Server.post (w : Server) (k : Nat) : Post := w.posts[k - 1]?.getD {}
def Server.liked (w : Server) (k : Nat) : Bool := (w.post k).liked

/-- The fake server. Its posts are built by the sequence's generator, never a constant, and
marked linear: run with `LEAN_ABORT_ON_NONLINEAR=1` (`make fuzz-quick` does), a copy of them
aborts the run. -/
def server : Fuzz.Server State where
  W := Server
  init := do
    let mut posts : Array Post := Array.emptyWithCapacity Like.posts
    for _ in [0:Like.posts] do
      posts := posts.push { others := ← Gen.below 40 }
    return { posts := posts.markLinear }
  handles := isLike
  handle := fun w id r => do
    match r with
    | .http "PUT" url _ body .. =>
      let some k := postOf url | return (w, .http 404 [] .empty)
      if ← Gen.chance 1 6 then return (w, .http 429 [] "rate limited".toUTF8)
      let v := body == Like.bit true
      let w := { w with posts := w.posts.modify (k - 1) ({ · with liked := v }),
                        writes := w.writes + 1 }
      if ← Gen.chance 1 20 then return (w, .http 503 [] .empty)
      return (w, .http 200 [] .empty)
    | .http "GET" url .. =>
      if let some k := postOf url then
        return (w, .http 200 [] (Like.bit (w.liked k)))
      let some k := viewOf url | return (w, .http 404 [] .empty)
      let p := w.post k
      return ({ w with served := w.served.insert id p.others },
        .http 200 [] (Like.viewBody (p.others + Cairn.Optimistic.ind p.liked) p.liked))
    | _ => return (w, .http 405 [] .empty)
  tick := fun w => do
    let i ← Gen.below Like.posts
    let up ← Gen.bool
    return { w with posts := w.posts.modify i fun p =>
      { p with others := if up then p.others + 1 else p.others - 1 } }
  checks := [(22, fun s w => shows s w), (24, fun s w => counts s w)]
  drained := [(22, fun s w => shows s w), (24, fun s w => counts s w)]
  describe := fun w =>
    s!"liked {w.posts.toList.map (·.liked)}, others {w.posts.toList.map (·.others)}, {w.writes} writes"
where
  /-- Every post at rest shows what the server holds. -/
  shows (s : State) (w : Server) : Bool :=
    (List.range' 1 Like.posts).all fun k =>
      !s.likes.table.settled k || (s.likes.shown k == w.liked k && s.likes.table.server k == w.liked k)
  /-- Every post at rest with a view shows the server's count: the other accounts' likes when
  its view was served, plus the server's value of the viewer's. -/
  counts (s : State) (w : Server) : Bool :=
    (List.range' 1 Like.posts).all fun k =>
      match s.likes.views[k]? with
      | some v =>
        !s.likes.table.settled k || match w.served[v.req]? with
          | some o => s.likes.countOf k == o + Cairn.Optimistic.ind (w.liked k)
          | none => false
      | none => true

def fuzz : Fuzz.Custom State where
  server := some server
  -- Most presses on post 1, so a press races its own write's reply.
  weights := fun _ r => if r.claim = 21 then (if r.key = 1 then 12 else 2) else 1

end Fixture
