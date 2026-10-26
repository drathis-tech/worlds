# Orbit Oafs – Worlds

Planet art for **Orbit Oafs**, a game about exploring space and finding habitable planets.

The planets are made by a Blender script, so you can make as many as you want.
Each seed number gives a different planet. The look is stylized and chunky:
faceted mountains, bright grass, turquoise water and puffy clouds.

![Earth-like planet, seed 7](previews/earthlike_seed7_orbit.jpg)

## What's here

| Folder | What it is |
| --- | --- |
| `blender/planet_generator.py` | The script that builds a planet in Blender and exports it for Godot |
| `exports/` | Ready-made planets as `.glb` files. Drag them into your Godot project. |
| `previews/` | Preview pictures of the example planets |

## Making a planet in Blender

You need Blender 4.2 or newer.

1. Open Blender and click the **Scripting** tab at the top.
2. In the text editor, click **Open** and choose `blender/planet_generator.py`.
3. At the top of the script, change `SETTINGS` if you like:
   - `seed`: any whole number. Each one is a different planet.
   - `planet_type`: only `"earthlike"` for now.
   - `radius`: planet size in metres.
   - `detail`: `6` is lighter, `7` is the default, `8` is very detailed.
4. Press **Run Script** (the ▶ button).

The planet shows up in a collection called `OrbitOafs_Planet`. Running the
script again replaces it, so the rest of your scene is not touched. A `.glb`
file is saved next to your `.blend` file in an `exports` folder. If the
`.blend` isn't saved yet, it goes to `orbit_oafs_exports` in your home folder.

### From the command line

```
blender -b -P blender/planet_generator.py -- --seed 7 --render
```

Options: `--seed N`, `--type NAME`, `--radius R`, `--detail N`, `--out FOLDER`,
`--no-export`, `--render` (saves preview pictures), `--save-blend`.

## Using a planet in Godot

1. Copy a `.glb` from `exports/` into your Godot project folder.
2. Drag it into a 3D scene.

Each planet has four parts you can control separately:

- `Terrain`: the ground. Its colours are stored in the model, so it needs no textures.
- `Ocean`: a see-through water sphere.
- `Trees`: all the trees in one mesh. Hide it on far-away planets to save performance.
- `Clouds`: rotate this slowly for moving weather.

The soft blue glow around the planet in the previews only exists inside Blender.
Godot needs a small shader for it, which is a planned next step.

## Planet types

| Type | Status |
| --- | --- |
| Earth-like (habitable) | ✅ Done |
| Others (desert, ice, lava, gas giant, …) | Still to be decided |

To add a new type, copy the `"earthlike"` block in `PRESETS` inside the script
and change its numbers and colours.
