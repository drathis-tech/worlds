# Orbit Oafs – Worlds

Explorable planets for **Orbit Oafs**, a game about exploring space and finding habitable planets.

Each planet is full size: about **20 minutes to run around** (12 m/s), or
about 48 minutes at walking pace. Ships
can land, and players can walk, run, swim and climb. There are forests,
meadows full of swaying grass, clover, dandelions, lupines and berry bushes,
golden grass patches, heather on the hills, autumn larches and red bushes,
dirt trails winding all over, rivers flowing through rocky gorges with
cliffs on both sides and boulders in the rapids, lakes with
reeds and foamy shores, gentle mountains with sandstone rock formations, snowy biomes
and frozen polar seas, all in warm golden-hour light with coloured haze in
the distance. You can
also fly straight up to space and back. The ground is built inside
Godot while the game runs, with lots of detail near the player and less far
away. That keeps a 2.3 km planet smooth and detailed without huge files. Change
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
| **Down in a river gorge** | **Cliffs above the river** |
| ![By the river, between the cliffs](previews/river.jpg) | ![Looking down into a river gorge](previews/gorge.jpg) |
| **River valley from above** | |
| ![A river winding through its gorge](previews/valley.jpg) | |
| **Meadow plants** | **Snowy forest** |
| ![Clover, dandelions, lupines and berry bushes](previews/meadow.jpg) | ![Snowy pines, firs, birches and bushes](previews/snow_forest.jpg) |
| **Polar cap from orbit** | |
| ![The pole from orbit](previews/orbit_pole.jpg) | |

These pictures come from Godot's Compatibility renderer running without a
graphics card. Forward+ on a real PC will look a bit nicer.

## The city planet

A planet that is one huge city, drifting alone far from any star, so it's
always night. About 17,000 skyscrapers (up to about 460 m tall in the
downtown cores) line a street grid that wraps the whole planet. There are
lit windows, neon signs, holographic billboards, glowing shopfronts, wet
streets with puddles and street lamps, flying traffic, rain, a purple haze,
and a galaxy across the sky. Walk the streets, climb buildings, or fly up to
space. From orbit, the city's grid glows like a lantern.

| Street level | Landing plaza |
| --- | --- |
| ![Neon street](previews/city_street.jpg) | ![Landing plaza](previews/city_plaza.jpg) |
| **Above the avenue** | **From a rooftop** |
| ![Street canyon](previews/city_canyon.jpg) | ![Galaxy over the downtown](previews/city_rooftop.jpg) |
| **High above** | **From orbit** |
| ![The city curving away](previews/city_skyline.jpg) | ![The glowing city planet](previews/city_orbit.jpg) |

**Try it:** in Godot, open `demo/city_demo.tscn` and press **F6** (Run Current
Scene). The controls are the same as on the nature planet.

**In your game:** add a Node3D with `planets/city/city_planet.gd` (a
`CityPlanet`). It has the same helpers as `Planet` (`landing_sites`,
`place_at_landing_site`, `up_at`, `altitude_of` and the `loaded` signal), so
ships and players work on both. Settings include **Planet Seed**, **Max
Height**, **Traffic**, **Rain**, **Clouds**, **Haze Distance** and
**Climbable Buildings**.

```
godot --path godot res://demo/city_demo.tscn -- --test-walk   # walk the streets, bump into a building
godot --path godot res://demo/city_demo.tscn -- --test-fly    # fly to space and back
godot --path godot res://demo/city_demo.tscn -- --shots       # screenshots
```

## What's here

| Path | What it is |
| --- | --- |
| `godot/` | A Godot 4.7 test project. Open it and press Play to walk around a planet. |
| `godot/planets/` | **The part your game needs.** Copy this folder into your project. |
| `godot/planets/city/` | The city planet |
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
   - **Radius**: 2300 m by default, which is about 20 minutes to run around.
   - **Lighting**: the mood. `golden_hour` (default), `pink_dusk` or `day`, in
     `planets/presets/`. It sets the sun, sky, blue shadows, haze and colour grading.
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
- **Rivers**: how many there are, how far apart (**River Spacing M**), how wide
  the water is (**River Width M**) and how wide their valleys are
  (**Valley Width M**). Rivers wind through the flat lowlands in a rocky
  gorge: **Gorge Width M** and **Cliff Height M** set its size, and
  **Rapids** how much of the river is white water with boulders sticking
  out (you can hop across on them). The water flows and carries streaks of
  foam downstream; the gorge floor is stony, with fallen rocks under the
  cliffs.
- the size of the snowy polar caps (**Polar Cap**) and how many snowy areas
  there are away from the poles (**Snowy Biomes**)
- every colour, tree and rock density, and the number of clouds
To make a new planet type, duplicate that file, change it, and set it as the
planet's **Preset**.

Settings on the Planet node:

- **Ground Detail**: how fine the ground is near the focus. 7 gives about 0.9 m.
- **Detail Distance**: how far out the detailed ground reaches.
- **Prop Draw Distance**: how far away trees and rocks are drawn.
- **Rock Formations**: how many big sandstone rock piles are scattered over
  the mountains. Each pile is a random stack of five rock shapes.
- Haze colour and thickness are part of the **Lighting** preset.
- **Low Clouds**: small clouds that drift around mountain tops.

Grass, flowers, clover, moss, ferns and pebbles are only drawn close by: grass to about 50 m,
ferns to 80 m. They fade in smoothly instead of popping. You can change those
distances and densities at the top of `planets/planet_scatter.gd` (`SMALL`).

## Trees, rocks and grass (Blender)

The props are made by `blender/props_generator.py` and saved to
`godot/planets/models/props.glb`. To change them:

1. Open Blender (4.2 or newer), go to the **Scripting** tab, open the script and press **Run Script**.
2. Edit the models by hand if you like. Keep their names (`Pine`,
   `PineTall`, `PineSnowy`, `Fir`, `FirSnowy`, `Birch`, `RoundTree`, `Bush`,
   `DeadTree`, `Log`, `Stump`, `Flowers`, `Fern`, `Reeds`, `Mushrooms`,
   `TallGrass`, `GrassClump`, `GrassShort`, `LeafyBush`, `WhiteFlowers`, `Larch`,
   `AutumnTree`, `AutumnBush`, `Pebbles`, `Rock`, `RockFlat`, `RockSnowy`, `Boulder`,
   `Grass`, `Clover`, `Heather`, `BerryBush`, `Lupines`, `Dandelions`, `Moss`,
   `BirchSnowy`, `BushSnowy`, `DeadTreeSnowy`, and the five rock-formation pieces `CliffSlab`, `CliffBlock`,
   `CliffPillar`, `CliffRound`, `CliffWedge`),
   because Godot finds them by name. Extra versions of a model are named with
   a number on the end (`Pine_2`, `Pine_3`, ...). Godot picks one at random for
   each prop, so you can add as many versions as you like. The script makes
   10 versions of every model (`VERSIONS` at the top of `build_all`).
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

- **Props:** every tree, rock, bush and plant has 10 different models.
  Each one placed also gets its own height, width, turn, slight lean (rocks
  tilt and sink into the ground) and colour tint.
- **Ground plants:** about 17 kinds, each growing where it makes sense:
  clover and dandelions in drifts on meadows, lupines on open hillsides,
  heather up high and in cooler places, moss on forest floors and shores,
  ferns and mushrooms under trees, reeds at the water.
- **Rock texture:** rocks and rock formations get blotches of lighter and
  darker stone, layers, speckles, cracks, yellow and orange lichen and moss
  on their tops, different on every rock.
- **Snowy trees:** snowy pines, firs, birches, bushes and dead trees in the
  cold lands, with more snow the colder it gets.
- **Mountains:** each mountain region has its own style, from sharp and
  ledged to round and smooth. Their shapes are bent by noise, with erosion
  gullies down their sides, standalone peaks and rocky outcrops in meadows.
- **Land:** some regions have stepped, terraced hills. Big areas each get
  their own shade of green, and forests have bare earthy patches.
- **Trails:** a network of winding dirt paths, with no trees or rocks on them,
  tall grass along the edges and pebbles in the dirt.

## Good to know

- Building the ground around the player at the start takes about 15 seconds on
  a 4-core computer (longer on a slow machine with no graphics card). Show a loading screen until the `loaded` signal fires.
- Trees and big rocks have collision. Grass, flowers, bushes and logs don't.
- Water is the same height everywhere (sea level), including lakes. Anything
  below it counts as underwater, which is how swimming knows when to start.
- Climbing only works on the ground itself, not on trees or props.
- The ground is the same every time for the same seed. Nothing is saved to disk.
