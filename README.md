# Orbit Oafs – Worlds

Explorable planets for **Orbit Oafs**, a game about exploring space and finding habitable planets.

Each planet is full size: about **20 minutes to walk around** at 5 m/s. Ships
can land, and players can walk, run, swim and climb. There are forests,
meadows full of swaying grass and flowers, dirt trails winding all over,
lakes with reeds, mountains of different styles to climb, snowy biomes and
frozen polar seas, all softened by a blue-white haze in the distance. You can
also fly straight up to space and back. The ground is built inside
Godot while the game runs, with lots of detail near the player and less far
away. That keeps a 1 km planet smooth and detailed without huge files. Change
one number (the seed) and you get a different planet.

| On the ground | From a hilltop |
| --- | --- |
| ![Standing in the grass](previews/ground.jpg) | ![Hazy view over the hills](previews/vista.jpg) |
| **On a dirt trail** | **Trails from above** |
| ![Walking a trail](previews/trail.jpg) | ![Trails winding over the hills](previews/trail_above.jpg) |
| **In the forest** | **Flying low** |
| ![Forest by a lake](previews/forest.jpg) | ![Flying over the hills](previews/low_flight.jpg) |
| **Flown up to space** | |
| ![The planet from space, with the on-screen info](previews/space_from_walker.jpg) | |
| **Mountains** | **From orbit** |
| ![Mountains by a lake](previews/mountain.jpg) | ![The whole planet](previews/orbit.jpg) |
| **Snowy taiga** | **Frozen polar sea** |
| ![Snowy forest](previews/snow.jpg) | ![Ice shelf near the pole](previews/ice.jpg) |
| **Polar cap from orbit** | |
| ![The pole from orbit](previews/orbit_pole.jpg) | |

These pictures come from Godot's Compatibility renderer running without a
graphics card. Forward+ on a real PC will look a bit nicer.

## What's here

| Path | What it is |
| --- | --- |
| `godot/` | A Godot 4.7 test project. Open it and press Play to walk around a planet. |
| `godot/planets/` | **The part your game needs.** Copy this folder into your project. |
| `blender/props_generator.py` | Builds the trees, bushes, rocks, logs, flowers and grass in Blender |
| `previews/` | Screenshots |

## Try it

1. Open `godot/project.godot` in Godot 4.7.
2. Press **Play**. You start on a landing site.
3. Controls:
   - **WASD** to move, mouse to look, **Shift** to run, **Space** to jump.
   - **In water:** you float. **Space** swims up and **C** dives. Swim into the shore to climb out.
   - **Climbing:** walk into a steep rock face (steeper than about 52°) and you climb it.
   - **Flying:** press **F**. Look where you want to go and hold **W**. **Space** goes up,
     **C** goes down, and **Shift** is 4× faster. You speed up the higher you go, so
     space is only a few seconds away. Press **F** again to walk.
   - The info at the top of the screen shows what you're doing, your altitude and speed.
   - **Esc** frees the mouse.

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
Godot to change:

- the ocean amount, mountain height and how many there are, and standalone peaks
- lakes and the snow line
- the size of the snowy polar caps (**Polar Cap**) and how many snowy areas
  there are away from the poles (**Snowy Biomes**)
- every colour, tree and rock density, and the number of clouds
To make a new planet type, duplicate that file, change it, and set it as the
planet's **Preset**.

Settings on the Planet node:

- **Ground Detail**: how fine the ground is near the focus. 6 gives about 0.8 m.
- **Detail Distance**: how far out the detailed ground reaches.
- **Prop Draw Distance**: how far away trees and rocks are drawn.
- **Haze Distance**: how hazy the air is. At this distance things are half
  hidden. Smaller is hazier, and 0 turns haze off. It thins out as you fly higher.
- **Low Clouds**: small clouds that drift around mountain tops.

Grass, flowers, ferns and pebbles are only drawn close by: grass to about 50 m,
ferns to 80 m. They fade in smoothly instead of popping. You can change those
distances and densities at the top of `planets/planet_scatter.gd` (`SMALL`).

## Trees, rocks and grass (Blender)

The props are made by `blender/props_generator.py` and saved to
`godot/planets/models/props.glb`. To change them:

1. Open Blender (4.2 or newer), go to the **Scripting** tab, open the script and press **Run Script**.
2. Edit the models by hand if you like. Keep their names (`Pine`,
   `PineTall`, `PineSnowy`, `Fir`, `FirSnowy`, `Birch`, `RoundTree`, `Bush`,
   `DeadTree`, `Log`, `Stump`, `Flowers`, `Fern`, `Reeds`, `Mushrooms`,
   `TallGrass`, `Pebbles`, `Rock`, `RockFlat`, `RockSnowy`, `Boulder`, `Grass`),
   because Godot finds them by name. Extra versions of a model are named with
   a number on the end (`Pine_2`, `Pine_3`, ...). Godot picks one at random for
   each prop, so you can add as many versions as you like.
3. Export them as `props.glb` into `godot/planets/models/`.

From the command line:

```
blender -b -P blender/props_generator.py -- --out godot/planets/models/props.glb
```

## Checking a planet without playing

```
godot --path godot -- --test-walk   # checks landing, walking and running
godot --path godot -- --test-swim   # checks swimming to a shore and climbing out
godot --path godot -- --test-climb  # checks climbing a steep rock face
godot --path godot -- --test-fly    # flies up to space and back down
godot --path godot -- --shots       # saves screenshots to Godot's user:// folder
SHOTS=vista,ground godot --path godot -- --shots   # only some of the screenshots
```

## Planet types

| Type | Status |
| --- | --- |
| Earth-like (habitable) | ✅ Done |
| Others (desert, ice, lava, gas giant, …) | Still to be decided. Each will be a new preset. |

## How the planet avoids looking repetitive

- **Props:** every tree, rock, bush and plant has 2–4 different models.
  Each one placed also gets its own height, width, turn, slight lean (rocks
  tilt and sink into the ground) and colour tint.
- **Mountains:** each mountain region has its own style, from sharp and
  ledged to round and smooth. Their shapes are bent by noise, with erosion
  gullies down their sides, standalone peaks and rocky outcrops in meadows.
- **Land:** some regions have stepped, terraced hills. Big areas each get
  their own shade of green, and forests have bare earthy patches.
- **Trails:** a network of winding dirt paths, with no trees or rocks on them,
  tall grass along the edges and pebbles in the dirt.

## Good to know

- Building the ground around the player at the start takes about 9 seconds on
  a 4-core computer. Show a loading screen until the `loaded` signal fires.
- Trees and big rocks have collision. Grass, flowers, bushes and logs don't.
- Water is the same height everywhere (sea level), including lakes. Anything
  below it counts as underwater, which is how swimming knows when to start.
- Climbing only works on the ground itself, not on trees or props.
- The ground is the same every time for the same seed. Nothing is saved to disk.
