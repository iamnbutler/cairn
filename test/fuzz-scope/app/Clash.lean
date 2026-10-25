import App
import Dep
import Clash.Claims
import Cairn.Fuzz.Collect

/-! Two of the app's own machines whose modules both end in `Claims` (`App.Claims`,
`Clash.Claims`) would both be the target `Claims`: `fuzz_targets%` refuses them, rather than
letting one shadow the other (cairn#221). -/

/--
error: fuzz_targets%: two machines are both the target `Claims`: App.machine and Clash.machine. A target is named after its module's last component, so rename one of the modules (cairn#221)
-/
#guard_msgs in
example : List Cairn.Fuzz.Target := fuzz_targets%
