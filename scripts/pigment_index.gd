extends RefCounted
## Spatial lookup for the existing vector color sampler. Candidates stay in paint order.
const Art = preload("res://scripts/artwork.gd")
const StrokeLookup = preload("res://scripts/stroke_lookup.gd")
const OpacityStack = preload("res://scripts/opacity_stack.gd")
const CELL_SIZE := 96.0
const LAYER_ORDER_STRIDE := 1 << 32
const MAX_CELLS_PER_OBJECT := 64
const MIN_TRANSMITTANCE := 1.0 / 4096.0

var cells: Dictionary = {}
var broad: Array = []
var entries: Dictionary = {}
var paper := Color.WHITE
var has_merged_opacity := false
var has_layer_opacity := false

func rebuild(document, solo_layer_id := "", bounds_provider := Callable()) -> void:
	cells.clear()
	broad.clear()
	paper = Color(document.paper)
	has_merged_opacity = false
	has_layer_opacity = false
	var next_entries := {}
	for layer_index in document.layers.size():
		var layer: Dictionary = document.layers[layer_index]
		var opacity: float = layer.get("opacity", 1.0)
		if not layer.visible or opacity <= 0.0 or (not solo_layer_id.is_empty() and layer.id != solo_layer_id): continue
		if opacity < 1.0: has_layer_opacity = true
		var layer_scope: Array = [{"id": layer.id, "opacity": opacity}] if opacity < 1.0 else []
		for object_index in layer.objects.size():
			var object: Dictionary = layer.objects[object_index]
			var entry: Dictionary = entries.get(object.id, {})
			if entry.is_empty() or not is_same(entry.object, object) or object.kind != "stroke":
				entry = make_entry(object)
			var groups: Array = object.get("opacity_groups", [])
			if not groups.is_empty(): has_merged_opacity = true
			index_entry(entry, object, layer_index, opacity, layer_scope + groups,
				layer_index * LAYER_ORDER_STRIDE + object_index, bounds_provider)
			next_entries[object.id] = entry
	entries = next_entries

func append_latest(layer: Dictionary, layer_index: int, object: Dictionary) -> bool:
	if entries.has(object.id) or not object.get("opacity_groups", []).is_empty(): return false
	var opacity: float = layer.get("opacity", 1.0)
	if opacity <= 0.0: return true
	var layer_scope: Array = []
	if opacity < 1.0:
		has_layer_opacity = true
		layer_scope = [{"id": layer.id, "opacity": opacity}]
	var entry := make_entry(object)
	index_entry(entry, object, layer_index, opacity, layer_scope,
		layer_index * LAYER_ORDER_STRIDE + layer.objects.size() - 1)
	entries[object.id] = entry
	return true

func erase_entry(id: String) -> void:
	var entry: Dictionary = entries.get(id, {})
	if entry.is_empty(): return
	var bounds: Rect2 = entry.bounds
	var first := cell_at(bounds.position)
	var last := cell_at(bounds.end)
	if is_broad(first, last):
		broad.erase(entry)
	else:
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				var key := Vector2i(x, y)
				var bucket: Array = cells[key]
				bucket.erase(entry)
				if bucket.is_empty(): cells.erase(key)
	entries.erase(id)

func is_broad(first: Vector2i, last: Vector2i) -> bool:
	return (last.x - first.x + 1) * (last.y - first.y + 1) > MAX_CELLS_PER_OBJECT

func insert_ordered(bucket: Array, entry: Dictionary) -> void:
	if bucket.is_empty() or bucket[-1].order < entry.order:
		bucket.append(entry)
	else:
		var index := bucket.bsearch_custom(entry, func(a, b): return a.order < b.order)
		bucket.insert(index, entry)

func make_entry(object: Dictionary) -> Dictionary:
	return {"object": object}

func index_entry(entry: Dictionary, object: Dictionary, layer_index: int, opacity: float, groups: Array,
		order: int, bounds_provider := Callable()) -> void:
	var pose := Art.object_transform(object)
	if not entry.has("bounds") or entry.pose != pose:
		entry.pose = pose
		entry.bounds = bounds_provider.call(object) if bounds_provider.is_valid() else Art.coverage_bounds(object)
	entry.order = order
	entry.layer = layer_index
	entry.opacity = opacity
	entry.groups = groups
	var bounds: Rect2 = entry.bounds
	var first := cell_at(bounds.position)
	var last := cell_at(bounds.end)
	if is_broad(first, last):
		insert_ordered(broad, entry)
		return
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var key := Vector2i(x, y)
			if not cells.has(key): cells[key] = []
			insert_ordered(cells[key], entry)

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i((point / CELL_SIZE).floor())

func sample(point: Vector2) -> Color:
	var nearby: Array = cells.get(cell_at(point), [])
	if not has_merged_opacity and not has_layer_opacity:
		return sample_opaque_stack(point, nearby)
	var result := paper
	var local_index := 0
	var broad_index := 0
	var last_layer := -1
	var layer_opacity := 1.0
	var combined := Color.TRANSPARENT
	var composite: OpacityStack = OpacityStack.new(paper) if has_merged_opacity else null
	while local_index < nearby.size() or broad_index < broad.size():
		var entry: Dictionary
		if broad_index == broad.size() or (local_index < nearby.size() and nearby[local_index].order < broad[broad_index].order):
			entry = nearby[local_index]
			local_index += 1
		else:
			entry = broad[broad_index]
			broad_index += 1
		var ink = entry_color(entry, point)
		if ink == null: continue
		if composite:
			composite.add(ink, entry.groups)
			continue
		if entry.layer != last_layer:
			if layer_opacity < 1.0:
				combined.a *= layer_opacity
				result = result.blend(combined)
				combined = Color.TRANSPARENT
			last_layer = entry.layer
			layer_opacity = entry.opacity
		if layer_opacity >= 1.0: result = result.blend(ink)
		else: combined = combined.blend(ink)
	if composite: return composite.result()
	if layer_opacity < 1.0:
		combined.a *= layer_opacity
		result = result.blend(combined)
	return result

func sample_opaque_stack(point: Vector2, nearby: Array) -> Color:
	# Front-to-back source-over can skip buried marks once their combined
	# contribution is below a fraction of an 8-bit channel.
	var rgb := Vector3.ZERO
	var remaining := 1.0
	var local_index := nearby.size() - 1
	var broad_index := broad.size() - 1
	while local_index >= 0 or broad_index >= 0:
		var entry: Dictionary
		if broad_index < 0 or (local_index >= 0 and nearby[local_index].order > broad[broad_index].order):
			entry = nearby[local_index]
			local_index -= 1
		else:
			entry = broad[broad_index]
			broad_index -= 1
		var ink = entry_color(entry, point)
		if ink == null: continue
		rgb += Vector3(ink.r, ink.g, ink.b) * (ink.a * remaining)
		remaining *= 1.0 - ink.a
		if remaining < MIN_TRANSMITTANCE: break
	var paper_weight := paper.a * remaining
	rgb += Vector3(paper.r, paper.g, paper.b) * paper_weight
	var alpha := 1.0 - remaining + paper_weight
	if alpha <= 0.0: return paper
	return Color(rgb.x / alpha, rgb.y / alpha, rgb.z / alpha, alpha)

func entry_color(entry: Dictionary, point: Vector2) -> Variant:
	if not entry.bounds.has_point(point): return null
	var object: Dictionary = entry.object
	var stroke: StrokeLookup = entry.get("stroke")
	if not stroke and object.kind == "stroke" and object.points.size() >= StrokeLookup.MIN_SAMPLES:
		stroke = StrokeLookup.new(object)
		entry.stroke = stroke
	if stroke: return stroke.color_at(object, point)
	if not Art.contains(entry.object, point): return null
	return Art.color_at(entry.object, point)
