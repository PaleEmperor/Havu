extends Control
## Stroke previews use the same vector geometry and renderer as the canvas.
const Art = preload("res://scripts/artwork.gd")
const BrushLibrary = preload("res://scripts/brush_library.gd")
const COOL := Color("#8ecac1")
const WARM := Color("#e1aaa1")
var preset: Dictionary = {}
var ink = Color("#dbe0dd")
var detailed := false
var cached: Dictionary = {}
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(rebuild)
	visibility_changed.connect(rebuild)
	rebuild()
func rebuild() -> void:
	if preset.is_empty() or not is_visible_in_tree(): return
	var points = []
	var color = "#" + ink.to_html(false)
	var sample_count := clampi(roundi(48 * 0.16 / float(preset.get("spacing", 0.16))), 14, 96)
	var mixing: bool = detailed and preset.brush in BrushLibrary.WET_ENGINES
	var carried := WARM
	var previous := Vector2.ZERO
	# Compress the size range so fine and broad presets stay distinguishable.
	var preview_width := maxf(0.8, pow(float(preset.size) / 150.0, 0.65) * size.y * 0.72)
	var inset := maxf(8, preview_width * 0.5 + 2) if detailed else 8.0
	var wave := minf(size.y * 0.20, (size.y - preview_width) * 0.38) if detailed else size.y * 0.20
	for i in range(sample_count):
		var t := float(i) / (sample_count - 1)
		var x := inset + t * maxf(1, size.x - inset * 2)
		var y := size.y * 0.5 + sin(t * TAU * 1.25) * wave
		var pressure := BrushLibrary.map_pressure(0.12 + sin(t * PI) * 0.84, preset)
		var point := Vector2(x, y)
		if detailed:
			point.y += sin(t * TAU * 21.0) * minf(3, size.y * 0.06)
			if i > 0:
				point = BrushLibrary.stabilize(point, previous, point.distance_to(previous), preset.smoothing, 5.0)
		if mixing:
			var substrate := WARM if point.x < size.x * 0.5 else COOL
			carried = BrushLibrary.mix_pigment(ink, substrate, carried, pressure, preset.brush, preset.blend, preset)
			color = "#" + carried.to_html(false)
		points.append([point.x, point.y, pressure, color])
		previous = point
	cached = {"id": "preview", "kind": "stroke", "brush": preset.brush, "points": points,
		"size": preview_width, "opacity": preset.opacity, "color": color, "pos": [0.0, 0.0], "scale": 1.0}
	cached.merge(BrushLibrary.profile_from(preset))
	if preset.brush in ["paint", "mix"] and is_equal_approx(float(preset.get("tip_ratio", 1.0)), 1.0):
		cached.continuous_edges = true
	if Art.is_grain(cached): Art.use_screen_edges(self, cached)
	elif material == Art.grain_material: material = null
	queue_redraw()
func _draw() -> void:
	if cached.is_empty(): return
	if detailed:
		if preset.brush in BrushLibrary.WET_ENGINES:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * 0.5, size.y)), WARM)
			draw_rect(Rect2(Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, size.y)), COOL)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color("#aeb0ab"))
	Art.draw_object(self, cached)
