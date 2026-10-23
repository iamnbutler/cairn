import Cairn.Fuzz.Trusted.Gen
import Cairn.Frame.Dump
import Cairn.Frame.Boundary
import Cairn.Runtime.Abi
import Cairn.Text.Host
import Cairn.Text.Field
import Cairn.Layout.Core

/-! # Lean's side of the trusted-base fuzzer

C exports for `cairn-fuzz-trusted` (host/Tests/CairnFuzzTrusted), the Swift executable that
links this library next to the Swift host, so both sides of each trusted boundary run in one
process (docs/fuzz.md, "Trusted base"). No `import Lean`: this links into a Swift binary.

* `cairn_tf_gen_frame seed`: a random frame (`Gen.frame`), encoded.
* `cairn_tf_decode_frame bytes` and `cairn_tf_decode_events bytes`: Lean's proved decoders'
  verdict on any bytes. The reply is `"R"` (rejected), or `"A="` / `"A~"` (accepted; `=` when
  re-encoding the value gives the same bytes back) followed by the canonical dump
  (`Cairn.Dump`), which the Swift side compares with its own dump.
* `cairn_tf_field_init/step/frame`: an app that is one text field, on the real runtime and
  boundary (`Runtime.stepBytes`, `Frame.boundary`, `TextMetrics.host`), so the host's
  `NSTextInputClient` and its shadow of the field can be checked against `Field.apply`.
  The same ABI as `cairn_app_*` (docs/runtime.md), under other names so it can't clash.
* `cairn_tf_wrap`: where Lean breaks a string into lines at a width with `TextMetrics.host`,
  and where layout puts each line, so the Swift side can shape each line as the renderer will
  and compare with Core Text's own line breaking. -/

namespace Cairn.Fuzz.Trusted
open Cairn

/-- `"A="`, `"A~"` or `"R"`, then the dump. -/
def verdict {α : Type} (decoded : Option α) (reencode : α → ByteArray) (dump : α → String)
    (b : ByteArray) : ByteArray :=
  match decoded with
  | none => "R".toUTF8
  | some v =>
    let same := (reencode v).data == b.data
    (if same then "A=" else "A~").toUTF8 ++ (dump v).toUTF8

@[export cairn_tf_gen_frame]
def genFrame (seed : UInt64) : ByteArray := encodeFrame (frameOf seed)

@[export cairn_tf_decode_frame]
def decodeFrameVerdict (b : ByteArray) : ByteArray :=
  verdict (decodeFrame b) encodeFrame Dump.frame b

@[export cairn_tf_decode_events]
def decodeEventsVerdict (b : ByteArray) : ByteArray :=
  verdict (decodeEvents b) encodeEvents Dump.events b

/-! ## One field -/

def fieldRef : ControlRef := { claim := 1 }

/-- One text field across the window, with a little padding so the field's text is inset and
long text scrolls. -/
def fieldView (f : Text.Field) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨8, 8, 8, 8⟩ } none
    [.field { width := .fill, padding := ⟨4, 6, 4, 6⟩, border := some ⟨1, ⟨0, 0, 0, 255⟩⟩ }
      { font := {} } { ref := fieldRef, role := .textField, label := "Field" }
      (f.view (ui.focus = some fieldRef))]

def fieldUpdate (f : Text.Field) : Action → Text.Field × List Effect
  | .edit _ op => Text.Field.apply op f
  | _ => (f, [])

def fieldApp : App Text.Field where
  init := {}
  view := fieldView
  update := fieldUpdate
  claims := []
  initFocus := some fieldRef

def fieldCfg : Runtime.Config := { metrics := TextMetrics.host }

@[export cairn_tf_field_init]
def fieldInit (w h scalePercent : UInt32) : Runtime.State Text.Field :=
  Runtime.initState fieldApp fieldCfg w h scalePercent

@[export cairn_tf_field_step]
def fieldStep (s : Runtime.State Text.Field) (events : ByteArray) : Runtime.State Text.Field :=
  Runtime.stepBytes fieldApp fieldCfg Frame.boundary s events

@[export cairn_tf_field_frame]
def fieldFrame (s : Runtime.State Text.Field) : ByteArray := Runtime.frameBytes Frame.boundary s

/-! ## Wrapped text -/

/-- A string wrapped at `width` (a para filling a window that wide), as int32s: the line count,
then for each line its scalar range `a, b`, Lean's width for it (`o b - o a`) and the `x, y, w`
of the line's laid-out rect. -/
@[export cairn_tf_wrap_lean]
def wrap (family size weight : UInt32) (italic : UInt8) (width : UInt32) (s : String) :
    ByteArray :=
  let f : Font := { family := family.toNat, size := size.toNat, weight := weight.toNat,
                    italic := italic != 0 }
  let m := TextMetrics.host
  let o := Layout.offAt (m.offsets f s)
  let ls := Text.Wrap.allLines o width.toNat s.toList
  let laid := Layout.layout m ⟨width.toNat, 1000000⟩ (.para { font := f } {} s)
  let rects := (match laid with | .box _ _ _ _ kids => kids | _ => []).map Laid.rect
  let words : List Int := ls.length :: (List.zip ls rects).flatMap fun (p, r) =>
    [(p.1 : Int), p.2, o p.2 - o p.1, r.x, r.y, r.w]
  words.foldl Text.Host.putI32 ByteArray.empty

end Cairn.Fuzz.Trusted
