class_name PlanetShape
extends RefCounted
## Works out how high the ground is in any direction from the planet centre.
## Everything here only reads data, so worker threads can share one shape.

var radius: float
var preset: PlanetPreset

var _sea := 0.0          # continent value at sea level
var _c_min := -1.0
var _c_max := 1.0
var _sites: Array = []   # flattened landing areas: [dir, height, cos_outer, cos_inner]

var _continent: FastNoiseLite
var _warp: Array[FastNoiseLite] = []
var _region: FastNoiseLite
var _mountains: FastNoiseLite
var _ridges: FastNoiseLite
var _crags: FastNoiseLite
var _hills: FastNoiseLite
var _lakes: FastNoiseLite
var _bumps: FastNoiseLite
var _patch: FastNoiseLite
var _peaks: FastNoiseLite
var _biome: FastNoiseLite
var _cold_edge: FastNoiseLite
var _style: FastNoiseLite      # which kind of mountains grow where
var _gully: FastNoiseLite      # erosion channels down mountain sides
var _outcrop: FastNoiseLite    # rocky lumps poking out of meadows
var _terrace: FastNoiseLite    # regions of stepped, terraced hills
var _trail_main: FastNoiseLite # long winding dirt trails
var _trail_side: FastNoiseLite # smaller side trails
var _trail_zone: FastNoiseLite # where side trails are
var _autumn: FastNoiseLite     # patches where trees have turned gold and red
var _river: FastNoiseLite      # rivers follow the zero lines of this noise
var _river_zone: FastNoiseLite # where rivers are

# The six sides of the cube that gets blown up into a ball:
# outward axis, u axis, v axis (u x v = outward).
const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]


func _init(p_preset: PlanetPreset, p_radius: float, p_seed: int) -> void:
	preset = p_preset
	radius = p_radius
	var s := p_seed * 7919
	_continent = _make(s + 1, preset.continent_scale, 3, FastNoiseLite.FRACTAL_FBM)
	# Bends the continents into more natural shapes. (Godot's built-in
	# domain warp is jumpy at this scale, so it's done by hand.)
	for k in 3:
		_warp.append(_make(s + 20 + k, preset.continent_scale, 3, FastNoiseLite.FRACTAL_FBM))
	_region = _make(s + 2, 1.6, 3, FastNoiseLite.FRACTAL_FBM)
	_mountains = _make(s + 3, preset.mountain_scale, 4, FastNoiseLite.FRACTAL_FBM)
	_ridges = _make(s + 9, preset.mountain_scale * 0.8, 2, FastNoiseLite.FRACTAL_FBM)
	_crags = _make(s + 4, radius / 45.0, 3, FastNoiseLite.FRACTAL_FBM)
	_hills = _make(s + 5, 7.0, 3, FastNoiseLite.FRACTAL_FBM)
	_lakes = _make(s + 6, 3.5, 3, FastNoiseLite.FRACTAL_FBM)
	_bumps = _make(s + 7, radius / preset.bump_size_m, 2, FastNoiseLite.FRACTAL_FBM)
	_patch = _make(s + 8, 2.5, 4, FastNoiseLite.FRACTAL_FBM)
	_peaks = _make(s + 10, preset.mountain_scale * 3.0, 3, FastNoiseLite.FRACTAL_FBM)
	_biome = _make(s + 11, 2.2, 3, FastNoiseLite.FRACTAL_FBM)
	_cold_edge = _make(s + 12, 9.0, 3, FastNoiseLite.FRACTAL_FBM)
	_style = _make(s + 13, 2.0, 2, FastNoiseLite.FRACTAL_FBM)
	_gully = _make(s + 14, radius / 38.0, 2, FastNoiseLite.FRACTAL_FBM)
	_outcrop = _make(s + 15, radius / 70.0, 3, FastNoiseLite.FRACTAL_FBM)
	_terrace = _make(s + 16, 2.6, 2, FastNoiseLite.FRACTAL_FBM)
	# Trails follow the "zero lines" of smooth noise: long, winding, and they
	# join up into a network all round the planet.
	_trail_main = _make(s + 17, radius / 330.0, 2, FastNoiseLite.FRACTAL_FBM)
	_trail_side = _make(s + 18, radius / 150.0, 2, FastNoiseLite.FRACTAL_FBM)
	_trail_zone = _make(s + 19, 3.0, 2, FastNoiseLite.FRACTAL_FBM)
	_autumn = _make(s + 23, 4.0, 3, FastNoiseLite.FRACTAL_FBM)
	_river = _make(s + 24, radius / preset.river_spacing_m, 2, FastNoiseLite.FRACTAL_FBM)
	_river_zone = _make(s + 25, 2.0, 2, FastNoiseLite.FRACTAL_FBM)
	_calibrate()


func _make(seed_value: int, frequency: float, octaves: int, fractal: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


## Picks the sea level so that `ocean_amount` of the surface is water.
func _calibrate() -> void:
	var values := PackedFloat32Array()
	var count := 6000
	for i in count:
		values.append(continent(fibonacci_dir(i, count)))
	values.sort()
	_c_min = values[0]
	_c_max = values[count - 1]
	_sea = values[int(preset.ocean_amount * (count - 1))]


## Evenly spread directions over a sphere.
static func fibonacci_dir(i: int, count: int) -> Vector3:
	var y := 1.0 - (i + 0.5) / count * 2.0
	var r := sqrt(1.0 - y * y)
	var a := i * 2.399963229728653
	return Vector3(cos(a) * r, y, sin(a) * r)


## Point (a, b) in -1..1 on a cube side -> direction from the centre.
## Points past the edge of the side wrap round onto the next side.
static func cube_dir(face: int, a: float, b: float) -> Vector3:
	var f: Array = FACES[face]
	var c: Vector3 = f[0] + f[1] * a + f[2] * b
	var m := maxf(absf(c.x), maxf(absf(c.y), absf(c.z)))
	if m > 1.0:
		c /= m
	var x2 := c.x * c.x
	var y2 := c.y * c.y
	var z2 := c.z * c.z
	return Vector3(
		c.x * sqrt(maxf(0.0, 1.0 - y2 * 0.5 - z2 * 0.5 + y2 * z2 / 3.0)),
		c.y * sqrt(maxf(0.0, 1.0 - z2 * 0.5 - x2 * 0.5 + z2 * x2 / 3.0)),
		c.z * sqrt(maxf(0.0, 1.0 - x2 * 0.5 - y2 * 0.5 + x2 * y2 / 3.0))).normalized()


func set_landing_sites(sites: Array) -> void:
	_sites = sites


## True if direction `d` is inside a flattened landing area.
func in_landing_site(d: Vector3) -> bool:
	for site in _sites:
		if d.dot(site[0]) > site[2]:
			return true
	return false


## Raw continent value: above the sea level value means land.
func continent(d: Vector3) -> float:
	return _continent.get_noise_3dv(d + _warp_at(d) * 0.25)


func _warp_at(d: Vector3) -> Vector3:
	return Vector3(_warp[0].get_noise_3dv(d), _warp[1].get_noise_3dv(d), _warp[2].get_noise_3dv(d))


## 0..1: how much of a dirt trail is at a spot (before checking land and slope).
func trail_network(d: Vector3) -> float:
	var main := 1.0 - smoothstep(0.014, 0.03, absf(_trail_main.get_noise_3dv(d)))
	var side := 0.0
	var zone := smoothstep(0.05, 0.25, _trail_zone.get_noise_3dv(d))
	if zone > 0.0:
		side = (1.0 - smoothstep(0.012, 0.026, absf(_trail_side.get_noise_3dv(d)))) * zone
	return maxf(main, side * 0.9)


## 0..1: how much a spot is inside a mountain range.
func mountain_mask(d: Vector3, land_t: float) -> float:
	var amount := preset.mountain_amount
	var region := _region.get_noise_3dv(d) * 0.5 + 0.5
	# Mountains rise gently from the coast instead of starting as a wall.
	return smoothstep(0.08, 0.85, land_t) * smoothstep(1.0 - amount, 1.3 - amount * 0.7, region)


## 0..1: how cold a spot is. Poles are cold, and so are some patches
## elsewhere (snowy biomes). 0.5 and above is snowy ground.
func coldness(d: Vector3) -> float:
	var lat := absf(d.y)   # 0 at the equator, 1 at the poles
	var wobble := _cold_edge.get_noise_3dv(d) * 0.06
	# the edge of the polar cap wanders a lot, so it isn't a straight line
	var big_wobble := _region.get_noise_3dv(d * 1.3 + Vector3(17.0, 3.0, -9.0)) * 0.16
	var polar := smoothstep(preset.polar_cap - 0.1, preset.polar_cap + 0.05, lat + wobble + big_wobble)
	var cold := 0.0
	if preset.snowy_biomes > 0.0:
		var b := _biome.get_noise_3dv(d) * 0.5 + 0.5 + wobble
		var start := 1.0 - preset.snowy_biomes * 0.5
		# no snowy patches near the equator
		cold = smoothstep(start - 0.12, start + 0.04, b) * smoothstep(0.15, 0.5, lat)
	return clampf(maxf(polar, cold), 0.0, 1.0)


## Height (metres) where snow starts, for a given coldness. Matches the terrain shader.
func snow_line_m(cold: float) -> float:
	return preset.snow_line * radius * (1.0 - smoothstep(0.3, 0.7, cold) * 0.85)


## 0..1: frozen sea (ice you can walk on) at a spot.
func ice(d: Vector3) -> float:
	if continent(d) >= _sea:
		return 0.0
	return smoothstep(0.62, 0.7, coldness(d))


## Rivers: Vector2(distance from the river's middle in metres, strength 0..1).
## Strength is 0 where there are no rivers (mountains, cold places, dry areas).
func river_at(d: Vector3, mask: float) -> Vector2:
	if preset.rivers <= 0.0:
		return Vector2(INF, 0.0)
	var zone := smoothstep(0.5 - preset.rivers * 0.5, 0.62 - preset.rivers * 0.5, _river_zone.get_noise_3dv(d) * 0.5 + 0.5)
	var strength := zone * (1.0 - smoothstep(0.12, 0.4, mask))
	if strength <= 0.0:
		return Vector2(INF, 0.0)
	var n := _river.get_noise_3dv(d)
	if absf(n) > 0.25:
		return Vector2(INF, 0.0)
	# distance to the zero line = value / steepness of the noise
	var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := d.cross(t1)
	var e := 4.0 / radius
	var g1 := (_river.get_noise_3dv((d + t1 * e).normalized()) - n) / 4.0
	var g2 := (_river.get_noise_3dv((d + t2 * e).normalized()) - n) / 4.0
	var grad := sqrt(g1 * g1 + g2 * g2)
	return Vector2(absf(n) / maxf(grad, 1e-6), strength)


## Which way a river flows at a spot, and how much river water is there
## (0..1). Vector4(direction x, y, z, amount).
func river_flow(d: Vector3) -> Vector4:
	var land := raw_height(d, false)
	if land.x < 0.0 or coldness(d) >= 0.55:
		return Vector4(0, 0, 0, 0)   # sea, lakes and frozen lands have no river surface
	var r := river_at(d, land.y)
	if r.y <= 0.0 or r.x > preset.river_width_m * 1.6:
		return Vector4(0, 0, 0, 0)
	var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := d.cross(t1)
	var e := 4.0 / radius
	var n := _river.get_noise_3dv(d)
	var g := t1 * (_river.get_noise_3dv((d + t1 * e).normalized()) - n) + t2 * (_river.get_noise_3dv((d + t2 * e).normalized()) - n)
	var dir := d.cross(g).normalized()   # along the river
	var amount := r.y * (1.0 - smoothstep(preset.river_width_m * 0.6, preset.river_width_m * 1.5, r.x))
	amount *= smoothstep(0.0, 2.0, land.x)   # blends into the lake or sea it runs into
	return Vector4(dir.x, dir.y, dir.z, amount)


## 0..1: how autumnal the trees are at a spot (gold larches, red bushes).
func autumn(d: Vector3) -> float:
	return smoothstep(0.15, 0.35, _autumn.get_noise_3dv(d))


## 0..1: forest density at a spot.
func forest(d: Vector3) -> float:
	return smoothstep(-0.05, 0.25, _patch.get_noise_3dv(d))


## Some mountain slopes get small shelves (grassy ledges) so the faces aren't
## all smooth; others stay smooth. `mh` is the mountain's own height.
func _shelves(d: Vector3, mh: float) -> float:
	var zone := smoothstep(0.32, 0.5, _style.get_noise_3dv(d * 2.7 + Vector3(5.0, 1.0, 3.0)) * 0.5 + 0.5)
	if zone <= 0.0:
		return mh
	# step height wanders a little so the shelves aren't evenly spaced
	var step_m := 6.0 + _crags.get_noise_3dv(d * 0.3) * 2.0
	var ts := mh / step_m
	var shelved := (floorf(ts) + smoothstep(0.2, 1.0, ts - floorf(ts))) * step_m
	return lerpf(mh, shelved, 0.5 * zone * smoothstep(8.0, 25.0, mh))


## Height in metres above sea level, without landing-site flattening.
## Returns Vector3(height, mountain mask, trail amount).
## `with_rivers` = false gives the land as it would be without river valleys.
func raw_height(d: Vector3, with_rivers := true) -> Vector3:
	var w := _warp_at(d)
	var c := _continent.get_noise_3dv(d + w * 0.25)
	var bumps := _bumps.get_noise_3dv(d) * preset.bump_height_m
	if c < _sea:
		var depth := (_sea - c) / maxf(1e-6, _sea - _c_min)
		var sea_floor := -preset.ocean_depth * radius * sqrt(depth) + bumps * 0.5
		# Near the poles the sea is frozen: a flat sheet of ice you can walk on,
		# ending in a low ice cliff.
		var ice_t := smoothstep(0.62, 0.7, coldness(d))
		if ice_t > 0.0:
			return Vector3(lerpf(sea_floor, 1.4 + bumps * 0.25, ice_t), 0.0, 0.0)
		return Vector3(sea_floor, 0.0, 0.0)

	# Heights are continuous at the coast, so shorelines stay smooth.
	var land_t := (c - _sea) / maxf(1e-6, _c_max - _sea)
	var h := preset.land_height * radius * (1.0 - pow(1.0 - minf(land_t, 1.0), 2.0))
	h += preset.hill_height * radius * (_hills.get_noise_3dv(d + w * 0.15) * 0.5 + 0.5) * smoothstep(0.0, 0.2, land_t)

	# Some regions have stepped, terraced hills (like old farmland or mesas).
	var terr := smoothstep(0.25, 0.45, _terrace.get_noise_3dv(d)) * smoothstep(0.05, 0.2, land_t)
	if terr > 0.0:
		var t_step := 5.0
		var tt := h / t_step
		var stepped := (floorf(tt) + smoothstep(0.3, 1.0, tt - floorf(tt))) * t_step
		h = lerpf(h, stepped, terr * 0.6)

	# Every mountain region has its own style: sharp and ledged, or round.
	var style := _style.get_noise_3dv(d) * 0.5 + 0.5
	var mask := mountain_mask(d, land_t)
	if mask > 0.0:
		var sharp := smoothstep(0.35, 0.7, style)
		# Bent (warped) mountain bodies, with ridge lines along their tops.
		var body := _mountains.get_noise_3dv(d + w * 0.3) * 0.5 + 0.5
		var ridge := 1.0 - absf(_ridges.get_noise_3dv(d + w * 0.2))
		var m := clampf(body * 0.9 + ridge * ridge * (0.15 + 0.45 * sharp) - 0.3, 0.0, 1.0) / 0.75
		var mh := preset.mountain_height * radius * pow(minf(m, 1.0), lerpf(1.6, 1.15, sharp)) * mask
		mh += _crags.get_noise_3dv(d) * lerpf(1.0, 2.2, sharp) * mask * smoothstep(5.0, 30.0, mh)
		# Erosion gullies running down the sides.
		var g := 1.0 - absf(_gully.get_noise_3dv(d + w * 0.05))
		mh -= pow(g, 7.0) * 3.0 * smoothstep(15.0, 60.0, mh)
		# Stylized rock ledges: flat steps with steep faces between them.
		var step := preset.ledge_height_m * lerpf(0.7, 1.3, style)
		var t := mh / step
		var ledged := (floorf(t) + smoothstep(0.1, 1.0, t - floorf(t))) * step
		var ledge_amount := clampf(preset.ledge_strength * lerpf(0.2, 1.5, sharp), 0.0, 0.65)
		var mtn := lerpf(mh, ledged, ledge_amount * smoothstep(4.0, 20.0, mh))
		# some slopes get extra small shelves (4 m steps), others stay smooth
		h += _shelves(d, mtn)

	# Standalone hills and peaks outside the big ranges: good for climbing.
	if preset.peak_amount > 0.0 and mask < 0.8:
		var p := _peaks.get_noise_3dv(d + w * 0.2) * 0.5 + 0.5
		var start := 1.0 - preset.peak_amount * 0.55
		var peak := smoothstep(start, start + 0.4, p)
		if peak > 0.0:
			var ph := preset.peak_height * radius * pow(peak, lerpf(1.9, 1.3, style)) * smoothstep(0.08, 0.3, land_t) * (1.0 - mask)
			ph += _crags.get_noise_3dv(d) * 1.2 * smoothstep(8.0, 30.0, ph)
			h += _shelves(d, ph)
			mask = maxf(mask, peak * 0.5 * smoothstep(0.08, 0.3, land_t))

	# Rocky outcrops poking out of the grass.
	var o := _outcrop.get_noise_3dv(d) * 0.5 + 0.5
	var crop := smoothstep(0.64, 0.86, o) * smoothstep(0.06, 0.15, land_t) * (1.0 - mask)
	if crop > 0.0:
		h += crop * (2.0 + _crags.get_noise_3dv(d * 1.7) * 1.2) * (1.0 + style * 0.5)

	if preset.lakes > 0.0 and mask < 0.4:
		var start := 0.42 - 0.22 * preset.lakes
		var lake_t := smoothstep(start, start + 0.08, _lakes.get_noise_3dv(d))
		lake_t *= smoothstep(0.03, 0.12, land_t) * (1.0 - mask * 2.5)
		h = lerpf(h, -3.0, lake_t)

	h += bumps * smoothstep(0.0, 0.05, land_t)

	# River valleys: a wide, gentle valley down to just above sea level, with
	# the river channel (below sea level, so it fills with water) in the middle.
	if with_rivers and coldness(d) < 0.55:
		var riv := river_at(d, mask)
		if riv.y > 0.0:
			var valley := 1.0 - smoothstep(preset.river_width_m, preset.valley_width_m, riv.x)
			var floor_h := 2.6 + riv.x * 0.012
			h = lerpf(h, minf(h, floor_h), valley * riv.y)
			var channel := 1.0 - smoothstep(preset.river_width_m * 0.35, preset.river_width_m, riv.x)
			h = lerpf(h, -2.4, channel * riv.y)

	# Dirt trails on dry land, fading out in the high mountains. The ground
	# along a trail is worn down a little.
	var trail := 0.0
	if h > 0.6:
		trail = trail_network(d) * (1.0 - smoothstep(0.35, 0.7, mask)) * (1.0 - crop) * smoothstep(0.6, 1.5, h)
		h -= trail * 0.3
	return Vector3(h, mask, trail)


## Height in metres above sea level at direction `d` (a unit vector).
func height(d: Vector3) -> float:
	return sample(d).x


## Height (with landing sites flattened), mountain mask and trail amount.
func sample(d: Vector3) -> Vector3:
	var r := raw_height(d)
	for site in _sites:
		var c: float = d.dot(site[0])
		if c > site[2]:
			r.x = lerpf(r.x, site[1], smoothstep(site[2], site[3], c))
	return r


## Finds flat, grassy, dry spots far apart from each other.
## Returns an array of [direction, height].
func find_landing_sites(count: int, site_radius_m: float, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var candidates := []
	for _i in 5000:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var hm := raw_height(d)
		if hm.x < 3.0 or hm.x > preset.snow_line * radius * 0.4 or hm.y > 0.15:
			continue
		var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := d.cross(t1)
		var worst := 0.0
		for k in 8:
			var ang := k * TAU / 8.0
			var dd := (d + (t1 * cos(ang) + t2 * sin(ang)) * (site_radius_m * 1.2 / radius)).normalized()
			var hh := raw_height(dd).x
			worst = maxf(worst, absf(hh - hm.x))
			if hh < 1.5:
				worst = INF
		if worst < 7.0:
			candidates.append([worst, d, hm.x])
	candidates.sort_custom(func(x, y): return x[0] < y[0])

	var sites := []
	var min_gap := cos(minf(1.0, 2.2 / sqrt(maxf(1.0, count))))
	for cand in candidates:
		var ok := true
		for s in sites:
			if cand[1].dot(s[0]) > min_gap:
				ok = false
				break
		if ok:
			sites.append([cand[1], cand[2]])
		if sites.size() >= count:
			break

	var outer := cos(site_radius_m * 1.6 / radius)
	var inner := cos(site_radius_m / radius)
	var flat := []
	for s in sites:
		flat.append([s[0], s[1], outer, inner])
	set_landing_sites(flat)
	return sites
