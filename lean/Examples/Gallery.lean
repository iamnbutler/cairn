module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Cairn.App
public import Cairn.UI.Images

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
* **Moves.** Reload asks again for every source, past the host's cache; Fit cycles how the
  pictures fill their boxes.

| Id | Kind | What |
|---|---|---|
| ^501 | move | Reload: every tile back to its placeholder, every source read again |
| ^502 | move | Fit: cover, contain, stretch |
| ^503 | place | the window |
| ^504 | invariant | pending loads have ids below the next request's |
| ^505 | flow | reload, then fit the pictures inside their tiles |

The v1 exports are in `Examples.Gallery.Abi`; theorems about the view in
`Examples.Gallery.Proofs`; the host side is `host/Sources/CairnGallery`. -/

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

def tileW : Nat := 200
def tileH : Nat := 150

-- region: gallery-state
structure State where
  images : Images := {}
  /-- The id the next request gets. -/
  nextReq : Nat := 0
  fit : Fit := .cover
  reloads : Nat := 0
deriving Repr, Inhabited
-- endregion: gallery-state

/-- Ask for every source under fresh ids. -/
def loadSources (s : State) (reload : Bool) : State × List Effect :=
  let (t, es) := s.images.loadAll s.nextReq reload sources
  ({ s with images := t, nextReq := s.nextReq + sources.length }, es)

/-- The launch state: every source asked for, under ids 0–5. -/
def initial : State := (loadSources {} false).1

def nextFit : Fit → Fit
  | .cover => .contain | .contain => .fill | .fill => .cover

def fitName : Fit → String
  | .cover => "Cover" | .contain => "Contain" | .fill => "Stretch"

def reloadRef : ControlRef := ⟨501, 0⟩
def fitRef : ControlRef := ⟨502, 0⟩

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
      exact ⟨rfl, fun src h => Images.state_loadAll s.images s.nextReq true src sources h⟩
-- endregion: gallery-reload

move ^502 fitMove (s : State) "Fit" in ^503 where
  does "Press Fit."
  sees "The pictures change how they fill their tiles: cover (cropped to fill), contain (whole, inside), stretch; the tiles keep their size."
  on press
    apply := { s with fit := nextFit s.fit }
    post s' := s'.fit = nextFit s.fit ∧ s'.nextReq = s.nextReq
    sound := by intro s; exact ⟨rfl, rfl⟩

-- region: gallery-receive
def receive (s : State) : Msg → State × List Effect
  | .reply id r => ({ s with images := s.images.receive id r }, [])
  | _ => (s, [])
-- endregion: gallery-receive

def machine : Machine State := { init := initial, moves := moves%, receive }

/-- Pending loads have ids below the next request's. -/
def Fresh (s : State) : Prop := ∀ p ∈ s.images.pending, p.1 < s.nextReq

theorem fresh_loadSources (s : State) (reload : Bool) (h : Fresh s) : Fresh (loadSources s reload).1 := by
  intro p hp
  rcases Images.pending_loadAll s.images reload sources s.nextReq p hp with ⟨_, h2⟩ | h'
  · exact h2
  · exact Nat.lt_of_lt_of_le (h p h') (Nat.le_add_right _ _)

invariant ^504 freshLoads "Pending loads have fresh ids" for machine where
  does "Every load waiting for its reply has an id below the next request's, so a reply to a later load is never taken for an earlier one."
  holds s := Fresh s
  init := fresh_loadSources {} false (fun _ h => nomatch h)
  step := machine.preserves <|
    Move.all_cons (reloadMove.preserves _ fun s h => fresh_loadSources s true h)
      (Move.all_cons (fitMove.preserves _ fun _ h => h) Move.all_nil)
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
  | .failed f _ => Image.faultText f

-- region: gallery-tile
def tileImage (s : State) (src : String) : Node :=
  .image { source := src, width := tileW, height := tileH, state := s.images.state src,
           fit := s.fit, backdrop := some ⟨236, 236, 240, 255⟩ }
-- endregion: gallery-tile

def tile (s : State) (t : Tile) : Node :=
  .box { axis := .column, width := .fixed tileW, height := .fixed (tileH + 44), gap := 6 } none
    [ tileImage s t.source,
      line 13 ink t.title (weight := 600),
      line 12 muted (status (s.images.state t.source)) ]

def tileRow (s : State) (ts : List Tile) : Node :=
  .box { axis := .row, width := .fill, height := .fixed (tileH + 44), gap := 20 } none (ts.map (tile s))

def header (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, height := .fixed 32, gap := 12, align := .center } none
    [ .box { width := .fill, height := .fixed 32, clip := true } none
        [.text { font := { size := 22, weight := 700 }, color := ink } "Gallery"],
      button ui fitRef s!"Fit: {fitName s.fit}" grey greyDark,
      button ui reloadRef "Reload" blue blueDark ]

def view (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨28, 28, 28, 28⟩, gap := 20,
         background := some bg, clip := true } none
    [ header s ui,
      tileRow s (tiles.take 3),
      tileRow s (tiles.drop 3),
      line 12 muted s!"Reloads: {s.reloads}" ]

-- region: gallery-app
def app : App State :=
  { machine.toApp [.window 503 "Gallery" view] claimInfos with
    initEffects := (loadSources {} false).2 }
-- endregion: gallery-app

example : claimInfos.map (·.id) = [501, 502, 503, 504, 505] := by decide

end Examples.Gallery
