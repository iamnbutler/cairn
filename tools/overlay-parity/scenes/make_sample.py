#!/usr/bin/env python3
"""Writes sample.json (stills) and motion-*.json (motion scripts) next to this file."""
import json, math, os, struct

HERE = os.path.dirname(os.path.abspath(__file__))
ELAPSED = 7.0

def f32(x):
    return struct.unpack('f', struct.pack('f', x))[0]

def level(t):
    return min(1.0, 0.15 + abs(math.sin(9 * t)) * (0.55 + 0.45 * math.sin(1.7 * t)) * 0.8)

def history(elapsed=ELAPSED):
    # One frame per 1/60 s from t = 1/60 to t = elapsed; the buffer starts as 120 zeros,
    # each frame drops the oldest entry and appends shown = max(level(t), shown * 0.9),
    # computed in float32 like the original. Returns the last 120, oldest first.
    buf = [0.0] * 120
    shown = 0.0
    n = round(elapsed * 60)
    for k in range(1, n + 1):
        shown = f32(max(f32(level(k / 60)), f32(shown * f32(0.9))))
        buf = buf[1:] + [shown]
    return buf

RECIPE = ("level(t) = min(1, 0.15 + |sin(9t)| * (0.55 + 0.45*sin(1.7t)) * 0.8), t in seconds. "
          "Simulated as the original's render loop at exactly 60 fps: the 120-entry buffer starts as zeros "
          "(as after reset()); for frames k = 1..round(elapsed*60) with t = k/60, shown = max(level(t), shown*0.9) "
          "(float32, shown starts at 0), removeFirst(), append(shown). levels is the buffer after the last frame, "
          "oldest first; levels[119] = shown at t = elapsed (7.0 s). The same levels are used for every phase "
          "(the original stops appending real levels once inactive; this scene does not model that).")

LEVELS = history()
TWO = "So the overlay should feel like a little tape machine, with the reel turning while I talk and a mark where it cut."
LONG = ("So the overlay should feel like a little tape machine, with the reel turning while I talk, and an orange "
        "mark on the tape wherever a phrase was cut. Earlier text scrolls off the top once there is more than about "
        "four lines of it, and the tail starts with an ellipsis so you can tell it was cut there.")
assert len(LONG) == 300, len(LONG)

def state(name, phase, text):
    return {"name": name, "phase": phase, "text": text, "clockSeconds": 7, "time": 1.25,
            "elapsed": ELAPSED, "levels": LEVELS, "cuts": [2.75, 5.95]}

states = []
for phase in ["listening", "handsFree", "transcribing", "typed", "failed"]:
    states.append(state(f"{phase}-empty", phase, ""))
    states.append(state(f"{phase}-two-line", phase, TWO))
states.append(state("listening-300", "listening", LONG))
states.append(state("typed-300", "typed", LONG))

with open(os.path.join(HERE, "sample.json"), "w") as f:
    json.dump({"levelsRecipe": RECIPE, "states": states}, f, indent=1)

def initial(phase="listening", text=""):
    s = state("initial", phase, text)
    del s["name"]
    return s

# Text appears (panel grows), a line is added, the final transcript replaces it, then hide.
first = "So the overlay should feel like a little tape machine,"
second = first + " with the reel turning while I talk and an orange mark on the tape wherever a phrase was cut."
motion = {
    "levelsRecipe": RECIPE,
    "initial": initial(),
    "waveform": "frozen",
    "lead": 0.3,
    "duration": 3.2,
    "captureHeight": 420,
    "events": [
        {"at": 0.0, "text": first},
        {"at": 0.8, "text": second},
        {"at": 1.6, "phase": "typed", "text": second},
        {"at": 2.4, "hide": True},
    ],
}
with open(os.path.join(HERE, "motion-text-hide.json"), "w") as f:
    json.dump(motion, f, indent=1)
motion2 = dict(motion, waveform="advance")
with open(os.path.join(HERE, "motion-text-hide-advance.json"), "w") as f:
    json.dump(motion2, f, indent=1)
print("ok", len(states), "states; levels[-3:] =", LEVELS[-3:])
