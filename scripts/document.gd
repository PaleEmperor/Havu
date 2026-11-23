extends RefCounted
## Plain, versioned vector document. No scene nodes or executable resources in files.
signal changed
const Art = preload("res://scripts/artwork.gd")
const BrushLibrary = preload("res://scripts/brush_library.gd")
const Raster = preload("res://scripts/raster_asset.gd")
const PaintTiles = preload("res://scripts/paint_tiles.gd")
const VectorUnion = preload("res://scripts/vector_union.gd")
const Fonts = preload("res://scripts/font_library.gd")
const VERSION = 1
const DISJOINT_COMPOUND_VERSION = 2
const ORIENTED_OBJECT_VERSION = 3
const MAX_PROJECT_BYTES := 64 * 1024 * 1024
const MAX_IMAGE_PAYLOAD := 40 * 1024 * 1024
const MAX_OBJECTS = 10000
const HISTORY_ENTRY_LIMIT := 50
const HISTORY_ESTIMATED_BYTES := 96 * 1024 * 1024
const MIN_CANVAS_SIZE := 64
const MAX_CANVAS_SIZE := 10000
enum ResizeArtwork { KEEP, FIT, ADAPT, COMPOSITION }
enum Alignment { LEFT, CENTER_X, RIGHT, TOP, CENTER_Y, BOTTOM }
enum Stacking { FRONT, BACK, FORWARD, BACKWARD }
var title = "The little green café"
var width = 900.0
var height = 1100.0
var paper = "#faf8f1"
var paper_visible := true
var layers: Array = []
var active = 0
var area_selection: Array[String] = []
var selection := "":
	set(value):
		selection = value
		area_selection.clear()
var history: Array = []
var future: Array = []
var serial = 0
var dirty = false
var revision := 0
var appended_on_commit: Dictionary = {}
var transformed_on_commit: Array[Dictionary] = []
var content_on_commit: Dictionary = {}

func uid() -> String:
	serial += 1
	return "o_%s_%s" % [Time.get_ticks_usec(), serial]

func new_layer(name_text = "Drawing", layer_type := "vector") -> Dictionary:
	return {"id": uid(), "name": name_text, "type": layer_type, "visible": true, "locked": false, "opacity": 1.0, "objects": []}

func layer_index(layer_id: String) -> int:
	for index in layers.size():
		if layers[index].id == layer_id: return index
	return -1

func snapshot(copy_content := true) -> Dictionary:
	return {"format": "havu", "version": VERSION, "title": title, "width": width, "height": height, "paper": paper, "paper_visible": paper_visible, "active": active, "layers": layers.duplicate(true) if copy_content else layers}

func restore(data: Dictionary, copy_content := true) -> void:
	title = data.title
	width = float(data.width)
	height = float(data.height)
	paper = data.paper
	paper_visible = data.get("paper_visible", true)
	layers = data.layers.duplicate(true) if copy_content else data.layers
	active = clampi(int(data.get("active", 0)), 0, layers.size() - 1)
	selection = ""

func checkpoint() -> void:
	push_history(snapshot())
	future.clear()

func push_history(entry: Dictionary) -> void:
	append_history_entry(history, entry)

func append_history_entry(stack: Array, entry: Dictionary) -> void:
	if not entry.has("_cost"): entry._cost = estimate_history_bytes(entry)
	stack.append(entry)
	var total: int = entry._cost
	for index in range(stack.size() - 2, -1, -1): total += stack[index]._cost
	# Retain at least one action, even if a full-document operation is large.
	while stack.size() > 1 and (stack.size() > HISTORY_ENTRY_LIMIT or total > HISTORY_ESTIMATED_BYTES):
		total -= stack.pop_front()._cost

func estimate_history_bytes(entry: Dictionary) -> int:
	var bytes := 512
	if entry.has("layers"):
		for layer in entry.layers:
			for object in layer.objects: bytes += estimate_object_bytes(object)
	elif entry.has("append"):
		bytes += estimate_object_bytes(entry.append)
	elif entry.has("transform"):
		for objects in entry.transform.values(): bytes += 480 * objects.size()
	elif entry.has("paint"):
		for tile in entry.before + entry.after: bytes += estimate_object_bytes(tile.tile)
	elif entry.has("artwork_groups"):
		bytes += 96 * entry.artwork_groups.size()
	elif entry.has("object_order"):
		for orders in entry.object_order.values(): bytes += 64 * orders[0].size()
	elif entry.has("membership"):
		for slots in entry.membership.values():
			for slot in slots: bytes += estimate_object_bytes(slot.object)
	elif entry.has("layer_order"):
		bytes += 128 * entry.layer_order[0].size()
	elif entry.has("span"):
		for object in entry.before + entry.after: bytes += estimate_object_bytes(object)
	return bytes

func estimate_object_bytes(object: Dictionary) -> int:
	var bytes: int = 768 + 128 * object.get("points", []).size() + 80 * object.get("vertices", []).size()
	bytes += 80 * object.get("clip", []).size() + 48 * object.get("node_anchors", []).size()
	for contour in object.get("paint_mask", []): bytes += 80 * contour.size()
	bytes += String(object.get("image_data", "")).length() * 4 + String(object.get("text", "")).length() * 4
	return bytes

func commit(appended: Dictionary = {}, transformed: Array[Dictionary] = [], content: Dictionary = {}) -> void:
	appended_on_commit = appended
	transformed_on_commit = transformed
	content_on_commit = content
	dirty = true
	revision += 1
	changed.emit()
	appended_on_commit = {}
	transformed_on_commit = []
	content_on_commit = {}

func append_with_history(object: Dictionary) -> void:
	if not editable(): return
	add(object)
	push_history({"append": object.duplicate(true), "layer": active})
	future.clear()
	commit(object)

func paints_pixels() -> bool:
	return not layers.is_empty() and layers[active].get("type", "vector") == "paint"

func commit_paint(stroke: Dictionary, erasing: bool) -> Error:
	if not editable() or not paints_pixels(): return ERR_UNAVAILABLE
	var layer: Dictionary = layers[active]
	var result := PaintTiles.new().apply(layer, Vector2i(ceili(width), ceili(height)), stroke, erasing)
	return record_paint_result(layer, result)

func fill_paint(point: Vector2i, ink: Color) -> Error:
	if not editable() or not paints_pixels(): return ERR_UNAVAILABLE
	var layer: Dictionary = layers[active]
	var result := PaintTiles.new().fill_region(layer, Vector2i(ceili(width), ceili(height)), point, ink)
	return record_paint_result(layer, result)

func record_paint_result(layer: Dictionary, result: Dictionary) -> Error:
	if result.is_empty(): return OK
	var previous: Array = layer.objects
	var bytes := embedded_image_bytes()
	for tile in previous: bytes -= tile.image_data.length()
	for tile in result.objects: bytes += tile.image_data.length()
	if bytes > MAX_IMAGE_PAYLOAD: return ERR_OUT_OF_MEMORY
	var old_by_id := {}
	var next_by_id := {}
	for tile in previous: old_by_id[tile.id] = tile
	for tile in result.objects:
		if not tile.has("id"): tile.id = uid()
		next_by_id[tile.id] = tile
	var before := paint_changes(previous, next_by_id)
	var after := paint_changes(result.objects, old_by_id)
	push_history({"paint": layer.id, "before": before, "after": after})
	future.clear()
	layer.objects = result.objects
	selection = ""
	commit({}, [], {"layer": layer.id, "remove": paint_ids(before), "add": paint_objects(after)})
	return OK

func paint_changes(objects: Array, opposite: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for index in objects.size():
		var tile: Dictionary = objects[index]
		if not is_same(opposite.get(tile.id), tile):
			entries.append({"index": index, "tile": tile})
	return entries

func paint_ids(entries: Array) -> Dictionary:
	var ids := {}
	for entry in entries: ids[entry.tile.id] = true
	return ids

func paint_objects(entries: Array) -> Array:
	var values := []
	for entry in entries: values.append(entry.tile)
	return values

func restore_paint(change: Dictionary, forward: bool) -> void:
	var index := layer_index(change.paint)
	if index < 0: return
	var layer: Dictionary = layers[index]
	var from: Array = change.before if forward else change.after
	var to: Array = change.after if forward else change.before
	var remove_ids := paint_ids(from)
	var restored := []
	var insert_at := 0
	for tile in layer.objects:
		if remove_ids.has(tile.id): continue
		while insert_at < to.size() and to[insert_at].index == restored.size():
			restored.append(to[insert_at].tile)
			insert_at += 1
		restored.append(tile)
	while insert_at < to.size():
		restored.append(to[insert_at].tile)
		insert_at += 1
	layer.objects = restored
	active = index
	selection = ""
	commit({}, [], {"layer": layer.id, "remove": remove_ids, "add": paint_objects(to)})

func append_vector_object(object: Dictionary, ink_gap := VectorUnion.TIP_GAP) -> bool:
	if not editable(): return false
	if not paints_pixels():
		var layer: Dictionary = layers[active]
		if layer.get("type", "vector") == "vector" and layer.get("merge_touching", false) and VectorUnion.can_union(object):
			object.merge_batch = layer.merge_batch
			var joined := VectorUnion.find_union(layer.objects, object, ink_gap)
			if not joined.is_empty():
				checkpoint()
				for index in joined.indices: layer.objects.remove_at(index)
				add(joined.object)
				commit()
				return true
		append_with_history(object)
		return true
	var above: int = active + 1
	var reuse: bool = (above < layers.size() and layers[above].get("type", "vector") == "vector"
		and layers[above].visible and not layers[above].locked and not layers[above].get("alpha_locked", false))
	if not reuse and layers.size() >= 100: return false
	checkpoint()
	if not reuse: layers.insert(above, new_layer("Vector", "vector"))
	active = above
	add(object)
	commit()
	return true

static func capture_transform_item(item: Dictionary) -> Dictionary:
	var object: Dictionary = item.object
	return {"object": object, "layer_id": item.layer.id,
		"position": Art.v(object.pos), "original_pos": object.pos,
		"scale": object.scale, "angle": object.get("angle"), "mirrored": object.get("mirrored")}

static func set_orientation(object: Dictionary, angle, mirrored) -> void:
	if angle == null: object.erase("angle")
	else: object.angle = angle
	if mirrored == null: object.erase("mirrored")
	else: object.mirrored = mirrored

static func turn_object(item: Dictionary, pivot: Vector2, radians: float, flip: int) -> void:
	var object: Dictionary = item.object
	if flip == 0 and is_zero_approx(radians):
		object.pos = item.original_pos
		set_orientation(object, item.angle, item.mirrored)
		return
	var angle := float(item.angle) if item.angle != null else 0.0
	var mirrored: bool = item.mirrored == true
	var offset: Vector2 = item.position - pivot
	if flip == 1:
		offset.x = -offset.x
		angle = -angle
		mirrored = not mirrored
	elif flip == 2:
		offset.y = -offset.y
		angle = PI - angle
		mirrored = not mirrored
	else:
		offset = offset.rotated(radians)
		angle += radians
	var center := pivot + offset
	object.pos = [center.x, center.y]
	angle = wrapf(angle, -PI, PI)
	set_orientation(object, null if is_zero_approx(angle) else angle, true if mirrored else null)

func arrange_units(items: Array[Dictionary]) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	var indices := {}
	for item in items:
		var object: Dictionary = item.object
		if object.get("paint_tile", false): continue
		var key := layout_unit(object)
		var box := Art.bounds(object)
		if not indices.has(key):
			indices[key] = units.size()
			units.append({"position": units.size(), "bounds": box, "items": [item]})
			continue
		var unit := units[int(indices[key])]
		unit.bounds = unit.bounds.merge(box)
		unit.items.append(item)
	return units

func translate_unit(unit: Dictionary, shift: Vector2, changes: Array[Dictionary]) -> void:
	if shift.is_zero_approx(): return
	for item in unit.items:
		var captured := capture_transform_item(item)
		var moved: Vector2 = captured.position + shift
		item.object.pos = [moved.x, moved.y]
		changes.append(captured)

func align_items(items: Array[Dictionary], alignment: Alignment, to_canvas: bool) -> bool:
	var units := arrange_units(items)
	if units.size() < (1 if to_canvas else 2): return false
	var guide := Rect2(Vector2.ZERO, Vector2(width, height)) if to_canvas else units[0].bounds as Rect2
	if not to_canvas:
		for unit in units: guide = guide.merge(unit.bounds)
	var axis := int(alignment) / 3
	var anchor := float(int(alignment) % 3) * 0.5
	var changes: Array[Dictionary] = []
	for unit in units:
		var box: Rect2 = unit.bounds
		var shift := Vector2.ZERO
		shift[axis] = guide.position[axis] + guide.size[axis] * anchor - box.position[axis] - box.size[axis] * anchor
		translate_unit(unit, shift, changes)
	record_transform(changes)
	return not changes.is_empty()

func distribute_items(items: Array[Dictionary], axis: int) -> bool:
	var units := arrange_units(items)
	if units.size() < 3: return false
	units.sort_custom(func(a, b):
		var left: float = a.bounds.position[axis]
		var right: float = b.bounds.position[axis]
		return a.position < b.position if left == right else left < right)
	var extent := 0.0
	for unit in units: extent += unit.bounds.size[axis]
	var start: float = units[0].bounds.position[axis]
	var end: float = units[-1].bounds.end[axis]
	for unit in units: end = maxf(end, float(unit.bounds.end[axis]))
	var gap := (end - start - extent) / (units.size() - 1)
	var changes: Array[Dictionary] = []
	for unit in units:
		var shift := Vector2.ZERO
		shift[axis] = start - unit.bounds.position[axis]
		translate_unit(unit, shift, changes)
		start += unit.bounds.size[axis] + gap
	record_transform(changes)
	return not changes.is_empty()

func stack_items(items: Array[Dictionary], order: Stacking) -> bool:
	var by_layer := {}
	for item in items:
		if not by_layer.has(item.layer.id): by_layer[item.layer.id] = {}
		by_layer[item.layer.id][item.object.id] = true
	var change := {}
	for layer_id in by_layer:
		var layer: Dictionary = layers[layer_index(layer_id)]
		# Keep flattened opacity scopes and fixed pixel tiles in their existing layer stack.
		if layer.get("type", "vector") != "vector" or layer.objects.any(func(object): return object.has("opacity_groups")):
			return false
		var previous: Array = layer.objects.map(func(object): return object.id)
		var next := stacked_ids(previous, by_layer[layer_id], order)
		if next != previous: change[layer_id] = [previous, next]
	if change.is_empty(): return false
	push_history({"object_order": change})
	future.clear()
	apply_object_order(change, true)
	return true

static func stacked_ids(previous: Array, ids: Dictionary, order: Stacking) -> Array:
	if order == Stacking.FRONT or order == Stacking.BACK:
		var selected_ids := previous.filter(func(id): return ids.has(id))
		var others := previous.filter(func(id): return not ids.has(id))
		return others + selected_ids if order == Stacking.FRONT else selected_ids + others
	var next := previous.duplicate()
	var step := 1 if order == Stacking.FORWARD else -1
	var indices := range(next.size() - 2, -1, -1) if step > 0 else range(1, next.size())
	for index in indices:
		if not ids.has(next[index]) or ids.has(next[index + step]): continue
		var id = next[index]
		next[index] = next[index + step]
		next[index + step] = id
	return next

func apply_object_order(change: Dictionary, forward: bool) -> void:
	for layer_id in change:
		var layer: Dictionary = layers[layer_index(layer_id)]
		var objects := {}
		for object in layer.objects: objects[object.id] = object
		layer.objects = change[layer_id][int(forward)].map(func(id): return objects[id])
	commit()

func record_transform(items: Array[Dictionary]) -> void:
	var by_layer := {}
	var changed_objects: Array[Dictionary] = []
	for item in items:
		var object: Dictionary = item.object
		if Art.v(object.pos) == item.position and object.scale == item.scale \
				and object.get("angle") == item.angle and object.get("mirrored") == item.mirrored: continue
		if not by_layer.has(item.layer_id): by_layer[item.layer_id] = {}
		by_layer[item.layer_id][object.id] = [
			[item.original_pos.duplicate(), item.scale, item.angle, item.mirrored],
			[object.pos.duplicate(), object.scale, object.get("angle"), object.get("mirrored")]]
		changed_objects.append(object)
	if by_layer.is_empty(): return
	push_history({"transform": by_layer})
	future.clear()
	commit({}, changed_objects, {"layers": by_layer.keys()})

func restore_transform(change: Dictionary, forward: bool) -> void:
	var changed_objects: Array[Dictionary] = []
	var slot := int(forward)
	var page_resize := change.has("page_sizes")
	if page_resize:
		var dimensions: Vector2 = change.page_sizes[slot]
		width = dimensions.x
		height = dimensions.y
		active = layer_index(change.active_id)
	for layer_id in change.transform:
		var index := layer_index(layer_id)
		if index == -1: continue
		var entries: Dictionary = change.transform[layer_id]
		var remaining := entries.size()
		for object in layers[index].objects:
			var pose: Array = entries.get(object.id, [])
			if pose.is_empty(): continue
			var state: Array = pose[slot]
			object.pos = state[0].duplicate()
			object.scale = state[1]
			set_orientation(object, state[2], state[3])
			changed_objects.append(object)
			remaining -= 1
			if remaining == 0: break
	selection = ""
	commit({}, changed_objects, {"layers": change.transform.keys(), "page_resize": page_resize})

func undo() -> void:
	if history.is_empty(): return
	var change: Dictionary = history.pop_back()
	if change.has("transform"):
		append_history_entry(future, change)
		restore_transform(change, false)
		return
	if change.has("artwork_groups"):
		append_history_entry(future, change)
		selection = ""
		apply_artwork_groups(change.artwork_groups, change.next_group, false)
		return
	if change.has("layer_flag"):
		append_history_entry(future, change)
		apply_layer_flag(change.layer, change.layer_flag, change.values[0])
		return
	if change.has("object_order"):
		append_history_entry(future, change)
		apply_object_order(change.object_order, false)
		return
	if change.has("membership") or change.has("layer_order"):
		append_history_entry(future, change)
		restore_membership_or_order(change, false)
		return
	if change.has("paint"):
		append_history_entry(future, change)
		restore_paint(change, false)
		return
	if change.has("recolor"):
		append_history_entry(future, change)
		restore_recolor(change, false)
		return
	if change.has("span"):
		append_history_entry(future, change)
		restore_layer_span(change, false)
		return
	if change.has("append"):
		var objects: Array = layers[change.layer].objects
		for index in range(objects.size() - 1, -1, -1):
			if objects[index].id == change.append.id:
				objects.remove_at(index)
				break
		active = change.layer
		selection = ""
		append_history_entry(future, change)
		commit({}, [], {"layer": layers[active].id, "remove": {change.append.id: true}, "add": [], "undo_append": true})
		return
	else:
		append_history_entry(future, snapshot())
		restore(change)
	commit()

func redo() -> void:
	if future.is_empty(): return
	var change: Dictionary = future.pop_back()
	if change.has("transform"):
		push_history(change)
		restore_transform(change, true)
		return
	if change.has("artwork_groups"):
		push_history(change)
		selection = ""
		apply_artwork_groups(change.artwork_groups, change.next_group, true)
		return
	if change.has("layer_flag"):
		push_history(change)
		apply_layer_flag(change.layer, change.layer_flag, change.values[1])
		return
	if change.has("object_order"):
		push_history(change)
		apply_object_order(change.object_order, true)
		return
	if change.has("membership") or change.has("layer_order"):
		push_history(change)
		restore_membership_or_order(change, true)
		return
	if change.has("paint"):
		push_history(change)
		restore_paint(change, true)
		return
	if change.has("recolor"):
		push_history(change)
		restore_recolor(change, true)
		return
	if change.has("span"):
		push_history(change)
		restore_layer_span(change, true)
		return
	if change.has("append"):
		active = change.layer
		var appended: Dictionary = change.append.duplicate(true)
		layers[active].objects.append(appended)
		selection = ""
		push_history(change)
		commit(appended)
		return
	else:
		push_history(snapshot())
		restore(change)
	commit()

func find_object(id: String) -> Dictionary:
	for layer in layers:
		for object in layer.objects:
			if object.id == id: return object
	return {}

func editable() -> bool:
	return not layers.is_empty() and layers[active].visible and not layers[active].locked

func can_edit(id: String) -> bool:
	for layer in layers:
		for object in layer.objects:
			if object.id == id: return layer.visible and not layer.locked
	return false

func select_objects(ids: Array[String]) -> void:
	selection = ids[0] if ids.size() == 1 else ""
	if ids.size() > 1: area_selection.assign(ids)

func select_artwork(ids: Array[String], solo_layer_id := "") -> bool:
	if ids.is_empty():
		selection = ""
		return false
	var picked := {}
	var groups := {}
	for id in ids: picked[id] = true
	for layer in layers:
		for object in layer.objects:
			if picked.has(object.id) and object.has("artwork_group"): groups[object.artwork_group] = true
	if groups.is_empty():
		select_objects(ids)
		return false

	var blocked := {}
	for layer in layers:
		if layer.visible and not layer.locked and (solo_layer_id.is_empty() or layer.id == solo_layer_id): continue
		for object in layer.objects:
			var group: String = object.get("artwork_group", "")
			if groups.has(group): blocked[group] = true
	var expanded: Array[String] = []
	for layer in layers:
		for object in layer.objects:
			var group: String = object.get("artwork_group", "")
			if not blocked.has(group) and (picked.has(object.id) or groups.has(group)):
				expanded.append(object.id)
	select_objects(expanded)
	return not blocked.is_empty()

func grouping_actions(items: Array[Dictionary]) -> Dictionary:
	var units := {}
	var has_group := false
	var all_vectors := true
	for item in items:
		var object: Dictionary = item.object
		var group: String = object.get("artwork_group", "")
		has_group = has_group or not group.is_empty()
		all_vectors = all_vectors and object.kind != "image"
		units["object:" + object.id if group.is_empty() else "group:" + group] = true
	return {"group": all_vectors and units.size() > 1, "ungroup": has_group}

func group_selected() -> bool:
	var items := selected_items()
	if not grouping_actions(items).group: return false
	change_artwork_groups(items, uid())
	return true

func ungroup_selected() -> bool:
	var items := selected_items()
	if not grouping_actions(items).ungroup: return false
	change_artwork_groups(items, "")
	return true

func change_artwork_groups(items: Array[Dictionary], next_group: String) -> void:
	var before := {}
	for item in items: before[item.object.id] = item.object.get("artwork_group", "")
	push_history({"artwork_groups": before, "next_group": next_group})
	future.clear()
	apply_artwork_groups(before, next_group, true)

func apply_artwork_groups(before: Dictionary, next_group: String, forward: bool) -> void:
	var remaining := before.size()
	for layer in layers:
		for object in layer.objects:
			if not before.has(object.id): continue
			var group: String = next_group if forward else before[object.id]
			if group.is_empty(): object.erase("artwork_group")
			else: object.artwork_group = group
			remaining -= 1
			if remaining == 0: break
		if remaining == 0: break
	commit({}, [], {"group_ids": before.keys()})

func union_selection_reason(items: Array[Dictionary]) -> String:
	if items.size() < 2: return "Select at least two vector objects."
	var first: Dictionary = items[0]
	var ink := Color(first.object.color)
	for item in items:
		if item.layer.id != first.layer.id: return "Move the objects to the same layer first."
		if not VectorUnion.can_union(item.object, true):
			return "Merge supports opaque filled shapes and solid ink."
		if Color(item.object.color) != ink: return "Give the objects the same color before using Union."
	var layer: Dictionary = first.layer
	if layer.get("alpha_locked", false): return "Turn off Alpha Lock before using Union."
	return ""

func union_selected(solo_layer_id := "") -> String:
	var items := layer_transfer_items(solo_layer_id)
	var reason := union_selection_reason(items)
	if not reason.is_empty(): return reason
	var ids := {}
	var values: Array[Dictionary] = []
	for item in items:
		ids[item.object.id] = true
		values.append(item.object)
	var united := VectorUnion.union_objects(values)
	if united.is_empty(): return "These outlines are too complex or could not form a valid union. Try fewer objects."
	var layer: Dictionary = items[0].layer
	var objects: Array = layer.objects
	var first := -1
	var last := -1
	for index in objects.size():
		if not ids.has(objects[index].id): continue
		if first == -1: first = index
		last = index
	var union_bounds := Art.bounds(united)
	var next := []
	for index in range(first, last):
		var object: Dictionary = objects[index]
		if ids.has(object.id): continue
		if Art.coverage_bounds(object).intersects(union_bounds, true):
			return "Move the selected objects next to each other in the drawing order before using Union."
		next.append(object)
	next.append(united)
	var layer_number := layer_index(layer.id)
	replace_layer_span(layer_number, first, last - first + 1, next, united.id)
	return ""

func recolor_shape(index: int, object: Dictionary, ink: String) -> void:
	var change := {"recolor": layers[index].id, "id": object.id, "color": [object.color, ink],
		"fill": object.get("fill_enabled")}
	push_history(change)
	future.clear()
	active = index
	selection = object.id
	object.color = ink
	object.fill_enabled = true
	commit({}, [], {"layer": layers[index].id, "redraw": object})

func restore_recolor(change: Dictionary, forward: bool) -> void:
	var index := layer_index(change.recolor)
	if index == -1: return
	for object in layers[index].objects:
		if object.id != change.id: continue
		object.color = change.color[int(forward)]
		if forward: object.fill_enabled = true
		elif change.fill == null: object.erase("fill_enabled")
		else: object.fill_enabled = change.fill
		active = index
		selection = ""
		commit({}, [], {"layer": layers[index].id, "redraw": object})
		return

func replace_layer_span(index: int, start: int, count: int, values: Array, selected_id: String) -> void:
	var layer: Dictionary = layers[index]
	var previous: Array = layer.objects.slice(start, start + count)
	# Artwork data is copied only for the replaced span. Keep history independent
	# of subsequent edits to the same objects.
	var change := {"span": layer.id, "start": start, "before": previous.duplicate(true),
		"after": values.duplicate(true)}
	push_history(change)
	future.clear()
	swap_layer_span(layer, start, count, values)
	active = index
	selection = selected_id
	commit({}, [], {"layers": [layer.id], "resync": [layer.id]})

func swap_layer_span(layer: Dictionary, start: int, count: int, values: Array) -> void:
	var objects: Array = layer.objects
	layer.objects = objects.slice(0, start) + values + objects.slice(start + count)

func restore_layer_span(change: Dictionary, forward: bool) -> void:
	var index := layer_index(change.span)
	if index == -1: return
	var previous: Array = change.before if forward else change.after
	var values: Array = change.after if forward else change.before
	swap_layer_span(layers[index], change.start, previous.size(), values.duplicate(true))
	active = index
	selection = ""
	commit({}, [], {"layers": [change.span], "resync": [change.span]})

func selected_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if selection.is_empty() and area_selection.is_empty(): return result
	var ids := {}
	for id in area_selection: ids[id] = true
	if not selection.is_empty(): ids[selection] = true
	var blocked_groups := {}
	if not area_selection.is_empty():
		for layer in layers:
			if layer.visible and not layer.locked: continue
			for object in layer.objects:
				if ids.has(object.id) and object.has("artwork_group"): blocked_groups[object.artwork_group] = true
	for layer in layers:
		if layer.locked or not layer.visible: continue
		for object in layer.objects:
			if ids.has(object.id) and not blocked_groups.has(object.get("artwork_group", "")):
				result.append({"layer": layer, "object": object})
	return result

func add(object: Dictionary) -> void:
	if not editable(): return
	if not object.has("id"): object.id = uid()
	if not object.has("pos"): object.pos = [0.0, 0.0]
	if not object.has("scale"): object.scale = 1.0
	layers[active].objects.append(object)
	selection = object.id

func import_image(asset: Dictionary, layer_name: String) -> bool:
	if layers.size() >= 100: return false
	if asset.image_data.length() + embedded_image_bytes() > MAX_IMAGE_PAYLOAD: return false
	checkpoint()
	var layer := new_layer(layer_name)
	active += 1
	layers.insert(active, layer)
	var image_size := Vector2(asset.extent[0], asset.extent[1])
	var scale_factor := minf(1.0, minf(width * 0.9 / image_size.x, height * 0.9 / image_size.y))
	var position := (Vector2(width, height) - image_size * scale_factor) * 0.5
	var object := asset.duplicate()
	object.merge({"kind": "image", "scale": scale_factor, "pos": [position.x, position.y], "opacity": 1.0, "color": "#ffffff"})
	add(object)
	commit()
	return true

func embedded_image_bytes() -> int:
	var total := 0
	for layer in layers:
		for object in layer.objects:
			if object.kind == "image": total += object.image_data.length()
	return total

func duplicate_layer(index: int) -> bool:
	if index < 0 or index >= layers.size() or layers.size() >= 100: return false
	var source: Dictionary = layers[index]
	var image_bytes := embedded_image_bytes()
	for object in source.objects:
		if object.kind == "image": image_bytes += object.image_data.length()
	if image_bytes > MAX_IMAGE_PAYLOAD: return false
	checkpoint()
	var copy := source.duplicate(true)
	copy.id = uid()
	copy.name = (source.name + " copy").left(120)
	if copy.get("merge_touching", false): copy.merge_batch = uid()
	var renamed_groups := {}
	var artwork_groups := {}
	for object in copy.objects:
		object.id = uid()
		object.erase("merge_batch")
		remap_artwork_group(object, artwork_groups)
		for group in object.get("opacity_groups", []):
			if not renamed_groups.has(group.id): renamed_groups[group.id] = uid()
			group.id = renamed_groups[group.id]
	active = index + 1
	layers.insert(active, copy)
	selection = ""
	commit()
	return true

func toggle_layer_flag(index: int, flag: String) -> void:
	if index < 0 or index >= layers.size() or flag not in ["visible", "locked"]: return
	var layer: Dictionary = layers[index]
	var previous: bool = layer[flag]
	push_history({"layer_flag": flag, "layer": layer.id, "values": [previous, not previous]})
	future.clear()
	apply_layer_flag(layer.id, flag, not previous)

func apply_layer_flag(layer_id: String, flag: String, value: bool) -> void:
	var index := layer_index(layer_id)
	if index < 0: return
	layers[index][flag] = value
	selection = ""
	commit({}, [], {"layer": layer_id, "layer_flag": flag})

func set_layer_opacity(index: int, value: float) -> void:
	if index < 0 or index >= layers.size() or layers[index].locked: return
	var opacity := clampf(value, 0.0, 1.0)
	if is_equal_approx(layers[index].get("opacity", 1.0), opacity): return
	checkpoint()
	layers[index].opacity = opacity
	commit()

func set_alpha_lock(index: int, enabled: bool) -> void:
	if index < 0 or index >= layers.size() or layers[index].locked: return
	if layers[index].get("alpha_locked", false) == enabled: return
	checkpoint()
	if enabled: layers[index].alpha_locked = true
	else: layers[index].erase("alpha_locked")
	commit()

func set_merge_touching(index: int, enabled: bool) -> bool:
	if index < 0 or index >= layers.size(): return false
	var layer: Dictionary = layers[index]
	if layer.locked or layer.get("type", "vector") != "vector": return false
	if layer.get("merge_touching", false) == enabled: return true
	checkpoint()
	if enabled:
		layer.merge_touching = true
		layer.merge_batch = uid()
	else:
		layer.erase("merge_touching")
		layer.erase("merge_batch")
	commit()
	return true

func visible_layers() -> Array[int]:
	var indices: Array[int] = []
	for index in layers.size():
		if layers[index].visible: indices.append(index)
	return indices

func can_merge_layers(indices: Array[int]) -> bool:
	if indices.size() < 2: return false
	var previous := -1
	for index in indices:
		if index <= previous or index >= layers.size() or not layers[index].visible or layers[index].locked: return false
		if previous >= 0:
			for skipped in range(previous + 1, index):
				if layers[skipped].visible: return false
		previous = index
		if layers[index].get("opacity", 1.0) < 1.0:
			for object in layers[index].objects:
				if object.get("opacity_groups", []).size() >= 32: return false
	return true

func merge_layers(indices: Array[int]) -> bool:
	if not can_merge_layers(indices): return false
	var all_paint := indices.all(func(index): return layers[index].get("type", "vector") == "paint")
	var paint_objects := []
	if all_paint:
		var chosen: Array[Dictionary] = []
		var bytes := embedded_image_bytes()
		for index in indices:
			chosen.append(layers[index])
			for tile in layers[index].objects: bytes -= tile.image_data.length()
		paint_objects = PaintTiles.new().merge_layers(chosen)
		for tile in paint_objects: bytes += tile.image_data.length()
		if bytes > MAX_IMAGE_PAYLOAD: return false
	checkpoint()
	var result: Dictionary = layers[indices[0]]
	if all_paint:
		for tile in paint_objects: tile.id = uid()
		result.objects = paint_objects
	else:
		result.objects = merged_vector_objects(indices)
		if indices.any(func(index): return layers[index].get("type", "vector") != "vector"):
			result.type = "composite"
	result.opacity = 1.0
	result.erase("alpha_locked")
	for offset in range(indices.size() - 1, 0, -1):
		layers.remove_at(indices[offset])
	active = indices[0]
	selection = ""
	commit()
	return true

func merged_vector_objects(indices: Array[int]) -> Array:
	var merged := []
	for index in indices:
		var source: Dictionary = layers[index]
		var alpha: float = source.get("opacity", 1.0)
		var group := {"id": uid(), "opacity": alpha} if alpha < 1.0 else {}
		for object in source.objects:
			if not group.is_empty():
				# Preserve the compositing of overlapping marks from this layer.
				object.opacity_groups = [group] + object.get("opacity_groups", [])
			merged.append(object)
	return merged

func rename_layer(index: int, next: String) -> void:
	if index < 0 or index >= layers.size() or layers[index].locked or next.is_empty() or layers[index].name == next: return
	checkpoint()
	layers[index].name = next
	commit()

func remove_layer(index: int) -> bool:
	if index < 0 or index >= layers.size() or layers.size() <= 1 or layers[index].locked: return false
	checkpoint()
	layers.remove_at(index)
	if active > index: active -= 1
	elif active == index: active = mini(index, layers.size() - 1)
	selection = ""
	commit()
	return true

func set_paper_visible(visible: bool) -> void:
	if paper_visible == visible: return
	checkpoint()
	paper_visible = visible
	commit()

func move_layer(source: int, destination: int) -> void:
	if source < 0 or source >= layers.size(): return
	if destination < 0 or destination >= layers.size() or source == destination: return
	if layers[source].locked: return
	var before := layers.map(func(layer): return layer.id)
	var active_id: String = layers[active].id
	var layer: Dictionary = layers.pop_at(source)
	layers.insert(destination, layer)
	active = layer_index(active_id)
	push_history({"layer_order": [before, layers.map(func(entry): return entry.id)], "active_id": active_id})
	future.clear()
	commit({}, [], {"layer_order": true})

func delete_selected() -> void:
	var items := selected_items()
	if items.is_empty(): return
	var change := {"membership": {}, "adding": false, "active_id": layers[active].id}
	var selected_by_layer := {}
	for item in items:
		var id: String = item.layer.id
		if not selected_by_layer.has(id): selected_by_layer[id] = {}
		selected_by_layer[id][item.object.id] = true
	for id in selected_by_layer:
		var layer: Dictionary = layers[layer_index(id)]
		var wanted: Dictionary = selected_by_layer[id]
		var kept := []
		var slots := []
		for index in layer.objects.size():
			var object: Dictionary = layer.objects[index]
			if wanted.has(object.id): slots.append({"index": index, "object": object.duplicate(true)})
			else: kept.append(object)
		change.membership[id] = slots
		layer.objects = kept
	push_history(change)
	future.clear()
	selection = ""
	commit_membership(change)

func restore_membership_or_order(change: Dictionary, forward: bool) -> void:
	active = layer_index(change.active_id)
	selection = ""
	if change.has("layer_order"):
		var by_id := {}
		for layer in layers: by_id[layer.id] = layer
		layers = change.layer_order[int(forward)].map(func(id): return by_id[id])
		active = layer_index(change.active_id)
		commit({}, [], {"layer_order": true})
		return
	var insert: bool = change.adding == forward
	for id in change.membership:
		var layer: Dictionary = layers[layer_index(id)]
		var slots: Array = change.membership[id]
		if insert:
			var restored := []
			var slot_index := 0
			for object in layer.objects:
				while slot_index < slots.size() and slots[slot_index].index == restored.size():
					restored.append(slots[slot_index].object.duplicate(true))
					slot_index += 1
				restored.append(object)
			while slot_index < slots.size():
				restored.append(slots[slot_index].object.duplicate(true))
				slot_index += 1
			layer.objects = restored
		else:
			var ids := {}
			for slot in slots: ids[slot.object.id] = true
			layer.objects = layer.objects.filter(func(object): return not ids.has(object.id))
	commit_membership(change)

func commit_membership(change: Dictionary) -> void:
	var affected: Array = change.membership.keys()
	commit({}, [], {"layers": affected, "resync": affected})

func layer_transfer_items(solo_layer_id := "") -> Array[Dictionary]:
	var items := selected_items()
	var expected := area_selection.size() if selection.is_empty() else 1
	if items.size() != expected: return []
	var groups := {}
	var selected_ids := {}
	for item in items:
		var object: Dictionary = item.object
		if object.get("paint_tile", false) or (not solo_layer_id.is_empty() and item.layer.id != solo_layer_id):
			return []
		selected_ids[object.id] = true
		if object.has("artwork_group"): groups[object.artwork_group] = true
	if not groups.is_empty():
		for layer in layers:
			for object in layer.objects:
				if groups.has(object.get("artwork_group")) and not selected_ids.has(object.id): return []
	return items

func can_receive_selection(layer: Dictionary, items: Array[Dictionary]) -> bool:
	if not layer.visible or layer.locked or layer.get("alpha_locked", false): return false
	if layer.get("type", "vector") not in ["vector", "composite"]: return false
	return items.any(func(item): return item.layer.id != layer.id)

func can_create_selection_layer(items: Array[Dictionary]) -> bool:
	if items.is_empty() or layers.size() >= 100: return false
	if items[0].layer.id == items[-1].layer.id: return true
	for item in items:
		if item.layer.get("opacity", 1.0) < 1.0 and item.object.get("opacity_groups", []).size() >= 32:
			return false
	return true

func move_selection_to_layer(destination_id := "", solo_layer_id := "") -> bool:
	var items := layer_transfer_items(solo_layer_id)
	if items.is_empty(): return false
	var destination_index := layer_index(destination_id)
	var new_target := destination_id.is_empty()
	var spans_layers: bool = items[0].layer.id != items[-1].layer.id
	var target: Dictionary
	if new_target:
		if not can_create_selection_layer(items): return false
		destination_index = layer_index(items[-1].layer.id) + 1
		target = new_layer("Selection")
		if not spans_layers:
			target.opacity = items[0].layer.get("opacity", 1.0)
	else:
		if destination_index < 0 or not can_receive_selection(layers[destination_index], items): return false
		target = layers[destination_index]

	checkpoint()
	if new_target: layers.insert(destination_index, target)
	var removed := {}
	var opacity_scopes := {}
	var scope_ids := {}
	var moved_ids: Array[String] = []
	for item in items:
		var object: Dictionary = item.object
		var source: Dictionary = item.layer
		moved_ids.append(object.id)
		if source.id == target.id: continue
		if not removed.has(source.id): removed[source.id] = {}
		removed[source.id][object.id] = true
		object.erase("merge_batch")
		var scopes: Array = []
		if new_target and spans_layers and source.get("opacity", 1.0) < 1.0:
			if not opacity_scopes.has(source.id):
				opacity_scopes[source.id] = {"id": uid(), "opacity": source.opacity}
			scopes.append(opacity_scopes[source.id])
		for scope in object.get("opacity_groups", []):
			var key: String = source.id + ":" + scope.id
			if not scope_ids.has(key): scope_ids[key] = uid()
			scopes.append({"id": scope_ids[key], "opacity": scope.opacity})
		if not scopes.is_empty(): object.opacity_groups = scopes
		target.objects.append(object)
	for source_id in removed:
		var source: Dictionary = layers[layer_index(source_id)]
		var ids: Dictionary = removed[source_id]
		source.objects = source.objects.filter(func(object): return not ids.has(object.id))
	active = destination_index
	select_objects(moved_ids)
	commit()
	return true

func duplicate_selected() -> void:
	var items := selected_items()
	if items.is_empty(): return
	var projected_images := embedded_image_bytes()
	var count := items.size()
	for layer in layers: count += layer.objects.size()
	if count > MAX_OBJECTS: return
	for item in items:
		if item.object.kind == "image": projected_images += item.object.image_data.length()
	if projected_images > MAX_IMAGE_PAYLOAD: return
	var change := {"membership": {}, "adding": true, "active_id": layers[active].id}
	var ids: Array[String] = []
	var groups := {}
	var artwork_groups := {}
	for item in items:
		var copy: Dictionary = item.object.duplicate(true)
		copy.id = uid()
		copy.erase("merge_batch")
		remap_artwork_group(copy, artwork_groups)
		for group in copy.get("opacity_groups", []):
			var key: String = item.layer.id + "::" + group.id
			if not groups.has(key): groups[key] = uid()
			group.id = groups[key]
		copy.pos = [copy.pos[0] + 24, copy.pos[1] + 24]
		if not change.membership.has(item.layer.id): change.membership[item.layer.id] = []
		change.membership[item.layer.id].append({"index": item.layer.objects.size(), "object": copy.duplicate(true)})
		item.layer.objects.append(copy)
		ids.append(copy.id)
	push_history(change)
	future.clear()
	select_objects(ids)
	commit_membership(change)

func remap_artwork_group(object: Dictionary, remap: Dictionary) -> void:
	if not object.has("artwork_group"): return
	var key: String = object.artwork_group
	if not remap.has(key): remap[key] = uid()
	object.artwork_group = remap[key]

func has_pixel_paint() -> bool:
	return layers.any(func(layer): return layer.get("type", "vector") == "paint" and not layer.objects.is_empty())

func resize_canvas(dimensions: Vector2i, mode: ResizeArtwork = ResizeArtwork.KEEP) -> Error:
	if dimensions.x < MIN_CANVAS_SIZE or dimensions.y < MIN_CANVAS_SIZE or dimensions.x > MAX_CANVAS_SIZE or dimensions.y > MAX_CANVAS_SIZE:
		return ERR_INVALID_PARAMETER
	if width == dimensions.x and height == dimensions.y: return OK
	if mode == ResizeArtwork.FIT and has_pixel_paint(): return ERR_UNAVAILABLE

	var old_size := Vector2(width, height)
	var new_size := Vector2(dimensions)
	var has_paint := has_pixel_paint()
	var factor := minf(new_size.x / old_size.x, new_size.y / old_size.y)
	var center_offset := (new_size - old_size * factor) * 0.5
	var paint_bounds := {}
	if mode == ResizeArtwork.COMPOSITION:
		var composition := composition_bounds(paint_bounds)
		if composition.has("error"): return composition.error
		var content: Rect2 = composition.bounds
		if not content.has_area(): content = Rect2(Vector2.ZERO, old_size)
		factor = minf(1.0, minf(new_size.x / content.size.x, new_size.y / content.size.y))
		var location := Vector2(
			adapted_axis(content.position.x, content.size.x, old_size.x, new_size.x, factor),
			adapted_axis(content.position.y, content.size.y, old_size.y, new_size.y, factor))
		center_offset = location.clamp(Vector2.ZERO, (new_size - content.size * factor).max(Vector2.ZERO)) - content.position * factor
		if factor == 1.0 and has_paint:
			# Align to the paint grid while keeping every vector on the same transform.
			center_offset = center_offset.round()
	var layout := adapted_layout_offsets(old_size, new_size, factor) if mode == ResizeArtwork.ADAPT else {}
	var next_layers: Array = []
	var image_bytes := 0
	for layer in layers:
		var next: Dictionary = layer.duplicate()
		if layer.get("type", "vector") == "paint":
			var changed_bounds := PaintTiles.new().transform_artwork(layer, dimensions, paint_bounds[layer.id], factor, center_offset) \
				if mode == ResizeArtwork.COMPOSITION else PaintTiles.resize_bounds(layer, dimensions)
			if changed_bounds.has("error"): return changed_bounds.error
			next.objects = changed_bounds.objects
			for object in next.objects:
				if not object.has("id"): object.id = uid()
		elif mode != ResizeArtwork.KEEP:
			var scaled := []
			for object in layer.objects:
				var offset: Vector2 = center_offset
				if mode == ResizeArtwork.ADAPT:
					if object.kind == "image":
						scaled.append(object)
						continue
					offset = layout[layout_unit(object)]
				var mark: Dictionary = object.duplicate()
				var position := Art.v(object.pos) * factor + offset
				mark.pos = [position.x, position.y]
				mark.scale = float(object.scale) * factor
				if not pair(mark.pos) or mark.scale <= 0.0 or mark.scale > 1000.0: return ERR_INVALID_DATA
				scaled.append(mark)
			next.objects = scaled
		for object in next.objects:
			if object.kind == "image": image_bytes += object.image_data.length()
		if image_bytes > MAX_IMAGE_PAYLOAD: return ERR_OUT_OF_MEMORY
		next_layers.append(next)
	if not has_paint:
		var transforms := {}
		for index in layers.size():
			var layer: Dictionary = layers[index]
			var resized: Array = next_layers[index].objects
			var poses := {}
			for object_index in layer.objects.size():
				var object: Dictionary = layer.objects[object_index]
				var next: Dictionary = resized[object_index]
				if object.pos == next.pos and object.scale == next.scale: continue
				poses[object.id] = [[object.pos.duplicate(), object.scale, object.get("angle"), object.get("mirrored")],
					[next.pos.duplicate(), next.scale, next.get("angle"), next.get("mirrored")]]
			if not poses.is_empty(): transforms[layer.id] = poses
		var change := {"transform": transforms, "page_sizes": [old_size, new_size], "active_id": layers[active].id}
		push_history(change)
		future.clear()
		restore_transform(change, true)
		return OK
	checkpoint()
	width = float(dimensions.x)
	height = float(dimensions.y)
	layers = next_layers
	selection = ""
	commit()
	return OK

func composition_bounds(paint_bounds: Dictionary) -> Dictionary:
	var result := Rect2()
	for layer in layers:
		if layer.get("type", "vector") == "paint":
			var paint := PaintTiles.artwork_bounds(layer)
			if paint.has("error"): return paint
			paint_bounds[layer.id] = paint.bounds
			var area := Rect2(paint.bounds)
			if area.has_area(): result = result.merge(area) if result.has_area() else area
			continue
		for object in layer.objects:
			var area := Art.coverage_bounds(object)
			if area.has_area(): result = result.merge(area) if result.has_area() else area
	return {"bounds": result}

func adapted_layout_offsets(old_size: Vector2, new_size: Vector2, factor: float) -> Dictionary:
	var bounds_by_unit := {}
	for layer in layers:
		for object in layer.objects:
			if object.kind == "image": continue
			var unit := layout_unit(object)
			var bounds := Art.bounds(object)
			if bounds_by_unit.has(unit):
				bounds = bounds.merge(bounds_by_unit[unit])
			bounds_by_unit[unit] = bounds

	var offsets := {}
	for unit in bounds_by_unit:
		var bounds: Rect2 = bounds_by_unit[unit]
		var start := Vector2(
			adapted_axis(bounds.position.x, bounds.size.x, old_size.x, new_size.x, factor),
			adapted_axis(bounds.position.y, bounds.size.y, old_size.y, new_size.y, factor))
		offsets[unit] = start - bounds.position * factor
	return offsets

func layout_unit(object: Dictionary) -> String:
	if object.has("artwork_group"): return "group:" + object.artwork_group
	return "object:" + object.id

static func adapted_axis(start: float, extent: float, old_length: float, new_length: float, factor: float) -> float:
	var free_space := old_length - extent
	# Match the item's position between the two edges, after accounting for its size.
	if free_space > 0.001 and start >= 0.0 and start <= free_space:
		return start / free_space * (new_length - extent * factor)
	# Full-page and partly off-page artwork follows its relative center.
	return (start + extent * 0.5) / old_length * new_length - extent * factor * 0.5

func blank(w = 900.0, h = 1100.0, background_visible := true, first_layer := "vector") -> void:
	width = float(w)
	height = float(h)
	title = "Untitled illustration"
	paper_visible = background_visible
	layers = [new_layer("Paint" if first_layer == "paint" else "Illustration", first_layer)]
	active = 0
	selection = ""
	history.clear()
	future.clear()
	dirty = false
	changed.emit()

func encode_for_save() -> PackedByteArray:
	var save_state := snapshot(false)
	for layer in layers:
		if not layer.objects.any(func(object): return object.get("compound_disjoint", false)): continue
		save_state.version = DISJOINT_COMPOUND_VERSION
		break
	for layer in layers:
		if not layer.objects.any(Art.has_orientation): continue
		save_state.version = ORIENTED_OBJECT_VERSION
		break
	return JSON.stringify(save_state, "", false).to_utf8_buffer()

func save_to(path: String) -> Error:
	return save_encoded_to(path, encode_for_save())

func save_encoded_to(path: String, encoded: PackedByteArray) -> Error:
	if encoded.size() > MAX_PROJECT_BYTES: return ERR_OUT_OF_MEMORY
	# Android's Storage Access Framework returns opaque content URIs.
	# They cannot be renamed or have extensions appended. Keep an internal
	# staged copy, then write exactly the URI selected by the user.
	if path.begins_with("content://"):
		var staged := write_project_file("user://external-save-recovery.havu", encoded)
		if staged != OK: return staged
		var external_file = FileAccess.open(path, FileAccess.WRITE)
		if external_file == null: return FileAccess.get_open_error()
		external_file.store_buffer(encoded)
		external_file.flush()
		var external_result = external_file.get_error()
		external_file.close()
		dirty = external_result != OK
		return external_result
	var result := write_project_file(path, encoded)
	if result == OK: dirty = false
	return result

func write_project_file(path: String, encoded: PackedByteArray) -> Error:
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(encoded)
	file.flush()
	var write_result = file.get_error()
	file.close()
	if write_result != OK: return write_result
	return DirAccess.rename_absolute(temporary, path)

func load_from(path: String) -> String:
	var result := read_project(path)
	if result.has("error"): return result.error
	restore(result.project, false)
	history.clear()
	future.clear()
	dirty = false
	changed.emit()
	return ""

static func read_project(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "Project could not be opened: " + error_string(FileAccess.get_open_error())}
	if file.get_length() > MAX_PROJECT_BYTES:
		file.close()
		return {"error": "Project exceeds the 64 MB beta limit."}
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(contents) != OK: return {"error": "This is not a valid Havu project."}
	var error := validate(parser.data)
	return {"project": parser.data} if error.is_empty() else {"error": error}

static func validate(data) -> String:
	if not data is Dictionary or data.get("format") != "havu" or (data.get("version") != VERSION and data.get("version") != DISJOINT_COMPOUND_VERSION and data.get("version") != ORIENTED_OBJECT_VERSION):
		return "Unsupported project format."
	if not data.get("title") is String or data.title.length() > 300: return "Invalid title."
	for key in ["width", "height"]:
		if not numeric(data.get(key)) or data[key] < MIN_CANVAS_SIZE or data[key] > MAX_CANVAS_SIZE:
			return "Invalid canvas size."
	if not valid_color(data.get("paper")) or not data.get("paper_visible", true) is bool: return "Invalid background."
	if not data.get("layers") is Array or data.layers.is_empty() or data.layers.size() > 100: return "Invalid layer list."
	var count = 0
	var ids = {}
	var image_size := 0
	var checked_images := {}
	for layer in data.layers:
		if not layer is Dictionary or not layer.get("objects") is Array or not layer.get("name") is String or not layer.get("id") is String: return "Invalid layer."
		if not layer.get("visible") is bool or not layer.get("locked") is bool: return "Invalid layer state."
		if layer.get("type", "vector") not in ["paint", "vector", "composite"]: return "Invalid layer type."
		var paint_origins := {}
		if not layer.get("alpha_locked", false) is bool: return "Invalid transparency lock."
		if not layer.get("merge_touching", false) is bool: return "Invalid Merge touching setting."
		if layer.get("merge_touching", false) and not valid_group_id(layer.get("merge_batch")): return "Invalid drawing batch."
		var layer_opacity = layer.get("opacity", 1.0)
		if not numeric(layer_opacity) or layer_opacity < 0 or layer_opacity > 1: return "Invalid layer opacity."
		for object in layer.objects:
			count += 1
			if count > MAX_OBJECTS: return "Project has too many objects."
			if not object is Dictionary or not object.get("id") is String or ids.has(object.id): return "Invalid object ID."
			ids[object.id] = true
			if object.get("kind") not in ["stroke", "rect", "ellipse", "text", "polygon", "path", "image"]: return "Unsupported object type."
			if not object.get("paint_tile", false) is bool: return "Invalid paint tile."
			if object.has("compound") and (object.kind != "polygon" or not object.compound is bool):
				return "Invalid compound outline."
			if object.has("compound_disjoint") and (not object.get("compound", false) or object.compound_disjoint != true):
				return "Invalid disconnected compound outline."
			if object.has("artwork_group") and (object.kind == "image" or not valid_group_id(object.artwork_group)):
				return "Invalid artwork group."
			if object.has("merge_batch") and (object.kind == "image" or not valid_group_id(object.merge_batch)):
				return "Invalid drawing batch."
			if layer.get("type", "vector") == "paint" and (object.kind != "image" or not object.get("paint_tile", false)):
				return "A paint layer contains an invalid mark."
			if not pair(object.get("pos")) or not numeric(object.get("scale")) or object.scale <= 0 or object.scale > 1000: return "Invalid object transform."
			if object.has("angle") and (not numeric(object.angle) or absf(object.angle) > PI + 0.000001):
				return "Invalid rotation angle."
			if object.has("mirrored") and not object.mirrored is bool: return "Invalid reflected orientation."
			if object.get("paint_tile", false) and Art.has_orientation(object): return "Invalid paint tile orientation."
			if not valid_color(object.get("color")): return "Invalid object color."
			if not numeric(object.get("opacity")) or object.opacity < 0 or object.opacity > 1: return "Invalid opacity."
			if object.has("opacity_groups") and not valid_opacity_groups(object.opacity_groups): return "Invalid opacity groups."
			if object.has("clip") and not point_list(object.clip, 3): return "Invalid clipping region."
			if object.has("paint_mask") and (object.kind != "stroke" or not valid_paint_mask(object.paint_mask)): return "Invalid paint mask."
			if object.kind in ["rect", "ellipse", "polygon", "path"]:
				if not object.get("fill_enabled", true) is bool: return "Invalid shape fill."
				if object.has("outline_width"):
					if not numeric(object.outline_width) or object.outline_width <= 0 or object.outline_width > 300: return "Invalid outline width."
					if not valid_color(object.get("outline_color")): return "Invalid outline color."
				if (object.kind == "path" or not object.get("fill_enabled", true)) and not object.has("outline_width"): return "Shape has no paint."
			match object.kind:
				"stroke":
					if not object.get("continuous_edges", false) is bool: return "Invalid brush edges."
					if not object.get("points") is Array or object.points.is_empty() or object.points.size() > 100000: return "Invalid stroke points."
					if not numeric(object.get("size")) or object.size < 0.1 or object.size > 1000: return "Invalid brush size."
					if object.get("brush") not in BrushLibrary.ENGINES: return "Unknown brush."
					if not BrushLibrary.valid_profile(object): return "Invalid brush profile."
					for point in object.points:
						if not point is Array or point.size() != 4 or not numeric(point[0]) or not numeric(point[1]) or not numeric(point[2]) or point[2] < 0 or point[2] > 1 or not valid_color(point[3]): return "Invalid stroke sample."
				"image":
					if object.has("clip") or not pair(object.get("extent")): return "Invalid image layer."
					if layer.get("type", "vector") == "paint":
						var origin := Vector2i(object.pos[0], object.pos[1])
						var page := Vector2i(ceili(data.width), ceili(data.height))
						var extent := (page - origin).min(Vector2i.ONE * PaintTiles.TILE_SIZE)
						var aligned := origin == (origin / PaintTiles.TILE_SIZE) * PaintTiles.TILE_SIZE
						if (not aligned or not Rect2i(Vector2i.ZERO, page).has_point(origin) or paint_origins.has(origin)
								or object.pos[0] != origin.x or object.pos[1] != origin.y
								or object.extent[0] != extent.x or object.extent[1] != extent.y or object.scale != 1.0):
							return "Invalid paint tile position."
						paint_origins[origin] = true
					if not object.get("image_data") is String or not object.get("image_key") is String or object.get("image_format") not in ["png", "jpeg", "webp"]: return "Missing image data."
					if object.image_data.length() > ceili(Raster.MAX_FILE_BYTES / 3.0) * 4: return "An embedded image exceeds the size limit."
					image_size += object.image_data.length()
					if image_size > MAX_IMAGE_PAYLOAD: return "This project contains too much embedded image data."
					if object.image_data.sha256_text() != object.image_key: return "Invalid embedded image."
					var image_metadata: Array = [object.extent, object.image_format]
					if checked_images.has(object.image_key):
						if checked_images[object.image_key] != image_metadata: return "Conflicting image metadata."
					else:
						var bytes := Marshalls.base64_to_raw(object.image_data)
						if Marshalls.raw_to_base64(bytes) != object.image_data: return "Invalid embedded image encoding."
						var image = Raster.decode(bytes, object.image_format)
						if not image or Vector2i(object.extent[0], object.extent[1]) != image.get_size(): return "Invalid embedded image dimensions."
						Raster.remember(object.image_key, image)
						checked_images[object.image_key] = image_metadata
				"rect", "ellipse":
					if not pair(object.get("extent")): return "Invalid shape size."
					if object.has("corner_radius") and (not numeric(object.corner_radius) or object.corner_radius < 0):
						return "Invalid corner radius."
				"polygon":
					if not point_list(object.get("vertices"), 3): return "Invalid polygon."
				"path":
					if not point_list(object.get("vertices"), 2) or not object.get("arrow", false) is bool: return "Invalid path."
				"text":
					if not object.get("text") is String or object.text.length() > 10000: return "Invalid text."
					if not numeric(object.get("font_size")) or object.font_size < 4 or object.font_size > 500: return "Invalid text size."
					if not Fonts.valid_id(object.get("font")): return "Invalid font."
					for key in ["font_label", "font_family"]:
						if not object.get(key, "") is String or object.get(key, "").length() > 120:
							return "Invalid font name."
					var weight = object.get("font_weight", 400)
					if not numeric(weight) or weight < 1 or weight > 1000 or not object.get("font_italic", false) is bool:
						return "Invalid font style."
			if object.has("node_anchors"):
				if object.kind not in ["stroke", "path", "polygon"]: return "Invalid node anchors."
				var samples: Array = object.points if object.kind == "stroke" else object.vertices
				if not valid_node_anchors(object.node_anchors, samples.size()): return "Invalid node anchors."

	return ""

static func valid_group_id(value) -> bool:
	return value is String and not value.is_empty() and value.length() <= 120

static func valid_node_anchors(value, count: int) -> bool:
	if not value is Array or value.size() > count: return false
	var previous := -1
	for index in value:
		if not numeric(index) or index != int(index) or index <= previous or index >= count: return false
		previous = int(index)
	return true

static func numeric(value) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and absf(float(value)) < 1000000

static func valid_opacity_groups(value) -> bool:
	if not value is Array or value.size() > 32: return false
	for group in value:
		if not group is Dictionary or not group.get("id") is String or not numeric(group.get("opacity")): return false
		if group.opacity < 0.0 or group.opacity >= 1.0: return false
	return true

static func valid_paint_mask(value) -> bool:
	if not value is Array or value.is_empty() or value.size() > 256: return false
	var total := 0
	for contour in value:
		if not point_list(contour, 3): return false
		total += contour.size()
	return total <= 24000

static func pair(value) -> bool:
	return value is Array and value.size() == 2 and numeric(value[0]) and numeric(value[1])

static func point_list(value, minimum) -> bool:
	if not value is Array or value.size() < minimum or value.size() > 100000: return false
	for point in value:
		if not pair(point): return false
	return true

static func valid_color(value) -> bool:
	return value is String and value.length() in [7, 9] and value.begins_with("#") and value.substr(1).is_valid_hex_number(false)
