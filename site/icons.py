#!/usr/bin/env python3
"""Draws the pixel-art cairn favicon and writes icon.svg, favicon.ico and
apple-touch-icon.png into public/. Run from anywhere: python3 site/icons.py"""

import os
import struct
import zlib

# 16x16. o outline; top stone T/t/u, middle l/m/n, bottom a/b/c (light, mid, dark).
GRID = [
    "................",
    "................",
    "......oooo......",
    ".....oTTtto.....",
    ".....ottttuo....",
    "...ooooooooooo..",
    "..olllmmmmmmmo..",
    "..ommmmmmmmnno..",
    "...onnnnnnnnno..",
    ".oooooooooooooo.",
    ".oaaabbbbbbbbbo.",
    ".obbbbbbbbbbcco.",
    ".obbbbbbbbcccco.",
    "..occcccccccco..",
    "...oooooooooo...",
    "................",
]

COLORS = {
    "o": "#2e3160",
    "T": "#c9eadf", "t": "#8cc6b6", "u": "#5f9590",
    "l": "#ddd6f4", "m": "#aca1db", "n": "#7d72b3",
    "a": "#cbd6f2", "b": "#8fa1d8", "c": "#6070a8",
}
DARK_OUTLINE = "#e9e4f5"
TILE = "#cfc8ee"  # opaque background where a platform needs one

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "public")

for row in GRID:
    assert len(row) == 16, row
assert len(GRID) == 16


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def svg():
    rects = []
    for y, row in enumerate(GRID):
        x = 0
        while x < 16:
            ch = row[x]
            if ch == ".":
                x += 1
                continue
            run = 1
            while x + run < 16 and row[x + run] == ch:
                run += 1
            cls = ' class="o"' if ch == "o" else ""
            rects.append(f'<rect{cls} x="{x}" y="{y}" width="{run}" height="1" fill="{COLORS[ch]}"/>')
            x += run
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">\n'
        f"<style>@media (prefers-color-scheme: dark) {{ .o {{ fill: {DARK_OUTLINE}; }} }}</style>\n"
        + "\n".join(rects)
        + "\n</svg>\n"
    )


def png(scale, size, background=None):
    pad = (size - 16 * scale) // 2
    bg = rgb(background) + (255,) if background else (0, 0, 0, 0)
    rows = []
    for py in range(size):
        line = bytearray([0])
        for px in range(size):
            gx, gy = (px - pad) // scale, (py - pad) // scale
            ch = GRID[gy][gx] if 0 <= gx < 16 and 0 <= gy < 16 and px >= pad and py >= pad else "."
            line += bytes(rgb(COLORS[ch]) + (255,) if ch != "." else bg)
        rows.append(bytes(line))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


def ico(images):
    # ICO with PNG payloads: header, one directory entry per image, then the PNGs.
    out = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    body = b""
    for size, data in images:
        out += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset + len(body))
        body += data
    return out + body


with open(os.path.join(OUT, "icon.svg"), "w") as f:
    f.write(svg())
with open(os.path.join(OUT, "favicon.ico"), "wb") as f:
    f.write(ico([(16, png(1, 16)), (32, png(2, 32))]))
with open(os.path.join(OUT, "apple-touch-icon.png"), "wb") as f:
    f.write(png(10, 180, TILE))
