class_name PlanetPreset
extends Resource
## The recipe for one kind of planet: its shape and colours.
## Make new planet types by duplicating presets/earthlike.tres and changing values.

@export_group("Shape")
## Share of the surface covered by ocean (0-1).
@export_range(0.0, 1.0) var ocean_amount: float = 0.48
## Bigger = more, smaller continents.
@export var continent_scale: float = 1.5
## Lowland height as a fraction of the radius.
@export var land_height: float = 0.01
## Ocean depth as a fraction of the radius.
@export var ocean_depth: float = 0.015
## Tallest mountains as a fraction of the radius (0.11 x 2300 m = 250 m). Lower = gentler slopes.
@export var mountain_height: float = 0.11
## Bigger = more, narrower mountain ridges.
@export var mountain_scale: float = 2.2
## 0 = no mountains, 1 = mountains everywhere.
@export_range(0.0, 1.0) var mountain_amount: float = 0.76
## Standalone hills and peaks outside the ranges, as a fraction of the radius.
@export var peak_height: float = 0.04
## 0 = no standalone peaks, 1 = lots.
@export_range(0.0, 1.0) var peak_amount: float = 0.55
## Rolling hills, as a fraction of the radius.
@export var hill_height: float = 0.006
## 0 = no lakes, 1 = lots of lakes.
@export_range(0.0, 1.0) var lakes: float = 0.5
## 0 = no rivers, 1 = rivers in most lowlands.
@export_range(0.0, 1.0) var rivers: float = 0.6
## Roughly how far apart rivers are, in metres.
@export var river_spacing_m: float = 1300.0
## Half the width of a river, in metres.
@export var river_width_m: float = 9.0
## Half the width of a river valley, in metres.
@export var valley_width_m: float = 170.0
## Height of the rocky ledges on mountains, in metres.
@export var ledge_height_m: float = 14.0
## 0 = smooth mountains, 1 = strong ledges.
@export_range(0.0, 1.0) var ledge_strength: float = 0.3
## Small bumps you notice when walking, in metres.
@export var bump_height_m: float = 0.9
## Size of those bumps, in metres.
@export var bump_size_m: float = 34.0
## Snow starts at this height, as a fraction of the radius.
@export var snow_line: float = 0.06
## Snowy polar caps start at this latitude (0 = equator, 1 = pole). Lower = bigger caps.
@export_range(0.0, 1.0) var polar_cap: float = 0.72
## 0 = no snowy areas away from the poles, 1 = lots of snowy biomes.
@export_range(0.0, 1.0) var snowy_biomes: float = 0.4

@export_group("Colours")
@export var grass_light: Color = Color("8cc84a")
@export var grass_dark: Color = Color("3f8f3a")
@export var grass_dry: Color = Color("e3be4f")
@export var forest_floor: Color = Color("2f6e33")
@export var rock_light: Color = Color("d6a587")
@export var rock_dark: Color = Color("8f6f78")
@export var snow: Color = Color("f4f8fc")
@export var snow_shadow: Color = Color("dbe6f2")
@export var ice: Color = Color("bfe6f4")
@export var taiga_grass: Color = Color("4f8a4a")
@export var sand: Color = Color("e8d2b0")
@export var dirt: Color = Color("94744f")
@export var dirt_dark: Color = Color("664d36")
@export var shallow_water: Color = Color("7fd8e0")
@export var deep_water: Color = Color("1f78b0")
@export var water: Color = Color("3fb4d6")
@export var sky: Color = Color("6fb6f0")
@export var horizon: Color = Color("cfe9fb")
@export var atmosphere: Color = Color("8fd3ff")
@export var cloud: Color = Color("ffffff")
@export var cloud_shadow: Color = Color("c3d6e8")

@export_group("Life")
## Trees per square metre inside forests.
@export var forest_density: float = 1.0 / 28.0
## Trees per square metre on open grass.
@export var open_tree_density: float = 1.0 / 600.0
## Boulders per square metre.
@export var rock_density: float = 1.0 / 500.0
## Number of cloud groups around the planet.
@export var cloud_count: int = 70
## Number of flat landing sites to find.
@export var landing_sites: int = 8
