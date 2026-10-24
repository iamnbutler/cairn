import Examples.Yap
import Cairn.Claims.Deliver

/-! # Yap on Cairn: the claims through the runtime

Every invariant of `Examples.Yap.machine` (^311–^323, ^346) is kept by every move and by
`receive`, so it holds in every state the running app reaches: whatever input, clock events,
timer firings, replies and subscription events arrive, in any order
(`Cairn.Claims.steps_reachableAll`). These are the statements a runtime step is checked
against. -/

namespace Examples.Yap
open Cairn Cairn.Claims Cairn.Runtime

/-- The app's state after any events. -/
abbrev after (cfg : Config) (size : Size) (scale : Nat) (es : List Event) : AppState :=
  (steps app cfg (start app cfg size scale) es).1.app

theorem reached (cfg : Config) (size : Size) (scale : Nat) (es : List Event) :
    machine.ReachableAll (after cfg size scale es) :=
  steps_reachableAll machine app rfl rfl rfl cfg size scale es

theorem shortcutNeverSends_on_screen cfg size scale es :
    shortcutNeverSends.holds (after cfg size scale es) :=
  shortcutNeverSends.reachableAll _ (reached cfg size scale es)

theorem holdTapSplit_on_screen cfg size scale es : holdTapSplit.holds (after cfg size scale es) :=
  holdTapSplit.reachableAll _ (reached cfg size scale es)

theorem oneRecording_on_screen cfg size scale es : oneRecording.holds (after cfg size scale es) :=
  oneRecording.reachableAll _ (reached cfg size scale es)

theorem recordingEnds_on_screen cfg size scale es : recordingEnds.holds (after cfg size scale es) :=
  recordingEnds.reachableAll _ (reached cfg size scale es)

theorem keptBeforeTyped_on_screen cfg size scale es :
    keptBeforeTyped.holds (after cfg size scale es) :=
  keptBeforeTyped.reachableAll _ (reached cfg size scale es)

theorem failedTypeFlagged_on_screen cfg size scale es :
    failedTypeFlagged.holds (after cfg size scale es) :=
  failedTypeFlagged.reachableAll _ (reached cfg size scale es)

theorem onlyLiveRepliesType_on_screen cfg size scale es :
    onlyLiveRepliesType.holds (after cfg size scale es) :=
  onlyLiveRepliesType.reachableAll _ (reached cfg size scale es)

theorem typedOnce_on_screen cfg size scale es : typedOnce.holds (after cfg size scale es) :=
  typedOnce.reachableAll _ (reached cfg size scale es)

theorem wholeWordFixes_on_screen cfg size scale es : wholeWordFixes.holds (after cfg size scale es) :=
  wholeWordFixes.reachableAll _ (reached cfg size scale es)

theorem retentionKeepsToday_on_screen cfg size scale es :
    retentionKeepsToday.holds (after cfg size scale es) :=
  retentionKeepsToday.reachableAll _ (reached cfg size scale es)

theorem first25Terms_on_screen cfg size scale es : first25Terms.holds (after cfg size scale es) :=
  first25Terms.reachableAll _ (reached cfg size scale es)

theorem recentFive_on_screen cfg size scale es : recentFive.holds (after cfg size scale es) :=
  recentFive.reachableAll _ (reached cfg size scale es)

theorem onlySendable_on_screen cfg size scale es : onlySendable.holds (after cfg size scale es) :=
  onlySendable.reachableAll _ (reached cfg size scale es)

theorem leaveOriginal_on_screen cfg size scale es : leaveOriginal.holds (after cfg size scale es) :=
  leaveOriginal.reachableAll _ (reached cfg size scale es)

/-- The surfaces' places are distinct. -/
example : (app.surfaces.map Surface.place).Nodup := by decide

end Examples.Yap
