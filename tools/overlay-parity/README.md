# Overlay parity

How docs/yap.md's "Overlay parity" images and numbers were made: the original Yap's overlay
captured in fixed states and over a scripted text change, and Cairn's rendered in the same states
and at the same frame times.

## The original (reference)

`harness.swift` is `yapref`, which drives the real `Overlay`, `OverlayView` and `WaveRenderer` from
a patched copy of `~/code/yap/App/Overlay.swift` (`PATCHES.md`: access changes and injected tape
values, nothing that changes what is drawn). It never records audio, watches keys or types: the
tape's levels and cuts are injected. It captures only its own panel, with ScreenCaptureKit's
desktop-independent window filter on that window.

```sh
mkdir /tmp/yo-ref && cp ~/code/yap/App/Overlay.swift ~/code/yap/App/Overlay.metal /tmp/yo-ref/
# apply PATCHES.md to /tmp/yo-ref/Overlay.swift (Overlay.metal stays as it is)
cp harness.swift /tmp/yo-ref/main.swift && cd /tmp/yo-ref
xcrun metal -c Overlay.metal -o Overlay.air && xcrun metallib Overlay.air -o default.metallib
xcrun swiftc -swift-version 6 -O -o yapref main.swift Overlay.swift
./yapref scenes/sample.json --out out                       # twelve stills
./yapref --motion scenes/motion-text-hide.json --out out/motion-text-hide
```

`scenes/make_sample.py` writes the scenes; `scenes/motion-text-hide.index.json` is the capture's
index (event and frame times) used below.

## Cairn

```sh
cd host
swift run CairnYap --overlay-scenes ../tools/overlay-parity/scenes/sample.json /tmp/yo-cairn/out
swift run CairnYap --overlay-motion ../tools/overlay-parity/scenes/motion-text-hide.json \
  ../tools/overlay-parity/scenes/motion-text-hide.index.json /tmp/yo-cairn/motion
```

Both lay the panel out in Lean as the app does (`cairn_yap_overlay_frame`) and render it offscreen
at 2x over a clear background.

## Comparing

`cmp.swift` (`swiftc -O cmp.swift -o cmp`) matches both images to sRGB, prints per-region counts of
channels more than 2, 8 and 32 levels apart, and writes reference | Cairn | difference × 4:

```sh
./cmp ref.png cairn.png side.png --region header:68,60,1044,112 tape:68,132,1044,248 text:68,268,1044,364
```

`strip.swift` stacks reference | Cairn for a list of motion frames at half size.
