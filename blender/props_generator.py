"""
Orbit Oafs - planet props generator for Blender (4.2 or newer).

Builds the trees, bushes, rocks and grass that Godot scatters over the
planets, and exports them as one .glb file:
    godot/planets/models/props.glb

Every model is real size (metres), stands on the origin and points up.
Godot finds each model by its name, so keep the names if you edit them.

HOW TO USE IN BLENDER
  1. Open Blender and go to the "Scripting" tab.
  2. Click "Open" and pick this file, then press Run Script.
  3. The models appear in a collection called "OrbitOafs_Props", side by side.
  You can tweak them by hand and export again with File > Export > glTF
  (choose "Selected Objects" and the .glb format).

HOW TO USE FROM THE COMMAND LINE
  blender -b -P blender/props_generator.py -- --out godot/planets/models/props.glb
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

COLLECTION = "OrbitOafs_Props"
VERSIONS = 10   # how many different versions of every model to make


def hex_color(h):
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


C = {k: hex_color(v) for k, v in {
    "trunk": "#6e4a2e",
    "trunk_dark": "#4f3420",
    "pine_dark": "#2a7440",
    "pine": "#3a9850",
    "pine_tip": "#70c86c",
    "leaf_dark": "#3f9a3a",
    "leaf": "#6cc24a",
    "leaf_tip": "#a6e070",
    "snow": "#f4f8fc",
    "snow_shadow": "#cfdeec",
    "rock_dark": "#7f7c77",
    "rock": "#aeaaa2",
    "rock_light": "#d3cfc7",
    "grass_dark": "#4f8f36",
    "grass_tip": "#b8d46a",
    "fir_dark": "#1f5a3a",
    "fir": "#2b7448",
    "fir_tip": "#4f9a62",
    "birch_bark": "#ece8df",
    "birch_mark": "#3a3632",
    "birch_leaf_dark": "#6aa83c",
    "birch_leaf": "#9ccf4e",
    "birch_leaf_tip": "#cbe87a",
    "log_inner": "#c89a64",
    "flower_stem": "#4a9a3a",
    "flower_yellow": "#ffd84a",
    "flower_white": "#fafafa",
    "flower_pink": "#f48fb8",
    "flower_purple": "#a77be0",
    "frost_dark": "#8a8f9e",
    "frost": "#c9d3df",
    "clover_dark": "#2f7a32",
    "clover": "#5fb04a",
    "heather_stem": "#3f6a35",
    "heather": "#a86bc8",
    "heather_pink": "#d77fb4",
    "berry_red": "#d8323a",
    "berry_blue": "#4a5ad8",
    "lupine_purple": "#8a5ad8",
    "lupine_pink": "#e36fae",
    "lupine_blue": "#5a8ae8",
    "moss_dark": "#3f6e2a",
    "moss": "#7fae3e",
    "lush_dark": "#2f6e2c",
    "lush_tip": "#86c25a",
    "leafy_dark": "#2c6630",
    "leafy": "#5fa846",
    "flower_cream": "#f3ecc8",
    "fern_dark": "#2f7a34",
    "fern": "#6cbf48",
    "dead_dark": "#5e5249",
    "dead": "#a39686",
    "reed_dark": "#4d8a3a",
    "reed": "#a8c860",
    "cattail": "#6b4428",
    "mushroom_stem": "#f1e8d6",
    "mushroom_red": "#d8452f",
    "mushroom_brown": "#a8774a",
    "tall_grass_tip": "#e2d27e",
    "larch_dark": "#b8861e",
    "larch": "#e8b42c",
    "larch_tip": "#ffd75a",
    "autumn_dark": "#a8321e",
    "autumn": "#e0542c",
    "autumn_tip": "#ff9a48",
    "sandstone_dark": "#9c7f8c",
    "sandstone": "#d9ae98",
    "sandstone_light": "#f3d9c4",
}.items()}


class Builder:
    """Collects geometry with per-corner colours into one mesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")

    def add_bmesh(self, src, color_fn, smooth=True):
        """Copy another bmesh in. color_fn(position, normal) -> RGBA."""
        src.normal_update()
        vmap = {v: self.bm.verts.new(v.co) for v in src.verts}
        for f in src.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.smooth = smooth
            for loop, src_loop in zip(nf.loops, f.loops):
                loop[self.col] = color_fn(src_loop.vert.co, src_loop.vert.normal)

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        return me


def ring_cone(segments, radius, z0, z1, droop=0.0, jag=0.0, rng=None):
    """A cone with a wavy, drooping rim: one tier of a pine tree."""
    bm = bmesh.new()
    rim = []
    for i in range(segments):
        a = i / segments * math.tau
        rnd = rng.random() if rng else 0.5
        rnd2 = rng.random() if rng else 0.5
        # branch tips stick out by different amounts, so the tier is ragged and lopsided
        r = radius * (1.0 + (jag if i % 2 else -jag) * (0.3 + 1.0 * rnd) + (rnd2 - 0.5) * 0.25)
        rim.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z0 - droop * (r / radius))))
    # a middle ring gives the tier a soft, rounded shape
    mid = [bm.verts.new((v.co.x * 0.55, v.co.y * 0.55, z0 + (z1 - z0) * 0.45)) for v in rim]
    top = bm.verts.new((0, 0, z1))
    under = bm.verts.new((0, 0, z0 + (z1 - z0) * 0.12))
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((rim[i], rim[j], mid[j], mid[i]))
        bm.faces.new((mid[i], mid[j], top))
        bm.faces.new((rim[j], rim[i], under))
    return bm


def cylinder(segments, r0, r1, z0, z1):
    bm = bmesh.new()
    lo, hi = [], []
    for i in range(segments):
        a = i / segments * math.tau
        lo.append(bm.verts.new((math.cos(a) * r0, math.sin(a) * r0, z0)))
        hi.append(bm.verts.new((math.cos(a) * r1, math.sin(a) * r1, z1)))
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    return bm


def blob(subdiv, radius, center, rng, wobble=0.18, squash=1.0):
    """A lumpy ball, used for leaves, bushes and rocks."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    for v in bm.verts:
        d = v.co.normalized()
        n = noise.noise(d * 1.8 + off, noise_basis="PERLIN_NEW")
        r = radius * (1.0 + n * wobble)
        v.co = Vector((d.x * r, d.y * r, d.z * r * squash)) + Vector(center)
    return bm


def snowy(c, n, start=0.25):
    """Adds snow lying on the upward-facing parts of a colour."""
    if n.z <= start:
        return c
    return lerp(c, lerp(C["snow_shadow"], C["snow"], n.z), min(1.0, (n.z - start) * 3.5))


def bark(p, n):
    return lerp(C["trunk_dark"], C["trunk"], 0.5 + p.z * 0.1)


def make_pine(name, height, tiers, width, snowy, seed, colors=("pine_dark", "pine", "pine_tip")):
    rng = random.Random(seed)
    dark, mid, tip = (C[k] for k in colors)
    b = Builder()
    b.add_bmesh(cylinder(7, width * 0.09, width * 0.05, -0.4, height * 0.5), bark)
    base = height * 0.18
    for t in range(tiers):
        f = t / max(1, tiers - 1)                # 0 bottom, 1 top
        z0 = base + (height - base) * f * 0.78
        r = width * (1.0 - f * 0.78)
        z1 = z0 + (height - base) * 0.34
        if t == tiers - 1:
            z1 = height
        # many deep notches make each tier look like a ring of drooping branches
        r *= rng.uniform(0.82, 1.18)
        tier = ring_cone(rng.randint(14, 20), r, z0, z1, droop=r * rng.uniform(0.2, 0.4), jag=0.24, rng=rng)
        # shift, tilt and turn every tier a little so the tree isn't symmetrical
        lean = Matrix.Rotation(rng.uniform(-0.14, 0.14), 3, "X") @ Matrix.Rotation(rng.uniform(-0.14, 0.14), 3, "Y")
        spin = Matrix.Rotation(rng.uniform(0, math.tau), 3, "Z")
        bmesh.ops.rotate(tier, verts=tier.verts[:], cent=(0, 0, z0), matrix=lean @ spin)
        shift = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * r * 0.12 + Vector((0.0, 0.0, rng.uniform(-0.15, 0.15) * (z1 - z0)))
        bmesh.ops.translate(tier, verts=tier.verts[:], vec=shift)

        def color(p, n, z0=z0, z1=z1, r=r):
            k = (p.z - z0) / max(0.01, z1 - z0)
            outer = min(1.0, Vector((p.x, p.y)).length / max(0.01, r))
            c = lerp(dark, mid, k * 0.8 + 0.2)
            c = lerp(c, tip, outer * 0.45 * (1.0 - k))
            if snowy and n.z > 0.25:
                c = lerp(c, lerp(C["snow_shadow"], C["snow"], n.z), min(1.0, (n.z - 0.25) * 3.0))
            return c

        b.add_bmesh(tier, color)
    return b.finish(name)


def make_round_tree(name, height, seed, colors=("leaf_dark", "leaf", "leaf_tip")):
    rng = random.Random(seed)
    b = Builder()
    b.add_bmesh(cylinder(7, 0.28, 0.16, -0.4, height * 0.6), bark)
    crown_z = height * 0.62
    puffs = [((0, 0, crown_z), height * 0.3)]
    for _ in range(5):
        a = rng.uniform(0, math.tau)
        rr = height * rng.uniform(0.12, 0.22)
        puffs.append(((math.cos(a) * rr, math.sin(a) * rr, crown_z + rng.uniform(-0.12, 0.18) * height),
                      height * rng.uniform(0.17, 0.24)))

    dark, mid, tip = (C[k] for k in colors)

    def color(p, n):
        k = (p.z - height * 0.4) / (height * 0.6)
        c = lerp(dark, mid, k)
        return lerp(c, tip, max(0.0, n.z) * 0.35)

    for center, r in puffs:
        b.add_bmesh(blob(2, r, center, rng, 0.15), color)
    return b.finish(name)


def make_bush(name, size, seed, colors=("leaf_dark", "leaf", "leaf_tip"), snow=False):
    rng = random.Random(seed)
    b = Builder()

    dark, mid, tip = (C[k] for k in colors)

    def color(p, n):
        c = lerp(lerp(dark, mid, p.z / size), tip, max(0.0, n.z) * 0.3)
        return snowy(c, n) if snow else c

    for _ in range(4):
        a = rng.uniform(0, math.tau)
        rr = size * rng.uniform(0.1, 0.35)
        r = size * rng.uniform(0.3, 0.45)
        b.add_bmesh(blob(2, r, (math.cos(a) * rr, math.sin(a) * rr, r * 0.6), rng, 0.2, 0.8), color)
    return b.finish(name)


def make_rock(name, size, squash, seed, sharp=True, snowy=False):
    rng = random.Random(seed)
    b = Builder()
    bm = blob(3, size * 0.5, (0, 0, size * 0.18 * squash), rng, 0.32, squash)
    # flatten the bottom so it sits on the ground
    for v in bm.verts:
        if v.co.z < -size * 0.05:
            v.co.z = -size * 0.05 - (v.co.z + size * 0.05) * 0.2

    def color(p, n):
        c = lerp(C["rock_dark"], C["rock"], 0.5 + n.z * 0.5)
        c = lerp(c, C["rock_light"], max(0.0, n.z - 0.5))
        if snowy and n.z > 0.3:
            c = lerp(c, lerp(C["snow_shadow"], C["snow"], n.z), min(1.0, (n.z - 0.3) * 4.0))
        return c

    b.add_bmesh(bm, color, smooth=not sharp)
    return b.finish(name)


def make_birch(name, height, seed, snow=False):
    """A slim white-barked tree with light, airy leaves."""
    rng = random.Random(seed)
    b = Builder()

    def birch_bark(p, n):
        # dark horizontal marks on white bark
        mark = math.sin(p.z * 9.0 + math.sin(p.z * 3.1) * 2.0 + math.atan2(p.y, p.x) * 1.5)
        return C["birch_mark"] if mark > 0.93 else C["birch_bark"]

    b.add_bmesh(cylinder(8, 0.2, 0.1, -0.4, height * 0.78), birch_bark)
    crown = []
    for i in range(7):
        a = rng.uniform(0, math.tau)
        zt = rng.uniform(0.45, 0.95)
        rr = height * 0.16 * (1.0 - zt * 0.5) * rng.uniform(0.5, 1.0)
        crown.append(((math.cos(a) * rr, math.sin(a) * rr, height * zt), height * rng.uniform(0.12, 0.18)))

    def color(p, n):
        if snow:
            # winter birch: bare golden-brown crown with snow on top
            c = lerp(C["frost_dark"], C["frost"], (p.z - height * 0.4) / (height * 0.6))
            return snowy(c, n, 0.05)
        c = lerp(C["birch_leaf_dark"], C["birch_leaf"], (p.z - height * 0.4) / (height * 0.6))
        return lerp(c, C["birch_leaf_tip"], max(0.0, n.z) * 0.4)

    for center, r in crown:
        b.add_bmesh(blob(2, r, center, rng, 0.22, 0.85), color)
    return b.finish(name)


def make_log(name, length, radius, seed):
    """A fallen log lying on the ground, with cut ends."""
    rng = random.Random(seed)
    b = Builder()
    bm = bmesh.new()
    seg = 9
    rings = []
    for k in range(3):
        x = -length / 2 + length * k / 2
        ring = []
        for i in range(seg):
            a = i / seg * math.tau
            r = radius * (1.0 + rng.uniform(-0.06, 0.06)) * (1.0 - 0.15 * (k == 2))
            ring.append(bm.verts.new((x, math.cos(a) * r, math.sin(a) * r + radius * 0.75)))
        rings.append(ring)
    for k in range(2):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[2])

    def color(p, n):
        if abs(n.x) > 0.8:
            return C["log_inner"]  # cut ends show the light wood
        return bark(p, n)

    b.add_bmesh(bm, color, smooth=False)
    return b.finish(name)


def make_flowers(name, seed, colors=("flower_yellow", "flower_white", "flower_pink", "flower_purple"), count=7):
    """A small patch of wild flowers (shown from both sides)."""
    rng = random.Random(seed)
    b = Builder()
    colors = list(colors)
    for i in range(count):
        a = rng.uniform(0, math.tau)
        x, y = math.cos(a) * rng.uniform(0, 0.3), math.sin(a) * rng.uniform(0, 0.3)
        h = rng.uniform(0.25, 0.45)
        stem = cylinder(4, 0.012, 0.01, -0.05, h)
        stem.verts.ensure_lookup_table()
        for v in stem.verts:
            v.co.x += x
            v.co.y += y
        b.add_bmesh(stem, lambda p, n: C["flower_stem"], smooth=False)
        petal = C[colors[(i + seed) % len(colors)]]
        head = blob(1, 0.06, (x, y, h), rng, 0.25, 0.5)
        b.add_bmesh(head, lambda p, n, petal=petal: petal, smooth=False)
    return b.finish(name)


def make_grass(name, seed):
    """A tuft of grass blades (shown from both sides)."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(14):
        bm = bmesh.new()
        a = rng.uniform(0, math.tau)
        x, y = math.cos(a) * rng.uniform(0, 0.28), math.sin(a) * rng.uniform(0, 0.28)
        h = rng.uniform(0.35, 0.65)
        w = rng.uniform(0.05, 0.08)
        side = Vector((math.cos(a + 1.57), math.sin(a + 1.57), 0)) * w
        lean = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.05, 0.2)
        p0 = bm.verts.new(Vector((x, y, -0.05)) - side)
        p1 = bm.verts.new(Vector((x, y, -0.05)) + side)
        p2 = bm.verts.new(Vector((x, y, h * 0.55)) + side * 0.6 + lean * 0.4)
        p3 = bm.verts.new(Vector((x, y, h * 0.55)) - side * 0.6 + lean * 0.4)
        tip = bm.verts.new(Vector((x, y, h)) + lean)
        bm.faces.new((p0, p1, p2, p3))
        bm.faces.new((p3, p2, tip))
        b.add_bmesh(bm, lambda p, n: lerp(C["grass_dark"], C["grass_tip"], p.z / 0.6))
    return b.finish(name)


def make_fern(name, seed):
    """A forest-floor fern: arching fronds with small leaflets (shown from both sides)."""
    rng = random.Random(seed)
    b = Builder()
    for f in range(7):
        a = f / 7 * math.tau + rng.uniform(-0.2, 0.2)
        length = rng.uniform(0.6, 0.95)
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-out.y, out.x, 0))
        bm = bmesh.new()
        steps = 6
        left, right, mid = [], [], []
        for k in range(steps + 1):
            t = k / steps
            # rises then droops, like a real frond
            pos = out * (length * t) + Vector((0, 0, 0.55 * math.sin(t * 2.6) * length))
            w = 0.13 * math.sin(math.pi * min(1.0, t * 1.15)) * length
            mid.append(bm.verts.new(pos))
            left.append(bm.verts.new(pos + side * w - Vector((0, 0, w * 0.4))))
            right.append(bm.verts.new(pos - side * w - Vector((0, 0, w * 0.4))))
        for k in range(steps):
            bm.faces.new((mid[k], left[k], left[k + 1], mid[k + 1]))
            bm.faces.new((mid[k], mid[k + 1], right[k + 1], right[k]))

        def color(p, n, length=length):
            t = min(1.0, Vector((p.x, p.y)).length / length)
            return lerp(C["fern_dark"], C["fern"], t)

        b.add_bmesh(bm, color, smooth=True)
    return b.finish(name)


def make_pebbles(name, seed):
    """A little cluster of stones."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(6):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.0, 0.45)
        r = rng.uniform(0.06, 0.16)
        stone = blob(1, r, (math.cos(a) * rr, math.sin(a) * rr, r * 0.25), rng, 0.25, 0.55)

        def color(p, n, shade=rng.uniform(0.85, 1.1)):
            c = lerp(C["rock_dark"], C["rock_light"], 0.4 + n.z * 0.5)
            return (c[0] * shade, c[1] * shade, c[2] * shade, 1.0)

        b.add_bmesh(stone, color, smooth=False)
    return b.finish(name)


def make_stump(name, seed):
    """A cut tree stump with a few roots."""
    rng = random.Random(seed)
    b = Builder()
    r = rng.uniform(0.3, 0.45)
    h = rng.uniform(0.35, 0.7)
    bm = cylinder(9, r * 1.15, r, -0.2, h)
    top = [v for v in bm.verts if v.co.z > h - 0.01]
    bm.faces.new(top)
    b.add_bmesh(bm, lambda p, n: C["log_inner"] if n.z > 0.8 else bark(p, n), smooth=False)
    for k in range(4):
        a = k / 4 * math.tau + rng.uniform(-0.4, 0.4)
        root = cylinder(5, 0.1, 0.04, 0.0, 0.7)
        for v in root.verts:
            v.co = Matrix.Rotation(a, 4, "Z") @ (Matrix.Rotation(1.25, 4, "X") @ v.co) + Vector((0, 0, 0.12))
        b.add_bmesh(root, bark, smooth=False)
    return b.finish(name)


def make_dead_tree(name, height, seed, snow=False):
    """A bare, grey, weathered tree."""
    rng = random.Random(seed)
    b = Builder()

    def wood(p, n):
        c = lerp(C["dead_dark"], C["dead"], 0.4 + 0.6 * min(1.0, p.z / height))
        return snowy(c, n, 0.4) if snow else c

    b.add_bmesh(cylinder(7, 0.28, 0.1, -0.4, height), wood)
    for _ in range(rng.randint(4, 6)):
        z = rng.uniform(height * 0.35, height * 0.85)
        a = rng.uniform(0, math.tau)
        length = rng.uniform(1.0, 2.4) * (1.1 - z / height)
        branch = cylinder(5, 0.08, 0.025, 0.0, length)
        tilt = rng.uniform(0.6, 1.1)
        for v in branch.verts:
            v.co = Matrix.Rotation(a, 4, "Z") @ (Matrix.Rotation(tilt, 4, "X") @ v.co) + Vector((0, 0, z))
        b.add_bmesh(branch, wood, smooth=False)
    return b.finish(name)


def make_reeds(name, seed):
    """Reeds and cattails for lake and sea shores (shown from both sides)."""
    rng = random.Random(seed)
    b = Builder()
    for i in range(16):
        bm = bmesh.new()
        a = rng.uniform(0, math.tau)
        x, y = math.cos(a) * rng.uniform(0, 0.35), math.sin(a) * rng.uniform(0, 0.35)
        h = rng.uniform(0.9, 1.6)
        w = 0.025
        lean = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.05, 0.25)
        side = Vector((math.cos(a + 1.57), math.sin(a + 1.57), 0)) * w
        base = Vector((x, y, -0.1))
        p0, p1 = bm.verts.new(base - side), bm.verts.new(base + side)
        p2 = bm.verts.new(base + Vector((0, 0, h * 0.6)) + lean * 0.4 + side * 0.7)
        p3 = bm.verts.new(base + Vector((0, 0, h * 0.6)) + lean * 0.4 - side * 0.7)
        tip = bm.verts.new(base + Vector((0, 0, h)) + lean)
        bm.faces.new((p0, p1, p2, p3))
        bm.faces.new((p3, p2, tip))
        b.add_bmesh(bm, lambda p, n: lerp(C["reed_dark"], C["reed"], p.z / 1.4), smooth=False)
        if i % 4 == 0:
            head = cylinder(6, 0.045, 0.045, 0.0, 0.22)
            for v in head.verts:
                v.co += base + Vector((0, 0, h * 0.8)) + lean * 0.75
            b.add_bmesh(head, lambda p, n: C["cattail"], smooth=True)
    return b.finish(name)


def make_mushrooms(name, seed, cap_key):
    """A little cluster of mushrooms."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(rng.randint(3, 5)):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.0, 0.25)
        x, y = math.cos(a) * rr, math.sin(a) * rr
        h = rng.uniform(0.08, 0.22)
        stem = cylinder(6, 0.025, 0.02, -0.02, h)
        for v in stem.verts:
            v.co += Vector((x, y, 0))
        b.add_bmesh(stem, lambda p, n: C["mushroom_stem"], smooth=True)
        cap = blob(1, rng.uniform(0.06, 0.11), (x, y, h), rng, 0.1, 0.55)

        def cap_color(p, n, x=x, y=y):
            spot = math.sin(p.x * 90) * math.sin(p.y * 90) > 0.75 and cap_key == "mushroom_red"
            return C["mushroom_stem"] if spot else lerp(C[cap_key], C["mushroom_stem"], max(0.0, -n.z))

        b.add_bmesh(cap, cap_color, smooth=True)
    return b.finish(name)


def rounded_box(size, roundness, rng, wobble=0.06):
    """A box with soft rounded edges and a slightly lumpy surface."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True)
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    for v in bm.verts:
        c = v.co.copy()
        # push the corners in towards a ball: higher roundness = softer block
        c = c.lerp(c.normalized() * 1.25, roundness * 0.6)
        n = noise.noise(c * 1.3 + off, noise_basis="PERLIN_NEW")
        c *= 1.0 + n * wobble
        v.co = Vector((c.x * size[0] * 0.5, c.y * size[1] * 0.5, c.z * size[2] * 0.5))
    return bm


def sandstone_color(height):
    def color(p, n):
        strata = 0.5 + 0.5 * math.sin(p.z * 1.7 + math.sin(p.x * 0.3) * 1.5)
        c = lerp(C["sandstone_dark"], C["sandstone"], 0.35 + 0.4 * strata + max(0.0, p.z / height) * 0.3)
        return lerp(c, C["sandstone_light"], max(0.0, n.z - 0.4) * 1.2)
    return color


def make_cliff_rock(name, seed, size, roundness, wobble, lean=0.0):
    """One big sandstone rock. Godot stacks these in endless combinations to
    build cliffs and rock formations. Base sits on the origin."""
    rng = random.Random(seed)
    b = Builder()
    bm = rounded_box(size, roundness, rng, wobble)
    if lean:
        # lean the top over (makes wedges and overhangs)
        for v in bm.verts:
            v.co.x += (v.co.z / size[2]) * lean * size[0]
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=Vector((0, 0, size[2] * 0.45)))
    b.add_bmesh(bm, sandstone_color(size[2]), smooth=True)
    return b.finish(name)


def make_grass_clump(name, seed, blades, h_min, h_max, spread, dark, tip):
    """A clump of curved grass blades (shown from both sides). Each blade bends
    over in three segments, so the clump looks soft and lush."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(blades):
        bm = bmesh.new()
        a = rng.uniform(0, math.tau)
        r = spread * math.sqrt(rng.random())
        base = Vector((math.cos(a) * r, math.sin(a) * r, -0.05))
        h = rng.uniform(h_min, h_max)
        w = rng.uniform(0.025, 0.05) * (h / 0.6) ** 0.5
        out = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.6, 1.0)
        out = out.lerp(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)), 0.4)
        bend = rng.uniform(0.15, 0.55)
        side = Vector((-out.y, out.x, 0)).normalized() * w
        pts = []
        for k in range(4):
            t = k / 3
            pos = base + Vector((0, 0, h * t * (1.0 - bend * t * 0.5))) + out * (bend * h * t * t)
            width = 1.0 - t * 0.85
            pts.append((bm.verts.new(pos - side * width), bm.verts.new(pos + side * width)))
        for k in range(3):
            bm.faces.new((pts[k][0], pts[k][1], pts[k + 1][1], pts[k + 1][0]))
        hh = h
        b.add_bmesh(bm, lambda p, n, hh=hh: lerp(C[dark], C[tip], (p.z + 0.05) / (hh + 0.05)), smooth=False)
    return b.finish(name)


def make_leafy_bush(name, seed, size):
    """A low, leafy forest-floor plant with broad pointed leaves
    (shown from both sides)."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(rng.randint(9, 14)):
        a = rng.uniform(0, math.tau)
        length = size * rng.uniform(0.5, 1.0)
        rise = rng.uniform(0.3, 0.9)
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-out.y, out.x, 0))
        bm = bmesh.new()
        w = length * rng.uniform(0.18, 0.28)
        start = Vector((0, 0, 0.0))
        mid = out * length * 0.5 + Vector((0, 0, length * rise * 0.6))
        tip = out * length + Vector((0, 0, length * rise * 0.35))
        v0 = bm.verts.new(start)
        v1 = bm.verts.new(mid + side * w)
        v2 = bm.verts.new(tip)
        v3 = bm.verts.new(mid - side * w)
        v4 = bm.verts.new(mid + Vector((0, 0, w * 0.25)))  # a fold down the middle
        bm.faces.new((v0, v1, v4))
        bm.faces.new((v4, v1, v2))
        bm.faces.new((v0, v4, v3))
        bm.faces.new((v4, v2, v3))
        ll = length
        b.add_bmesh(bm, lambda p, n, ll=ll: lerp(C["leafy_dark"], C["leafy"], min(1.0, Vector((p.x, p.y)).length / ll)), smooth=True)
    return b.finish(name)


def leaf_diamond(b, center, length, width, angle, lift, color_fn):
    """One small flat leaf: a diamond of two triangles pointing out at `angle`."""
    bm = bmesh.new()
    out = Vector((math.cos(angle), math.sin(angle), lift))
    side = Vector((-math.sin(angle), math.cos(angle), 0.0)) * width
    c = Vector(center)
    v0 = bm.verts.new(c)
    v1 = bm.verts.new(c + out * (length * 0.5) + side)
    v2 = bm.verts.new(c + out * length)
    v3 = bm.verts.new(c + out * (length * 0.5) - side)
    bm.faces.new((v0, v1, v2, v3))
    b.add_bmesh(bm, color_fn, smooth=False)


def make_clover(name, seed):
    """A low carpet of clover: little three-lobed leaves and a few white heads."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(rng.randint(9, 13)):
        a = rng.uniform(0, math.tau)
        rr = 0.35 * math.sqrt(rng.random())
        x, y = math.cos(a) * rr, math.sin(a) * rr
        z = rng.uniform(0.05, 0.14)
        shade = rng.uniform(0.0, 1.0)
        for lobe in range(3):
            la = lobe * math.tau / 3 + a
            leaf_diamond(b, (x, y, z), 0.075, 0.035, la, 0.15,
                         lambda p, n, shade=shade: lerp(C["clover_dark"], C["clover"], 0.4 + 0.6 * shade))
    for _ in range(rng.randint(1, 3)):
        a = rng.uniform(0, math.tau)
        x, y = math.cos(a) * rng.uniform(0, 0.3), math.sin(a) * rng.uniform(0, 0.3)
        b.add_bmesh(blob(1, 0.035, (x, y, 0.17), rng, 0.2, 0.9), lambda p, n: C["flower_white"], smooth=True)
    return b.finish(name)


def make_heather(name, seed):
    """A low, dense heather shrub with purple-pink flower tips."""
    rng = random.Random(seed)
    b = Builder()
    size = rng.uniform(0.35, 0.6)
    tip = rng.choice(["heather", "heather_pink"])
    for _ in range(rng.randint(6, 10)):
        a = rng.uniform(0, math.tau)
        rr = size * rng.uniform(0.0, 0.6)
        r = size * rng.uniform(0.25, 0.4)
        b.add_bmesh(blob(1, r, (math.cos(a) * rr, math.sin(a) * rr, r * 0.5), rng, 0.3, 0.7),
                    lambda p, n, tip=tip: lerp(C["heather_stem"], C[tip], min(1.0, max(0.0, (n.z - 0.35) * 2.5)) * min(1.0, p.z / (size * 0.4))), smooth=False)
    return b.finish(name)


def make_berry_bush(name, seed):
    """A round bush with clusters of red berries."""
    rng = random.Random(seed)
    b = Builder()
    size = rng.uniform(0.9, 1.4)

    def leaf(p, n):
        return lerp(lerp(C["leaf_dark"], C["leaf"], p.z / size), C["leaf_tip"], max(0.0, n.z) * 0.25)

    for _ in range(4):
        a = rng.uniform(0, math.tau)
        rr = size * rng.uniform(0.1, 0.3)
        r = size * rng.uniform(0.3, 0.42)
        b.add_bmesh(blob(2, r, (math.cos(a) * rr, math.sin(a) * rr, r * 0.65), rng, 0.2, 0.85), leaf)
    berry = rng.choice(["berry_red", "berry_blue"])
    for _ in range(rng.randint(14, 24)):
        a = rng.uniform(0, math.tau)
        e = rng.uniform(0.1, 1.2)
        rad = size * 0.48
        p = Vector((math.cos(a) * math.cos(e) * rad, math.sin(a) * math.cos(e) * rad, size * 0.3 + math.sin(e) * rad * 0.8))
        b.add_bmesh(blob(1, 0.045, p, rng, 0.05), lambda p, n, berry=berry: C[berry], smooth=True)
    return b.finish(name)


def make_lupines(name, seed):
    """Tall spikes of purple, pink or blue flowers (shown from both sides)."""
    rng = random.Random(seed)
    b = Builder()
    color = rng.choice(["lupine_purple", "lupine_pink", "lupine_blue"])
    for _ in range(rng.randint(3, 6)):
        a = rng.uniform(0, math.tau)
        x, y = math.cos(a) * rng.uniform(0, 0.25), math.sin(a) * rng.uniform(0, 0.25)
        h = rng.uniform(0.5, 0.9)
        stem = cylinder(4, 0.012, 0.008, -0.05, h)
        for v in stem.verts:
            v.co.x += x
            v.co.y += y
        b.add_bmesh(stem, lambda p, n: C["flower_stem"], smooth=False)
        # leaves at the bottom
        for k in range(5):
            la = k * math.tau / 5 + rng.uniform(0, 0.5)
            leaf_diamond(b, (x, y, 0.04), 0.16, 0.035, la, 0.3, lambda p, n: C["leafy"])
        steps = rng.randint(4, 5)
        for k in range(steps):
            t = k / steps
            z = h * (0.45 + 0.55 * t)
            r = 0.055 * (1.0 - t * 0.55)
            b.add_bmesh(blob(1, r, (x, y, z), rng, 0.25, 1.5),
                        lambda p, n, color=color, t=t: lerp(C[color], C["flower_white"], t * 0.35), smooth=True)
    return b.finish(name)


def make_dandelions(name, seed):
    """A little patch of dandelions: yellow heads and some white puffballs."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(rng.randint(4, 8)):
        a = rng.uniform(0, math.tau)
        x, y = math.cos(a) * rng.uniform(0, 0.3), math.sin(a) * rng.uniform(0, 0.3)
        h = rng.uniform(0.12, 0.3)
        stem = cylinder(4, 0.008, 0.007, -0.02, h)
        for v in stem.verts:
            v.co.x += x
            v.co.y += y
        b.add_bmesh(stem, lambda p, n: C["flower_stem"], smooth=False)
        puff = rng.random() < 0.3
        head = blob(1, 0.05 if puff else 0.035, (x, y, h), rng, 0.15, 1.0 if puff else 0.5)
        b.add_bmesh(head, lambda p, n, puff=puff: C["flower_white"] if puff else C["flower_yellow"], smooth=True)
        for k in range(3):
            leaf_diamond(b, (x, y, 0.02), 0.13, 0.03, rng.uniform(0, math.tau), 0.1, lambda p, n: C["clover_dark"])
    return b.finish(name)


def make_moss(name, seed):
    """Soft, lumpy cushions of moss for rocks, logs and forest floors."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(rng.randint(3, 6)):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0, 0.35)
        r = rng.uniform(0.12, 0.25)
        b.add_bmesh(blob(1, r, (math.cos(a) * rr, math.sin(a) * rr, 0.0), rng, 0.25, 0.35),
                    lambda p, n: lerp(C["moss_dark"], C["moss"], max(0.0, n.z) * 0.8 + 0.2), smooth=True)
    return b.finish(name)


def make_tall_grass(name, seed):
    """Tall meadow grass, knee to waist high (shown from both sides)."""
    rng = random.Random(seed)
    b = Builder()
    for _ in range(18):
        bm = bmesh.new()
        a = rng.uniform(0, math.tau)
        x, y = math.cos(a) * rng.uniform(0, 0.4), math.sin(a) * rng.uniform(0, 0.4)
        h = rng.uniform(0.6, 1.1)
        w = rng.uniform(0.03, 0.05)
        side = Vector((math.cos(a + 1.57), math.sin(a + 1.57), 0)) * w
        lean = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.1, 0.35)
        base = Vector((x, y, -0.05))
        p0, p1 = bm.verts.new(base - side), bm.verts.new(base + side)
        p2 = bm.verts.new(base + Vector((0, 0, h * 0.55)) + lean * 0.35 + side * 0.6)
        p3 = bm.verts.new(base + Vector((0, 0, h * 0.55)) + lean * 0.35 - side * 0.6)
        tip = bm.verts.new(base + Vector((0, 0, h)) + lean)
        bm.faces.new((p0, p1, p2, p3))
        bm.faces.new((p3, p2, tip))
        b.add_bmesh(bm, lambda p, n: lerp(C["grass_dark"], C["tall_grass_tip"], p.z / 1.0), smooth=False)
    return b.finish(name)


# ---------------------------------------------------------------------------
# Materials and scene
# ---------------------------------------------------------------------------
def vertex_color_material(name, double_sided=False):
    mat = bpy.data.materials.new(name)
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    mat.use_backface_culling = not double_sided
    return mat


def fresh_collection():
    old = bpy.data.collections.get(COLLECTION)
    if old:
        for obj in list(old.all_objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if isinstance(data, bpy.types.Mesh) and data.users == 0:
                bpy.data.meshes.remove(data)
        bpy.data.collections.remove(old)
    coll = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(coll)
    return coll


def build_all():
    coll = fresh_collection()
    solid = vertex_color_material("OO_Props")
    two_sided = vertex_color_material("OO_Props_TwoSided", double_sided=True)
    # Several versions of every model ("Pine", "Pine_2", "Pine_3", ...).
    # Godot picks one at random for each tree, so the forest never repeats.
    specs = [
        ("Pine", lambda n, a: make_pine(n, a[0], a[1], a[2], False, a[3]),
         solid, [(8.0, 5, 2.4, 1), (7.0, 4, 2.7, 41), (9.5, 6, 2.2, 42)]),
        ("PineTall", lambda n, a: make_pine(n, a[0], a[1], a[2], False, a[3]),
         solid, [(11.5, 7, 2.6, 2), (13.5, 8, 2.3, 43)]),
        ("PineSnowy", lambda n, a: make_pine(n, a[0], a[1], a[2], True, a[3]),
         solid, [(8.5, 5, 2.5, 3), (10.0, 6, 2.3, 44)]),
        ("Fir", lambda n, a: make_pine(n, a[0], a[1], a[2], False, a[3], ("fir_dark", "fir", "fir_tip")),
         solid, [(12.0, 8, 1.8, 10), (10.0, 7, 1.6, 45), (14.0, 9, 1.9, 46)]),
        ("FirSnowy", lambda n, a: make_pine(n, a[0], a[1], a[2], True, a[3], ("fir_dark", "fir", "fir_tip")),
         solid, [(11.0, 8, 1.9, 11), (9.0, 6, 1.7, 47)]),
        ("Birch", lambda n, a: make_birch(n, a[0], a[1]), solid, [(9.0, 12), (8.0, 48), (10.5, 49)]),
        ("RoundTree", lambda n, a: make_round_tree(n, a[0], a[1]), solid, [(6.5, 4), (5.5, 50), (7.5, 51)]),
        ("Bush", lambda n, a: make_bush(n, a[0], a[1]), solid, [(1.6, 5), (1.2, 52), (2.0, 53)]),
        ("Rock", lambda n, a: make_rock(n, a[0], a[1], a[2]), solid,
         [(1.4, 0.8, 6), (1.2, 0.6, 54), (1.8, 0.9, 55), (1.0, 0.7, 56)]),
        ("RockFlat", lambda n, a: make_rock(n, a[0], a[1], a[2]), solid, [(2.2, 0.45, 7), (2.6, 0.35, 57)]),
        ("Boulder", lambda n, a: make_rock(n, a[0], a[1], a[2]), solid,
         [(4.5, 0.75, 8), (3.8, 0.9, 58), (5.5, 0.6, 59)]),
        ("RockSnowy", lambda n, a: make_rock(n, a[0], a[1], a[2], snowy=True), solid,
         [(1.6, 0.75, 15), (2.2, 0.6, 60)]),
        ("Grass", lambda n, a: make_grass(n, a[0]), two_sided, [(9,), (61,)]),
        ("GrassClump", lambda n, a: make_grass_clump(n, a[0], 30, 0.45, 0.85, 0.35, "lush_dark", "lush_tip"),
         two_sided, [(90,), (91,), (92,)]),
        ("GrassShort", lambda n, a: make_grass_clump(n, a[0], 16, 0.15, 0.32, 0.3, "grass_dark", "grass_tip"),
         two_sided, [(93,), (94,)]),
        ("LeafyBush", lambda n, a: make_leafy_bush(n, a[0], a[1]), two_sided, [(95, 0.7), (96, 1.0), (97, 0.55)]),
        ("WhiteFlowers", lambda n, a: make_flowers(n, a[0], ("flower_white", "flower_white", "flower_cream"), 11),
         two_sided, [(98,), (99,)]),
        ("Flowers", lambda n, a: make_flowers(n, a[0]), two_sided, [(14,), (62,), (63,)]),
        ("Fern", lambda n, a: make_fern(n, a[0]), two_sided, [(16,), (64,)]),
        ("Clover", lambda n, a: make_clover(n, a[0]), solid, [(200,)]),
        ("Heather", lambda n, a: make_heather(n, a[0]), solid, [(201,)]),
        ("BerryBush", lambda n, a: make_berry_bush(n, a[0]), solid, [(202,)]),
        ("Lupines", lambda n, a: make_lupines(n, a[0]), two_sided, [(203,)]),
        ("Dandelions", lambda n, a: make_dandelions(n, a[0]), two_sided, [(204,)]),
        ("Moss", lambda n, a: make_moss(n, a[0]), solid, [(205,)]),
        ("BirchSnowy", lambda n, a: make_birch(n, a[0], a[1], snow=True), solid, [(9.0, 206)]),
        ("BushSnowy", lambda n, a: make_bush(n, a[0], a[1], snow=True), solid, [(1.6, 207)]),
        ("DeadTreeSnowy", lambda n, a: make_dead_tree(n, a[0], a[1], snow=True), solid, [(7.5, 208)]),
        ("Pebbles", lambda n, a: make_pebbles(n, a[0]), solid, [(17,), (65,)]),
        ("Log", lambda n, a: make_log(n, a[0], a[1], a[2]), solid, [(5.0, 0.35, 13), (6.5, 0.45, 66)]),
        ("Stump", lambda n, a: make_stump(n, a[0]), solid, [(67,), (68,)]),
        ("DeadTree", lambda n, a: make_dead_tree(n, a[0], a[1]), solid, [(7.0, 69), (9.0, 70)]),
        ("Reeds", lambda n, a: make_reeds(n, a[0]), two_sided, [(71,), (72,)]),
        ("Mushrooms", lambda n, a: make_mushrooms(n, a[0], a[1]), solid,
         [(73, "mushroom_red"), (74, "mushroom_brown")]),
        ("TallGrass", lambda n, a: make_tall_grass(n, a[0]), two_sided, [(75,), (76,)]),
        ("Larch", lambda n, a: make_pine(n, a[0], a[1], a[2], False, a[3], ("larch_dark", "larch", "larch_tip")),
         solid, [(10.0, 7, 1.9, 77), (8.5, 6, 1.8, 78), (12.0, 8, 2.0, 79)]),
        ("AutumnBush", lambda n, a: make_bush(n, a[0], a[1], ("autumn_dark", "autumn", "autumn_tip")), solid,
         [(1.6, 80), (2.2, 81)]),
        ("AutumnTree", lambda n, a: make_round_tree(n, a[0], a[1], ("autumn_dark", "autumn", "autumn_tip")), solid,
         [(6.5, 82), (7.5, 83)]),
        # five different rock shapes; every formation is built from a random mix
        ("CliffSlab", lambda n, a: make_cliff_rock(n, a[0], a[1:4], 0.5, 0.08), solid, [(84, 9.0, 7.0, 3.0)]),
        ("CliffBlock", lambda n, a: make_cliff_rock(n, a[0], a[1:4], 0.55, 0.07), solid, [(85, 6.0, 5.5, 5.0)]),
        ("CliffPillar", lambda n, a: make_cliff_rock(n, a[0], a[1:4], 0.6, 0.06), solid, [(86, 3.5, 3.2, 9.0)]),
        ("CliffRound", lambda n, a: make_cliff_rock(n, a[0], a[1:4], 0.95, 0.12), solid, [(87, 5.5, 5.0, 4.0)]),
        ("CliffWedge", lambda n, a: make_cliff_rock(n, a[0], a[1:4], 0.45, 0.07, lean=0.35), solid, [(88, 7.0, 4.5, 5.5)]),
    ]
    # What each argument is, so extra versions can be made by changing them:
    # f = a size (varied up to +-20%), i = a count (varied by +-1),
    # s = a random seed (a new one gives a new shape), x = keep as it is.
    roles = {
        "Pine": "fifs", "PineTall": "fifs", "PineSnowy": "fifs", "Fir": "fifs", "FirSnowy": "fifs",
        "Larch": "fifs", "Birch": "fs", "RoundTree": "fs", "AutumnTree": "fs", "Bush": "fs",
        "AutumnBush": "fs", "Rock": "ffs", "RockFlat": "ffs", "Boulder": "ffs", "RockSnowy": "ffs",
        "Log": "ffs", "DeadTree": "fs", "LeafyBush": "sf", "Mushrooms": "sx",
        "BirchSnowy": "fs", "BushSnowy": "fs", "DeadTreeSnowy": "fs",
        "CliffSlab": "sfff", "CliffBlock": "sfff", "CliffPillar": "sfff", "CliffRound": "sfff", "CliffWedge": "sfff",
    }
    vary = random.Random(2024)

    def make_version(base_args, role):
        out = []
        for value, r in zip(base_args, role):
            if r == "f":
                out.append(value * vary.uniform(0.8, 1.22))
            elif r == "i":
                out.append(max(2, value + vary.randint(-1, 1)))
            elif r == "s":
                out.append(vary.randint(100, 99999))
            else:
                out.append(value)
        return tuple(out)

    built = []
    for base, fn, mat, variants in specs:
        role = roles.get(base, "s")
        versions = list(variants)
        k = 0
        while len(versions) < VERSIONS:
            versions.append(make_version(variants[k % len(variants)], role))
            k += 1
        for k, args in enumerate(versions[:VERSIONS]):
            name = base if k == 0 else "%s_%d" % (base, k + 1)
            built.append((fn(name, args), mat))
    models = built
    objects = []
    for i, (me, mat) in enumerate(models):
        me.materials.append(mat)
        me.color_attributes.active_color = me.color_attributes["Col"]
        obj = bpy.data.objects.new(me.name, me)
        obj.location = ((i % VERSIONS) * 8.0, (i // VERSIONS) * 10.0, 0)
        coll.objects.link(obj)
        if me.name.startswith(("Rock", "Boulder", "Cliff")):
            if hasattr(me, "set_sharp_from_angle"):
                for p in me.polygons:
                    p.use_smooth = True
                me.set_sharp_from_angle(angle=math.radians(40))
        objects.append(obj)
    return objects


def export(objects, path):
    # Godot finds models by name, so export them all standing on the origin.
    saved = [o.location.copy() for o in objects]
    for o in objects:
        o.location = (0, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True)
    for o, loc in zip(objects, saved):
        o.location = loc
    print("Exported", path)


def main():
    out = None
    if "--" in sys.argv:
        args = sys.argv[sys.argv.index("--") + 1:]
        if "--out" in args:
            out = args[args.index("--out") + 1]
    if out is None:
        here = os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.path.expanduser("~")
        out = os.path.join(here, "props.glb")
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    export(build_all(), out)


if __name__ == "__main__":
    main()
