"""
Orbit Oafs - planet generator for Blender (4.2 or newer).

Builds a stylized planet (terrain, ocean, trees, clouds) and exports it as a
.glb file that Godot can import directly.

HOW TO USE IN BLENDER
  1. Open Blender and go to the "Scripting" tab at the top.
  2. Click "Open" and pick this file (or paste it into a new text block).
  3. Change the values in SETTINGS below if you like (seed, planet type, ...).
  4. Press the Run Script button (the play icon).
  The planet appears in a collection called "OrbitOafs_Planet". Running the
  script again replaces that collection, so the rest of your scene is safe.

HOW TO USE FROM THE COMMAND LINE
  blender -b -P blender/planet_generator.py -- --seed 7 --type earthlike
  Options: --seed N  --type NAME  --radius R  --detail N  --out DIR
           --no-export  --render  --save-blend
"""

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
    "radius": 10.0,              # planet size in metres (Godot units)
    "detail": 7,                 # 6 = chunky/light, 7 = default, 8 = heavy
    "export_glb": True,          # write a .glb file for Godot
    "render_preview": False,     # render preview images (slow-ish)
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
# All heights are fractions of the planet radius.
PRESETS = {
    "earthlike": {
        "ocean_amount": 0.48,      # share of the surface under water (0-1)
        "continent_scale": 1.5,    # bigger = more, smaller continents
        "mountain_height": 0.13,
        "mountain_scale": 3.2,
        "mountain_amount": 0.62,   # 0 = no mountains, 1 = mountains everywhere
        "hill_height": 0.012,
        "snow_line": 0.08,
        "lakes": 0.5,               # 0 = no lakes, 1 = lots
        "tree_count": 1600,
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


# ---------------------------------------------------------------------------
# Terrain
# ---------------------------------------------------------------------------
class Shape:
    """Works out the height of the ground in any direction from the centre."""

    def __init__(self, preset, rng):
        self.p = preset
        self.off = [Vector((rng.uniform(-500, 500) for _ in range(3))) for _ in range(10)]
        self.sea = 0.0
        self.cmin, self.cmax = -1.0, 1.0

    def continent(self, d):
        s = self.p["continent_scale"]
        q = d * s
        warp = Vector((
            fbm(q + self.off[1], 3),
            fbm(q + self.off[2], 3),
            fbm(q + self.off[3], 3),
        )) * 0.55
        return fbm(q + warp + self.off[0], 6)

    def calibrate(self, dirs):
        """Pick the sea level so that ocean_amount of the surface is water."""
        vals = sorted(self.continent(d) for d in dirs)
        self.cmin, self.cmax = vals[0], vals[-1]
        idx = int(self.p["ocean_amount"] * (len(vals) - 1))
        self.sea = vals[idx]

    def mountain_mask(self, d, land_t):
        amount = self.p["mountain_amount"]
        region = fbm(d * 1.6 + self.off[5], 3) * 0.5 + 0.5
        return smoothstep(0.02, 0.35, land_t) * smoothstep(1.0 - amount, 1.15 - amount * 0.7, region)

    def height(self, d):
        c = self.continent(d)
        if c < self.sea:
            depth = (self.sea - c) / max(1e-6, self.sea - self.cmin)
            return -0.05 * depth ** 0.5

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
        return h


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


def build_terrain(shape, preset, detail):
    pal = {k: hex_color(v) for k, v in preset["colors"].items()}
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=1.0)

    dirs = [v.co.normalized() for v in bm.verts]
    shape.calibrate(dirs)
    for v, d in zip(bm.verts, dirs):
        v.co = d * (1.0 + shape.height(d))

    bm.normal_update()
    snow_line = preset["snow_line"]

    # One colour per corner of the mesh, so colours stay shared between
    # neighbouring triangles. That keeps the exported file small.
    vert_color = {}
    patch_of = {}
    for v in bm.verts:
        d = v.co.normalized()
        h = v.co.length - 1.0
        slope = v.normal.dot(d)
        tint = fbm(d * 5.0 + shape.off[8], 3)
        patch = fbm(d * 2.5 + shape.off[9], 3)
        patch_of[v] = patch
        vert_color[v] = ground_color(pal, h, slope, tint, patch, snow_line)

    col = bm.loops.layers.float_color.new("Col")
    tree_spots = []
    for f in bm.faces:
        center = f.calc_center_median()
        d = center.normalized()
        h = center.length - 1.0
        slope = f.normal.dot(d)
        if h > 0.006 and (slope < 0.86 or h > snow_line):
            # Rock and snow get one flat colour per triangle: crisp facets.
            tint = fbm(d * 5.0 + shape.off[8], 3)
            c = ground_color(pal, h, slope, tint, 0.0, snow_line)
            for loop in f.loops:
                loop[col] = c
        else:
            for loop in f.loops:
                loop[col] = vert_color[loop.vert]
        if 0.005 < h < snow_line * 0.55 and slope > 0.94:
            patch = sum(patch_of[v] for v in f.verts) / len(f.verts)
            tree_spots.append(([v.co.copy() for v in f.verts], patch, h))

    me = bpy.data.meshes.new("Terrain")
    bm.to_mesh(me)
    bm.free()
    return me, tree_spots


# ---------------------------------------------------------------------------
# Small props: trees and clouds (all merged into one mesh each, cheap to draw)
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
            for loop in f.loops:
                if gradient:
                    lo, hi, c0, c1 = gradient
                    t = (verts[new_verts.index(loop.vert)][2] - lo) / (hi - lo)
                    loop[self.col] = lerp_color(c0, c1, t)
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
    top = segments
    faces = [(i, (i + 1) % segments, top) for i in range(segments)]
    return verts, faces  # no bottom cap: it is never seen


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


def orient(d, position, scale, spin):
    rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
    return Matrix.Translation(position) @ rot @ Matrix.Rotation(spin, 4, "Z") @ Matrix.Scale(scale, 4)


def build_trees(tree_spots, preset, rng):
    pal = {k: hex_color(v) for k, v in preset["colors"].items()}
    want = preset["tree_count"]
    if not tree_spots or want <= 0:
        return None

    # Trees cluster in forest patches and thin out on plain grass.
    weighted = [(f, h) for f, patch, h in tree_spots
                if rng.random() < 0.08 + smoothstep(-0.1, 0.25, patch)]
    rng.shuffle(weighted)
    weighted = weighted[:want]

    trunk = prism(4, 0.12, -0.2, 0.45)
    pine_a = cone(5, 0.55, 0.3, 1.25)
    pine_b = cone(5, 0.4, 0.8, 1.7)
    blob = ico(1, 0.5, 0.95)

    mb = MeshBuilder()
    for f, h in weighted:
        # random point inside the triangle
        a, b, c = f[:3]
        u, v = rng.random(), rng.random()
        if u + v > 1.0:
            u, v = 1.0 - u, 1.0 - v
        pos = a + (b - a) * u + (c - a) * v
        d = pos.normalized()
        size = rng.uniform(0.007, 0.012)
        m = orient(d, pos, size, rng.uniform(0, math.tau))
        shade = rng.uniform(0.85, 1.12)
        mb.add(*trunk, m, pal["trunk"])
        if h > 0.012 or rng.random() < 0.45:
            mb.add(*pine_a, m, scale_color(pal["pine"], shade))
            mb.add(*pine_b, m, scale_color(pal["pine"], shade * 1.08))
        else:
            mb.add(*blob, m, scale_color(pal["leaf"], shade))
    return mb.finish("Trees")


def build_clouds(preset, rng):
    pal = {k: hex_color(v) for k, v in preset["colors"].items()}
    count = preset["cloud_count"]
    if count <= 0:
        return None
    puff = ico(2, 1.0, 0.0)
    altitude = 1.0 + preset["mountain_height"] + 0.03
    mb = MeshBuilder()
    for _ in range(count):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
        frame = rot @ Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z")
        length = rng.uniform(0.1, 0.28)
        for _ in range(int(length * 70) + rng.randint(2, 5)):
            x = rng.uniform(-1.0, 1.0)
            y = rng.uniform(-0.4, 0.4) * (1.0 - abs(x))
            middle = 1.0 - abs(x) * 0.6
            s = rng.uniform(0.028, 0.06) * middle
            # Bend the cloud around the planet so it hugs the curve.
            p = (d + frame.to_3x3() @ Vector((x * length, y * length, 0.0))).normalized()
            pos = p * (altitude + s * 0.25)
            m = (Matrix.Translation(pos)
                 @ Vector((0, 0, 1)).rotation_difference(p).to_matrix().to_4x4()
                 @ Matrix.Diagonal((s, s, s * 0.55, 1.0)))
            mb.add(*puff, m, None, smooth=True,
                   gradient=(-1.0, 0.6, pal["cloud_bottom"], pal["cloud_top"]))
    return mb.finish("Clouds")


def build_ocean(detail):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=max(4, detail - 2), radius=1.0)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new("Ocean")
    bm.to_mesh(me)
    bm.free()
    return me


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
    nodes = mat.node_tree.nodes
    return next(n for n in nodes if n.type == "BSDF_PRINCIPLED")


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
            if data is not None and data.users == 0:
                if isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
        bpy.data.collections.remove(old)
    for mat in list(bpy.data.materials):
        if mat.name.startswith("OO_") and mat.users == 0:
            bpy.data.materials.remove(mat)
    coll = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(coll)
    return coll


def add_object(coll, name, mesh, material, parent, radius, sharp_angle=None):
    mesh.transform(Matrix.Scale(radius, 4))
    mesh.materials.append(material)
    if sharp_angle is not None:
        for poly in mesh.polygons:
            poly.use_smooth = True
        if hasattr(mesh, "set_sharp_from_angle"):
            mesh.set_sharp_from_angle(angle=sharp_angle)
        elif hasattr(mesh, "use_auto_smooth"):
            mesh.use_auto_smooth = True
            mesh.auto_smooth_angle = sharp_angle
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


def export_glb(root, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [root] + list(root.children):
        if not obj.get("preview_only"):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True)


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
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = hex_color("#0a0f24")
    bg.inputs["Strength"].default_value = 1.0

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
    cam_data.clip_start = radius * 0.01
    cam_data.clip_end = radius * 100
    cam = bpy.data.objects.new("OO_Camera", cam_data)
    cam["preview_only"] = True
    coll.objects.link(cam)
    scene.camera = cam
    return cam


def look_at(cam, target, eye):
    cam.location = eye
    cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()


def render_previews(folder, base, cam, radius, terrain_obj):
    scene = bpy.context.scene
    paths = []

    # 1) whole planet from orbit
    look_at(cam, Vector((0, 0, 0)), Vector((radius * 2.6, -radius * 2.6, radius * 1.2)))
    scene.render.filepath = os.path.join(folder, base + "_orbit.png")
    bpy.ops.render.render(write_still=True)
    paths.append(scene.render.filepath)

    # 2) low flight over the most mountainous area
    me = terrain_obj.data
    lit = [v for v in me.vertices if v.co.normalized().dot(KEY_LIGHT) > 0.55] or list(me.vertices)
    best = max(lit, key=lambda v: v.co.length)
    d = best.co.normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 0.1:
        side = d.cross(Vector((1, 0, 0)))
    side.normalize()
    eye = d * radius * 1.7 + side * radius * 0.45
    target = d * radius * 1.0 - side * radius * 0.05
    look_at(cam, target, eye)
    scene.render.filepath = os.path.join(folder, base + "_closeup.png")
    bpy.ops.render.render(write_still=True)
    paths.append(scene.render.filepath)
    return paths


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def parse_args(settings):
    if "--" not in sys.argv:
        return settings
    args = sys.argv[sys.argv.index("--") + 1:]
    s = dict(settings)
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--seed":
            s["seed"] = int(args[i + 1]); i += 1
        elif a == "--type":
            s["planet_type"] = args[i + 1]; i += 1
        elif a == "--radius":
            s["radius"] = float(args[i + 1]); i += 1
        elif a == "--detail":
            s["detail"] = int(args[i + 1]); i += 1
        elif a == "--out":
            s["output_dir"] = args[i + 1]; i += 1
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
    radius = settings["radius"]
    rng = random.Random(seed)
    name = f"{settings['planet_type']}_seed{seed}"

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    coll = fresh_collection()
    root = bpy.data.objects.new(f"Planet_{name}", None)
    root.empty_display_type = "SPHERE"
    root.empty_display_size = radius
    root["planet_type"] = settings["planet_type"]
    root["seed"] = seed
    coll.objects.link(root)

    shape = Shape(preset, rng)
    colors = {k: hex_color(v) for k, v in preset["colors"].items()}
    terrain_mat = vertex_color_material("OO_Terrain")

    terrain_me, tree_spots = build_terrain(shape, preset, settings["detail"])
    terrain = add_object(coll, "Terrain", terrain_me, terrain_mat, root, radius,
                         sharp_angle=math.radians(32))

    add_object(coll, "Ocean", build_ocean(settings["detail"]),
               water_material(colors["water"]), root, radius)

    trees_me = build_trees(tree_spots, preset, rng)
    if trees_me:
        add_object(coll, "Trees", trees_me, terrain_mat, root, radius)

    clouds_me = build_clouds(preset, rng)
    if clouds_me:
        add_object(coll, "Clouds", clouds_me, vertex_color_material("OO_Clouds", 1.0, glow=0.3),
                   root, radius)

    atmo = add_object(coll, "Atmosphere_PreviewOnly", build_atmosphere(),
                      atmosphere_material(colors["atmosphere"]), root, radius)
    atmo["preview_only"] = True
    atmo.hide_viewport = True

    folder = None
    if settings["export_glb"] or settings["render_preview"] or settings["save_blend"]:
        folder = output_folder(settings)

    if settings["export_glb"]:
        path = os.path.join(folder, name + ".glb")
        export_glb(root, path)
        print("Exported", path)

    if settings["render_preview"]:
        cam = setup_preview(coll, radius)
        for p in render_previews(folder, name, cam, radius, terrain):
            print("Rendered", p)

    if settings["save_blend"]:
        path = os.path.join(folder, name + ".blend")
        bpy.ops.wm.save_as_mainfile(filepath=path, copy=True)
        print("Saved", path)

    return root


if __name__ == "__main__":
    generate(parse_args(SETTINGS))
