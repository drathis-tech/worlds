class_name PlanetHud
extends CanvasLayer
## On-screen info for the test character: what it's doing, altitude, speed
## and the controls. Works on any planet (nature or city).

@export var walker: PlanetWalker

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)


func _process(_delta: float) -> void:
	if walker == null:
		return
	var planet := get_tree().get_first_node_in_group("planets")
	var r: float = planet.get("radius") if planet else 1000.0
	var mode := "WALKING"
	if walker.flying:
		mode = "FLYING"
	elif walker.swimming:
		mode = "SWIMMING"
	elif walker.climbing:
		mode = "CLIMBING"
	var alt := walker.altitude()
	var where := "in space" if alt > r * 0.6 else ("in the sky" if alt > 60.0 else "")
	_label.text = "%s   altitude %d m %s   speed %d m/s\n" % [mode, roundi(alt), where, roundi(walker.velocity.length())]
	_label.text += "WASD move · mouse look · Shift run · Space jump/up · C down · F fly · Esc mouse"
