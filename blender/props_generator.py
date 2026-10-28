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
    "grass_dark": "#3f9a34",
    "grass_tip": "#a8de62",
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
    "tall_grass_tip": "#d4dc78",
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
        r = radius * (1.0 + (jag if i % 2 else -jag) * (0.6 + 0.4 * (rng.random() if rng else 0.5)))
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
        tier = ring_cone(12, r, z0, z1, droop=r * 0.22, jag=0.12, rng=rng)

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


def make_round_tree(name, height, seed):
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

    def color(p, n):
        k = (p.z - height * 0.4) / (height * 0.6)
        c = lerp(C["leaf_dark"], C["leaf"], k)
        return lerp(c, C["leaf_tip"], max(0.0, n.z) * 0.35)

    for center, r in puffs:
        b.add_bmesh(blob(2, r, center, rng, 0.15), color)
    return b.finish(name)


def make_bush(name, size, seed):
    rng = random.Random(seed)
    b = Builder()

    def color(p, n):
        return lerp(lerp(C["leaf_dark"], C["leaf"], p.z / size), C["leaf_tip"], max(0.0, n.z) * 0.3)

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


def make_birch(name, height, seed):
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


def make_flowers(name, seed):
    """A small patch of wild flowers (shown from both sides)."""
    rng = random.Random(seed)
    b = Builder()
    colors = ["flower_yellow", "flower_white", "flower_pink", "flower_purple"]
    for i in range(7):
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


def make_dead_tree(name, height, seed):
    """A bare, grey, weathered tree."""
    rng = random.Random(seed)
    b = Builder()

    def wood(p, n):
        return lerp(C["dead_dark"], C["dead"], 0.4 + 0.6 * min(1.0, p.z / height))

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
        ("Flowers", lambda n, a: make_flowers(n, a[0]), two_sided, [(14,), (62,), (63,)]),
        ("Fern", lambda n, a: make_fern(n, a[0]), two_sided, [(16,), (64,)]),
        ("Pebbles", lambda n, a: make_pebbles(n, a[0]), solid, [(17,), (65,)]),
        ("Log", lambda n, a: make_log(n, a[0], a[1], a[2]), solid, [(5.0, 0.35, 13), (6.5, 0.45, 66)]),
        ("Stump", lambda n, a: make_stump(n, a[0]), solid, [(67,), (68,)]),
        ("DeadTree", lambda n, a: make_dead_tree(n, a[0], a[1]), solid, [(7.0, 69), (9.0, 70)]),
        ("Reeds", lambda n, a: make_reeds(n, a[0]), two_sided, [(71,), (72,)]),
        ("Mushrooms", lambda n, a: make_mushrooms(n, a[0], a[1]), solid,
         [(73, "mushroom_red"), (74, "mushroom_brown")]),
        ("TallGrass", lambda n, a: make_tall_grass(n, a[0]), two_sided, [(75,), (76,)]),
    ]
    built = []
    for base, fn, mat, variants in specs:
        for k, args in enumerate(variants):
            name = base if k == 0 else "%s_%d" % (base, k + 1)
            built.append((fn(name, args), mat))
    models = built
    objects = []
    for i, (me, mat) in enumerate(models):
        me.materials.append(mat)
        me.color_attributes.active_color = me.color_attributes["Col"]
        obj = bpy.data.objects.new(me.name, me)
        obj.location = ((i % 12) * 7.0, (i // 12) * 9.0, 0)
        coll.objects.link(obj)
        if me.name.startswith("Rock") or me.name.startswith("Boulder"):
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
