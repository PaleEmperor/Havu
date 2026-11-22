extends RefCounted
## Preserve appearance by joining opaque, unstyled vector fills of one color.
const Art = preload("res://scripts/artwork.gd")
const Compound = preload("res://scripts/compound_polygon.gd")
const TIP_GAP := 1.5
const MAX_VERTICES := 8192

static func find_union(objects: Array, incoming: Dictionary, ink_gap := TIP_GAP) -> Dictionary:
	var batch: String = incoming.merge_batch
	var first := 0
	while first < objects.size() and objects[first].get("merge_batch", "") != batch:
		first += 1
	if first == objects.size(): return {}
	var outline := mergeable_outline(incoming)
	if outline.is_empty(): return {}
	var stroke_outline := outline
	var gap := ink_gap if incoming.kind == "stroke" else 0.0
	var bounds := Art.polygon_bounds(outline)
	var compound := false
	var color := Color(incoming.color)
	var above: Array[Rect2] = []
	var candidates: Array[Dictionary] = []
	for index in range(objects.size() - 1, first - 1, -1):
		var object: Dictionary = objects[index]
		if object.opacity <= 0.0: continue
		var other := Art.coverage_bounds(object)
		var compatible: bool = object.get("merge_batch", "") == batch and can_union(object) and Color(object.color) == color
		if compatible and not above.any(func(box): return box.intersects(other)):
			candidates.append({"index": index, "bounds": other})
		else:
			above.append(other)

	var joined: Array[int] = []
	while not candidates.is_empty():
		var changed := false
		for index in range(candidates.size() - 1, -1, -1):
			var candidate := candidates[index]
			if not bounds.grow(gap).intersects(candidate.bounds, true): continue
			var edge := mergeable_outline(objects[candidate.index])
			if edge.is_empty():
				candidates.remove_at(index)
				continue
			var patched := outline
			if gap > 0.0:
				patched = join_near_tips(incoming, stroke_outline, outline, edge, gap,
					objects[candidate.index].get("compound", false))
			var contours := Geometry2D.merge_polygons(patched, edge)
			var union := Compound.connected_outline(contours)
			var valid := valid_outline(union)
			if not valid and patched != outline:
				contours = Geometry2D.merge_polygons(outline, edge)
				union = Compound.connected_outline(contours)
				valid = valid_outline(union)
			if not valid: continue
			outline = union
			compound = contours.size() > 1
			bounds = Art.polygon_bounds(outline)
			joined.append(candidate.index)
			candidates.remove_at(index)
			changed = true
		if not changed: break

	if joined.is_empty(): return {}
	joined.sort()
	joined.reverse()
	var result := {"kind": "polygon", "color": incoming.color, "opacity": 1.0,
		"pos": [0.0, 0.0], "scale": 1.0, "vertices": Art.pack_contours([outline])[0], "merge_batch": incoming.merge_batch}
	if compound: result.compound = true
	if incoming.has("id"): result.id = incoming.id
	return {"object": result, "indices": joined}

static func union_objects(objects: Array[Dictionary]) -> Dictionary:
	var outline := mergeable_outline(objects[0])
	if outline.is_empty(): return {}
	var contours: Array[PackedVector2Array] = []
	for index in range(1, objects.size()):
		var edge := mergeable_outline(objects[index])
		if edge.is_empty(): return {}
		contours.clear()
		for contour in Geometry2D.merge_polygons(outline, edge):
			contours.append_array(Compound.boundary_loops(contour))
		outline = Compound.joined_outline(contours)
		if outline.size() < 3 or outline.size() > MAX_VERTICES: return {}
	var shells := 0
	for contour in contours:
		if not Geometry2D.is_polygon_clockwise(contour): shells += 1
	var disconnected := shells > 1
	if disconnected:
		var pieces := Compound.components(outline)
		if pieces.size() != shells: return {}
		var expected := 0.0
		var actual := 0.0
		for contour in contours: expected += Compound.signed_area(contour)
		for piece in pieces:
			if not valid_outline(piece): return {}
			actual += Compound.signed_area(piece)
		if absf(absf(expected) - absf(actual)) > maxf(0.001, absf(expected) * 0.00001): return {}
	elif not Compound.matches_area(outline, contours): return {}
	var top := objects.back() as Dictionary
	var result := {"id": top.id, "kind": "polygon", "color": top.color, "opacity": 1.0,
		"pos": [0.0, 0.0], "scale": 1.0, "vertices": Art.pack_contours([outline])[0]}
	if contours.size() > 1: result.compound = true
	if disconnected: result.compound_disjoint = true
	return result

static func join_near_tips(stroke: Dictionary, stroke_outline: PackedVector2Array,
		outline: PackedVector2Array, other: PackedVector2Array, gap: float, compound: bool) -> PackedVector2Array:
	var points: Array = stroke.points
	var transform := Transform2D(0.0, Vector2.ONE * float(stroke.get("scale", 1.0)), 0.0, Art.v(stroke.get("pos", [0.0, 0.0])))
	var taper := Art.stroke_taper(stroke)
	var edges := Compound.bridge_edges(other) if compound else {}
	var patched := outline
	for index in ([0, points.size() - 1] if points.size() > 1 else [0]):
		var point: Array = points[index]
		var tip := transform * Art.v(point)
		var radius := Art.stroke_radius(float(stroke.size) * 0.5 * transform.x.length(), point[2],
			stroke.get("pressure_curve", 1.0), stroke.get("minimum_width", 0.12)) * Art.taper_factor(taper, index, points.size())
		if (Compound.contains(other, tip) if compound else Geometry2D.is_point_in_polygon(tip, other)): continue
		var nearest := closest_edge(other, tip, edges)
		if tip.distance_to(nearest) > radius + gap: continue
		var cap := closest_edge(stroke_outline, nearest)
		var separation := cap.distance_to(nearest)
		if separation > gap or (separation > 0.01 and Geometry2D.is_point_in_polygon(nearest, stroke_outline)): continue
		var width := clampf(radius * 0.3, 0.12, 0.7)
		var bridge := Geometry2D.offset_polyline(PackedVector2Array([tip, nearest]), width,
			Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		if bridge.size() != 1: continue
		var connected := Compound.connected_outline(Geometry2D.merge_polygons(patched, bridge[0]))
		if not connected.is_empty(): patched = connected
	return patched

static func closest_edge(outline: PackedVector2Array, point: Vector2, skip := {}) -> Vector2:
	var closest := INF
	var nearest := outline[0]
	for index in outline.size():
		if skip.has(index): continue
		var next := (index + 1) % outline.size()
		var candidate := Geometry2D.get_closest_point_to_segment(point, outline[index], outline[next])
		var distance := point.distance_squared_to(candidate)
		if distance < closest:
			closest = distance
			nearest = candidate
	return nearest

static func valid_outline(outline: PackedVector2Array) -> bool:
	return outline.size() >= 3 and outline.size() <= MAX_VERTICES and not Geometry2D.triangulate_polygon(outline).is_empty()

static func can_union(object: Dictionary) -> bool:
	if object.opacity != 1.0 or Color(object.color).a != 1.0: return false
	if object.has("artwork_group") or object.has("node_anchors") or object.has("clip") or object.has("paint_mask"): return false
	if not object.get("opacity_groups", []).is_empty(): return false
	if object.kind == "stroke": return Art.uses_ink_outline(object) and object.points.size() <= (MAX_VERTICES - 24) / 2
	return object.kind in ["rect", "ellipse", "polygon"] and Art.has_fill(object) and Art.outline_width(object) <= 0.0 \
		and object.get("vertices", []).size() <= MAX_VERTICES

static func mergeable_outline(object: Dictionary) -> PackedVector2Array:
	if not can_union(object): return PackedVector2Array()
	var points := Art.stroke_polygon(object) if object.kind == "stroke" else Art.polygon(object)
	if points.size() < 3: return PackedVector2Array()
	if not object.get("compound_disjoint", false) and Geometry2D.triangulate_polygon(points).is_empty(): return PackedVector2Array()
	var scale := Vector2.ONE * float(object.get("scale", 1.0))
	return Transform2D(0.0, scale, 0.0, Art.v(object.get("pos", [0.0, 0.0]))) * points
