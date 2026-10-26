"""
Orbit Oafs - planet generator for Blender (4.2 or newer).

Builds a full-size, explorable planet that a ship can land on and players can
walk around, and exports it for Godot:

  <name>.glb          the planet: terrain chunks with collision, ocean, clouds
                      and landing sites
  <name>_trees.json   where every tree goes (Godot places them efficiently)
  trees_<type>.glb    the tree models used by the .json file

HOW TO USE IN BLENDER
  1. Open Blender and go to the "Scripting" tab at the top.
  2. Click "Open" and pick this file (or paste it into a new text block).
  3. Change the values in SETTINGS below if you like (seed, radius, ...).
  4. Press the Run Script button (the play icon). It takes a minute or two.
  The planet appears in a collection called "OrbitOafs_Planet". Running the
  script again replaces that collection, so the rest of your scene is safe.

HOW TO USE FROM THE COMMAND LINE
  blender -b -P blender/planet_generator.py -- --seed 7 --render
  Options: --seed N  --type NAME  --radius METRES  --spacing METRES
           --chunks N  --out DIR  --no-export  --render  --save-blend
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

# ---------------------------------------------------------------------------
# Settings you can change
# ---------------------------------------------------------------------------
SETTINGS = {
    "planet_type": "earthlike",  # one of the names in PRESETS below
    "seed": 42,                  # change this for a different planet
    "radius": 500.0,             # metres. 500 m = about 10 minutes to walk around
    "ground_spacing": 3.5,       # metres between ground points (smaller = finer, slower)
    "chunks": 4,                 # each of the 6 cube sides is cut into chunks x chunks pieces
    "export_glb": True,          # write the files for Godot
    "render_preview": False,     # render preview pictures (slow-ish)
    "save_blend": False,         # also save a .blend file
    "output_dir": "",            # "" = next to the .blend, or ~/orbit_oafs_exports
}


def hex_color(h):
    """'#RRGGBB' (sRGB, like in an image editor) -> linear RGBA for Blender."""
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


# Each planet type is a set of shape numbers plus a colour palette.
# Big shapes (continents, mountains) are fractions of the planet radius, so a
# planet keeps its look at any size. Small details are in metres.
PRESETS = {
    "earthlike": {
        "ocean_amount": 0.48,      # share of the surface under water (0-1)
        "continent_scale": 1.5,    # bigger = more, smaller continents
        "mountain_height": 0.13,   # fraction of radius (0.13 x 500 m = 65 m peaks)
        "mountain_scale": 3.2,
        "mountain_amount": 0.62,   # 0 = no mountains, 1 = mountains everywhere
        "hill_height": 0.012,
        "snow_line": 0.08,
        "lakes": 0.5,              # 0 = no lakes, 1 = lots
        "bump_height_m": 1.5,      # small bumps you notice when walking
        "bump_size_m": 22.0,
        "forest_trees_per_m2": 1 / 40,
        "open_trees_per_m2": 1 / 1500,
        "tree_height_m": (6.0, 11.0),
        "landing_sites": 6,
        "landing_site_radius_m": 25.0,  # flattened area around each site
        "cloud_count": 26,
        "colors": {
            "deep": "#2a86b8",
            "shallow": "#7fe6dc",
            "sand": "#e9dba3",
            "grass_light": "#8fd14f",
            "grass": "#5cb83e",
            "forest": "#3a8f3a",
            "rock_light": "#c4beb2",
            "rock_dark": "#8f8b84",
            "snow": "#f5f8fc",
            "water": "#33c3ee",
            "trunk": "#7a5232",
            "pine": "#2f7f3c",
            "leaf": "#62b845",
            "cloud_top": "#ffffff",
            "cloud_bottom": "#d4e3ef",
            "atmosphere": "#8fd3ff",
        },
    },
}


# ---------------------------------------------------------------------------
# Noise helpers
# ---------------------------------------------------------------------------
def fbm(p, octaves=5, lacunarity=2.0, gain=0.5):
    """Layered smooth noise, roughly in -1..1."""
    total, amp, norm = 0.0, 1.0, 0.0
    for _ in range(octaves):
        total += noise.noise(p, noise_basis="PERLIN_NEW") * amp
        norm += amp
        amp *= gain
        p = p * lacunarity
    return total / norm


def ridged(p, octaves=4):
    """Sharp mountain ridges, roughly in 0..1."""
    total, amp, norm = 0.0, 1.0, 0.0
    for _ in range(octaves):
        n = 1.0 - abs(noise.noise(p, noise_basis="PERLIN_NEW"))
        total += n * n * amp
        norm += amp
        amp *= 0.5
        p = p * 2.1
    return total / norm


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def lerp_color(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


def scale_color(c, f):
    return (c[0] * f, c[1] * f, c[2] * f, c[3])


def tangent_frame(d):
    """Two directions lying flat on the ground at direction d."""
    helper = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    t1 = d.cross(helper).normalized()
    return t1, d.cross(t1).normalized()


def random_direction(rng):
    return Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()


# ---------------------------------------------------------------------------
# Terrain shape
# ---------------------------------------------------------------------------
class Shape:
    """Works out the height of the ground in any direction from the centre.

    Heights are returned as a fraction of the radius (0.01 = 1% of radius).
    """

    def __init__(self, preset, rng, radius):
        self.p = preset
        self.radius = radius
        self.off = [Vector([rng.uniform(-500, 500) for _ in range(3)]) for _ in range(12)]
        self.sea = 0.0
        self.cmin, self.cmax = -1.0, 1.0
        self.sites = []  # flattened landing areas: (direction, height, cos_outer, cos_inner)

    def continent(self, d):
        q = d * self.p["continent_scale"]
        warp = Vector((
            fbm(q + self.off[1], 3),
            fbm(q + self.off[2], 3),
            fbm(q + self.off[3], 3),
        )) * 0.55
        return fbm(q + warp + self.off[0], 6)

    def calibrate(self):
        """Pick the sea level so that ocean_amount of the surface is water."""
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=5, radius=1.0)
        vals = sorted(self.continent(v.co.normalized()) for v in bm.verts)
        bm.free()
        self.cmin, self.cmax = vals[0], vals[-1]
        self.sea = vals[int(self.p["ocean_amount"] * (len(vals) - 1))]

    def mountain_mask(self, d, land_t):
        amount = self.p["mountain_amount"]
        region = fbm(d * 1.6 + self.off[5], 3) * 0.5 + 0.5
        return smoothstep(0.02, 0.35, land_t) * smoothstep(1.0 - amount, 1.15 - amount * 0.7, region)

    def bumps(self, d):
        freq = self.radius / self.p["bump_size_m"]
        return self.p["bump_height_m"] / self.radius * fbm(d * freq + self.off[10], 3)

    def raw_height(self, d):
        c = self.continent(d)
        if c < self.sea:
            depth = (self.sea - c) / max(1e-6, self.sea - self.cmin)
            return -0.05 * depth ** 0.5 + self.bumps(d) * 0.5, 0.0

        # Heights are continuous at the coast, so shorelines stay smooth.
        land_t = (c - self.sea) / max(1e-6, self.cmax - self.sea)
        h = 0.022 * land_t ** 0.6
        h += self.p["hill_height"] * (fbm(d * 7.0 + self.off[4], 3) * 0.5 + 0.5) * smoothstep(0.0, 0.2, land_t)

        mask = self.mountain_mask(d, land_t)
        if mask > 0.0:
            m = ridged(d * self.p["mountain_scale"] + self.off[6], 4)
            h += self.p["mountain_height"] * (m ** 1.6) * mask

        lakes = self.p["lakes"]
        if lakes > 0.0 and mask < 0.4:
            start = 0.42 - 0.22 * lakes
            lake = fbm(d * 3.5 + self.off[7], 3)
            t = smoothstep(start, start + 0.08, lake) * smoothstep(0.03, 0.12, land_t) * (1.0 - mask * 2.5)
            h = h + (-0.008 - h) * t
        h += self.bumps(d) * smoothstep(0.0, 0.05, land_t)
        return h, mask

    def height(self, d):
        h, _ = self.raw_height(d)
        for sd, sh, cos_outer, cos_inner in self.sites:
            c = d.dot(sd)
            if c > cos_outer:
                h += (sh - h) * smoothstep(cos_outer, cos_inner, c)
        return h


def choose_landing_sites(shape, preset, rng):
    """Find flat, grassy, dry spots far apart from each other."""
    R = shape.radius
    want = preset["landing_sites"]
    if want <= 0:
        return []
    site_r = preset["landing_site_radius_m"]
    candidates = []
    for _ in range(2500):
        d = random_direction(rng)
        h, mask = shape.raw_height(d)
        h_m = h * R
        if not (2.0 < h_m < preset["snow_line"] * R * 0.4) or mask > 0.2:
            continue
        t1, t2 = tangent_frame(d)
        worst = 0.0
        for k in range(8):
            a = k / 8 * math.tau
            dd = (d + (t1 * math.cos(a) + t2 * math.sin(a)) * (site_r * 1.4 / R)).normalized()
            hh, _ = shape.raw_height(dd)
            worst = max(worst, abs(hh - h) * R)
            if hh * R < 1.0:  # water too close
                worst = 1e9
        if worst < 4.0:
            candidates.append((worst, d, h))

    candidates.sort(key=lambda c: c[0])
    sites = []
    min_gap = math.cos(min(1.2, 3.0 / math.sqrt(want)))
    for _, d, h in candidates:
        if all(d.dot(s[0]) < min_gap for s in sites):
            sites.append((d, h))
        if len(sites) >= want:
            break

    outer = site_r * 1.6 / R
    inner = site_r / R
    shape.sites = [(d, h, math.cos(outer), math.cos(inner)) for d, h in sites]
    return sites


def ground_color(pal, h, slope, tint, patch, snow_line):
    """Pick a colour from height (fraction of radius) and slope (1 = flat)."""
    if h < 0.0:
        return lerp_color(pal["shallow"], pal["deep"], (-h) / 0.03)
    if h < 0.004 and slope > 0.9:
        return pal["sand"]
    if h > snow_line + tint * 0.012 and slope > 0.6:
        return pal["snow"]
    if slope < 0.86:
        c = lerp_color(pal["rock_light"], pal["rock_dark"], 0.5 + tint)
        return lerp_color(c, pal["rock_dark"], (0.86 - slope) * 1.5)
    c = lerp_color(pal["grass_light"], pal["grass"], 0.5 + tint * 1.4)
    c = lerp_color(c, pal["forest"], smoothstep(0.1, 0.3, patch))
    if h > snow_line * 0.6:  # grass turns to rock high up
        c = lerp_color(c, pal["rock_light"], smoothstep(snow_line * 0.6, snow_line * 0.9, h))
    return c


# ---------------------------------------------------------------------------
# Cube-sphere chunks
# ---------------------------------------------------------------------------
# The planet is a cube blown up into a ball. Each cube side is cut into
# chunks so Godot only draws and collides with the pieces near the player.
FACES = [  # name, outward axis, u axis, v axis (u x v = outward)
    ("px", Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))),
    ("nx", Vector((-1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0))),
    ("py", Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0))),
    ("ny", Vector((0, -1, 0)), Vector((1, 0, 0)), Vector((0, 0, 1))),
    ("pz", Vector((0, 0, 1)), Vector((1, 0, 0)), Vector((0, 1, 0))),
    ("nz", Vector((0, 0, -1)), Vector((0, 1, 0)), Vector((1, 0, 0))),
]


def cube_dir(face, a, b):
    """Point (a, b) in -1..1 on a cube side -> direction from the centre."""
    _, n, u, v = face
    x, y, z = n + u * a + v * b
    x2, y2, z2 = x * x, y * y, z * z
    s = Vector((
        x * math.sqrt(max(0.0, 1 - y2 / 2 - z2 / 2 + y2 * z2 / 3)),
        y * math.sqrt(max(0.0, 1 - z2 / 2 - x2 / 2 + z2 * x2 / 3)),
        z * math.sqrt(max(0.0, 1 - x2 / 2 - y2 / 2 + x2 * y2 / 3)),
    ))
    return s.normalized()


class Chunk:
    def __init__(self, face_index, ci, cj, chunks, n):
        self.face_index = face_index
        self.face = FACES[face_index]
        self.ci, self.cj = ci, cj
        self.chunks = chunks
        self.n = n
        self.id = (face_index * chunks + ci) * chunks + cj
        self.name = f"{self.face[0]}_{ci}_{cj}"

    def grid_dir(self, i, j, n=None):
        n = n or self.n
        total = self.chunks * n
        a = -1.0 + 2.0 * (self.ci * n + i) / total
        b = -1.0 + 2.0 * (self.cj * n + j) / total
        return cube_dir(self.face, a, b)


def mesh_from_lists(name, verts, faces, loop_colors, loop_normals=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    if loop_colors is not None:
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        attr.data.foreach_set("color", [c for col in loop_colors for c in col])
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    if loop_normals is not None:
        if hasattr(me, "use_auto_smooth"):  # Blender before 4.1
            me.use_auto_smooth = True
        me.normals_split_custom_set(loop_normals)
    me.update()
    return me


def build_terrain_chunk(chunk, shape, preset, pal, rng):
    """Returns (mesh, trees, has_water)."""
    R = shape.radius
    n = chunk.n
    snow_line = preset["snow_line"]
    W = n + 3  # grid with one extra ring all round, for seamless normals

    # Nudge every ground point a little so facets look hand-made instead of
    # a regular grid. The nudge depends only on the direction, so pieces that
    # share an edge still line up exactly.
    spacing = math.pi * 0.5 * R / (chunk.chunks * n)
    jitter = 0.35 * spacing / R
    jitter_freq = 0.8 * R / spacing

    dirs, pos, hts = [None] * (W * W), [None] * (W * W), [0.0] * (W * W)
    for i in range(-1, n + 2):
        for j in range(-1, n + 2):
            k = (i + 1) * W + (j + 1)
            d = chunk.grid_dir(i, j)
            d = (d + noise.noise_vector(d * jitter_freq, noise_basis="PERLIN_NEW") * jitter).normalized()
            h = shape.height(d)
            dirs[k], hts[k], pos[k] = d, h, d * (R * (1.0 + h))

    def at(i, j):
        return (i + 1) * W + (j + 1)

    verts, normals, colors, index = [], [], [], {}
    has_water = False
    for i in range(n + 1):
        for j in range(n + 1):
            k = at(i, j)
            d, h = dirs[k], hts[k]
            nrm = (pos[at(i + 1, j)] - pos[at(i - 1, j)]).cross(pos[at(i, j + 1)] - pos[at(i, j - 1)]).normalized()
            tint = fbm(d * 5.0 + shape.off[8], 3) + 0.35 * fbm(d * (R / 30.0) + shape.off[11], 2)
            patch = fbm(d * 2.5 + shape.off[9], 3) + 0.12 * fbm(d * (R / 60.0) + shape.off[11], 2)
            index[(i, j)] = len(verts)
            verts.append(pos[k][:])
            normals.append(nrm)
            colors.append((ground_color(pal, h, nrm.dot(d), tint, patch, snow_line), patch))
            has_water = has_water or h < 0.0

    faces, loop_colors, loop_normals = [], [], []
    trees = []
    forest = preset["forest_trees_per_m2"]
    open_ = preset["open_trees_per_m2"]
    gi0, gj0 = chunk.ci * n, chunk.cj * n
    for i in range(n):
        for j in range(n):
            v00, v10 = index[(i, j)], index[(i + 1, j)]
            v11, v01 = index[(i + 1, j + 1)], index[(i, j + 1)]
            if (gi0 + i + gj0 + j) % 2 == 0:
                tris = ((v00, v10, v11), (v00, v11, v01))
            else:
                tris = ((v00, v10, v01), (v10, v11, v01))
            for tri in tris:
                p0, p1, p2 = (Vector(verts[t]) for t in tri)
                center = (p0 + p1 + p2) / 3.0
                d = center.normalized()
                h = center.length / R - 1.0
                cross = (p1 - p0).cross(p2 - p0)
                fn = cross.normalized()
                slope = fn.dot(d)
                faces.append(tri)
                if h > 0.006 and (slope < 0.86 or h > snow_line):
                    # Rock and snow: one flat colour and normal per triangle,
                    # which gives crisp low-poly facets.
                    tint = fbm(d * 5.0 + shape.off[8], 3)
                    c = ground_color(pal, h, slope, tint, 0.0, snow_line)
                    loop_colors.extend((c, c, c))
                    loop_normals.extend((fn, fn, fn))
                    continue
                loop_colors.extend(colors[t][0] for t in tri)
                loop_normals.extend(normals[t] for t in tri)

                # Trees on gentle, dry grass below the rocky zone.
                h_m = h * R
                if h_m > 1.5 and h < snow_line * 0.55 and slope > 0.92:
                    patch = sum(colors[t][1] for t in tri) / 3.0
                    density = open_ + (forest - open_) * smoothstep(0.0, 0.25, patch)
                    if rng.random() < cross.length * 0.5 * density:
                        u, v = rng.random(), rng.random()
                        if u + v > 1.0:
                            u, v = 1.0 - u, 1.0 - v
                        p = p0 + (p1 - p0) * u + (p2 - p0) * v
                        lo, hi = preset["tree_height_m"]
                        kind = 0 if (h > 0.012 or rng.random() < 0.45) else 1
                        trees.append((chunk.id, kind, p, rng.uniform(0, math.tau),
                                      rng.uniform(lo, hi) / 1.7))

    # Skirts: short walls hanging down from each chunk edge. They hide any
    # hairline gaps when Godot shows neighbouring chunks at different detail.
    skirt = 2.0 + 2.0 * spacing
    edges = [
        [(i, 0) for i in range(n + 1)],
        [(n, j) for j in range(n + 1)],
        [(i, n) for i in range(n, -1, -1)],
        [(0, j) for j in range(n, -1, -1)],
    ]
    for edge in edges:
        low = []
        for ij in edge:
            k = index[ij]
            p = Vector(verts[k])
            low.append(len(verts))
            verts.append((p - p.normalized() * skirt)[:])
        for e in range(len(edge) - 1):
            a, b = index[edge[e]], index[edge[e + 1]]
            la, lb = low[e], low[e + 1]
            faces.append((a, la, lb, b))  # faces outwards, towards the neighbour
            for src in (a, a, b, b):
                loop_colors.append(colors[src][0])
                loop_normals.append(normals[src])

    me = mesh_from_lists("Terrain_" + chunk.name, verts, faces, loop_colors, loop_normals)
    return me, trees, has_water


def build_ocean_chunk(chunk, R):
    m = max(4, chunk.n // 4)
    verts, normals, index = [], [], {}
    for i in range(m + 1):
        for j in range(m + 1):
            d = chunk.grid_dir(i, j, m)
            index[(i, j)] = len(verts)
            verts.append((d * R)[:])
            normals.append(d)
    faces, loop_normals = [], []
    for i in range(m):
        for j in range(m):
            q = (index[(i, j)], index[(i + 1, j)], index[(i + 1, j + 1)], index[(i, j + 1)])
            faces.append(q)
            loop_normals.extend(normals[k] for k in q)
    return mesh_from_lists("Ocean_" + chunk.name, verts, faces, None, loop_normals)


# ---------------------------------------------------------------------------
# Small props: tree models and clouds
# ---------------------------------------------------------------------------
class MeshBuilder:
    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")

    def add(self, verts, faces, matrix, color, smooth=False, gradient=None):
        new_verts = [self.bm.verts.new(matrix @ Vector(v)) for v in verts]
        for face in faces:
            try:
                f = self.bm.faces.new([new_verts[i] for i in face])
            except ValueError:
                continue
            f.smooth = smooth
            for loop, vi in zip(f.loops, face):
                if gradient:
                    lo, hi, c0, c1 = gradient
                    loop[self.col] = lerp_color(c0, c1, (verts[vi][2] - lo) / (hi - lo))
                else:
                    loop[self.col] = color

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        return me


def cone(segments, r, z0, z1):
    verts = [(math.cos(a) * r, math.sin(a) * r, z0)
             for a in (i / segments * math.tau for i in range(segments))]
    verts.append((0.0, 0.0, z1))
    faces = [(i, (i + 1) % segments, segments) for i in range(segments)]
    faces.append(tuple(reversed(range(segments))))  # base, seen when walking under trees
    return verts, faces


def prism(segments, r, z0, z1):
    ring = [(math.cos(a) * r, math.sin(a) * r)
            for a in (i / segments * math.tau for i in range(segments))]
    verts = [(x, y, z0) for x, y in ring] + [(x, y, z1) for x, y in ring]
    faces = [(i, (i + 1) % segments, segments + (i + 1) % segments, segments + i)
             for i in range(segments)]
    return verts, faces  # no caps: hidden by the ground and the leaves


def ico(subdiv, r, z):
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=r)
    verts = [(v.co.x, v.co.y, v.co.z + z) for v in tmp.verts]
    tmp.verts.index_update()
    faces = [tuple(v.index for v in f.verts) for f in tmp.faces]
    tmp.free()
    return verts, faces


TREE_KINDS = ["Pine", "RoundTree"]  # index = "kind" in the trees file


def tree_parts(kind, pal, shade=1.0):
    """Tree model parts, 1.7 units tall, base at the origin, pointing up +Z."""
    parts = [(prism(5, 0.12, -0.3, 0.45), pal["trunk"])]
    if kind == 0:
        parts.append((cone(6, 0.55, 0.3, 1.25), scale_color(pal["pine"], shade)))
        parts.append((cone(6, 0.4, 0.8, 1.7), scale_color(pal["pine"], shade * 1.08)))
    else:
        parts.append((ico(1, 0.55, 1.05), scale_color(pal["leaf"], shade)))
    return parts


def build_tree_model(kind, pal):
    mb = MeshBuilder()
    for (verts, faces), color in tree_parts(kind, pal):
        mb.add(verts, faces, Matrix.Identity(4), color)
    return mb.finish(TREE_KINDS[kind])


def tree_matrix(p, yaw, scale):
    rot = Vector((0, 0, 1)).rotation_difference(p.normalized()).to_matrix().to_4x4()
    return Matrix.Translation(p) @ rot @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Scale(scale, 4)


def build_preview_trees(trees, pal, rng):
    """All trees merged into one mesh, only for looking at in Blender."""
    if not trees:
        return None
    mb = MeshBuilder()
    for _, kind, p, yaw, scale in trees:
        m = tree_matrix(p, yaw, scale)
        for (verts, faces), color in tree_parts(kind, pal, rng.uniform(0.85, 1.12)):
            mb.add(verts, faces, m, color)
    return mb.finish("Trees_PreviewOnly")


def build_clouds(preset, pal, rng):
    """Puffy clouds on a unit-radius planet (scaled up later)."""
    count = preset["cloud_count"]
    if count <= 0:
        return None
    puff = ico(2, 1.0, 0.0)
    altitude = 1.0 + preset["mountain_height"] + 0.03
    mb = MeshBuilder()
    for _ in range(count):
        d = random_direction(rng)
        rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
        frame = rot @ Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z")
        length = rng.uniform(0.1, 0.28)
        for _ in range(int(length * 70) + rng.randint(2, 5)):
            x = rng.uniform(-1.0, 1.0)
            y = rng.uniform(-0.4, 0.4) * (1.0 - abs(x))
            s = rng.uniform(0.028, 0.06) * (1.0 - abs(x) * 0.6)
            # Bend the cloud around the planet so it hugs the curve.
            p = (d + frame.to_3x3() @ Vector((x * length, y * length, 0.0))).normalized()
            m = (Matrix.Translation(p * (altitude + s * 0.25))
                 @ Vector((0, 0, 1)).rotation_difference(p).to_matrix().to_4x4()
                 @ Matrix.Diagonal((s, s, s * 0.55, 1.0)))
            mb.add(*puff, m, None, smooth=True,
                   gradient=(-1.0, 0.6, pal["cloud_bottom"], pal["cloud_top"]))
    return mb.finish("Clouds")


def build_atmosphere():
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=5, radius=1.2)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new("Atmosphere")
    bm.to_mesh(me)
    bm.free()
    return me


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
def _use_nodes(mat):
    # Blender 5 always uses nodes; older versions need switching on.
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True


def _principled(mat):
    _use_nodes(mat)
    return next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def _set_input(node, names, value):
    for name in names:
        if name in node.inputs:
            node.inputs[name].default_value = value
            return


def vertex_color_material(name, roughness=0.9, glow=0.0):
    mat = bpy.data.materials.new(name)
    bsdf = _principled(mat)
    attr = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    attr.location = (-300, 200)
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    _set_input(bsdf, ["Roughness"], roughness)
    _set_input(bsdf, ["Specular IOR Level", "Specular"], 0.2)
    if glow > 0.0:
        # a little self-light keeps clouds bright white on the shadow side
        _set_input(bsdf, ["Emission Color", "Emission"], (glow, glow, glow * 1.05, 1.0))
        _set_input(bsdf, ["Emission Strength"], 1.0)
    return mat


def water_material(color):
    mat = bpy.data.materials.new("OO_Water")
    bsdf = _principled(mat)
    bsdf.inputs["Base Color"].default_value = color
    _set_input(bsdf, ["Roughness"], 0.12)
    _set_input(bsdf, ["Alpha"], 0.62)
    for attr, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        if hasattr(mat, attr):
            try:
                setattr(mat, attr, value)
            except TypeError:
                pass
    return mat


def atmosphere_material(color):
    """Rim glow. Preview renders only: glTF can't carry this shader."""
    mat = bpy.data.materials.new("OO_Atmosphere_Preview")
    _use_nodes(mat)
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    transparent = nt.nodes.new("ShaderNodeBsdfTransparent")
    emission = nt.nodes.new("ShaderNodeEmission")
    weight = nt.nodes.new("ShaderNodeLayerWeight")
    power = nt.nodes.new("ShaderNodeMath")
    power.operation = "POWER"
    power.inputs[1].default_value = 4.0
    weight.inputs["Blend"].default_value = 0.25
    emission.inputs["Color"].default_value = color
    emission.inputs["Strength"].default_value = 1.5
    nt.links.new(weight.outputs["Facing"], power.inputs[0])
    nt.links.new(power.outputs[0], mix.inputs["Fac"])
    nt.links.new(transparent.outputs[0], mix.inputs[1])
    nt.links.new(emission.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "BLENDED"
    return mat


# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------
COLLECTION = "OrbitOafs_Planet"
KEY_LIGHT = Vector((-0.15, -0.9, 0.55)).normalized()  # preview sun direction


def fresh_collection():
    old = bpy.data.collections.get(COLLECTION)
    if old:
        for obj in list(old.all_objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if isinstance(data, bpy.types.Mesh) and data.users == 0:
                bpy.data.meshes.remove(data)
        bpy.data.collections.remove(old)
    for mat in list(bpy.data.materials):
        if mat.name.startswith("OO_") and mat.users == 0:
            bpy.data.materials.remove(mat)
    coll = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(coll)
    return coll


def add_empty(coll, name, parent, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    obj.location = location
    obj.parent = parent
    coll.objects.link(obj)
    return obj


def add_object(coll, name, mesh, material, parent, scale=1.0):
    if scale != 1.0:
        mesh.transform(Matrix.Scale(scale, 4))
    mesh.materials.append(material)
    if "Col" in mesh.color_attributes:
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    obj = bpy.data.objects.new(name, mesh)
    obj.parent = parent
    coll.objects.link(obj)
    return obj


def output_folder(settings):
    if settings["output_dir"]:
        folder = bpy.path.abspath(settings["output_dir"])
    elif bpy.data.filepath:
        folder = os.path.join(os.path.dirname(bpy.data.filepath), "exports")
    else:
        folder = os.path.join(os.path.expanduser("~"), "orbit_oafs_exports")
    os.makedirs(folder, exist_ok=True)
    return folder


def export_selected(objects, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True)


def to_godot(v):
    """Blender is Z-up, Godot is Y-up (the glTF exporter does the same swap)."""
    return (round(v.x, 2), round(v.z, 2), round(-v.y, 2))


def write_trees_json(path, name, trees, R, models_file):
    data = {
        "planet": name,
        "radius": R,
        "tree_models_file": models_file,
        "tree_models": TREE_KINDS,
        "fields": ["chunk", "kind", "x", "y", "z", "yaw", "scale"],
        "trees": [[c, k, *to_godot(p), round(yaw, 3), round(s, 3)] for c, k, p, yaw, s in trees],
    }
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))


# ---------------------------------------------------------------------------
# Preview renders
# ---------------------------------------------------------------------------
def setup_preview(coll, radius):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1200
    scene.view_settings.view_transform = "Standard"

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    if bpy.app.version < (5, 0, 0):
        world.use_nodes = True

    # Warm key light from upper left, cool weak fill from behind.
    for name, direction, energy, color in (
        ("OO_Sun", KEY_LIGHT, 4.0, (1.0, 0.96, 0.9)),
        ("OO_Fill", Vector((0.6, 0.7, -0.3)), 0.8, (0.6, 0.75, 1.0)),
    ):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = energy
        light.angle = math.radians(3)
        light.color = color
        obj = bpy.data.objects.new(name, light)
        obj.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        obj["preview_only"] = True
        coll.objects.link(obj)

    cam_data = bpy.data.cameras.new("OO_Camera")
    cam_data.clip_end = radius * 100
    cam = bpy.data.objects.new("OO_Camera", cam_data)
    cam["preview_only"] = True
    coll.objects.link(cam)
    scene.camera = cam
    return cam


def look_at(cam, target, eye, up=Vector((0, 0, 1))):
    forward = (target - eye).normalized()
    right = forward.cross(up).normalized()
    cam_up = right.cross(forward)
    # cameras look down their -Z axis with +Y as up
    rot = Matrix((right, cam_up, -forward)).transposed()
    cam.matrix_world = Matrix.Translation(eye) @ rot.to_4x4()


def set_sky(color, strength):
    bg = bpy.context.scene.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = color
    bg.inputs["Strength"].default_value = strength


def render_previews(folder, base, cam, shape, sites, atmosphere):
    scene = bpy.context.scene
    R = shape.radius
    paths = []

    # 1) whole planet from orbit
    set_sky(hex_color("#0a0f24"), 1.0)
    cam.data.lens = 50
    cam.data.clip_start = R * 0.01
    look_at(cam, Vector((0, 0, 0)), Vector((R * 2.6, -R * 2.6, R * 1.2)))
    scene.render.filepath = os.path.join(folder, base + "_orbit.png")
    bpy.ops.render.render(write_still=True)
    paths.append(scene.render.filepath)

    # 2) what a pilot sees just after take-off from the sunniest landing site
    if sites:
        d, _ = max(sites, key=lambda s: s[0].dot(KEY_LIGHT))
        t1, _ = tangent_frame(d)
        ground = d * R * (1.0 + shape.height(d))
        eye = ground + d * 22.0 - t1 * 30.0
        ahead = (d + t1 * (220.0 / R)).normalized()
        target = ahead * R * (1.0 + shape.height(ahead))
        set_sky(hex_color("#9fd4f5"), 1.0)  # stand-in for the in-game sky
        atmosphere.hide_render = True
        cam.data.lens = 24
        cam.data.clip_start = 0.5
        look_at(cam, target, eye, up=d)
        scene.render.filepath = os.path.join(folder, base + "_surface.png")
        bpy.ops.render.render(write_still=True)
        paths.append(scene.render.filepath)
        atmosphere.hide_render = False
    return paths


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def parse_args(settings):
    if "--" not in sys.argv:
        return settings
    args = sys.argv[sys.argv.index("--") + 1:]
    s = dict(settings)
    with_value = {"--seed": ("seed", int), "--type": ("planet_type", str),
                  "--radius": ("radius", float), "--spacing": ("ground_spacing", float),
                  "--chunks": ("chunks", int), "--out": ("output_dir", str)}
    i = 0
    while i < len(args):
        a = args[i]
        if a in with_value:
            key, cast = with_value[a]
            s[key] = cast(args[i + 1])
            i += 1
        elif a == "--no-export":
            s["export_glb"] = False
        elif a == "--render":
            s["render_preview"] = True
        elif a == "--save-blend":
            s["save_blend"] = True
        i += 1
    return s


def generate(settings):
    preset = PRESETS[settings["planet_type"]]
    seed = settings["seed"]
    R = settings["radius"]
    chunks = settings["chunks"]
    rng = random.Random(seed)
    name = f"{settings['planet_type']}_seed{seed}"
    pal = {k: hex_color(v) for k, v in preset["colors"].items()}

    # ground points per chunk side, from the wanted spacing in metres
    n = max(8, round(math.pi * 0.5 * R / chunks / settings["ground_spacing"]))

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    coll = fresh_collection()
    root = add_empty(coll, f"Planet_{name}", None)
    root.empty_display_type = "SPHERE"
    root.empty_display_size = R
    root["planet_type"] = settings["planet_type"]
    root["seed"] = seed
    root["radius"] = R

    shape = Shape(preset, rng, R)
    shape.calibrate()
    sites = choose_landing_sites(shape, preset, rng)

    terrain_mat = vertex_color_material("OO_Terrain")
    water_mat = water_material(pal["water"])
    terrain_root = add_empty(coll, "Terrain", root)
    ocean_root = add_empty(coll, "Ocean", root)
    all_trees = []
    total = 6 * chunks * chunks
    for f in range(6):
        for ci in range(chunks):
            for cj in range(chunks):
                chunk = Chunk(f, ci, cj, chunks, n)
                me, trees, has_water = build_terrain_chunk(chunk, shape, preset, pal, rng)
                # "-col" tells Godot to add collision to this piece on import.
                add_object(coll, f"Terrain_{chunk.name}-col", me, terrain_mat, terrain_root)
                if has_water:
                    add_object(coll, f"Ocean_{chunk.name}",
                               build_ocean_chunk(chunk, R), water_mat, ocean_root)
                all_trees.extend(trees)
        print(f"Planet: built {(f + 1) * chunks * chunks}/{total} ground pieces")

    sites_root = add_empty(coll, "LandingSites", root)
    for k, (d, _) in enumerate(sites, 1):
        site = add_empty(coll, f"LandingSite_{k}", sites_root,
                         d * R * (1.0 + shape.height(d)))
        site.rotation_euler = Vector((0, 0, 1)).rotation_difference(d).to_euler()
        site.empty_display_type = "SINGLE_ARROW"
        site.empty_display_size = 10.0

    clouds_me = build_clouds(preset, pal, rng)
    if clouds_me:
        add_object(coll, "Clouds", clouds_me, vertex_color_material("OO_Clouds", 1.0, glow=0.3),
                   root, scale=R)

    atmo = add_object(coll, "Atmosphere_PreviewOnly", build_atmosphere(),
                      atmosphere_material(pal["atmosphere"]), root, scale=R)
    atmo["preview_only"] = True
    atmo.hide_viewport = True

    trees_me = build_preview_trees(all_trees, pal, random.Random(seed + 1))
    if trees_me:
        tree_obj = add_object(coll, "Trees_PreviewOnly", trees_me, terrain_mat, root)
        tree_obj["preview_only"] = True
    print(f"Planet: {len(all_trees)} trees, {len(sites)} landing sites")

    folder = None
    if settings["export_glb"] or settings["render_preview"] or settings["save_blend"]:
        folder = output_folder(settings)

    if settings["export_glb"]:
        planet_objects = [root] + [o for o in root.children_recursive if not o.get("preview_only")]
        path = os.path.join(folder, name + ".glb")
        export_selected(planet_objects, path)
        print("Exported", path)

        models_file = f"trees_{settings['planet_type']}.glb"
        models = [add_object(coll, TREE_KINDS[k], build_tree_model(k, pal), terrain_mat, None)
                  for k in range(len(TREE_KINDS))]
        export_selected(models, os.path.join(folder, models_file))
        for k, obj in enumerate(models):
            obj.location = (k * 3.0, -R * 1.5, 0)  # move out of the way in Blender
            obj["preview_only"] = True

        trees_path = os.path.join(folder, name + "_trees.json")
        write_trees_json(trees_path, name, all_trees, R, models_file)
        print("Exported", trees_path)

    if settings["render_preview"]:
        cam = setup_preview(coll, R)
        for p in render_previews(folder, name, cam, shape, sites, atmo):
            print("Rendered", p)

    if settings["save_blend"]:
        path = os.path.join(folder, name + ".blend")
        bpy.ops.wm.save_as_mainfile(filepath=path, copy=True)
        print("Saved", path)

    return root


if __name__ == "__main__":
    generate(parse_args(SETTINGS))
