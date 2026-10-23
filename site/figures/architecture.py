# Builds the architecture figure as inline SVG. Pixel style: stepped corners, crisp 2px ink,
# chevron heads; one ink (currentColor), a tint for the proved part, the accent for "proved".
S = 3  # corner step

def box(x, y, w, h, cls=""):
    s = S
    pts = [(x+2*s,y),(x+w-2*s,y),(x+w-2*s,y+s),(x+w-s,y+s),(x+w-s,y+2*s),(x+w,y+2*s),
           (x+w,y+h-2*s),(x+w-s,y+h-2*s),(x+w-s,y+h-s),(x+w-2*s,y+h-s),(x+w-2*s,y+h),
           (x+2*s,y+h),(x+2*s,y+h-s),(x+s,y+h-s),(x+s,y+h-2*s),(x,y+h-2*s),
           (x,y+2*s),(x+s,y+2*s),(x+s,y+s),(x+2*s,y+s)]
    c = f' class="{cls}"' if cls else ""
    return f'<polygon{c} points="{" ".join(f"{a},{b}" for a,b in pts)}"/>'

def head(x, y, d):  # open chevron pointing in direction d at tip (x, y)
    k = 6
    if d == "down":  return f'<polyline points="{x-k},{y-k} {x},{y} {x+k},{y-k}"/>'
    if d == "left":  return f'<polyline points="{x+k},{y-k} {x},{y} {x+k},{y+k}"/>'
    if d == "right": return f'<polyline points="{x-4},{y-4} {x},{y} {x-4},{y+4}"/>'

def text(x, y, s, cls, anchor="start"):
    a = f' text-anchor="{anchor}"' if anchor != "start" else ""
    return f'<text x="{x}" y="{y}" class="{cls}"{a}>{s}</text>'

X, W = 120, 340          # boxes
cxm = X + W // 2         # main axis
out = []
# Swift
out += ["<!-- swift -->", box(X, 16, W, 76),
        text(X+16, 40, "SWIFT · MAIN THREAD", "hd"),
        text(X+16, 64, "the window and its events", "nm"),
        text(X+16, 82, "no application logic", "it")]
# events down
out += ["<!-- events -->", f'<line x1="{cxm}" y1="92" x2="{cxm}" y2="140"/>', head(cxm, 140, "down"),
        text(cxm+12, 114, "events, as bytes", "it")]
# Lean
out += ["<!-- lean -->", box(X, 148, W, 116, "tint"),
        text(X+16, 172, "LEAN · OWNS THE STATE", "hd")]
names = ["update", "view", "layout", "hit map", "encode"]
iw, gap = 52, 12
x0 = X + 16
for i, n in enumerate(names):
    bx = x0 + i*(iw+gap)
    out.append(box(bx, 186, iw, 28, "chip"))
    out.append(text(bx+iw//2, 205, n, "sm", "middle"))
    if i < len(names)-1:
        gx = bx + iw + gap//2 + 2
        out.append(head(gx, 200, "right"))
out += [text(X+16, 238, "pure, total functions; every", "it"),
        text(X+16, 254, "claim is a theorem about them", "it")]
# frame down
out += ["<!-- frame -->", f'<line x1="{cxm}" y1="264" x2="{cxm}" y2="312"/>', head(cxm, 312, "down"),
        text(cxm+12, 286, "the frame, as bytes", "it")]
# Metal
out += ["<!-- metal -->", box(X, 320, W, 64),
        text(X+16, 344, "METAL · RENDER THREAD", "hd"),
        text(X+16, 368, "paints the latest frame", "nm")]
# back to Swift: dashed elbow from Lean's right side to Swift's right side
rx = X + W + 34
out += ["<!-- the frame answers AppKit -->",
        f'<polyline class="dash" points="{X+W},{206} {rx},{206} {rx},{54} {X+W+8},{54}"/>', head(X+W+8, 54, "left"),
        text(rx+10, 120, "accessibility and", "it"), text(rx+10, 136, "text input answer", "it"),
        text(rx+10, 152, "from the last frame", "it")]
# brackets on the left
def bracket(y0, y1, label, note, cls=""):
    bx = X - 14
    c = f' class="{cls}"' if cls else ""
    return [f'<polyline{c} points="{bx+6},{y0} {bx},{y0} {bx},{y1} {bx+6},{y1}"/>',
            text(bx-10, (y0+y1)//2 - 2, label, ("lb " + cls).strip(), "end"),
            text(bx-10, (y0+y1)//2 + 15, note, "it", "end")]
out += ["<!-- what is proved and what is trusted -->"]
out += bracket(18, 90, "trusted", "kept thin")
out += bracket(150, 262, "proved", "in Lean", "accent")
out += bracket(322, 382, "trusted", "probes, goldens")
svg = f'''<svg viewBox="0 0 640 396" role="img" aria-labelledby="arch-t">
<title id="arch-t">How a frame is made: Swift captures events, Lean computes the frame, Metal paints it</title>
{chr(10).join(out)}
</svg>'''
open("/tmp/cairn-preview/arch.svg", "w").write(svg)
print(len(svg))
