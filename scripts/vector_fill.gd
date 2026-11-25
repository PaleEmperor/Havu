extends RefCounted
## Find a bounded region in the union of painted vector geometry.
const Art = preload("res://scripts/artwork.gd")
const MAX_SAMPLES := 12000
const MAX_FOOTPRINTS := 2400

static func find_region(objects: Array, seed: Vector2, page := Rect2(), cached_bounds := Callable()) -> Dictionary:
	# Most compartments use nearby geometry. Keep a large layer from
	# exhausting the geometry budget before we reach the tapped region.
	if objects.size() >= 100:
		for radius in [192.0, 768.0]:
			var search := Rect2(seed - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
			var local := find_bounded_region(objects, seed, Rect2(), search, cached_bounds)
			if not local.is_empty() and search.encloses(Art.polygon_bounds(local.vertices)):
				return local
	return find_bounded_region(objects, seed, page, Rect2(), cached_bounds)

static func find_bounded_region(objects: Array, seed: Vector2, page: Rect2, search: Rect2,
		cached_bounds: Callable) -> Dictionary:
	var footprints: Array[Dictionary] = []
	var enclosed: Array[Dictionary] = []
	var samples := 0
	for index in range(objects.size() - 1, -1, -1):
		var object: Dictionary = objects[index]
		if object.opacity <= 0.0: continue
		if object.kind not in Art.SHAPES and object.kind != "stroke": continue
		if search.has_area():
			var bounds: Rect2 = cached_bounds.call(object) if cached_bounds.is_valid() else Art.coverage_bounds(object)
			if object.kind == "stroke" and not Art.uses_ink_outline(object):
				bounds = bounds.grow(float(object.size) * float(object.scale))
			if not bounds.intersects(search, true): continue
		var polygons: Array = []
		if object.kind == "stroke":
			samples += object.points.size()
			if samples > MAX_SAMPLES: return {}
			polygons = brush_polygons(object)
		elif object.kind == "path" and Art.outline_width(object) > 0.0 and Color(object.outline_color).a > 0.0:
			samples += object.vertices.size()
			if samples > MAX_SAMPLES: return {}
			polygons = line_polygons(object)
		elif object.kind in ["rect", "ellipse", "polygon"]:
			var points := Art.polygon(object)
			samples += points.size()
			if samples > MAX_SAMPLES: return {}
			polygons = shape_polygons(object, points)
		var transform := Art.object_transform(object)
		for polygon: PackedVector2Array in polygons:
			if polygon.size() < 3: continue
			var outline := transform * polygon
			if Geometry2D.is_polygon_clockwise(outline): outline.reverse()
			var bounds := Art.polygon_bounds(outline)
			footprints.append({"outline": outline, "bounds": bounds, "index": index})
			if footprints.size() > MAX_FOOTPRINTS: return {}
			if not bounds.has_point(seed): continue
			if Art.Compound.bridge_edges(outline).is_empty():
				if Geometry2D.is_point_in_polygon(seed, outline): return {}
			else:
				if Art.Compound.contains(outline, seed): return {}
				for contour in Art.Compound.boundary_loops(outline):
					if Geometry2D.is_polygon_clockwise(contour) and Geometry2D.is_point_in_polygon(seed, contour):
						enclosed.append({"outline": contour, "index": index})

	for candidate in enclosed:
		var changes := {}
		var region := refine_region(candidate.outline, footprints, seed, changes)
		if not region.is_empty():
			var result := region_result(region, candidate.index)
			changes.erase(candidate.index)
			if changes.is_empty(): result.single_boundary = candidate.index
			return result

	var shells: Array[Dictionary] = []
	for footprint in footprints:
		var merged := footprint.outline as PackedVector2Array
		var bounds := footprint.bounds as Rect2
		var insertion := int(footprint.index)
		var index := 0
		while index < shells.size():
			var other := shells[index]
			if not bounds.intersects(other.bounds, true):
				index += 1
				continue
			var contours := Geometry2D.merge_polygons(merged, other.outline)
			var outer := PackedVector2Array()
			for contour in contours:
				if not Geometry2D.is_polygon_clockwise(contour):
					if not outer.is_empty():
						outer.clear()
						break
					outer = contour
			if outer.is_empty():
				index += 1
				continue
			insertion = mini(insertion, other.index)
			for contour in contours:
				if not Geometry2D.is_polygon_clockwise(contour) or not Geometry2D.is_point_in_polygon(seed, contour): continue
				var region := refine_region(contour, footprints, seed)
				if not region.is_empty(): return region_result(region, insertion)
			# A hole elsewhere cannot grow to include the tap as ink is added.
			merged = outer
			bounds = Art.polygon_bounds(merged)
			shells.remove_at(index)
			index = 0
		shells.append({"outline": merged, "bounds": bounds, "index": insertion})
	if not page.has_point(seed): return {}
	return find_page_region(page, footprints, seed)

# Subtract the ink from the page and follow only the connected piece at the
# tap. An internal loop alone must not make the entire outside fillable.
static func find_page_region(page: Rect2, footprints: Array[Dictionary], seed: Vector2) -> Dictionary:
	if not footprints.any(func(footprint): return footprint.bounds.intersects(page, true) and touches_page(footprint.bounds, page)):
		return {}
	var region := Art.AreaSelection.corners(page)
	var bounds := page
	var divided_page := false
	for footprint in footprints:
		if not bounds.intersects(footprint.bounds): continue
		var contours := Geometry2D.clip_polygons(region, footprint.outline)
		var next := seed_component(contours, seed)
		if next.is_empty() or next.size() > 8192: return {}
		if not divided_page:
			var edge_pieces := 0
			for contour in contours:
				if Geometry2D.is_polygon_clockwise(contour) or not touches_page(Art.polygon_bounds(contour), page): continue
				edge_pieces += 1
			divided_page = edge_pieces > 1
		region = next
		bounds = Art.polygon_bounds(region)
	if not divided_page or Geometry2D.triangulate_polygon(region).is_empty(): return {}
	var compound := not Art.Compound.bridge_edges(region).is_empty()
	if not compound:
		# Blend under the brush antialiasing while keeping the exact page edge.
		var expanded := Geometry2D.offset_polygon(region, 0.3)
		if expanded.size() == 1:
			var clipped := seed_component(Geometry2D.intersect_polygons(expanded[0], Art.AreaSelection.corners(page)), seed)
			if not clipped.is_empty() and clipped.size() <= 8192 and not Geometry2D.triangulate_polygon(clipped).is_empty():
				region = clipped
	return {"vertices": region, "index": 0, "compound": compound}

static func seed_component(contours: Array[PackedVector2Array], seed: Vector2) -> PackedVector2Array:
	for piece in Art.Compound.filled_outlines(contours):
		if Art.Compound.contains(piece, seed): return piece
	return PackedVector2Array()

static func touches_page(bounds: Rect2, page: Rect2) -> bool:
	const EDGE_EPSILON := 0.001
	return bounds.position.x <= page.position.x + EDGE_EPSILON or bounds.position.y <= page.position.y + EDGE_EPSILON \
		or bounds.end.x >= page.end.x - EDGE_EPSILON or bounds.end.y >= page.end.y - EDGE_EPSILON

static func brush_polygons(object: Dictionary) -> Array:
	var footprints := Art.paint_footprints(object)
	var polygons := []
	for footprint in footprints:
		if footprint.color.a <= 0.0: continue
		var outline: PackedVector2Array = footprint.polygon
		if Art.uses_ink_outline(object):
			# A self-crossing brush ribbon can enclose a hole by itself. Break
			# it into overlapping segments so that the union retains the hole.
			var contours := Geometry2D.merge_polygons(outline, outline)
			if contours.size() > 1:
				var segments := []
				var mask := Art.prepare_paint_mask(object)
				for segment in Art.segments(object):
					if segment.color.a > 0.0:
						segments.append_array(Art.clipped_polygon(object, segment.polygon, mask))
				return segments
		polygons.append(outline)
	return polygons

static func line_polygons(object: Dictionary) -> Array:
	var line := Art.polygon(object)
	var radius := Art.outline_width(object) * 0.5
	var contours := Geometry2D.offset_polyline(line, radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	if contours.any(Geometry2D.is_polygon_clockwise):
		contours.clear()
		for index in range(1, line.size()):
			var segment := PackedVector2Array([line[index - 1], line[index]])
			contours.append_array(Geometry2D.offset_polyline(segment, radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	var polygons := []
	for contour in contours:
		polygons.append_array(Art.clipped_polygon(object, contour))
	return polygons

static func shape_polygons(object: Dictionary, points: PackedVector2Array) -> Array:
	var polygons := []
	if Art.has_fill(object) and Color(object.color).a > 0.0:
		for piece in Art.shape_fill_components(object, points):
			var clipped: Array[PackedVector2Array] = []
			clipped.assign(Art.clipped_polygon(object, piece))
			polygons.append_array(Art.Compound.filled_outlines(clipped))
	var radius := Art.outline_width(object) * 0.5
	if radius <= 0.0 or Color(object.outline_color).a <= 0.0: return polygons
	var loops: Array[PackedVector2Array] = [points]
	if object.get("compound", false): loops = Art.Compound.boundary_loops(points)
	for contour in loops:
		var outlines := Geometry2D.offset_polyline(contour, radius, Geometry2D.JOIN_ROUND, Geometry2D.END_JOINED)
		polygons.append_array(Art.Compound.filled_outlines(outlines))
	return polygons

static func region_result(region: PackedVector2Array, index: int) -> Dictionary:
	return {"vertices": region, "index": index, "compound": not Art.Compound.bridge_edges(region).is_empty()}

static func refine_region(region: PackedVector2Array, footprints: Array[Dictionary], seed: Vector2,
		changes: Variant = null) -> PackedVector2Array:
	if Geometry2D.is_polygon_clockwise(region): region.reverse()
	var bounds := Art.polygon_bounds(region)
	for footprint in footprints:
		if not bounds.intersects(footprint.bounds): continue
		var area := absf(Art.Compound.signed_area(region)) if changes != null else 0.0
		region = seed_component(Geometry2D.clip_polygons(region, footprint.outline), seed)
		if region.is_empty() or region.size() > 8192: return PackedVector2Array()
		if changes != null and not is_equal_approx(area, absf(Art.Compound.signed_area(region))):
			changes[footprint.index] = true
		bounds = Art.polygon_bounds(region)
	if Geometry2D.triangulate_polygon(region).is_empty(): return PackedVector2Array()
	if not Art.Compound.bridge_edges(region).is_empty(): return region
	# Overlap the antialiased edge slightly so paper cannot show through a seam.
	var expanded := Geometry2D.offset_polygon(region, 0.3)
	return expanded[0] if expanded.size() == 1 and not Geometry2D.triangulate_polygon(expanded[0]).is_empty() else region
