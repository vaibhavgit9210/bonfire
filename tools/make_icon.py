#!/usr/bin/env python3
"""
Renders the app icon for xcode/Bonfire.

Nothing is hand-drawn: the flame comes from the same particle physics the app
runs, with the same constants and the same mulberry32, so the icon is literally
a frame of the fire. The logs and the glow are signed-distance fields.

    python3 tools/make_icon.py

Writes every size the asset catalog asks for, as opaque RGB (iOS rejects app
icons with an alpha channel).
"""

import json
import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "xcode", "Bonfire", "Assets.xcassets", "AppIcon.appiconset")

SIZE = 1024
SS = 2                      # supersample, then box-filter down
N = SIZE * SS

# ---------------------------------------------------------------- randomness

M32 = 0xFFFFFFFF


class Rng:
    """mulberry32, matching index.html and FireSim.swift."""

    def __init__(self, seed):
        self.a = seed & M32

    def next(self):
        self.a = (self.a + 0x6D2B79F5) & M32
        a = self.a
        t = ((a ^ (a >> 15)) * (a | 1)) & M32
        t = ((t + (((t ^ (t >> 7)) * (t | 61)) & M32)) & M32) ^ t
        return ((t ^ (t >> 14)) & M32) / 4294967296.0


_perm = list(range(256))
_r = Rng(7717)
for _i in range(255, 0, -1):
    _j = int(_r.next() * (_i + 1))
    _perm[_i], _perm[_j] = _perm[_j], _perm[_i]


def _lat(i, j):
    return _perm[(_perm[i & 255] + (j & 255)) & 255] / 255.0


def noise2(x, y):
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a, b = _lat(xi, yi), _lat(xi + 1, yi)
    c, d = _lat(xi, yi + 1), _lat(xi + 1, yi + 1)
    top = a + (b - a) * fx
    bot = c + (d - c) * fx
    return top + (bot - top) * fy


def noise1(x):
    return noise2(x, 0.5)


RAMP = [
    (255, 253, 240), (255, 244, 202), (255, 228, 148), (255, 203, 92),
    (255, 172, 52), (252, 140, 28), (242, 108, 16), (222, 78, 10),
    (190, 50, 6), (150, 30, 4), (108, 16, 3), (66, 8, 2),
]

# ---------------------------------------------------------------- the fire

EMITTERS = [(-58, 34, 0.80, 0.0), (-2, 42, 1.00, 2.1), (54, 34, 0.85, 4.3)]


class Sim:
    """The flame half of FireSim, same constants, enough for one frame."""

    def __init__(self, U):
        self.U = U
        self.T = 0.0
        self.rnd = Rng(0x5EED)
        self.flames = []
        self.sparks = []
        self.facc = 0.0
        self.cacc = 0.0
        self.sacc = 0.0

    def pick(self):
        p = self.rnd.next() * 2.65
        s = 0.0
        for e in EMITTERS:
            s += e[2]
            if p <= s:
                return e
        return EMITTERS[1]

    def emit_flame(self, core):
        if len(self.flames) > 900:
            return
        U, r = self.U, self.rnd
        ex, ew, _, eph = self.pick()
        wob = (noise1(self.T * 0.5 + eph) - 0.5) * 24
        sp = r.next() + r.next() - 1
        p = {}
        p["x"] = (ex + wob + sp * ew) * U
        p["y"] = (10 + (r.next() - 0.5) * 18) * U
        p["vx"] = sp * -12 * U + (r.next() - 0.5) * 30 * U
        p["vy"] = -(150 if core else 95) * U * (0.7 + r.next() * 0.6)
        p["age"] = 0.0
        p["life"] = (0.24 + r.next() * 0.32) if core else (0.8 + r.next() * 0.85)
        p["size"] = ((14 + r.next() * 18) if core else (36 + r.next() * 48)) * U
        p["a0"] = (0.13 + r.next() * 0.12) if core else (0.13 + r.next() * 0.13)
        p["heat"] = 0.0 if core else r.next() * 0.3
        p["c0"] = 0.0 if core else 1.4
        p["swirl"] = (r.next() - 0.5) * 2
        if not core and r.next() < 0.06:
            p["life"] *= 1.35
            p["vy"] *= 1.5
            p["size"] *= 0.75
            p["a0"] *= 1.2
        self.flames.append(p)

    def emit_spark(self):
        U, r = self.U, self.rnd
        self.sparks.append({
            "x": (r.next() - 0.5) * 86 * U,
            "y": -(r.next() * 60) * U,
            "vx": (r.next() - 0.5) * 40 * U,
            "vy": -(150 + r.next() * 220) * U,
            "age": 0.0,
            "life": 1.1 + r.next() * 3.4,
            "size": (1.6 + r.next() * 3.2) * U,
            "flick": r.next() * 6.28,
        })

    def step(self, dt):
        U = self.U
        self.T += dt
        breath = 0.78 + noise1(self.T * 0.13 + 40) * 0.5
        gust = (noise1(self.T * 0.085) - 0.5) * 2
        windX = gust * 46 * U * (0.6 + breath * 0.5)

        self.facc += dt * 480 * breath
        while self.facc >= 1:
            self.emit_flame(False)
            self.facc -= 1
        self.cacc += dt * 150 * breath
        while self.cacc >= 1:
            self.emit_flame(True)
            self.cacc -= 1
        self.sacc += dt * 10
        while self.sacc >= 1:
            self.emit_spark()
            self.sacc -= 1

        live = []
        for p in self.flames:
            p["age"] += dt
            if p["age"] >= p["life"]:
                continue
            f = p["age"] / p["life"]
            t1 = noise2(p["x"] * 0.010, p["y"] * 0.010 - self.T * 0.55) - 0.5
            t2 = noise2(p["x"] * 0.034 + 17.3, p["y"] * 0.034 - self.T * 1.7) - 0.5
            turb = (t1 * 170 + t2 * 105) * U
            p["vx"] += (turb + p["swirl"] * 20 * U + windX * (0.25 + f * 1.1)) * dt
            p["vy"] -= (345 * (1 - f * 0.7) + 75 * breath) * U * dt
            p["vx"] -= p["x"] * 1.8 * dt
            p["vx"] *= 0.16 ** dt
            p["vy"] *= 0.42 ** dt
            p["x"] += p["vx"] * dt
            p["y"] += p["vy"] * dt
            live.append(p)
        self.flames = live

        live = []
        for p in self.sparks:
            p["age"] += dt
            if p["age"] >= p["life"]:
                continue
            k1 = noise2(p["x"] * 0.02 + 5, p["y"] * 0.02 - self.T * 1.1) - 0.5
            p["vx"] += (k1 * 260 * U + windX * 1.4) * dt
            p["vy"] += 150 * U * dt
            p["vy"] -= 210 * U * dt * max(0.0, 1 - p["age"] / (p["life"] * 0.5))
            p["vx"] *= 0.5 ** dt
            p["vy"] *= 0.62 ** dt
            p["x"] += p["vx"] * dt
            p["y"] += p["vy"] * dt
            if p["y"] > 40 * U:
                continue
            live.append(p)
        self.sparks = live


# ---------------------------------------------------------------- rendering

buf = np.zeros((N, N, 3), dtype=np.float32)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)

BASE_X = N * 0.5
BASE_Y = N * 0.86
U = N / 430.0                      # framing: the flame should fill the square


def blob(cx, cy, diameter, rgb, alpha, falloff=2.1, core=0.55):
    """One additive radial sprite, the same profile as SceneArt.radialTexture."""
    if alpha <= 0.002 or diameter <= 1:
        return
    rad = diameter * 0.5
    x0, x1 = int(cx - rad), int(cx + rad) + 1
    y0, y1 = int(cy - rad), int(cy + rad) + 1
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(N, x1), min(N, y1)
    if x1 <= x0 or y1 <= y0:
        return
    sx = (xx[y0:y1, x0:x1] - cx) / rad
    sy = (yy[y0:y1, x0:x1] - cy) / rad
    d = np.sqrt(sx * sx + sy * sy)
    a = np.where(d >= 1, 0.0, np.power(np.clip(1 - d, 0, 1), falloff))
    a = np.minimum(1.0, a * (1 + core * np.square(np.clip(1 - d * 2.2, 0, 1))))
    a = a * alpha
    for c in range(3):
        buf[y0:y1, x0:x1, c] += a * (rgb[c] / 255.0)


def capsule(ax, ay, bx, by, r):
    """Signed distance to a thick segment, for the logs."""
    pax, pay = xx - ax, yy - ay
    bax, bay = bx - ax, by - ay
    h = np.clip((pax * bax + pay * bay) / (bax * bax + bay * bay), 0.0, 1.0)
    dx, dy = pax - bax * h, pay - bay * h
    # dy is the offset across the log, negative above its axis
    return np.sqrt(dx * dx + dy * dy) - r, dy


def draw_log(ax, ay, bx, by, r, lit=1.0):
    """Opaque dark log with a warm rim along the edge facing the fire."""
    d, dy = capsule(ax, ay, bx, by, r)
    mask = np.clip(0.5 - d, 0, 1)                    # antialiased edge
    if mask.max() <= 0:
        return
    # the fire sits above these, so light the upper flank and let the belly go
    # dark. Measured across the log's own axis, so a tilted log stays even.
    top = np.clip(0.5 - dy / (2 * r), 0, 1) ** 1.35
    shade = np.stack([
        (13 + lit * 175 * top) / 255.0,
        (9 + lit * 78 * top) / 255.0,
        (7 + lit * 32 * top) / 255.0,
    ], axis=-1)
    m = mask[..., None]
    np.copyto(buf, buf * (1 - m) + shade * m)


# --- background: warm dark, brighter toward the fire
d = np.sqrt((xx - BASE_X) ** 2 + (yy - BASE_Y * 0.80) ** 2) / (N * 0.55)
g = np.clip(1 - d, 0, 1) ** 2.4
buf += np.stack([0.030 + g * 0.19, 0.014 + g * 0.066, 0.010 + g * 0.020], axis=-1)

# --- pool of firelight on the ground
blob(BASE_X, BASE_Y + 4 * U, 520 * U, (255, 146, 46), 0.18, falloff=2.4, core=0)

# --- run the fire and draw it
sim = Sim(U)
for _ in range(int(3.2 * 60)):
    sim.step(1 / 60)

# coals
cr = Rng(0x1F5A37)
for _ in range(90):
    t = cr.next() * math.tau
    rr = math.sqrt(cr.next())
    b = 0.35 + cr.next() * 0.65
    blob(BASE_X + math.cos(t) * rr * 78 * U, BASE_Y + 6 * U + math.sin(t) * rr * 16 * U,
         (10 + cr.next() * 22) * U, (255, 190, 96), b * 0.55, falloff=2.2, core=1.4)

# flames
last = len(RAMP) - 1
for p in sim.flames:
    f = p["age"] / p["life"]
    ci = p["c0"] + (f ** 1.3) * (1 + p["heat"]) * (last - p["c0"])
    idx = max(0, min(last, int(ci)))
    a = p["a0"] * min(1, p["age"] / 0.05) * ((1 - f) ** 1.35) * 1.1
    blob(BASE_X + p["x"], BASE_Y + p["y"], p["size"] * (0.55 + f * 1.05), RAMP[idx], a)

# two short logs crossed under the flame, drawn last so they sit in front
draw_log(BASE_X - 128 * U, BASE_Y + 34 * U, BASE_X + 112 * U, BASE_Y + 6 * U, 15 * U, 1.0)
draw_log(BASE_X - 106 * U, BASE_Y + 10 * U, BASE_X + 130 * U, BASE_Y + 40 * U, 13 * U, 0.9)

# sparks
for p in sim.sparks:
    f = p["age"] / p["life"]
    fk = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(sim.T * 22 + p["flick"]))
    blob(BASE_X + p["x"], BASE_Y + p["y"], p["size"] * (2.4 + fk * 1.6),
         (255, 224, 160), (1 - f) ** 2 * fk * 0.9, falloff=2.6, core=1.6)

# bloom
blob(BASE_X, BASE_Y - 110 * U, 560 * U, (255, 146, 46), 0.07, falloff=2.4, core=0)

# --- tone map and finish
buf = 1.0 - np.exp(-buf * 1.35)                  # keeps the hot core from clipping flat
vig = np.clip(1.04 - 0.60 * (np.sqrt((xx - N / 2) ** 2 + (yy - N / 2) ** 2) / (N * 0.70)) ** 2.4, 0, 1)
buf *= vig[..., None]

img = Image.fromarray(np.clip(buf * 255, 0, 255).astype(np.uint8), "RGB")
img = img.resize((SIZE, SIZE), Image.LANCZOS)

# ---------------------------------------------------------------- write out

os.makedirs(OUT, exist_ok=True)
SIZES = [16, 32, 64, 128, 256, 512, 1024]
for s in SIZES:
    out = img if s == SIZE else img.resize((s, s), Image.LANCZOS)
    out.convert("RGB").save(os.path.join(OUT, "icon-%d.png" % s), "PNG", optimize=True)

contents = {
    "images": [
        {"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"filename": "icon-16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
        {"filename": "icon-32.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
        {"filename": "icon-32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
        {"filename": "icon-64.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
        {"filename": "icon-128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
        {"filename": "icon-256.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
        {"filename": "icon-256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
        {"filename": "icon-512.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
        {"filename": "icon-512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
        {"filename": "icon-1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
    ],
    "info": {"author": "xcode", "version": 1},
}
with open(os.path.join(OUT, "Contents.json"), "w") as fh:
    json.dump(contents, fh, indent=2)

root = os.path.join(OUT, "..", "Contents.json")
with open(root, "w") as fh:
    json.dump({"info": {"author": "xcode", "version": 1}}, fh, indent=2)

print("wrote", len(SIZES), "pngs to", os.path.normpath(OUT))
