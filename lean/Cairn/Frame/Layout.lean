import Cairn.Frame.Build
import Cairn.Layout.Proofs

/-! `Frame.ofLaid` composed with layout. Kept apart from `Cairn.Frame.Build`, which is a `module`
the host links, so that `Build` needs only the vocabulary of layout (`Layout.Facts`), not its
proofs. -/

namespace Cairn.Frame

/-- Composed with layout: the accessibility tree has exactly the view's controls, in order. -/
theorem controls_ofLaid_layout (ui : UI) (m : TextMetrics) (w : Size) (n : Node) :
    (ofLaid ui (Layout.layout m w n)).ax.toList.filterMap AxNode.control =
      n.controls.map Control.ref := by
  rw [controls_ofLaid, Layout.layout_controls]

end Cairn.Frame
