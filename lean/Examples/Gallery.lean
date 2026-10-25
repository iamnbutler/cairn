module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Cairn.App
public import Cairn.UI.Images
public import Cairn.UI.Grid
public import Cairn.Layout.Core

/-! # Gallery: images

The example for images (docs/effects.md, "Images"). Six tiles: three pictures bundled with the
app (a PNG, a JPEG stored turned a quarter with an EXIF orientation, a GIF), one fetched over
https, and two that fail (a file that is no image, a file that isn't there).

* **Layout first.** Each tile's image is `Node.image` at 200 × 150 points in every state, so the
  grid is laid out before any pixels exist and nothing moves when they arrive or fail
  (`Layout.measure_image`).
* **Requests.** At launch every source is asked for with `loadImage` (`Images.loadAll`); a reply
  gives the pixel size (shown under the tile) or the fault (shown in the tile). Lean never holds
  pixels: the host keeps them by source and paints them into the box Lean laid out.
* **Moves.** Reload cancels any load still in flight (`Images.cancelAll`), then asks again for
  every source, past the host's cache; pressing a tile does the same for that tile alone; Fit
  cycles how the pictures fill their boxes.
* **A grid that follows the window** (`Cairn.Grid`). The tiles are as many columns of at least
  180 points as fit the width the window leaves them, 4:3 pictures with a caption under each,
  20 points apart; they shrink when the rows would be taller than the window. Resizing reflows
  them. The view reads the window size from `UI.size`; the host only reports it.

| Id | Kind | What |
|---|---|---|
| ^501 | move | Reload: every tile back to its placeholder, every source read again |
| ^502 | move | Fit: cover, contain, stretch |
| ^503 | place | the window |
| ^504 | invariant | pending loads have ids below the next request's |
| ^505 | flow | reload, then fit the pictures inside their tiles |
| ^506 | move | Load 24: 24 thumbnails from a slow server, at most six fetched at once |
| ^507 | move | Cancel: the thumbnails still loading stop, queued or being fetched |
| ^508 | flow | load many, then cancel |
| ^509 | move | Press a tile: that tile alone loads again |
| ^510 | invariant | at every window size the tiles don't overlap, stay in the window and read in order |

The v1 exports are in `Examples.Gallery.Abi`; theorems about the view in
`Examples.Gallery.Proofs` (^510's evidence among them); the host side is `host/Sources/CairnGallery`. -/

@[expose] public section

namespace Examples.Gallery
open Cairn Cairn.Claims

structure Tile where
  source : String
  title : String
deriving Repr

/-- A poster from the Cairn site (immutable: its name is its content's hash). -/
def posterURL : String := "https://cairn.iamnbutler.workers.dev/m/videos/a79d52b1bab3288e.jpg"

/-- Paths are relative to the app's resources (the host starts there). -/
def tiles : List Tile := [
  ⟨"images/ridge.png", "Ridge (PNG)"⟩,
  ⟨"images/tide.jpg", "Tide (JPEG, turned)"⟩,
  ⟨"images/moss.gif", "Moss (GIF)"⟩,
  ⟨posterURL, "Clock poster (https)"⟩,
  ⟨"images/broken.png", "Broken (text)"⟩,
  ⟨"images/missing.png", "Missing"⟩ ]

def sources : List String := tiles.map (·.source)

/-- How many thumbnails Load 24 asks for at once. -/
def manyCount : Nat := 24

/-- Thumbnails from the host's demo server (`host/Sources/CairnGallery`, `SlowServer`), which
answers each after a second or two. -/
def manySources : List String :=
  (List.range manyCount).map fun i => s!"https://slow.cairn.test/many/{i}.png"

def isMany (src : String) : Bool := manySources.contains src

theorem manySources_length : manySources.length = manyCount := by
  simp only [manySources, List.length_map, List.length_range]

-- region: gallery-grid
/-- The tiles' grid: columns of at least 180 points, 4:3 pictures with 50 points of caption
under each, 20 points apart. -/
def tileGrid : Grid := { minWidth := 180, ratioW := 4, ratioH := 3, gap := 20, caption := 50 }
-- endregion: gallery-grid

/-! ### Following the window

The view lays the window out as padding, the tiles' column and the thumbnails' column, so the
tiles get what the window's width leaves and what its height leaves under the header and
above the footer. -/

def pad : Nat := 28
def colGap : Nat := 32
def manyW : Nat := 352
def headerH : Nat := 32
def rowGap : Nat := 20
def footerH : Nat := 18

/-- The tiles' width and height in a window of size `sz` (zero when it has no room). -/
def gridW (sz : Size) : Nat := (sz.w - (2 * pad + colGap + manyW : Nat)).toNat
def gridH (sz : Size) : Nat := (sz.h - (2 * pad + headerH + 2 * rowGap + footerH : Nat)).toNat

/-- Where the tiles' grid sits in the window. -/
def gridX : Int := pad
def gridY : Int := pad + headerH + rowGap


-- region: gallery-state
structure State where
  images : Images := {}
  /-- The id the next request gets. -/
  nextReq : Nat := 0
  fit : Fit := .cover
  reloads : Nat := 0
  /-- Presses of Load 24 and of Cancel. -/
  batches : Nat := 0
  cancels : Nat := 0
deriving Repr, Inhabited
-- endregion: gallery-state

/-- Cancel every load still in flight, then ask for every source under fresh ids. -/
def loadSources (s : State) (reload : Bool) : State × List Effect :=
  let (t0, cs) := s.images.cancelAll
  let (t, es) := t0.loadAll s.nextReq reload sources
  ({ s with images := t, nextReq := s.nextReq + sources.length }, cs ++ es)

/-- Cancel the thumbnails still loading, then ask for all of them again, past the cache. -/
def loadMany (s : State) : State × List Effect :=
  let (t0, cs) := s.images.cancelWhere isMany
  let (t, es) := t0.loadAll s.nextReq true manySources
  ({ s with images := t, nextReq := s.nextReq + manyCount, batches := s.batches + 1 }, cs ++ es)

/-- Cancel the thumbnails still loading. -/
def cancelMany (s : State) : State × List Effect :=
  let (t, cs) := s.images.cancelWhere isMany
  ({ s with images := t, cancels := s.cancels + 1 }, cs)

/-- Cancel tile `k`'s load if it is still in flight, then ask for its source again, past the
cache. -/
def loadTile (s : State) (k : Nat) : State × List Effect :=
  match sources[k]? with
  | some src =>
    let (t0, cs) := s.images.cancelWhere (· == src)
    let (t, es) := t0.loadAll s.nextReq true [src]
    ({ s with images := t, nextReq := s.nextReq + 1 }, cs ++ es)
  | none => (s, [])

/-- The launch state: every source asked for, under ids 0–5. -/
def initial : State := (loadSources {} false).1

def nextFit : Fit → Fit
  | .cover => .contain | .contain => .fill | .fill => .cover

def fitName : Fit → String
  | .cover => "Cover" | .contain => "Contain" | .fill => "Stretch"

def reloadRef : ControlRef := ⟨501, 0⟩
def fitRef : ControlRef := ⟨502, 0⟩
def manyRef : ControlRef := ⟨506, 0⟩
def cancelRef : ControlRef := ⟨507, 0⟩
def tileRef (k : Nat) : ControlRef := ⟨509, k⟩

place ^503 window "Gallery window" where
  does "Six image tiles in a grid, each with its name and pixel size or fault, under a header with Fit and Reload."

-- region: gallery-reload
move ^501 reloadMove (s : State) "Reload" in ^503 where
  does "Press Reload."
  sees "Every tile shows its placeholder, then its picture or its fault again; each source is read again, not taken from the host's cache."
  on press
    emit := let (s', es) := loadSources s true; ({ s' with reloads := s.reloads + 1 }, es)
    post s' := s'.fit = s.fit ∧ ∀ src ∈ sources, s'.images.state src = .loading
    sound := by
      intro s
      exact ⟨rfl, fun src h => Images.state_loadAll _ s.nextReq true src sources h⟩
-- endregion: gallery-reload

move ^502 fitMove (s : State) "Fit" in ^503 where
  does "Press Fit."
  sees "The pictures change how they fill their tiles: cover (cropped to fill), contain (whole, inside), stretch; the tiles keep their size."
  on press
    apply := { s with fit := nextFit s.fit }
    post s' := s'.fit = nextFit s.fit ∧ s'.nextReq = s.nextReq
    sound := by intro s; exact ⟨rfl, rfl⟩

-- region: gallery-many
move ^506 manyMove (s : State) "Load 24" in ^503 where
  does "Press Load 24."
  sees "24 thumbnails start loading; at most six are fetched at once and the rest wait their turn, and the line above them counts what is in flight, queued, loaded and cancelled."
  on press
    emit := loadMany s
    post s' := s'.batches = s.batches + 1 ∧ ∀ src ∈ manySources, s'.images.state src = .loading
    sound := by
      intro s
      exact ⟨rfl, fun src h => Images.state_loadAll _ s.nextReq true src manySources h⟩

move ^507 cancelMove (s : State) "Cancel" in ^503 where
  does "Press Cancel."
  sees "The thumbnails still loading stop where they are: those not yet fetched never are, those being fetched are stopped, and no late answer changes them."
  on press
    emit := cancelMany s
    post s' := s'.cancels = s.cancels + 1 ∧ ∀ p ∈ s'.images.pending, isMany p.2 = false
    sound := by
      intro s
      exact ⟨rfl, fun p hp => (Images.pending_cancelWhere _ _ p hp).2⟩
-- endregion: gallery-many

theorem state_loadTile (s : State) (k : Nat) (src : String) (h : sources[k]? = some src) :
    (loadTile s k).1.images.state src = .loading ∧
      ∀ o, o ≠ src → (loadTile s k).1.images.state o = s.images.state o := by
  simp only [loadTile, h]
  refine ⟨Images.state_loadAll _ _ _ _ _ (List.mem_singleton_self _), fun o ho => ?_⟩
  rw [Images.state_loadAll_notin _ _ _ _ _ (by simpa only [List.mem_singleton] using ho)]
  rfl

-- region: gallery-tile-move
move ^509 tileMove (s : State) (k : Nat) "Reload a tile" in ^503 where
  does "Press a tile."
  sees "That tile alone goes back to its placeholder, then shows its picture or its fault again, read past the host's cache; the other tiles stay as they are."
  enabled := k < sources.length
  on press
    emit := loadTile s k
    post s' := ∀ src, sources[k]? = some src →
      s'.images.state src = .loading ∧ ∀ o, o ≠ src → s'.images.state o = s.images.state o
    sound := by intro s k _ src h; exact state_loadTile s k src h
-- endregion: gallery-tile-move

-- region: gallery-receive
def receive (s : State) : Msg → State × List Effect
  | .reply id r => ({ s with images := s.images.receive id r }, [])
  | _ => (s, [])
-- endregion: gallery-receive

def machine : Machine State := { init := initial, moves := moves%, receive }

/-- Pending loads have ids below the next request's. -/
def Fresh (s : State) : Prop := ∀ p ∈ s.images.pending, p.1 < s.nextReq

theorem fresh_loadMany (s : State) (_h : Fresh s) : Fresh (loadMany s).1 := by
  intro p hp
  rcases Images.pending_loadAll _ true manySources s.nextReq p hp with ⟨_, h2⟩ | h'
  · rw [manySources_length] at h2; exact h2
  · exact Nat.lt_of_lt_of_le (_h p (Images.pending_cancelWhere _ _ p h').1) (Nat.le_add_right _ _)

theorem fresh_cancelMany (s : State) (h : Fresh s) : Fresh (cancelMany s).1 :=
  fun p hp => h p (Images.pending_cancelWhere _ _ p hp).1

theorem fresh_loadTile (s : State) (k : Nat) (h : Fresh s) : Fresh (loadTile s k).1 := by
  unfold loadTile
  split
  · intro p hp
    rcases Images.pending_loadAll _ true _ s.nextReq p hp with ⟨_, h2⟩ | h'
    · simp only [List.length_singleton] at h2; exact h2
    · exact Nat.lt_of_lt_of_le (h p (Images.pending_cancelWhere _ _ p h').1) (Nat.le_add_right _ _)
  · exact h

theorem fresh_loadSources (s : State) (reload : Bool) (_h : Fresh s) : Fresh (loadSources s reload).1 := by
  intro p hp
  rcases Images.pending_loadAll _ reload sources s.nextReq p hp with ⟨_, h2⟩ | h'
  · exact h2
  · exact nomatch h'

invariant ^504 freshLoads "Pending loads have fresh ids" for machine where
  does "Every load waiting for its reply has an id below the next request's, so a reply to a later load is never taken for an earlier one."
  holds s := Fresh s
  init := fresh_loadSources {} false (fun _ h => nomatch h)
  step := machine.preserves <|
    Move.all_cons (reloadMove.preserves _ fun s h => fresh_loadSources s true h)
      (Move.all_cons (fitMove.preserves _ fun _ h => h)
        (Move.all_cons (manyMove.preserves _ fresh_loadMany)
          (Move.all_cons (cancelMove.preserves _ fresh_cancelMany)
            (Move.all_cons (tileMove.preserves _ fun s k _ h => fresh_loadTile s k h) Move.all_nil))))
  receive := by
    intro s m h
    cases m with
    | reply id r => exact fun p hp => h p (Images.pending_receive _ _ _ _ hp)
    | _ => exact h

flow ^505 reloadContain "Reload, then fit inside" for machine where
  does "Press Reload, then Fit."
  sees "The pictures load again and then show whole inside their tiles."
  goal s := s.reloads = 1 ∧ s.fit = .contain
  witness press ^501, press ^502

flow ^508 manyCancel "Load many, then cancel" for machine where
  does "Press Load 24, then Cancel."
  sees "Thumbnails start loading six at a time; on Cancel the rest stop and the counts say how many were cancelled."
  goal s := s.batches = 1 ∧ s.cancels = 1
  witness press ^506, press ^507

-- region: gallery-fit
/-- Where the tiles go in a window of size `sz`, in order (`tilesNode` lays them out there:
`Examples.Gallery.tiles_laid`). -/
def tileRects (sz : Size) : List Rect :=
  tileGrid.rects gridX gridY (gridW sz) (gridH sz) tiles.length

/-- At every window size: no two tiles overlap, each comes after the one before in reading
order, and in a window with room for the padding and header every tile is inside it. -/
def TilesFit : Prop :=
  ∀ sz : Size,
    (tileRects sz).Pairwise (fun a b => a.disjoint b ∧
      (a.y + a.h ≤ b.y ∨ (a.y = b.y ∧ a.x + a.w ≤ b.x))) ∧
    ((pad : Int) ≤ sz.w → gridY ≤ sz.h → ∀ r ∈ tileRects sz, r.inside (Layout.windowRect sz))

theorem tilesFit : TilesFit := by
  intro sz
  refine ⟨Grid.rects_pairwise _ _ _ _ _ _, fun hw hh r hr => ?_⟩
  have hin := Grid.rects_inside _ _ _ _ _ _ r hr
  simp only [Rect.inside, Layout.windowRect, gridX, gridY, gridW, gridH, pad, headerH, rowGap,
    footerH, colGap, manyW] at hin hw hh ⊢
  omega

invariant ^510 tilesFitInvariant "Tiles fit the window at every size" for machine where
  does "At every window size the tiles don't overlap, read left to right and top to bottom, and stay inside the window; resizing reflows them."
  holds _s := TilesFit
  init := tilesFit
  step := fun _ _ _ => tilesFit
  receive := fun _ _ _ => tilesFit
-- endregion: gallery-fit

/-- Every claim the gallery makes. -/
def claimInfos : List ClaimInfo := claims%

/-! ## View -/

def bg : Color := ⟨246, 246, 248, 255⟩
def ink : Color := ⟨28, 28, 30, 255⟩
def muted : Color := ⟨110, 110, 118, 255⟩
def blue : Color := ⟨64, 96, 255, 255⟩
def blueDark : Color := ⟨44, 72, 214, 255⟩
def grey : Color := ⟨120, 120, 128, 255⟩
def greyDark : Color := ⟨96, 96, 104, 255⟩
def white : Color := ⟨255, 255, 255, 255⟩
def focusRing : Color := ⟨0, 122, 255, 255⟩

def button (ui : UI) (r : ControlRef) (label : String) (fill hover : Color) : Node :=
  .box { width := .fixed 132, height := .fixed 32, radius := 6, align := .center,
         justify := .center, clip := true,
         background := some (if ui.hover = some r then hover else fill),
         border := if ui.focus = some r then some ⟨2, focusRing⟩ else none }
    (some { ref := r, label := label })
    [.text { font := { size := 13, weight := 600 }, color := white } label]

def line (size : Nat) (color : Color) (t : String) (weight : Nat := 400) : Node :=
  .box { width := .fill, height := .fixed (size + 6), clip := true } none
    [.text { font := { size, weight }, color } t]

/-- What a tile says under its picture. -/
def status : ImageState → String
  | .loading => "Loading…"
  | .ready w h => s!"{w} × {h} px"
  | .failed .. => "Failed to load"

-- region: gallery-tile
/-- A tile's picture, `w × h` points in every state. -/
def tileImage (s : State) (w h : Nat) (src : String) : Node :=
  .image { source := src, width := w, height := h, state := s.images.state src,
           fit := s.fit, backdrop := some ⟨236, 236, 240, 255⟩ }
-- endregion: gallery-tile

def tileHover : Color := ⟨228, 230, 238, 255⟩

/-- Tile `k` in a `w × h` cell: the picture, its name and its size or fault. Pressing it loads
it again (^509). -/
def tile (s : State) (ui : UI) (w h : Nat) (it : Tile × Nat) : Node :=
  .box { axis := .column, width := .fill, height := .fill, gap := 6, radius := 6,
         background := if ui.hover = some (tileRef it.2) then some tileHover else none }
    (some { ref := tileRef it.2, label := s!"Reload {it.1.title}" })
    [ tileImage s w (h - tileGrid.caption) it.1.source,
      line 13 ink it.1.title (weight := 600),
      line 12 muted (status (s.images.state it.1.source)) ]

-- region: gallery-tiles
/-- The tiles: `tileGrid` at the size the window leaves them. -/
def tilesNode (s : State) (ui : UI) : Node :=
  tileGrid.node (gridW ui.size) (gridH ui.size) (tile s ui) tiles.zipIdx
-- endregion: gallery-tiles

def header (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, height := .fixed 32, gap := 12, align := .center } none
    [ .box { width := .fill, height := .fixed 32, clip := true } none
        [.text { font := { size := 22, weight := 700 }, color := ink } "Gallery"],
      button ui fitRef s!"Fit: {fitName s.fit}" grey greyDark,
      button ui reloadRef "Reload" blue blueDark ]

/-! ### Many at once -/

def thumbW : Nat := 52
def thumbH : Nat := 39

def thumb (s : State) (src : String) : Node :=
  .image { source := src, width := thumbW, height := thumbH, state := s.images.state src,
           fit := .cover, backdrop := some ⟨228, 228, 234, 255⟩ }

def thumbRow (s : State) (srcs : List String) : Node :=
  .box { axis := .row, width := .fill, height := .fixed thumbH, gap := 8 } none (srcs.map (thumb s))

/-- How many of `srcs` satisfy `p`. -/
def countOf (srcs : List String) (p : String → Bool) : Nat := (srcs.filter p).length

/-- The thumbnails' counts, in two lines. Lean's runtime sends at most `App.maxInFlight` (6)
requests at once and queues the rest, oldest first, so of the thumbnails the app is waiting
for, six at most are in flight. -/
def manyCounts (s : State) : String × String :=
  let asked := (s.images.pending.filter (isMany ·.2)).length
  let sent := min 6 asked
  let waiting (src : String) : Bool := s.images.pending.any (·.2 == src)
  let loaded := countOf manySources fun src => match s.images.state src with | .ready .. => true | _ => false
  let cancelled := if s.batches = 0 then 0 else
    countOf manySources fun src => !waiting src && s.images.state src == .loading
  (s!"In flight {sent} of 6 · queued {asked - sent}",
   s!"Loaded {loaded} of {manyCount} · cancelled {cancelled}")

def galleryColumn (s : State) (ui : UI) : Node :=
  .box { width := .fixed (gridW ui.size), height := .fill, gap := rowGap } none
    [ header s ui,
      tilesNode s ui,
      line 12 muted s!"Reloads: {s.reloads}" ]

def manyColumn (s : State) (ui : UI) : Node :=
  .box { width := .fixed manyW, height := .fill, gap := 14 } none
    [ line 17 ink "Many at once" (weight := 700),
      .box { axis := .row, width := .fill, height := .fixed 32, gap := 12 } none
        [ button ui manyRef "Load 24" blue blueDark,
          button ui cancelRef "Cancel" grey greyDark ],
      line 13 ink (manyCounts s).1,
      line 13 muted (manyCounts s).2,
      thumbRow s (manySources.take 6),
      thumbRow s ((manySources.drop 6).take 6),
      thumbRow s ((manySources.drop 12).take 6),
      thumbRow s (manySources.drop 18) ]

def view (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, height := .fill, padding := ⟨pad, pad, pad, pad⟩, gap := colGap,
         background := some bg, clip := true } none
    [ galleryColumn s ui, manyColumn s ui ]

-- region: gallery-app
def app : App State :=
  { machine.toApp [.window 503 "Gallery" view] claimInfos with
    initEffects := (loadSources {} false).2 }
-- endregion: gallery-app

example : claimInfos.map (·.id) = [501, 502, 503, 504, 505, 506, 507, 508, 509, 510] := by decide

end Examples.Gallery
