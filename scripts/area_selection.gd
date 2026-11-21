extends RefCounted

const TOOLS := ["select_rect", "select_ellipse", "select_lasso", "select_square", "select_circle"]

static func outline(tool: String, start: Vector2, end: Vector2, freehand: PackedVector2Array) -> PackedVector2Array:
	if tool == "select_lasso": return freehand
	var delta := end - start
	if tool in ["select_square", "select_circle"]:
		var side := minf(absf(delta.x), absf(delta.y))
		delta = Vector2(-side if delta.x < 0 else side, -side if delta.y < 0 else side)
	var box := Rect2(start, delta).abs()
	if tool in ["select_rect", "select_square"]: return corners(box)
	var points := PackedVector2Array()
	for index in 48:
		points.append(box.get_center() + Vector2.from_angle(TAU * index / 48.0) * box.size * 0.5)
	return points

static func corners(box: Rect2) -> PackedVector2Array:
	return PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])

static func encloses(tool: String, region: PackedVector2Array, bounds: Rect2, object_box: Rect2) -> bool:
	if not bounds.encloses(object_box): return false
	if tool in ["select_rect", "select_square"]: return true
	if tool in ["select_ellipse", "select_circle"]:
		var radii := bounds.size * 0.5
		for point in corners(object_box):
			if ((point - bounds.get_center()) / radii).length_squared() > 1.0: return false
		return true
	return Geometry2D.clip_polygons(corners(object_box), region).is_empty()
