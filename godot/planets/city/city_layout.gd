class_name CityLayout
extends RefCounted
## The street grid of a city planet. The planet is a cube blown up into a
## ball; each cube side is split into BLOCKS x BLOCKS city blocks, using an
## "equal-angle" mapping so blocks are nearly the same size everywhere.
## Every grid line is a great circle, so avenues run perfectly straight.
##
## The ground shader (shaders/city_ground.gdshader) uses exactly the same
## maths, so roads in the shader line up with the buildings placed here.

const BLOCKS := 24          # blocks along each cube side (about 65 m each on a 1 km planet)
const AVENUE_EVERY := 4     # every 4th road is a wide avenue
const STREET_HALF := 5.0    # half width of a street, metres
const AVENUE_HALF := 9.0    # half width of an avenue, metres
const SIDEWALK := 3.0       # sidewalk width, metres


## Direction from the planet centre for grid point (x, y) in -1..1 on a cube side.
static func dir_from(face: int, x: float, y: float) -> Vector3:
	var f: Array = PlanetShape.FACES[face]
	return (f[0] + f[1] * tan(x * PI * 0.25) + f[2] * tan(y * PI * 0.25)).normalized()


## The other way round: Vector3(face, x, y) for a direction.
static func coords(d: Vector3) -> Vector3:
	var a := d.abs()
	var face := 0
	if a.x >= a.y and a.x >= a.z:
		face = 0 if d.x > 0.0 else 1
	elif a.y >= a.z:
		face = 2 if d.y > 0.0 else 3
	else:
		face = 4 if d.z > 0.0 else 5
	var f: Array = PlanetShape.FACES[face]
	var dn: float = d.dot(f[0])
	return Vector3(face, atan(d.dot(f[1]) / dn) * 4.0 / PI, atan(d.dot(f[2]) / dn) * 4.0 / PI)


## Half width of the road along grid line k (0..BLOCKS).
static func road_half(k: int) -> float:
	return AVENUE_HALF if k % AVENUE_EVERY == 0 else STREET_HALF


## Grid line number -> -1..1 coordinate.
static func line_coord(k: float) -> float:
	return k / BLOCKS * 2.0 - 1.0


## True if this block is an open plaza (no buildings, a landing pad in the middle).
## Kept to small whole numbers so the shader gets exactly the same answer.
static func is_plaza(face: int, i: int, j: int, city_seed: int) -> bool:
	return (i * 131 + j * 197 + face * 311 + city_seed * 17) % 1009 < 36
