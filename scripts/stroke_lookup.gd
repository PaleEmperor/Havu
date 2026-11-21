extends RefCounted
## Cache local geometry in short blocks for repeated pigment sampling.
const Art = preload("res://scripts/artwork.gd")
const BLOCK_SIZE := 12
const MIN_SAMPLES := 24

var positions := PackedVector2Array()
var radii := PackedFloat64Array()
var sample_bounds: Array[Rect2] = []
var coverage_bounds: Array[Rect2] = []
var tapered := false

func _init(stroke: Dictionary) -> void:
	var points: Array = stroke.points
	var taper := Art.stroke_taper(stroke)
	tapered = not taper.is_empty()
	var max_radius := float(stroke.size) * 0.5
	var curve: float = stroke.get("pressure_curve", 1.0)
	var minimum: float = stroke.get("minimum_width", 0.12)
	positions.resize(points.size())
	radii.resize(points.size())
	for index in points.size():
		positions[index] = Art.v(points[index])
		var radius := Art.stroke_radius(max_radius, points[index][2], curve, minimum)
		radii[index] = radius * Art.taper_factor(taper, index, points.size()) if tapered else radius

	for first in range(0, points.size(), BLOCK_SIZE):
		var end := mini(first + BLOCK_SIZE, points.size())
		var bounds := Rect2(positions[first], Vector2.ZERO)
		var radius := radii[first]
		for index in range(first + 1, end):
			bounds = bounds.expand(positions[index])
			radius = maxf(radius, radii[index])
		sample_bounds.append(bounds)
		if first > 0:
			bounds = bounds.expand(positions[first - 1])
			if tapered: radius = maxf(radius, radii[first - 1])
		coverage_bounds.append(bounds.grow(radius + 0.001))

func color_at(stroke: Dictionary, point: Vector2) -> Variant:
	var local := Art.local_point(stroke, point)
	if not contains(local) or not Art.point_inside_clip(stroke, local): return null
	var distance := INF
	var closest := 0
	for block in sample_bounds.size():
		var bounds := sample_bounds[block]
		if local.distance_squared_to(local.clamp(bounds.position, bounds.end)) >= distance: continue
		var first := block * BLOCK_SIZE
		for index in range(first, mini(first + BLOCK_SIZE, positions.size())):
			var next := local.distance_squared_to(positions[index])
			if next < distance:
				distance = next
				closest = index
	return Art.stroke_sample_color(stroke, stroke.points[closest], distance)

func contains(point: Vector2) -> bool:
	for block in coverage_bounds.size():
		if not coverage_bounds[block].has_point(point): continue
		var first := block * BLOCK_SIZE
		for index in range(first, mini(first + BLOCK_SIZE, positions.size())):
			var end := positions[index]
			var near := end
			var radius := radii[index]
			if index > 0:
				var start := positions[index - 1]
				near = Geometry2D.get_closest_point_to_segment(point, start, end)
				if tapered:
					var length := start.distance_to(end)
					if length > 0.0: radius = lerpf(radii[index - 1], radius, start.distance_to(near) / length)
			if point.distance_squared_to(near) <= radius * radius: return true
	return false
