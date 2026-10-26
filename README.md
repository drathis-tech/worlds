# Orbit Oafs – Worlds

Explorable planets for **Orbit Oafs**, a game about exploring space and finding habitable planets.

Each planet is full size: about **20 minutes to walk around** at 5 m/s. Ships
can land, and players can walk, run and climb. The ground is built inside
Godot while the game runs, with lots of detail near the player and less far
away. That keeps a 1 km planet smooth and detailed without huge files. Change
one number (the seed) and you get a different planet.

| On the ground | Flying low |
| --- | --- |
| ![Standing on a landing site](previews/ground.jpg) | ![Flying over forests](previews/low_flight.jpg) |
| **Mountains** | **From orbit** |
| ![Mountains by a lake](previews/mountain.jpg) | ![The whole planet](previews/orbit.jpg) |

These pictures come from Godot's Compatibility renderer running without a
graphics card. Forward+ on a real PC will look a bit nicer.

## What's here

| Path | What it is |
| --- | --- |
| `godot/` | A Godot 4.7 test project. Open it and press Play to walk around a planet. |
| `godot/planets/` | **The part your game needs.** Copy this folder into your project. |
| `blender/props_generator.py` | Builds the trees, bushes, rocks and grass in Blender |
| `previews/` | Screenshots |

## Try it

1. Open `godot/project.godot` in Godot 4.7.
2. Press **Play**. You start on a landing site.
3. Controls: **WASD** to move, mouse to look, **Shift** to run, **Space** to jump, **Esc** frees the mouse.

## Put a planet in your game

1. Copy the `godot/planets` folder into the root of your Godot project, so it ends up at `res://planets`.
2. Add a **Node3D** to your scene and attach `planets/planet.gd`. It becomes a `Planet`.
3. In the Inspector:
   - **Planet Seed**: any number. Each one gives a different planet.
   - **Radius**: 1000 m by default, which is about 20 minutes to walk around.
   - **Focus**: your player or ship. The ground near it gets the most detail
     and the collision. If you leave it empty, the active camera is used.
   - **Start At Landing Site** (optional): something to place on a landing site at the start.
4. Add a **DirectionalLight3D** as the sun.

The planet adds its own gravity, ocean, clouds, sky, haze and atmosphere glow.

### Things your code can use

```gdscript
planet.place_at_landing_site(ship)        # put the ship on a flat landing spot
planet.landing_sites                      # Marker3D nodes, +Y points up
planet.up_at(ship.global_position)        # "up" anywhere on the planet
planet.altitude_of(ship.global_position)  # metres above sea level
planet.ground_height_at(position)         # ground height under a point
planet.loaded                             # signal: ground around the focus is ready
```

**Gravity** pulls toward the planet's centre through an `Area3D`. A
`RigidBody3D` follows it automatically. In a `CharacterBody3D`, use
`get_gravity()` and set `up_direction = -get_gravity().normalized()`.
`planets/planet_walker.gd` is a complete working example.

**Collision** only exists near the Focus. Anything else that needs to touch
the ground, like a second ship, should stay near the Focus. Otherwise you can
switch the Focus to it.

## Changing how planets look

All the planet settings live in `planets/presets/earthlike.tres`. Open it in
Godot to change the ocean amount, mountain height and how many there are,
lakes, the snow line, every colour, tree density and the number of clouds.
To make a new planet type, duplicate that file, change it, and set it as the
planet's **Preset**.

Detail settings on the Planet node:

- **Ground Detail**: how fine the ground is near the focus. 6 gives about 0.8 m.
- **Detail Distance**: how far out the detailed ground reaches.
- **Prop Draw Distance**: how far away trees and rocks are drawn.

## Trees, rocks and grass (Blender)

The props are made by `blender/props_generator.py` and saved to
`godot/planets/models/props.glb`. To change them:

1. Open Blender (4.2 or newer), go to the **Scripting** tab, open the script and press **Run Script**.
2. Edit the models by hand if you like. Keep their names (`Pine`,
   `PineTall`, `PineSnowy`, `RoundTree`, `Bush`, `Rock`, `RockFlat`,
   `Boulder`, `Grass`), because Godot finds them by name.
3. Export them as `props.glb` into `godot/planets/models/`.

From the command line:

```
blender -b -P blender/props_generator.py -- --out godot/planets/models/props.glb
```

## Checking a planet without playing

```
godot --path godot -- --test-walk   # checks landing, walking and running
godot --path godot -- --shots       # saves screenshots to Godot's user:// folder
```

## Planet types

| Type | Status |
| --- | --- |
| Earth-like (habitable) | ✅ Done |
| Others (desert, ice, lava, gas giant, …) | Still to be decided. Each will be a new preset. |

## Good to know

- Building the ground around the player at the start takes about 5 seconds on
  a 4-core computer. Show a loading screen until the `loaded` signal fires.
- Trees and big rocks have collision. Grass and bushes don't.
- The water has no collision. Players sink into it, so swimming still needs to be added.
- The ground is the same every time for the same seed. Nothing is saved to disk.
