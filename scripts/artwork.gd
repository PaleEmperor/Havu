extends RefCounted
## Shared vector geometry for drawing, picking, blending and SVG export.
const Raster = preload("res://scripts/raster_asset.gd")
const OpacityStack = preload("res://scripts/opacity_stack.gd")
const AreaSelection = preload("res://scripts/area_selection.gd")
const Fonts = preload("res://scripts/font_library.gd")
const Compound = preload("res://scripts/compound_polygon.gd")
const SANS = preload("res://assets/fonts/StudioSans.ttf")
const SERIF = preload("res://assets/fonts/StudioSerif.ttf")
const SHAPES := ["rect", "ellipse", "polygon", "path"]
const VECTOR_EDGE_SHADER := preload("res://assets/vector_edge.gdshader")
const EDGE_UV_ORIGIN := Vector2(16.0, 16.0)
const GRAIN_SHADER := preload("res://assets/grain_tip.gdshader")
const GRAIN_SIDES := 7
const GRAIN_STRIDE := 16
const GRAIN_BATCHES := &"_grain_batches"
const SOFT_BATCH_SIZE := 24
static var edge_material: ShaderMaterial
static var grain_material: ShaderMaterial
static var grain_tip: ArrayMesh

static func v(pair_value) -> Vector2:
	return Vector2(pair_value[0], pair_value[1])

static func local_point(object: Dictionary, point: Vector2) -> Vector2:
	return (point - v(object.pos)) / float(object.scale)

static func polygon(object: Dictionary) -> PackedVector2Array:
	var result = PackedVector2Array()
	match object.kind:
		"rect":
			var e = v(object.extent)
			var radius := clampf(object.get("corner_radius", 0.0), 0, minf(absf(e.x), absf(e.y)) * 0.5)
			if radius > 0 and e.x > 0 and e.y > 0:
				var centers := [Vector2(e.x - radius, radius), e - Vector2.ONE * radius,
					Vector2(radius, e.y - radius), Vector2.ONE * radius]
				for corner in 4:
					for i in range(9):
						result.append(centers[corner] + Vector2.from_angle((corner - 1) * PI / 2 + i * PI / 16) * radius)
				return result
			result = PackedVector2Array([Vector2.ZERO, Vector2(e.x, 0), e, Vector2(0, e.y)])
		"ellipse":
			var e = v(object.extent)
			for i in range(72):
				var angle = float(i) / 72 * TAU
				result.append(e * 0.5 + Vector2(cos(angle), sin(angle)) * e * 0.5)
		"polygon", "path":
			for p in object.vertices: result.append(v(p))
	return result

static func has_fill(object: Dictionary) -> bool:
	return object.kind != "path" and object.get("fill_enabled", true)

static func outline_width(object: Dictionary) -> float:
	return float(object.get("outline_width", 0.0))

static func arrow_head(points: PackedVector2Array, width: float) -> PackedVector2Array:
	var tip := points[-1]
	var direction := tip - points[-2]
	var length := minf(direction.length() * 0.8, maxf(10.0, width * 4.0))
	var unit := direction.normalized()
	var base := tip - unit * length
	var side := unit.orthogonal() * length * 0.46
	return PackedVector2Array([tip, base + side, base - side])

static func vector_outline(points: PackedVector2Array, closed: bool, arrow: PackedVector2Array) -> PackedVector2Array:
	if closed: return close_points(points)
	if arrow.is_empty(): return points
	var shaft := points.duplicate()
	shaft[-1] = (arrow[1] + arrow[2]) * 0.5
	return shaft

static func outline_contains(points: PackedVector2Array, point: Vector2, distance: float) -> bool:
	for index in range(1, points.size()):
		var closest := Geometry2D.get_closest_point_to_segment(point, points[index - 1], points[index])
		if point.distance_squared_to(closest) <= distance * distance: return true
	return false

static func stroke_radius(max_radius: float, pressure: float, curve: float, minimum := 0.12) -> float:
	var width_pressure := pressure if curve == 1.0 else pow(pressure, curve)
	return max_radius * lerpf(minimum, 1.0, width_pressure)

static func stroke_alpha(pressure: float, response: float, curve: float) -> float:
	if response <= 0.0: return 1.0
	return lerpf(1.0, pressure if curve == 1.0 else pow(pressure, curve), response)

static func stroke_taper(object: Dictionary) -> Array[PackedFloat32Array]:
	var points: Array = object.points
	var start_length := float(object.get("taper_start", 0.0)) * float(object.size)
	var end_length := 0.0 if object.get("live_stroke", false) else float(object.get("taper_end", 0.0)) * float(object.size)
	if points.size() <= 1 or (start_length <= 0.0 and end_length <= 0.0): return []
	var tip: float = object.get("taper_tip", 0.08)
	return [taper_tail(points, false, start_length, tip), taper_tail(points, true, end_length, tip)]

static func taper_tail(points: Array, reverse: bool, length: float, tip: float) -> PackedFloat32Array:
	var factors := PackedFloat32Array()
	if length <= 0.0: return factors
	var first := points.size() - 1 if reverse else 0
	var direction := -1 if reverse else 1
	var previous := v(points[first])
	var distance := 0.0
	factors.append(tip)
	for offset in range(1, points.size()):
		var point := v(points[first + direction * offset])
		distance += point.distance_to(previous)
		if distance >= length: break
		factors.append(lerpf(tip, 1.0, smoothstep(0.0, length, distance)))
		previous = point
	return factors

static func taper_factor(taper: Array[PackedFloat32Array], index: int, count: int) -> float:
	if taper.is_empty(): return 1.0
	var start: float = taper[0][index] if index < taper[0].size() else 1.0
	var reverse_index := count - 1 - index
	var end: float = taper[1][reverse_index] if reverse_index < taper[1].size() else 1.0
	return minf(start, end)

static func stroke_polygon(object: Dictionary, first := 0, end := -1) -> PackedVector2Array:
	var points: Array = object.points
	var stop := points.size() if end < 0 else end
	var left = PackedVector2Array()
	var right = PackedVector2Array()
	var max_radius := float(object.size) * 0.5
	var curve: float = object.get("pressure_curve", 1.0)
	var minimum: float = object.get("minimum_width", 0.12)
	var taper := stroke_taper(object)
	if points.size() == 1:
		var radius := stroke_radius(max_radius, points[0][2], curve, minimum)
		for i in range(32): left.append(v(points[0]) + Vector2.from_angle(TAU * i / 32) * radius)
		return left
	for i in range(first, stop):
		var direction := stroke_direction(points, i)
		var normal = Vector2(-direction.y, direction.x)
		var radius := stroke_radius(max_radius, points[i][2], curve, minimum)
		if not taper.is_empty(): radius *= taper_factor(taper, i, points.size())
		left.append(v(points[i]) + normal * radius)
		right.append(v(points[i]) - normal * radius)
	# Adjacent batches share the same cross-section. Only the ends of the
	# whole stroke have round caps.
	if stop == points.size():
		var tip := v(points[-1])
		var end_direction := stroke_direction(points, stop - 1).angle()
		var end_radius := stroke_radius(max_radius, points[-1][2], curve, minimum) * taper_factor(taper, points.size() - 1, points.size())
		for i in range(1, 12): left.append(tip + Vector2.from_angle(end_direction + PI / 2 - PI * i / 12) * end_radius)
	right.reverse()
	left.append_array(right)
	if first == 0:
		var start := v(points[0])
		var start_direction := stroke_direction(points, 0).angle()
		var start_radius := stroke_radius(max_radius, points[0][2], curve, minimum) * taper_factor(taper, 0, points.size())
		for i in range(1, 12): left.append(start + Vector2.from_angle(start_direction - PI / 2 - PI * i / 12) * start_radius)
	return left

static func stroke_direction(points: Array, index: int) -> Vector2:
	var before := v(points[maxi(0, index - 1)])
	var after := v(points[mini(points.size() - 1, index + 1)])
	var direction := (after - before).normalized()
	return Vector2.RIGHT if direction.is_zero_approx() else direction

static func bounds(object: Dictionary) -> Rect2:
	var result = Rect2()
	if object.kind == "image":
		result = Rect2(Vector2.ZERO, v(object.extent))
	elif object.kind == "text":
		var font := Fonts.font_for(object.font)
		var lines = object.text.split("\n")
		var text_width = 1.0
		for line in lines: text_width = maxf(text_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(object.font_size)).x)
		result = Rect2(0, -float(object.font_size), text_width, float(object.font_size) * 1.35 * lines.size())
	else:
		var points = stroke_polygon(object) if object.kind == "stroke" else polygon(object)
		if not points.is_empty():
			result = Rect2(points[0], Vector2.ZERO)
			for point in points: result = result.expand(point)
			if object.kind == "path" and object.get("arrow", false):
				for point in arrow_head(points, outline_width(object)): result = result.expand(point)
			if object.kind in SHAPES and outline_width(object) > 0: result = result.grow(outline_width(object) * 0.5)
	result.position = result.position * float(object.scale) + v(object.pos)
	result.size *= float(object.scale)
	return result

static func coverage_bounds(object: Dictionary) -> Rect2:
	if object.kind != "stroke": return bounds(object).grow(0.01)
	# The sampler uses distance to the centerline, including round caps.
	var points: Array = object.points
	var result := Rect2(v(points[0]), Vector2.ZERO)
	for point in points: result = result.expand(v(point))
	result = result.grow(float(object.size) * 0.5 + 0.01)
	return Rect2(result.position * float(object.scale) + v(object.pos), result.size * float(object.scale))

static func contains(object: Dictionary, point: Vector2, tolerance = 0.0) -> bool:
	var local = local_point(object, point)
	if not point_inside_clip(object, local): return false
	if object.kind in ["text", "image"]: return bounds(object).grow(tolerance).has_point(point)
	if object.kind == "stroke":
		var points = object.points
		var curve: float = object.get("pressure_curve", 1.0)
		var minimum: float = object.get("minimum_width", 0.12)
		var max_radius := float(object.size) * 0.5
		var local_tolerance := float(tolerance) / float(object.scale)
		var taper := stroke_taper(object)
		for i in range(points.size()):
			var p = points[i]
			var near = v(p) if i == 0 else Geometry2D.get_closest_point_to_segment(local, v(points[i - 1]), v(p))
			var radius := stroke_radius(max_radius, p[2], curve, minimum)
			if not taper.is_empty(): radius *= taper_factor(taper, i, points.size())
			if not taper.is_empty() and i > 0:
				var start := v(points[i - 1])
				var length := start.distance_to(v(p))
				if length > 0.0:
					var start_radius := stroke_radius(max_radius, points[i - 1][2], curve, minimum) * taper_factor(taper, i - 1, points.size())
					radius = lerpf(start_radius, radius, start.distance_to(near) / length)
			radius += local_tolerance
			if radius >= 0.0 and local.distance_squared_to(near) <= radius * radius: return true
		return false
	var points := polygon(object)
	var closed: bool = object.kind != "path"
	if closed and has_fill(object) and shape_point_inside(object, points, local): return true
	var width := outline_width(object)
	if width <= 0: return false
	var arrow := arrow_head(points, width) if not closed and object.get("arrow", false) else PackedVector2Array()
	if not arrow.is_empty() and Geometry2D.is_point_in_polygon(local, arrow): return true
	return shape_outline_contains(object, points, local, width * 0.5 + tolerance / float(object.scale), arrow)

static func shape_point_inside(object: Dictionary, points: PackedVector2Array, local: Vector2) -> bool:
	if object.get("compound", false): return Compound.contains(points, local)
	return Geometry2D.is_point_in_polygon(local, points)

static func shape_outline_contains(object: Dictionary, points: PackedVector2Array, local: Vector2,
		radius: float, arrow: PackedVector2Array) -> bool:
	if not object.get("compound", false):
		return outline_contains(vector_outline(points, object.kind != "path", arrow), local, radius)
	var bridges := Compound.bridge_edges(points)
	var radius_squared := radius * radius
	for index in points.size():
		if bridges.has(index): continue
		var near := Geometry2D.get_closest_point_to_segment(local, points[index], points[(index + 1) % points.size()])
		if local.distance_squared_to(near) <= radius_squared: return true
	return false

static func shape_interior_contains(object: Dictionary, point: Vector2) -> bool:
	if object.kind not in SHAPES or object.kind == "path": return false
	var local := local_point(object, point)
	return point_inside_clip(object, local) and shape_point_inside(object, polygon(object), local)

static func closed_stroke_outline(object: Dictionary) -> PackedVector2Array:
	var points: Array = object.points
	if points.size() < 3 or v(points[0]).distance_to(v(points[-1])) > float(object.size) * 2.0:
		return PackedVector2Array()
	return outline_vertices(points)

static func outline_vertices(points: Array) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for sample in points:
		var point := v(sample)
		if outline.is_empty() or not outline[-1].is_equal_approx(point):
			outline.append(point)
	if outline.size() > 1 and outline[0].is_equal_approx(outline[-1]): outline.resize(outline.size() - 1)
	return outline if outline.size() >= 3 else PackedVector2Array()

static func selection_contours(object: Dictionary) -> Array[PackedVector2Array]:
	var contours: Array[PackedVector2Array] = []
	match object.kind:
		"stroke":
			var outline := closed_stroke_outline(object)
			if outline.is_empty() or Geometry2D.triangulate_polygon(outline).is_empty():
				outline = stroke_polygon(object)
			if not Geometry2D.triangulate_polygon(outline).is_empty():
				contours.append(outline)
			else:
				var centerline := PackedVector2Array()
				for sample in object.points: centerline.append(v(sample))
				var pieces := Geometry2D.offset_polyline(centerline, float(object.size) * 0.5,
					Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
				# Use individual stroke footprints if an offset makes a hole.
				if pieces.size() == 1:
					contours.assign(pieces)
				else:
					for dab in segments(object): contours.append(dab.polygon)
		"path":
			var points := polygon(object)
			var width := outline_width(object)
			if points.size() >= 2 and width > 0.0:
				var arrow := arrow_head(points, width) if object.get("arrow", false) else PackedVector2Array()
				contours.assign(Geometry2D.offset_polyline(vector_outline(points, false, arrow), width * 0.5,
					Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT))
				if not arrow.is_empty(): contours.append(arrow)
		"text", "image":
			return [AreaSelection.corners(bounds(object))]
		_:
			contours.assign(shape_fill_components(object, polygon(object)))
	var selection: Array[PackedVector2Array] = []
	var mask := prepare_paint_mask(object)
	var position := v(object.pos)
	for outline in contours:
		if outline.size() < 3: continue
		for piece in clipped_polygon(object, outline, mask):
			if Geometry2D.triangulate_polygon(piece).is_empty(): continue
			var transformed := PackedVector2Array()
			for point in piece: transformed.append(point * float(object.scale) + position)
			selection.append(transformed)
	return selection

static func add_selection_contour(contours: Array[PackedVector2Array], outline: PackedVector2Array) -> void:
	if outline.size() < 3: return
	var area := polygon_bounds(outline)
	var index := contours.size() - 1
	while index >= 0:
		if area.intersects(polygon_bounds(contours[index]), true):
			var merged := Geometry2D.merge_polygons(contours[index], outline)
			if merged.size() == 1:
				outline = merged[0]
				area = polygon_bounds(outline)
				contours.remove_at(index)
				index = contours.size()
		index -= 1
	contours.append(outline)

static func pack_contours(contours: Array[PackedVector2Array]) -> Array:
	var packed := []
	for outline in contours:
		var points := []
		for point in outline: points.append([point.x, point.y])
		packed.append(points)
	return packed

static func intersect_masks(left: Array, right: Array) -> Array:
	var contours: Array[PackedVector2Array] = []
	for left_region in left:
		var outline := unpack_polygon(left_region)
		for right_region in right:
			for piece in Geometry2D.intersect_polygons(outline, unpack_polygon(right_region)):
				add_selection_contour(contours, piece)
	return pack_contours(contours)

static func point_inside_clip(object: Dictionary, local: Vector2) -> bool:
	if object.has("clip") and not Geometry2D.is_point_in_polygon(local, unpack_polygon(object.clip)): return false
	if not object.has("paint_mask"): return true
	for region in object.paint_mask:
		if Geometry2D.is_point_in_polygon(local, unpack_polygon(region)): return true
	return false

static func unpack_polygon(coordinates: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in coordinates: polygon.append(v(point))
	return polygon

static func color_at(object: Dictionary, point: Vector2) -> Color:
	if object.kind in SHAPES and outline_width(object) > 0:
		var local := local_point(object, point)
		var points := polygon(object)
		var closed: bool = object.kind != "path"
		var result := Color.TRANSPARENT
		if has_fill(object) and shape_point_inside(object, points, local):
			result = Color(object.color)
			result.a *= object.opacity
		var width := outline_width(object)
		if width > 0:
			var arrow := arrow_head(points, width) if not closed and object.get("arrow", false) else PackedVector2Array()
			if shape_outline_contains(object, points, local, width * 0.5, arrow) or (
				not arrow.is_empty() and Geometry2D.is_point_in_polygon(local, arrow)):
				var ink := Color(object.outline_color)
				ink.a *= object.opacity
				result = result.blend(ink)
		return result
	var color = Color(object.color)
	if object.kind == "image":
		color = Raster.pixel_at(object, local_point(object, point))
	elif object.kind == "stroke":
		var local = local_point(object, point)
		var distance = INF
		var closest: Array = object.points[0]
		for sample in object.points:
			var current = local.distance_squared_to(v(sample))
			if current < distance:
				distance = current
				closest = sample
		return stroke_sample_color(object, closest, distance)
	color.a *= float(object.opacity)
	return color

static func stroke_sample_color(object: Dictionary, sample: Array, distance_squared: float) -> Color:
	var color := Color(sample[3])
	color.a *= stroke_alpha(sample[2], object.get("opacity_pressure", 0.0), object.get("opacity_curve", 1.0))
	if object.brush == "soft":
		var coverage := clampf(1.0 - sqrt(distance_squared) / maxf(1.0, object.size / 2), 0.0, 1.0)
		color.a *= pow(coverage, float(object.get("feather", 0.8)) / 0.8)
	color.a *= float(object.opacity)
	return color

static func sample(document, point: Vector2) -> Color:
	var composite := OpacityStack.new(Color(document.paper))
	for layer in document.layers:
		var opacity: float = layer.get("opacity", 1.0)
		if not layer.visible or opacity <= 0.0: continue
		var scope: Array = [{"id": layer.id, "opacity": opacity}] if opacity < 1.0 else []
		for object in layer.objects:
			if not contains(object, point): continue
			composite.add(color_at(object, point), scope + object.get("opacity_groups", []))
		composite.close_to(0)
	return composite.result()

static func vector_paint_mask(layer: Dictionary) -> Array:
	var regions: Array[PackedVector2Array] = []
	var extents: Array[Rect2] = []
	var total := 0
	for object in layer.objects:
		if object.opacity < 1.0 or Color(object.color).a < 1.0 or object.has("paint_mask"): continue
		if not object.get("opacity_groups", []).is_empty(): continue
		for region in opaque_footprints(object):
			if regions.size() >= 256 or total + region.size() > 24000: continue
			var transformed := PackedVector2Array()
			var position := v(object.pos)
			for point in region: transformed.append(point * float(object.scale) + position)
			var area := polygon_bounds(transformed)
			var merged := false
			# Merge touching regions when their union is representable without a hole.
			for index in regions.size():
				if not area.intersects(extents[index]): continue
				var union := Geometry2D.merge_polygons(regions[index], transformed)
				if union.size() != 1: continue
				var growth := union[0].size() - regions[index].size()
				if total + growth > 24000: continue
				total += growth
				regions[index] = union[0]
				extents[index] = area.merge(extents[index])
				merged = true
				break
			if not merged:
				regions.append(transformed)
				extents.append(area)
				total += transformed.size()
	var packed := []
	for region in regions:
		var coordinates := []
		for point in region: coordinates.append([point.x, point.y])
		packed.append(coordinates)
	return packed

static func opaque_footprints(object: Dictionary) -> Array:
	if object.kind in SHAPES and has_fill(object):
		if object.get("vertices", []).size() > 4000: return []
		var footprints := []
		for points in shape_fill_components(object, polygon(object)):
			if not Geometry2D.triangulate_polygon(points).is_empty():
				footprints.append_array(clipped_polygon(object, points))
		return footprints
	if object.kind != "stroke": return []
	if uses_ink_outline(object) and object.points.size() <= 4000:
		var outline := stroke_polygon(object)
		if not Geometry2D.triangulate_polygon(outline).is_empty():
			return clipped_polygon(object, outline)
	if object.brush in ["pencil", "chalk", "soft"] or object.points.size() > 256: return []
	var footprints := []
	for dab in segments(object):
		if dab.color.a >= 1.0:
			footprints.append_array(clipped_polygon(object, dab.polygon))
	return footprints

static func prepare_paint_mask(object: Dictionary) -> Array:
	var prepared := []
	for region in object.get("paint_mask", []):
		var points := unpack_polygon(region)
		prepared.append([points, polygon_bounds(points)])
	return prepared

static func polygon_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points: bounds = bounds.expand(point)
	return bounds

static func clipped_polygon(object: Dictionary, points: PackedVector2Array, paint_mask := []) -> Array:
	var pieces: Array = Geometry2D.intersect_polygons(points, unpack_polygon(object.clip)) if object.has("clip") else [points]
	if paint_mask.is_empty(): return pieces
	var clipped := []
	for piece in pieces:
		var bounds := polygon_bounds(piece)
		for region in paint_mask:
			if bounds.intersects(region[1]):
				clipped.append_array(Compound.filled_outlines(Geometry2D.intersect_polygons(piece, region[0])))
	return clipped

static func paint_polygon(target: CanvasItem, object: Dictionary, points: PackedVector2Array, color: Color, paint_mask := []) -> void:
	if points.size() < 3: return
	for piece in clipped_polygon(object, points, paint_mask):
		if piece.size() < 3: continue
		var triangles := Geometry2D.triangulate_polygon(piece)
		if not triangles.is_empty(): paint_triangles(target, piece, triangles, color, paint_mask.is_empty(), object.get("compound", false))

static func use_screen_edges(target: CanvasItem, object: Dictionary) -> void:
	if uses_grain_instances(object):
		if grain_material == null:
			grain_material = ShaderMaterial.new()
			grain_material.shader = GRAIN_SHADER
		target.material = grain_material
		return
	if object.kind not in SHAPES and not (object.kind == "stroke" and (
			uses_ink_outline(object) or uses_wet_batches(object))): return
	if edge_material == null:
		edge_material = ShaderMaterial.new()
		edge_material.shader = VECTOR_EDGE_SHADER
	target.material = edge_material

static func paint_triangles(target: CanvasItem, points: PackedVector2Array, triangles: PackedInt32Array,
		color: Color, antialias: bool, compound := false) -> void:
	if antialias and edge_material != null and target.material == edge_material:
		var rim := screen_edge_geometry(points, triangles, color, compound)
		RenderingServer.canvas_item_add_triangle_array(target.get_canvas_item(), rim.indices, rim.vertices, rim.colors, rim.uv)
		return
	RenderingServer.canvas_item_add_triangle_array(target.get_canvas_item(), triangles, points, PackedColorArray([color]))
	if antialias and not compound: target.draw_polyline(close_points(points), color, 0.65, true)

static func screen_edge_geometry(points: PackedVector2Array, triangles: PackedInt32Array, color: Color, compound := false) -> Dictionary:
	var vertices := points.duplicate()
	vertices.append_array(points)
	var indices := triangles.duplicate()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var count := points.size()
	colors.resize(count * 2)
	uv.resize(count * 2)
	var clear := Color(color, 0.0)
	var sign := -1.0 if Geometry2D.is_polygon_clockwise(points) else 1.0
	var first_segment := points[0] - points[-1]
	var previous_normal := sign * Vector2(first_segment.y, -first_segment.x).normalized()
	var bridges := Compound.bridge_edges(points) if compound else {}
	var incoming_normals := {}
	var outgoing_normals := {}
	if compound:
		for index in count:
			if bridges.has(index): continue
			var following := (index + 1) % count
			var segment := points[following] - points[index]
			var normal := sign * Vector2(segment.y, -segment.x).normalized()
			outgoing_normals[points[index]] = normal
			incoming_normals[points[following]] = normal
	for index in count:
		var segment := points[(index + 1) % count] - points[index]
		var next_normal := sign * Vector2(segment.y, -segment.x).normalized()
		var incoming := previous_normal
		var outgoing := next_normal
		if compound:
			incoming = incoming_normals.get(points[index], incoming)
			outgoing = outgoing_normals.get(points[index], outgoing)
		var direction := (incoming + outgoing).normalized()
		if direction.is_zero_approx(): direction = outgoing
		uv[count + index] = EDGE_UV_ORIGIN + direction / maxf(0.5, direction.dot(outgoing))
		colors[index] = color
		colors[count + index] = clear
		var following := (index + 1) % count
		if not segment.is_zero_approx() and not bridges.has(index):
			indices.append(index)
			indices.append(following)
			indices.append(count + following)
			indices.append(index)
			indices.append(count + following)
			indices.append(count + index)
		previous_normal = next_normal
	return {"indices": indices, "vertices": vertices, "colors": colors, "uv": uv}

static func close_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed = points.duplicate()
	if not points.is_empty(): closed.append(points[0])
	return closed

static func draw_object(target: CanvasItem, object: Dictionary, origin = Vector2.ZERO, zoom = 1.0, local_geometry := false) -> void:
	if not local_geometry:
		target.draw_set_transform(origin + v(object.pos) * zoom, 0, Vector2.ONE * zoom * float(object.scale))
	var color = Color(object.color)
	color.a *= object.opacity
	match object.kind:
		"image":
			var texture := Raster.texture(object)
			if texture: target.draw_texture_rect(texture, Rect2(Vector2.ZERO, v(object.extent)), false, color)
		"text":
			var font := Fonts.font_for(object.font)
			var y = 0.0
			for line in object.text.split("\n"):
				target.draw_string(font, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(object.font_size), color)
				y += float(object.font_size) * 1.35
		"stroke":
			var batch_size := stroke_batch_size(object)
			for first in range(0, object.points.size(), batch_size):
				draw_stroke_range(target, object, first, mini(first + batch_size, object.points.size()), first / batch_size)
			if target.has_meta(GRAIN_BATCHES):
				var batches: Array = target.get_meta(GRAIN_BATCHES)
				batches.resize(ceili(float(object.points.size()) / batch_size) if uses_grain_instances(object) else 0)
		_:
			draw_shape(target, object)

static func shape_fill_components(object: Dictionary, points: PackedVector2Array) -> Array[PackedVector2Array]:
	if object.get("compound_disjoint", false): return Compound.components(points)
	return [points]

static func draw_shape(target: CanvasItem, object: Dictionary) -> void:
	var points := polygon(object)
	if has_fill(object):
		var fill := Color(object.color)
		fill.a *= object.opacity
		for piece in shape_fill_components(object, points):
			paint_polygon(target, object, piece, fill)
	var width := outline_width(object)
	if width <= 0 or points.size() < 2: return
	var closed: bool = object.kind != "path"
	if not closed and points.size() == 2 and points[0].is_equal_approx(points[1]): return
	var ink := Color(object.outline_color)
	ink.a *= object.opacity
	var arrow := arrow_head(points, width) if not closed and object.get("arrow", false) else PackedVector2Array()
	if object.get("compound", false):
		for contour in Compound.boundary_loops(points):
			target.draw_polyline(close_points(contour), ink, width, true)
	else:
		target.draw_polyline(vector_outline(points, closed, arrow), ink, width, true)
	if not arrow.is_empty(): paint_polygon(target, object, arrow, ink)

static func stroke_batch_size(object: Dictionary) -> int:
	if uses_grain_instances(object): return 128
	if object.brush == "soft": return SOFT_BATCH_SIZE
	if uses_ink_outline(object) and object.opacity < 1.0: return 100001
	return 64

static func uses_ink_outline(object: Dictionary) -> bool:
	return object.brush == "ink" and float(object.get("opacity_pressure", 0.0)) == 0.0

static func uses_wet_batches(object: Dictionary) -> bool:
	return object.get("brush") in ["paint", "mix", "soft"] and not object.has("clip") and not object.has("paint_mask")

static func wet_batch_geometry(object: Dictionary, first: int, end: int) -> Dictionary:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for dab in segments(object, first, end):
		var polygon: PackedVector2Array = dab.polygon
		var triangles := Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty(): continue
		var geometry := screen_edge_geometry(polygon, triangles, dab.color)
		var offset := vertices.size()
		for index in geometry.indices: indices.append(offset + index)
		vertices.append_array(geometry.vertices)
		colors.append_array(geometry.colors)
		uv.append_array(geometry.uv)
	return {"vertices": vertices, "colors": colors, "indices": indices, "uv": uv}

static func ink_outline(object: Dictionary, first: int, end: int) -> PackedVector2Array:
	return stroke_polygon(object, maxi(0, first - 1), end)

static func draw_stroke_range(target: CanvasItem, object: Dictionary, first: int, end: int, batch_index := 0) -> void:
	if grain_material != null and target.material == grain_material and uses_grain_instances(object):
		draw_grain(target, object, first, end, batch_index)
		return
	if edge_material != null and target.material == edge_material and uses_wet_batches(object):
		# One GPU polygon buffer per batch, with source-over order preserved.
		var batch := wet_batch_geometry(object, first, end)
		if not batch.indices.is_empty():
			RenderingServer.canvas_item_add_triangle_array(
				target.get_canvas_item(), batch.indices, batch.vertices, batch.colors, batch.uv)
		return
	var mask := prepare_paint_mask(object) if object.has("paint_mask") else []
	if uses_ink_outline(object):
		var outline := ink_outline(object, first, end)
		var triangles := Geometry2D.triangulate_polygon(outline)
		if not triangles.is_empty():
			var color := Color(object.color)
			color.a *= object.opacity
			if object.has("clip") or not mask.is_empty():
				paint_polygon(target, object, outline, color, mask)
			else:
				paint_triangles(target, outline, triangles, color, true)
			return
	# Tight curves and self-crossings can produce an invalid single outline.
	for segment in segments(object, first, end):
		paint_polygon(target, object, segment.polygon, segment.color, mask)

static func is_grain(object: Dictionary) -> bool:
	return object.get("brush") in ["pencil", "chalk"]

static func uses_grain_instances(object: Dictionary) -> bool:
	return is_grain(object) and not object.has("clip") and not object.has("paint_mask")

static func grain_profile(object: Dictionary) -> Vector3:
	var density: float = object.get("grain", 1.0)
	var pencil: bool = object.brush == "pencil"
	var flecks := maxi(1, roundi((5 if pencil else 9) * density))
	var ratio := (0.1 if pencil else 0.2) * sqrt(density) * float(object.get("grain_size", 1.0))
	var spread := minf(0.8 * float(object.get("grain_spread", 1.0)), 1.0 - ratio)
	return Vector3(flecks, ratio, spread)

static func grain_offset(seed_value: float, spread: float) -> Vector2:
	return Vector2(sin(seed_value * 1.71), cos(seed_value * 2.37)) * spread

static func grain_buffer(object: Dictionary, first: int, end: int) -> PackedFloat32Array:
	var profile := grain_profile(object)
	var flecks := int(profile.x)
	var data := PackedFloat32Array()
	var limit := mini(end, object.points.size())
	data.resize(maxi(0, limit - first) * flecks * GRAIN_STRIDE)
	var max_radius := float(object.size) * 0.5
	var curve: float = object.get("pressure_curve", 1.0)
	var minimum: float = object.get("minimum_width", 0.12)
	var opacity_pressure: float = object.get("opacity_pressure", 0.0)
	var opacity_curve: float = object.get("opacity_curve", 1.0)
	var taper := stroke_taper(object)
	var index := 0
	for i in range(first, limit):
		var point: Array = object.points[i]
		var pressure: float = point[2]
		var radius := stroke_radius(max_radius, pressure, curve, minimum) * taper_factor(taper, i, object.points.size())
		var extent := radius * profile.z
		var tip_radius := maxf(0.3, radius * profile.y)
		var color := Color(point[3])
		color.a *= object.opacity * stroke_alpha(pressure, opacity_pressure, opacity_curve) * (0.35 + 0.5 * pressure)
		var center := v(point)
		for grain in flecks:
			var seed_value := float(i * 31 + grain * 97)
			var position := center + grain_offset(seed_value, extent)
			# Transform2D rows, RGBA, then the phase and a shader marker.
			data[index] = tip_radius
			data[index + 3] = position.x
			data[index + 5] = tip_radius
			data[index + 7] = position.y
			data[index + 8] = color.r
			data[index + 9] = color.g
			data[index + 10] = color.b
			data[index + 11] = color.a
			data[index + 12] = fposmod(seed_value, TAU)
			data[index + 13] = 1.0
			index += GRAIN_STRIDE
	return data

static func make_grain_tip() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	for ring in 2:
		for corner in GRAIN_SIDES:
			vertices.append(Vector2.from_angle(TAU * corner / GRAIN_SIDES))
			uv.append(Vector2(corner, ring))
	var indices := PackedInt32Array()
	for corner in range(1, GRAIN_SIDES - 1):
		indices.append_array(PackedInt32Array([0, corner, corner + 1]))
	for corner in GRAIN_SIDES:
		var next := (corner + 1) % GRAIN_SIDES
		indices.append_array(PackedInt32Array([corner, next, next + GRAIN_SIDES, corner, next + GRAIN_SIDES, corner + GRAIN_SIDES]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader can expand the antialiased rim past the unit outline.
	mesh.custom_aabb = AABB(Vector3(-1.4, -1.4, 0), Vector3(2.8, 2.8, 0))
	return mesh

static func draw_grain(target: CanvasItem, object: Dictionary, first: int, end: int, batch_index: int) -> void:
	if first >= end: return
	var data := grain_buffer(object, first, end)
	var count := data.size() / GRAIN_STRIDE
	if count == 0: return
	var batches: Array = target.get_meta(GRAIN_BATCHES, [])
	if batches.size() <= batch_index: batches.resize(batch_index + 1)
	var batch: MultiMesh = batches[batch_index]
	if batch == null:
		if grain_tip == null: grain_tip = make_grain_tip()
		batch = MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_2D
		batch.use_colors = true
		batch.use_custom_data = true
		batch.mesh = grain_tip
		batches[batch_index] = batch
		# Draw commands retain RIDs, so keep the resources with their canvas item.
		target.set_meta(GRAIN_BATCHES, batches)
	if batch.instance_count != count: batch.instance_count = count
	batch.buffer = data
	target.draw_multimesh(batch, null)

static func clipped_stroke_has_paint(object: Dictionary) -> bool:
	var mask := prepare_paint_mask(object)
	if mask.is_empty() and not object.has("clip"): return true
	if uses_ink_outline(object):
		var outline := stroke_polygon(object)
		if not Geometry2D.triangulate_polygon(outline).is_empty():
			return not clipped_polygon(object, outline, mask).is_empty()
	for first in range(0, object.points.size(), 64):
		for segment in segments(object, first, first + 64):
			if not clipped_polygon(object, segment.polygon, mask).is_empty(): return true
	return false

static func paint_footprints(object: Dictionary) -> Array:
	var footprints := []
	var mask := prepare_paint_mask(object)
	var batch := stroke_batch_size(object)
	for first in range(0, object.points.size(), batch):
		var end := mini(first + batch, object.points.size())
		if uses_ink_outline(object):
			var outline := ink_outline(object, first, end)
			if not Geometry2D.triangulate_polygon(outline).is_empty():
				var color := Color(object.color)
				color.a *= object.opacity
				for piece in clipped_polygon(object, outline, mask):
					footprints.append({"polygon": piece, "color": color})
				continue
		for dab in segments(object, first, end):
			for piece in clipped_polygon(object, dab.polygon, mask):
				footprints.append({"polygon": piece, "color": dab.color})
	return footprints

static func segments(object: Dictionary, first := 0, end := -1) -> Array:
	var result = []
	var limit: int = object.points.size() if end < 0 else mini(end, object.points.size())
	var max_radius := float(object.size) * 0.5
	var curve: float = object.get("pressure_curve", 1.0)
	var minimum: float = object.get("minimum_width", 0.12)
	var opacity_pressure: float = object.get("opacity_pressure", 0.0)
	var opacity_curve: float = object.get("opacity_curve", 1.0)
	var taper := stroke_taper(object)
	var dry := is_grain(object)
	var profile := grain_profile(object) if dry else Vector3.ZERO
	var custom_tip := object.has("tip_ratio") or object.has("tip_angle")
	var angled_tip: bool = object.brush == "marker" or custom_tip
	var tip := Transform2D.IDENTITY
	var inverse_tip := Transform2D.IDENTITY
	if angled_tip:
		var rotation := Transform2D(deg_to_rad(object.get("tip_angle", -45.0)), Vector2.ZERO)
		tip = rotation.scaled_local(Vector2(1, object.get("tip_ratio", 0.25))) * rotation.inverse()
		if custom_tip: inverse_tip = tip.affine_inverse()
	var passes := 5 if object.brush == "soft" else 1
	var feather: float = object.get("feather", 0.8)
	var ribbon: bool = (object.get("continuous_edges", false) and object.brush in ["paint", "mix"]
		and is_equal_approx(float(object.get("tip_ratio", 1.0)), 1.0))
	for i in range(first, limit):
		var p = object.points[i]
		var previous = object.points[maxi(0, i - 1)]
		var radius := stroke_radius(max_radius, p[2], curve, minimum)
		if not taper.is_empty(): radius *= taper_factor(taper, i, object.points.size())
		var previous_radius := radius
		if i > 0 and (ribbon or not taper.is_empty()):
			previous_radius = stroke_radius(max_radius, previous[2], curve, minimum)
			if not taper.is_empty(): previous_radius *= taper_factor(taper, i - 1, object.points.size())
		var color = Color(p[3])
		color.a *= object.opacity * stroke_alpha(p[2], opacity_pressure, opacity_curve)
		if ribbon and object.points.size() > 1:
			if i == 0: continue
			var strip := ribbon_segment(object.points, i, previous_radius, radius)
			if not Geometry2D.triangulate_polygon(strip).is_empty():
				result.append({"polygon": strip, "color": color})
				continue
		if dry:
			var grain_radius := maxf(0.3, radius * profile.y)
			var grain_color := Color(color, color.a * (0.35 + 0.5 * p[2]))
			for grain in int(profile.x):
				var seed_value := float(i * 31 + grain * 97)
				var center := v(p) + grain_offset(seed_value, radius * profile.z)
				var fleck := PackedVector2Array()
				for k in GRAIN_SIDES:
					fleck.append(center + Vector2.from_angle(TAU * k / GRAIN_SIDES) * grain_radius * (0.7 + absf(sin(seed_value + k)) * 0.3))
				result.append({"polygon": fleck, "color": grain_color})
			continue
		if taper.is_empty(): previous_radius = radius
		var a := v(previous)
		var b := v(p)
		var delta := b - a
		var angle := (inverse_tip.basis_xform(delta) if custom_tip else delta).angle()
		var dot := a.distance_squared_to(b) < 0.000001
		var outer := PackedVector2Array()
		if dot:
			for k in range(32):
				var offset := Vector2.from_angle(TAU * k / 32) * radius
				if angled_tip: offset = tip.basis_xform(offset)
				outer.append(a + offset)
		else:
			for k in range(13):
				var offset := Vector2.from_angle(angle - PI / 2 + PI * k / 12) * radius
				if angled_tip: offset = tip.basis_xform(offset)
				outer.append(b + offset)
			for k in range(13):
				var offset := Vector2.from_angle(angle + PI / 2 + PI * k / 12) * previous_radius
				if angled_tip: offset = tip.basis_xform(offset)
				outer.append(a + offset)
		var ring_color = color
		if passes > 1: ring_color.a *= 0.12 + (0.8 - feather) * 0.30
		result.append({"polygon": outer, "color": ring_color})
		# Each feather band is a scaled copy of the same two caps.
		for ring in range(1, passes):
			var shrink := float(ring) / passes * feather
			var shape := PackedVector2Array()
			if dot:
				for point in outer: shape.append(point.lerp(a, shrink))
			else:
				for k in range(13): shape.append(outer[k].lerp(b, shrink))
				for k in range(13, 26): shape.append(outer[k].lerp(a, shrink))
			result.append({"polygon": shape, "color": ring_color})
	return result

static func ribbon_segment(points: Array, index: int, a_radius: float, b_radius: float) -> PackedVector2Array:
	var a := v(points[index - 1])
	var b := v(points[index])
	var a_angle := stroke_direction(points, index - 1).angle()
	var b_angle := stroke_direction(points, index).angle()
	var a_side := Vector2.from_angle(a_angle + PI / 2) * a_radius
	var b_side := Vector2.from_angle(b_angle + PI / 2) * b_radius
	var strip := PackedVector2Array([a + a_side, b + b_side])
	if index == points.size() - 1:
		for step in range(1, 12): strip.append(b + Vector2.from_angle(b_angle + PI / 2 - PI * step / 12) * b_radius)
	strip.append(b - b_side)
	strip.append(a - a_side)
	if index == 1:
		for step in range(1, 12): strip.append(a + Vector2.from_angle(a_angle - PI / 2 - PI * step / 12) * a_radius)
	return strip

static func points_string(points: PackedVector2Array) -> String:
	var result = PackedStringArray()
	for point in points: result.append("%.3f,%.3f" % [point.x, point.y])
	return " ".join(result)

static func svg(document, embed_fonts = true) -> String:
	var output = ['<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%s" height="%s" viewBox="0 0 %s %s">' % [document.width, document.height, document.width, document.height]]
	output.append('<title>%s</title>' % document.title.xml_escape())
	var embedded := {}
	if embed_fonts:
		for layer in document.layers:
			if not layer.visible: continue
			for object in layer.objects:
				if object.kind != "text" or embedded.has(object.font): continue
				var path := Fonts.bundled_path(object.font)
				if path.is_empty(): continue
				var font := Fonts.font_for(object.font) as FontFile
				if not font: continue
				var bytes := font.data
				if bytes.is_empty(): continue
				var format := "opentype" if path.ends_with(".otf") else "truetype"
				embedded[object.font] = "@font-face{font-family:'%s';src:url(data:font/%s;base64,%s) format('%s');}" % [
					Fonts.svg_alias(object.font), path.get_extension(), Marshalls.raw_to_base64(bytes), format]
		if not embedded.is_empty():
			output.append('<defs><style>' + "\n".join(embedded.values()) + '</style></defs>')
	output.append('<defs><clipPath id="page"><rect width="%s" height="%s"/></clipPath></defs>' % [document.width, document.height])
	if document.paper_visible:
		output.append('<rect width="100%%" height="100%%" fill="%s"/>' % document.paper)
	output.append('<g clip-path="url(#page)">')
	var counter = 0
	for layer in document.layers:
		if not layer.visible: continue
		output.append('<g aria-label="%s" opacity="%s">' % [layer.name.xml_escape(true), layer.get("opacity", 1.0)])
		var scopes := []
		for object in layer.objects:
			var groups: Array = object.get("opacity_groups", [])
			var shared := OpacityStack.shared_depth(scopes, groups)
			for unused in range(shared, scopes.size()): output.append('</g>')
			for depth in range(shared, groups.size()): output.append('<g opacity="%s">' % groups[depth].opacity)
			scopes = groups
			counter += 1
			output.append('<g transform="translate(%s %s) scale(%s)">' % [object.pos[0], object.pos[1], object.scale])
			if object.has("clip"):
				var clip = PackedVector2Array()
				for p in object.clip: clip.append(v(p))
				output.append('<defs><clipPath id="clip%s"><polygon points="%s"/></clipPath></defs><g clip-path="url(#clip%s)">' % [counter, points_string(clip), counter])
			if object.has("paint_mask"):
				output.append('<defs><clipPath id="mask%s">' % counter)
				for region in object.paint_mask:
					output.append('<polygon points="%s"/>' % points_string(unpack_polygon(region)))
				output.append('</clipPath></defs><g clip-path="url(#mask%s)">' % counter)
			match object.kind:
				"image":
					output.append('<image width="%s" height="%s" opacity="%s" xlink:href="data:image/%s;base64,%s"/>' %
						[object.extent[0], object.extent[1], object.opacity, object.image_format, object.image_data])
				"text":
					var y = 0.0
					var family: String
					var font_attributes := ""
					if embedded.has(object.font):
						family = Fonts.svg_alias(object.font)
					else:
						var font := Fonts.font_for(object.font)
						family = object.get("font_family", font.get_font_name())
						var weight: int = int(object.get("font_weight", font.get_font_weight()))
						var italic: bool = object.get("font_italic", (font.get_font_style() & TextServer.FONT_ITALIC) != 0)
						font_attributes = ' font-weight="%d" font-style="%s"' % [weight, "italic" if italic else "normal"]
					for line in object.text.split("\n"):
						output.append('<text x="0" y="%s" font-family="%s"%s font-size="%s" fill="%s" fill-opacity="%s">%s</text>' %
							[y, family.xml_escape(true), font_attributes, object.font_size, object.color, object.opacity, line.xml_escape()])
						y += object.font_size * 1.35
				"stroke":
					var batch_size := stroke_batch_size(object)
					for first in range(0, object.points.size(), batch_size):
						var end := mini(first + batch_size, object.points.size())
						if uses_ink_outline(object):
							var outline := ink_outline(object, first, end)
							if not Geometry2D.triangulate_polygon(outline).is_empty():
								output.append(svg_polygon(outline, Color(object.color), object.opacity))
								continue
						for segment in segments(object, first, end):
							output.append(svg_polygon(segment.polygon, segment.color, 1.0))
				_:
					output.append(svg_shape(object))
			if object.has("clip"): output.append('</g>')
			if object.has("paint_mask"): output.append('</g>')
			output.append('</g>')
		for unused in scopes: output.append('</g>')
		output.append('</g>')
	output.append('</g></svg>')
	return "\n".join(output)

static func svg_shape(object: Dictionary) -> String:
	var points := polygon(object)
	if not object.get("compound_disjoint", false) and not object.has("fill_enabled") and not object.has("outline_width") and not object.has("corner_radius"):
		return svg_polygon(points, Color(object.color), object.opacity)
	var fill := Color(object.color)
	var fill_value := 'fill="#%s" fill-opacity="%s"' % [fill.to_html(false), fill.a * object.opacity] if has_fill(object) else 'fill="none"'
	var width := outline_width(object)
	var stroke_value := ""
	if width > 0:
		var ink := Color(object.outline_color)
		stroke_value = ' stroke="#%s" stroke-opacity="%s" stroke-width="%s" stroke-linejoin="round"' % [
			ink.to_html(false), ink.a * object.opacity, width]
	var paint := fill_value + stroke_value
	if object.get("compound_disjoint", false) or (object.get("compound", false) and width > 0):
		var contours := PackedStringArray()
		for contour in Compound.boundary_loops(points):
			contours.append("M" + points_string(contour) + "Z")
		return '<path d="%s" fill-rule="evenodd" %s/>' % [" ".join(contours), paint]
	match object.kind:
		"rect":
			return '<rect width="%s" height="%s" rx="%s" %s/>' % [object.extent[0], object.extent[1], object.get("corner_radius", 0), paint]
		"ellipse":
			var radii := v(object.extent) * 0.5
			return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" %s/>' % [radii.x, radii.y, radii.x, radii.y, paint]
		"path":
			var arrow := arrow_head(points, width) if object.get("arrow", false) else PackedVector2Array()
			var shaft := '<polyline points="%s" %s/>' % [points_string(vector_outline(points, false, arrow)), paint]
			if arrow.is_empty(): return shaft
			return shaft + svg_polygon(arrow, Color(object.outline_color), object.opacity)
	return '<polygon points="%s" %s/>' % [points_string(points), paint]

static func svg_polygon(points: PackedVector2Array, color: Color, opacity: float) -> String:
	return '<polygon points="%s" fill="#%s" fill-opacity="%s"/>' % [points_string(points), color.to_html(false), color.a * opacity]
