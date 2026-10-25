# fuzz-scope

Two Lake packages for `make fuzz-scope` (cairn#221): `app` (package `fuzzapp`) requires `dep`
(package `fuzzdep`), and each declares a machine in a module ending in `Claims`. The app's fuzz
executable lists its own machine as `Claims`, and the dependency's only with `--deps`, as
`fuzzdep/Claims`; `app/Clash.lean` checks that two of the app's own machines named `Claims`
fail to compile. Both require this checkout's Cairn by path. Never published.
