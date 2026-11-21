extends RefCounted
## Encode one connected polygon with holes for Godot's single-loop triangulator.
## Each hole is joined by two coincident, opposite edges with zero area.

static func connected_outline(contours: Array[PackedVector2Array]) -> PackedVector2Array:
	if contours.size() == 1: return contours[0]
	var outline := PackedVector2Array()
	var holes: Array[Dictionary] = []
	for contour in contours:
		if Geometry2D.is_polygon_clockwise(contour):
			var anchor := 0
			for index in range(1, contour.size()):
				if contour[index].x > contour[anchor].x: anchor = index
			holes.append({"points": contour, "anchor": anchor, "x": contour[anchor].x})
		elif outline.is_empty():
			outline = contour
		else:
			return PackedVector2Array()
	holes.sort_custom(func(a, b): return a.x > b.x)
	for hole in holes:
		outline = attach_hole(outline, hole.points, hole.anchor)
		if outline.is_empty(): break
	return outline

static func attach_hole(outline: PackedVector2Array, hole: PackedVector2Array, anchor: int) -> PackedVector2Array:
	var start := hole[anchor]
	var edge := -1
	var closest := INF
	# A horizontal ray from the rightmost hole vertex cannot cross that
	# hole again. Process rightward holes first so the nearest edge is solid.
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		if (a.y > start.y) == (b.y > start.y): continue
		var x := lerpf(a.x, b.x, (start.y - a.y) / (b.y - a.y))
		if x <= start.x or x >= closest: continue
		closest = x
		edge = index
	if edge < 0: return PackedVector2Array()
	var join := Vector2(closest, start.y)
	var result := outline.slice(0, edge + 1)
	if result[-1] != join: result.append(join)
	for index in hole.size(): result.append(hole[(anchor + index) % hole.size()])
	result.append(start)
	if outline[(edge + 1) % outline.size()] != join: result.append(join)
	result.append_array(outline.slice(edge + 1))
	return result

static func bridge_edges(points: PackedVector2Array) -> Dictionary:
	var directed := {}
	var bridges := {}
	for index in points.size():
		var next := (index + 1) % points.size()
		var reversed := [points[next], points[index]]
		if directed.has(reversed):
			bridges[index] = true
			bridges[directed[reversed]] = true
		directed[[points[index], points[next]]] = index
	return bridges

# Godot's clipping methods return holes alongside solid contours. Recombine
# each hole with its containing shell before treating the result as paint.
static func filled_outlines(contours: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if contours.size() <= 1 or not contours.any(Geometry2D.is_polygon_clockwise): return contours
	var shells: Array = []
	for contour in contours:
		if not Geometry2D.is_polygon_clockwise(contour):
			var group: Array[PackedVector2Array] = [contour]
			shells.append(group)
	for hole in contours:
		if not Geometry2D.is_polygon_clockwise(hole): continue
		# The nearest containing shell handles nested islands as well.
		var owner := -1
		var area := INF
		for index in shells.size():
			var shell: PackedVector2Array = shells[index][0]
			if not Geometry2D.is_point_in_polygon(hole[0], shell): continue
			var size := 0.0
			for i in shell.size(): size += shell[i].cross(shell[(i + 1) % shell.size()])
			if absf(size) < area:
				owner = index
				area = absf(size)
		if owner >= 0: shells[owner].append(hole)
	var pieces: Array[PackedVector2Array] = []
	for shell in shells:
		var piece := connected_outline(shell)
		if not piece.is_empty(): pieces.append(piece)
	return pieces
