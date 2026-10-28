class_name PlanetLighting
extends Resource
## A lighting mood for a planet: the sun, the sky colours, the colour of
## shadows and the haze. Swap the planet's Lighting to change the whole look
## (presets/golden_hour.tres, presets/pink_dusk.tres, presets/day.tres).

@export_group("Sun")
## Colour of the sunlight.
@export var sun_color: Color = Color("ffbf8f")
## Brightness of the sunlight.
@export var sun_energy: float = 1.7
## How high the sun is above the horizon at the start, in degrees. Low = long shadows.
@export_range(-10.0, 90.0) var sun_elevation: float = 14.0
## Which way the sun is, around the horizon, in degrees.
@export_range(0.0, 360.0) var sun_azimuth: float = 35.0

@export_group("Shadows")
## Colour light gets in the shade. Saturated blue/lavender gives painterly shadows.
@export var shadow_color: Color = Color("6f78d6")
@export var shadow_energy: float = 0.75

@export_group("Sky")
@export var sky_top: Color = Color("6aa2e6")
## Horizon colour on the sun's side.
@export var horizon_sun: Color = Color("ffc0a8")
## Horizon colour on the side away from the sun.
@export var horizon_away: Color = Color("c3c6ef")
## Glow around the sun.
@export var sun_glow: Color = Color("ffd2a0")

@export_group("Haze")
## Colour distant land fades into.
@export var haze_color: Color = Color("e9b8c4")
## At this distance (metres) things on the ground are half hidden. Smaller = hazier.
@export var haze_distance: float = 320.0

@export_group("Colour grading")
@export var saturation: float = 1.15
@export var contrast: float = 1.05
@export var exposure: float = 1.0
