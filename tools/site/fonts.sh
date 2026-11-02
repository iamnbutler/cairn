#!/bin/sh
# Subsets Pixelify Sans (@fontsource/pixelify-sans, site/web/package.json) into site/public/fonts/:
# a core file per weight with ASCII and the punctuation the site's prose uses, which every page
# preloads, and an -ext file with the rest of the font's Latin, which a browser fetches only for a
# page that shows one of those characters (fonts.css gives each file its unicode-range).
# Needs fontTools (pip install fonttools brotli). Run it after updating the package: make site-fonts.
set -eu
CORE="U+20-7E,U+A0,U+AB,U+B7,U+BB,U+2013-2014,U+2018-201D,U+2022,U+2026,U+2039-203A,U+2212"
EXT="U+A1-AA,U+AC-B6,U+B8-BA,U+BC-FF,U+102,U+131,U+152-153,U+2C6,U+2DA,U+2DC,U+300-308,U+201A,U+201E,U+20AC,U+2122,U+2215"
src=site/web/node_modules/@fontsource/pixelify-sans/files
out=site/public/fonts
mkdir -p "$out"
for w in 400 600 700; do
  for part in core ext; do
    [ "$part" = core ] && set_="$CORE" name="pixelify-$w" || { set_="$EXT"; name="pixelify-$w-ext"; }
    python3 -m fontTools.subset "$src/pixelify-sans-latin-$w-normal.woff2" --unicodes="$set_" \
      --flavor=woff2 --layout-features=kern --no-hinting --desubroutinize --output-file="$out/$name.woff2"
  done
done
ls -l "$out"
