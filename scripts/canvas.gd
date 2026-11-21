extends Control
const Art = preload("res://scripts/artwork.gd")
const VectorFill = preload("res://scripts/vector_fill.gd")
const Document = preload("res://scripts/document.gd")
const PigmentIndex = preload("res://scripts/pigment_index.gd")
const BrushLibrary = preload("res://scripts/brush_library.gd")
const OpacityStack = preload("res://scripts/opacity_stack.gd")
const IsolatedOpacity = preload("res://scripts/isolated_opacity.gd")
const AreaSelection = preload("res://scripts/area_selection.gd")
const AREA_TOOLS := AreaSelection.TOOLS
const SELECTION_PADDING := 5.0
const RESIZE_HIT_RADIUS := 16.0
const PAINT_CACHE_THRESHOLD := 1200
const WET_PIGMENT_SPACING := 0.26
const ANDROID_POINTER_IDLE := 0.18
const DEFAULT_STROKE_NODE_SPREAD := 0.25
const SHAPE_TOOLS := {
	"rect": "rect", "square": "rect", "rounded_rect": "rect", "ellipse": "ellipse", "circle": "ellipse",
	"triangle": "polygon", "diamond": "polygon", "star": "polygon", "line": "path", "arrow": "path", "path": "path",
}
signal path_changed
signal node_mode_changed
signal status(message)
signal selected(object)
signal color_used(value: Color)
signal view_changed
var document:
	set(value):
		if document != null and document.changed.is_connected(on_artwork_changed):
			document.changed.disconnect(on_artwork_changed)
		document = value
		if document != null and not exporting:
			document.changed.connect(on_artwork_changed)
			sync_artwork()
var tool = "brush"
var brush = "ink"
var brush_profile: Dictionary = {}
var shape_settings := {"fill_enabled": true, "outline_enabled": false, "outline_color": null,
	"outline_width": 4.0, "opacity": 1.0}
var path_points := PackedVector2Array()
var marquee_active := false
var marquee_end := Vector2.ZERO
var lasso_points := PackedVector2Array()
var selected_area := PackedVector2Array()
var moving_selection: Array[Dictionary] = []
var selection_move_bounds := Rect2()
var selection_preview_bounds := Rect2()
var selection_scale_min := 0.02
var selection_scale_max := 1000.0
var color = Color("#226451")
var brush_size = 18.0
var opacity = 1.0
var blending = 0.65
var smoothing = 0.35
var stroke_mixing := 0.65
var stroke_pigment := Color.WHITE
var stroke_pigment_hex := ""
var stroke_smoothing := 0.35
var stroke_lag_limit := 0.0
var pressure_enabled = true
var pen_button_tools := {}
var pen_shortcut_contact := Callable()
var touch_paints = false
var manage_input_accumulation := true
var clip_enabled = false
var clip_regions: Array = []
var zoom = 0.65
var fit_padding := Vector2(86, 68)
var ui_scale := 1.0
var origin = Vector2.ZERO
var view_fitted := true
var last_page_size := Vector2.ZERO
var previous_view_size := Vector2.ZERO
var drawing = false
var current: Dictionary = {}
var start = Vector2.ZERO
var raw_point := Vector2.ZERO
var raw_pressure := 0.55
var input_was_accumulated := true
var last_brush_activity := -10000
var last_pressure = 0.55
var metrics_pointer := Vector2.INF
var metrics_pressure := -1.0
var carry = Color.WHITE
var sampled_pigment := Color.WHITE
var pigment_sample_point := Vector2.ZERO
var pigment_spacing_squared := 0.0
var android_pointer_idle: Timer
var android_pointer_unbuffered := false
var dragging = false
var moving = false
var resizing = false
var adding_node := false
var stroke_node_spread := DEFAULT_STROKE_NODE_SPREAD
var path_node_spread := 0.0
var node_index = -1
var node_arc := PackedFloat64Array()
var node_twins: Array = []
var node_cycle := 0.0
var node_reach := 0.0
var original: Dictionary = {}
var edit_started = false
var edit_future: Array = []
var artwork_root: Node2D
var preview_root: Node2D
var selection_overlay: Node2D
var retained_marks: Dictionary = {}
var layer_renderers: Dictionary = {}
var solo_layer_id := ""
var merge_renderers: Dictionary = {}
var cache_completed_paint := OS.has_feature("android")
var paint_cache: IsolatedOpacity
var overview_cache := false
var opacity_preview_layer := ""
var opacity_preview_value := 1.0
static var checker_texture: ImageTexture
var live_batch: Node2D
var live_first := 0
var pigment := PigmentIndex.new()
var pigment_dirty := true
var touch_points: Dictionary = {}
var touch_navigating := false
var touch_tap_tool := ""
var touch_start := Vector2.ZERO
var touch_tap_moved := false
var exporting = false
var text_content = "A little something lovely"
var text_font = "serif"
var text_size = 42.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	set_process_input(false)
	mouse_exited.connect(clear_pointer_metrics)
	resized.connect(resize_view)
	artwork_root = Node2D.new()
	add_child(artwork_root)
	if not exporting and OS.has_feature("android"):
		android_pointer_idle = Timer.new()
		android_pointer_idle.one_shot = true
		android_pointer_idle.timeout.connect(restore_android_pointer_buffering)
		add_child(android_pointer_idle)
	if not exporting:
		preview_root = Node2D.new()
		add_child(preview_root)
		selection_overlay = Node2D.new()
		selection_overlay.draw.connect(draw_selection)
		add_child(selection_overlay)
	sync_artwork()

func resize_view() -> void:
	if exporting: return
	var old_size := previous_view_size
	previous_view_size = size
	if document == null: return
	if old_size != Vector2.ZERO and old_size != size:
		if marquee_active:
			marquee_active = false
			lasso_points.clear()
		if drawing or moving or resizing or node_index >= 0: finish()
		dragging = false
		reset_touch()
	if view_fitted or old_size == Vector2.ZERO:
		fit()
	else:
		origin += (size - old_size) * 0.5
		redraw_view()

func fit() -> void:
	if document == null: return
	view_fitted = true
	previous_view_size = size
	zoom = minf((size.x - fit_padding.x) / document.width, (size.y - fit_padding.y) / document.height)
	zoom = maxf(zoom, 0.05)
	origin = (size - Vector2(document.width, document.height) * zoom) * 0.5
	redraw_view()
	view_changed.emit()

func zoom_at(factor: float, screen: Vector2) -> void:
	view_fitted = false
	var anchor = to_document(screen)
	zoom = clampf(zoom * factor, 0.05 / ui_scale, 12.0 / ui_scale)
	origin = screen - anchor * zoom
	redraw_view()
	view_changed.emit()

func visible_zoom() -> float:
	return zoom * ui_scale

func set_ui_scale(factor: float) -> void:
	if is_equal_approx(ui_scale, factor): return
	if not view_fitted:
		var center := to_document(size * 0.5)
		zoom *= ui_scale / factor
		origin = size * 0.5 - center * zoom
	ui_scale = factor
	redraw_view()
	view_changed.emit()

func pan_by(delta: Vector2) -> void:
	if delta.is_zero_approx(): return
	view_fitted = false
	origin += delta
	redraw_view()

func to_document(point: Vector2) -> Vector2:
	return (point - origin) / zoom

func _draw() -> void:
	if document == null: return
	if not exporting:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#111111"))
		# Subtle drafting grid, kept outside the exported page.
		for x in range(18, int(size.x), 28):
			for y in range(18, int(size.y), 28): draw_circle(Vector2(x, y), 0.6, Color("#252525"))
		draw_rect(Rect2(origin + Vector2(6, 9), Vector2(document.width, document.height) * zoom), Color(0, 0, 0, 0.24))
	var page := Rect2(origin, Vector2(document.width, document.height) * zoom)
	if document.paper_visible:
		draw_rect(page, Color(document.paper))
	elif not exporting:
		if checker_texture == null:
			var tile := Image.create_empty(20, 20, false, Image.FORMAT_RGBA8)
			tile.fill(Color("#d8d5ce"))
			tile.fill_rect(Rect2i(0, 0, 10, 10), Color("#f5f2ed"))
			tile.fill_rect(Rect2i(10, 10, 10, 10), Color("#f5f2ed"))
			checker_texture = ImageTexture.create_from_image(tile)
		var visible_page := page.intersection(Rect2(Vector2.ZERO, size))
		if visible_page.has_area(): draw_texture_rect(checker_texture, visible_page, true)

func draw_selection() -> void:
	if document == null: return
	if drawing and current.get("erasing", false):
		var radius := maxf(1.5, float(current.size) * zoom * 0.5)
		selection_overlay.draw_circle(origin + raw_point * zoom, radius, Color("#a4f0d2"), false, 1.2, true)
	if clip_enabled and tool == "brush":
		for region in clip_regions:
			var border := PackedVector2Array()
			for point in region: border.append(origin + Art.v(point) * zoom)
			selection_overlay.draw_polyline(Art.close_points(border), Color(0.48, 0.84, 0.68, 0.76), 1.4, true)
	if tool == "path":
		var screen_points := PackedVector2Array()
		for point in path_points: screen_points.append(origin + point * zoom)
		if screen_points.size() > 1: selection_overlay.draw_polyline(screen_points, Color("#79d7b4"), 2.0, true)
		for point in screen_points: selection_overlay.draw_circle(point, 4.5, Color("#a1f2d4"))
		return
	if marquee_active:
		var screen_outline := PackedVector2Array()
		for point in AreaSelection.outline(tool, start, marquee_end, lasso_points):
			screen_outline.append(origin + point * zoom)
		if screen_outline.size() >= 3 and screen_outline.size() <= 96 and not Geometry2D.triangulate_polygon(screen_outline).is_empty():
			selection_overlay.draw_colored_polygon(screen_outline, Color(0.38, 0.83, 0.68, 0.16))
		if screen_outline.size() >= 2:
			var border := Art.close_points(screen_outline)
			selection_overlay.draw_polyline(border, Color("#19674f"), 3, true)
			selection_overlay.draw_polyline(border, Color("#a4f0d2"), 1.4, true)
		return
	if tool != "select" and tool != "nodes" and tool not in AREA_TOOLS: return
	if not document.area_selection.is_empty() and tool != "nodes":
		var bounds := items_bounds(document.selected_items()) if moving_selection.is_empty() else selection_preview_bounds
		if bounds.has_area(): draw_multi_selection_bounds(bounds)
		return
	var object = document.find_object(document.selection)
	if object.is_empty():
		if selected_area.size() >= 3:
			var outline := PackedVector2Array()
			for point in selected_area: outline.append(origin + point * zoom)
			selection_overlay.draw_polyline(Art.close_points(outline), Color("#19674f"), 2, true)
		return
	var bounds = Art.bounds(object)
	var box = Rect2(origin + bounds.position * zoom, bounds.size * zoom)
	selection_overlay.draw_rect(box.grow(SELECTION_PADDING), Color("#67d6b0"), false, 1.2)
	if tool != "nodes":
		selection_overlay.draw_rect(Rect2(box.end - Vector2(5, 5), Vector2(10, 10)), Color("#a1f2d4"))
	elif object.kind in ["stroke", "polygon", "path"]:
		var points: Array = node_points(object)
		var added: Array = object.get("node_anchors", [])
		for index in editable_nodes(object):
			var point = origin + (Art.v(points[index]) * float(object.scale) + Art.v(object.pos)) * zoom
			var highlighted: bool = index == node_index or index in added
			var fill := Color("#a1f2d4") if highlighted else Color("#172a21")
			if node_index >= 0 and not highlighted:
				fill = fill.lerp(Color("#a1f2d4"), node_weight(index) * 0.65)
			selection_overlay.draw_circle(point, 4.5, fill)
			selection_overlay.draw_circle(point, 4.5, Color("#8be8c3"), false, 1.2, true)

func draw_multi_selection_bounds(bounds: Rect2) -> void:
	var box := Rect2(origin + bounds.position * zoom, bounds.size * zoom).grow(SELECTION_PADDING)
	var border := Art.close_points(AreaSelection.corners(box))
	selection_overlay.draw_polyline(border, Color("#19674f"), 3, true)
	selection_overlay.draw_polyline(border, Color("#a4f0d2"), 1.4, true)
	for corner in AreaSelection.corners(box):
		selection_overlay.draw_circle(corner, 3, Color("#a4f0d2"), true, -1, true)
	var handle: Vector2 = origin + bounds.end * zoom
	selection_overlay.draw_rect(Rect2(handle - Vector2(5, 5), Vector2(10, 10)), Color("#a1f2d4"))

func items_bounds(items: Array[Dictionary]) -> Rect2:
	var bounds := Rect2()
	for item in items:
		if not layer_is_visible(item.layer): continue
		var box := Art.coverage_bounds(item.object)
		bounds = bounds.merge(box) if bounds.has_area() else box
	return bounds

func update_marquee(point: Vector2) -> void:
	marquee_end = point
	if tool == "select_lasso" and lasso_points.size() < 2048 and lasso_points[-1].distance_to(point) * zoom >= 3:
		lasso_points.append(point)
	refresh_selection()

func finish_marquee() -> void:
	marquee_active = false
	if tool == "select_lasso" and lasso_points.size() > 2 and lasso_points[0].is_equal_approx(lasso_points[-1]):
		lasso_points.remove_at(lasso_points.size() - 1)
	var region := AreaSelection.outline(tool, start, marquee_end, lasso_points)
	lasso_points = PackedVector2Array()
	if region.size() < 3:
		clear_selection()
		return
	var bounds := Art.polygon_bounds(region)
	if bounds.size.x * zoom < 4 or bounds.size.y * zoom < 4:
		clear_selection()
		return
	if tool == "select_lasso" and Geometry2D.triangulate_polygon(region).is_empty():
		status.emit("Draw a single loop to make a freehand selection.")
		return
	selected_area = region
	var ids: Array[String] = []
	for layer_index in document.layers.size():
		var layer: Dictionary = document.layers[layer_index]
		if not layer_is_visible(layer) or layer.locked: continue
		for object in layer.objects:
			if object.get("paint_tile", false): continue
			if AreaSelection.encloses(tool, region, bounds, Art.coverage_bounds(object)):
				ids.append(object.id)
				document.active = layer_index
	var blocked: bool = document.select_artwork(ids, solo_layer_id)
	selected.emit({})
	if blocked and document.selected_items().is_empty(): status.emit("Show and unlock the group’s layers to select it.")
	elif ids.is_empty(): status.emit("Area selected. Use Paint inside selection to keep brush marks inside it.")
	else: status.emit("%d selected · Drag the box to move or the corner to resize." % document.selected_items().size())
	refresh_selection()

func clear_selection() -> void:
	document.selection = ""
	selected_area.clear()
	selected.emit({})
	refresh_selection()

func selection_resize_hit(bounds: Rect2, point: Vector2) -> bool:
	# Leave room to grab the body of a small object at overview zoom.
	var radius := minf(RESIZE_HIT_RADIUS / zoom, bounds.size.length() * 0.35)
	return bounds.end.distance_to(point) <= radius

func selection_box_hit(bounds: Rect2, point: Vector2) -> bool:
	return bounds.has_area() and (bounds.grow((SELECTION_PADDING + 1.0) / zoom).has_point(point)
		or selection_resize_hit(bounds, point))

func editable_selected_object() -> Dictionary:
	for item in document.selected_items():
		if layer_is_visible(item.layer): return item.object
	return {}

func begin_selection_transform(point: Vector2) -> bool:
	if not document.area_selection.is_empty(): return begin_selection_move(point)
	var object := editable_selected_object()
	if object.is_empty(): return false
	var bounds := Art.bounds(object)
	if not selection_box_hit(bounds, point): return false
	edit_started = false
	original = object.duplicate(true)
	resizing = selection_resize_hit(bounds, point)
	moving = not resizing
	return true

func begin_selection_move(point: Vector2) -> bool:
	var items: Array[Dictionary] = document.selected_items()
	if items.is_empty(): return false
	var bounds := items_bounds(items)
	if not selection_box_hit(bounds, point): return false
	var resize_group := selection_resize_hit(bounds, point)
	selection_scale_min = 0.0
	selection_scale_max = 1000.0
	for item in items:
		if layer_is_visible(item.layer):
			var scale := float(item.object.scale)
			moving_selection.append({"object": item.object, "position": Art.v(item.object.pos), "scale": scale})
			selection_scale_min = maxf(selection_scale_min, minf(1.0, 0.02 / scale))
			selection_scale_max = minf(selection_scale_max, 1000.0 / scale)
	selection_move_bounds = bounds
	selection_preview_bounds = bounds
	edit_started = false
	resizing = resize_group
	moving = not resize_group
	return true

func update_selection_move(point: Vector2) -> void:
	var offset: Vector2 = point - start
	if not edit_started:
		if offset.length() < 1.0 / zoom: return
		edit_future = document.future.duplicate(true)
		document.checkpoint()
		selected_area.clear()
		edit_started = true
	var ratio := 1.0
	var pivot := selection_move_bounds.position
	if resizing:
		var diagonal := selection_move_bounds.size
		ratio = clampf(1.0 + offset.dot(diagonal) / diagonal.length_squared(), selection_scale_min, selection_scale_max)
		offset = Vector2.ZERO
	selection_preview_bounds = Rect2(pivot + offset, selection_move_bounds.size * ratio)
	for item in moving_selection:
		var position: Vector2 = pivot + (item.position - pivot) * ratio + offset
		item.object.pos = [position.x, position.y]
		if resizing: item.object.scale = item.scale * ratio
		var entry: Dictionary = retained_marks.get(item.object.id, {})
		if not entry.is_empty(): entry.mark.queue_redraw()
	if paint_cache: paint_cache.invalidate_cache()
	refresh_selection()

func redraw_view() -> void:
	if artwork_root:
		var density := 1.0 if exporting else maxf(0.01, get_screen_transform().get_scale().x)
		var overview := cache_completed_paint and not exporting and IsolatedOpacity.use_overview(size, zoom, density, overview_cache)
		if overview != overview_cache:
			overview_cache = overview
			if not drawing: # Switch once when crossing the zoom band.
				sync_artwork()
				return
		artwork_root.position = origin
		artwork_root.scale = Vector2.ONE * zoom
		if preview_root and preview_root.get_parent() == self:
			preview_root.position = origin
			preview_root.scale = Vector2.ONE * zoom
		if paint_cache or not merge_renderers.is_empty():
			if paint_cache: paint_cache.update_view(size, origin, zoom, density)
			if not merge_renderers.is_empty():
				for holder in layer_renderers.values():
					if holder is IsolatedOpacity and holder != paint_cache: holder.update_view(size, origin, zoom, density)
				for holder in merge_renderers.values():
					if holder is IsolatedOpacity: holder.update_view(size, origin, zoom, density)
	refresh_selection()
	queue_redraw()

func refresh_selection() -> void:
	if selection_overlay: selection_overlay.queue_redraw()

func validate_solo_layer() -> void:
	if solo_layer_id.is_empty(): return
	var index: int = document.layer_index(solo_layer_id)
	if index < 0 or not document.layers[index].visible: solo_layer_id = ""

func set_solo_layer(layer_id: String) -> void:
	if solo_layer_id == layer_id: return
	solo_layer_id = layer_id
	sync_artwork()

func layer_is_visible(layer: Dictionary) -> bool:
	return layer.visible and (solo_layer_id.is_empty() or layer.id == solo_layer_id)

func on_artwork_changed() -> void:
	var object: Dictionary = document.appended_on_commit
	var layer: Dictionary = document.layers[document.active] if not document.layers.is_empty() else {}
	if not object.is_empty() and paint_cache and layer_renderers.get(layer.get("id")) == paint_cache \
			and not object.has("opacity_groups") and not retained_marks.has(object.id) \
			and not layer.objects.is_empty() and is_same(layer.objects.back(), object):
		# An append to the cached layer changes only its newest mark.
		# Keep the existing surface and add the mark on its next frame.
		var entry := mount_mark(paint_cache.artwork, object)
		retained_marks[object.id] = entry
		paint_cache.append_mark(entry.mark)
		if not pigment_dirty:
			pigment_dirty = not pigment.append_latest(layer, document.active, object)
		refresh_selection()
		return
	sync_artwork()

func mount_mark(holder: Node2D, object: Dictionary) -> Dictionary:
	var mark := Node2D.new()
	if object.kind == "image": mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	Art.use_screen_edges(mark, object)
	mark.draw.connect(Art.draw_object.bind(mark, object))
	holder.add_child(mark)
	return {"mark": mark, "object": object, "appearance": object.duplicate()}

func sync_artwork() -> void:
	if not artwork_root or document == null: return
	validate_solo_layer()
	if preview_root and preview_root.get_parent() != self: preview_root.reparent(self, false)
	var next_layers := {}
	var next_merge_renderers := {}
	var next_marks := {}
	var stale_layers: Array[Node2D] = []
	var layer_index := 0
	var cache_layer := select_paint_cache_layer()
	paint_cache = null
	for layer in document.layers:
		if not layer_is_visible(layer): continue
		var layer_alpha: float = opacity_preview_value if layer.id == opacity_preview_layer else layer.get("opacity", 1.0)
		var holder: Node2D = layer_renderers.get(layer.id)
		var use_group := layer_alpha < 1.0
		var nesting := find_nested_scopes(layer)
		var isolate_layer: bool = use_group and nesting.has_groups
		var cache_layer_marks: bool = layer.id == cache_layer and not nesting.has_groups
		var needs_surface := isolate_layer or cache_layer_marks
		if not holder or (holder is IsolatedOpacity) != needs_surface or (
				holder is IsolatedOpacity and holder.cache_finished_marks != cache_layer_marks) or (
				holder is CanvasGroup) != (use_group and not isolate_layer):
			if holder: stale_layers.append(holder)
			holder = make_opacity_holder(use_group, needs_surface)
			if holder is IsolatedOpacity:
				holder.cache_finished_marks = cache_layer_marks
				holder.overview = cache_layer_marks and overview_cache
			artwork_root.add_child(holder)
		if cache_layer_marks:
			paint_cache = holder
			paint_cache.invalidate_cache()
		if use_group: set_holder_opacity(holder, layer_alpha)
		if holder.get_index() != layer_index: artwork_root.move_child(holder, layer_index)
		layer_index += 1
		next_layers[layer.id] = holder

		var scopes := []
		var holders: Array[Node2D] = [holder_artwork(holder)]
		var positions: Array[int] = [0]
		for object in layer.objects:
			var groups: Array = object.get("opacity_groups", [])
			if not groups.is_empty() or not scopes.is_empty():
				var shared := OpacityStack.shared_depth(scopes, groups)
				holders.resize(shared + 1)
				positions.resize(shared + 1)
				for depth in range(shared, groups.size()):
					var key := scope_key(layer.id, object.id, depth)
					var subgroup: Node2D = merge_renderers.get(key)
					var parent := holders[-1]
					var isolate: bool = nesting.keys.has(key)
					if not subgroup or (subgroup is IsolatedOpacity) != isolate:
						if subgroup: stale_layers.append(subgroup)
						subgroup = make_opacity_holder(true, isolate)
						parent.add_child(subgroup)
					elif subgroup.get_parent() != parent:
						subgroup.reparent(parent, false)
					set_holder_opacity(subgroup, float(groups[depth].opacity))
					if subgroup.get_index() != positions[-1]: parent.move_child(subgroup, positions[-1])
					positions[-1] += 1
					next_merge_renderers[key] = subgroup
					holders.append(holder_artwork(subgroup))
					positions.append(0)
				scopes = groups
			var mark_holder := holders[-1]
			var object_index := positions[-1]
			var mark: Node2D
			var entry: Dictionary = retained_marks.get(object.id, {})
			if not entry.is_empty() and is_same(entry.object, object) and entry.appearance == object:
				mark = entry.mark
				if mark.get_parent() != mark_holder:
					mark.reparent(mark_holder, false)
					mark.show()
			else:
				if not entry.is_empty(): remove_mark(entry.mark)
				entry = mount_mark(mark_holder, object)
				mark = entry.mark
			if mark.get_index() != object_index: mark_holder.move_child(mark, object_index)
			next_marks[object.id] = entry
			positions[-1] += 1

	for id in retained_marks:
		if not next_marks.has(id): remove_mark(retained_marks[id].mark)
	for key in merge_renderers:
		if not next_merge_renderers.has(key): remove_mark(merge_renderers[key])
	for id in layer_renderers:
		if not next_layers.has(id): stale_layers.append(layer_renderers[id])
	for holder in stale_layers: remove_mark(holder)
	layer_renderers = next_layers
	merge_renderers = next_merge_renderers
	retained_marks = next_marks
	if drawing: mount_preview()
	pigment_dirty = true
	var page_size := Vector2(document.width, document.height)
	var was_resized := last_page_size != Vector2.ZERO and page_size != last_page_size
	last_page_size = page_size
	if view_fitted and was_resized and not exporting: fit()
	else: redraw_view()

func select_paint_cache_layer() -> String:
	if exporting or not cache_completed_paint: return ""
	# Limit the canvas to one extra surface. Ordinary opaque layers can
	# composite the live stroke above their cached finished strokes.
	var overview_layer := ""
	for index in document.layers.size():
		var layer: Dictionary = document.layers[index]
		if not layer_is_visible(layer) or layer.get("opacity", 1.0) < 1.0 or layer.id == opacity_preview_layer: continue
		var dabs := 0
		var isolated := false
		for object in layer.objects:
			if object.has("opacity_groups"):
				isolated = true
				break
			if object.kind == "stroke":
				match object.brush:
					"soft", "pencil", "chalk": dabs += object.points.size() * 5
					_: dabs += object.points.size()
		if not isolated and dabs >= PAINT_CACHE_THRESHOLD: return layer.id
		if overview_cache and not isolated and index == document.active and layer.get("type", "vector") != "paint" and not layer.objects.is_empty():
			overview_layer = layer.id
	return overview_layer

func scope_key(layer_id: String, object_id: String, depth: int) -> String:
	return "%s:%s:%d" % [layer_id, object_id, depth]

func find_nested_scopes(layer: Dictionary) -> Dictionary:
	var isolated := {}
	var has_groups := false
	var previous := []
	var keys := []
	for object in layer.objects:
		var next: Array = object.get("opacity_groups", [])
		if next.is_empty() and previous.is_empty(): continue
		var shared := OpacityStack.shared_depth(previous, next)
		keys.resize(shared)
		for depth in range(shared, next.size()): keys.append(scope_key(layer.id, object.id, depth))
		for depth in range(keys.size() - 1): isolated[keys[depth]] = true
		if not next.is_empty(): has_groups = true
		previous = next
	return {"keys": isolated, "has_groups": has_groups}

func make_opacity_holder(use_group: bool, isolated: bool) -> Node2D:
	if isolated: return IsolatedOpacity.new()
	if use_group: return CanvasGroup.new()
	return Node2D.new()

func set_holder_opacity(holder: Node2D, value: float) -> void:
	if holder is IsolatedOpacity: holder.set_opacity(value)
	else: holder.self_modulate.a = value

func holder_artwork(holder: Node2D) -> Node2D:
	return holder.artwork if holder is IsolatedOpacity else holder

func remove_mark(mark: Node2D) -> void:
	mark.get_parent().remove_child(mark)
	mark.queue_free()

func preview_layer_opacity(layer_id: String, value: float) -> void:
	var old_layer := opacity_preview_layer
	opacity_preview_layer = layer_id
	opacity_preview_value = value
	var holder: Node2D = layer_renderers.get(layer_id)
	if old_layer == layer_id and (holder is CanvasGroup or holder is IsolatedOpacity):
		set_holder_opacity(holder, value)
	else:
		sync_artwork()

func mount_preview() -> void:
	if not preview_root or not document.editable(): return
	var holder: Node2D = layer_renderers.get(document.layers[document.active].id)
	if not holder: return
	if holder != paint_cache: holder = holder_artwork(holder)
	if preview_root.get_parent() != holder: preview_root.reparent(holder, false)
	preview_root.position = Vector2.ZERO
	preview_root.scale = Vector2.ONE
	preview_root.move_to_front()

func sample_pigment(point: Vector2) -> Color:
	if pigment_dirty:
		pigment.rebuild(document, solo_layer_id)
		pigment_dirty = false
	return pigment.sample(point)

func sample_visible_color(screen: Vector2, point: Vector2) -> Color:
	# Only the eyedropper reads the rendered image. Blending stays on the
	# document sampler so painting does not stall on GPU readbacks.
	if DisplayServer.get_name() != "headless":
		var viewport := get_viewport()
		var image := viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			var pixel := Vector2i((viewport.get_final_transform() * get_global_transform_with_canvas() * screen).floor())
			if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
				return image.get_pixelv(pixel)
	return sample_pigment(point)

func end_preview() -> void:
	metrics_pressure = -1.0
	if drawing and current.get("kind") == "stroke":
		if manage_input_accumulation:
			Input.use_accumulated_input = input_was_accumulated
			if android_pointer_idle: android_pointer_idle.start(ANDROID_POINTER_IDLE)
		last_brush_activity = Time.get_ticks_msec()
	clear_preview()

func request_android_unbuffered_pointer() -> void:
	if not android_pointer_idle: return
	android_pointer_idle.stop()
	if android_pointer_unbuffered: return
	android_pointer_unbuffered = true
	set_android_pointer_buffering(false)

func restore_android_pointer_buffering() -> void:
	if not android_pointer_unbuffered: return
	android_pointer_unbuffered = false
	android_pointer_idle.stop()
	set_android_pointer_buffering(true)

func set_android_pointer_buffering(buffered: bool) -> void:
	if not Engine.has_singleton("AndroidRuntime"): return
	var java = Engine.get_singleton("JavaClassWrapper")
	var version = java.wrap("android.os.Build$VERSION")
	if version.SDK_INT < 30: return
	var runtime = Engine.get_singleton("AndroidRuntime")
	var activity = runtime.getActivity()
	if activity == null: return
	var update_dispatch := func():
		var godot = activity.getGodot()
		if godot == null: return
		var renderer = godot.getRenderView()
		if renderer == null: return
		var view = renderer.getView()
		var device = java.wrap("android.view.InputDevice")
		# Keep normal Android motion batching for navigation outside a stroke.
		view.requestUnbufferedDispatch(device.SOURCE_CLASS_NONE if buffered else device.SOURCE_CLASS_POINTER)
	activity.runOnUiThread(runtime.createRunnableFromGodotCallable(update_dispatch))

func clear_preview() -> void:
	if not preview_root: return
	for batch in preview_root.get_children():
		preview_root.remove_child(batch)
		batch.queue_free()
	if preview_root.get_parent() != self: preview_root.reparent(self, false)
	live_batch = null
	live_first = 0

func redraw_preview() -> void:
	if not preview_root: return
	if current.get("erasing", false):
		refresh_selection()
		return
	if current.kind != "stroke":
		if not live_batch:
			live_batch = Node2D.new()
			Art.use_screen_edges(live_batch, current)
			live_batch.draw.connect(Art.draw_object.bind(live_batch, current))
			preview_root.add_child(live_batch)
		live_batch.queue_redraw()
		return
	var batch_size := Art.stroke_batch_size(current)
	# Dabs are independent. Seal short batches so textured brushes don't
	# regenerate dozens of already rendered dabs as each sample arrives.
	if not Art.uses_ink_outline(current): batch_size = 24 if Art.uses_grain_instances(current) else 12
	var end: int = current.points.size()
	var neighbor := 1 if Art.uses_ink_outline(current) or current.get("continuous_edges", false) else 0
	while live_first + batch_size + neighbor <= end:
		if live_batch:
			preview_root.remove_child(live_batch)
			live_batch.queue_free()
			live_batch = null
		var completed := Node2D.new()
		Art.use_screen_edges(completed, current)
		completed.draw.connect(Art.draw_stroke_range.bind(completed, current, live_first, live_first + batch_size))
		preview_root.add_child(completed)
		live_first += batch_size
	if live_first >= end: return
	if not live_batch:
		live_batch = Node2D.new()
		Art.use_screen_edges(live_batch, current)
		live_batch.draw.connect(draw_live_batch.bind(live_batch, current, live_first))
		preview_root.add_child(live_batch)
	live_batch.queue_redraw()

func draw_live_batch(batch: Node2D, stroke: Dictionary, first: int) -> void:
	Art.draw_stroke_range(batch, stroke, first, stroke.points.size())

func editable_nodes(object: Dictionary) -> Array:
	var nodes = []
	var count := node_points(object).size()
	var step = maxi(1, ceili(float(count) / 40))
	for i in range(0, count, step): nodes.append(i)
	if not nodes.has(count - 1): nodes.append(count - 1)
	for index in object.get("node_anchors", []):
		if not nodes.has(int(index)): nodes.append(int(index))
	return nodes

func set_add_node_mode(enabled: bool) -> void:
	if adding_node == enabled: return
	adding_node = enabled
	node_mode_changed.emit()

func add_node_at(point: Vector2) -> void:
	var layer: Dictionary = document.layers[document.active]
	var object: Dictionary = document.find_object(document.selection)
	var segment := {}
	if object.get("kind") in ["stroke", "polygon", "path"] and layer.objects.has(object):
		segment = nearest_node_segment(object, point)
	else:
		for index in range(layer.objects.size() - 1, -1, -1):
			var candidate: Dictionary = layer.objects[index]
			if candidate.kind not in ["stroke", "polygon", "path"]: continue
			segment = nearest_node_segment(candidate, point)
			if not segment.is_empty():
				object = candidate
				break
	if segment.is_empty():
		status.emit("Tap an edge of a path, polygon, or brush stroke on this layer.")
		return

	var points := node_points(object)
	var weight: float = segment.weight
	var length := Art.v(points[segment.first]).distance_to(Art.v(points[segment.last]))
	var snap: float = 0.75 / (zoom * float(object.scale))
	var anchor := -1
	if minf(weight, 1.0 - weight) * length <= snap:
		anchor = segment.first if weight < 0.5 else segment.last
	if anchor >= 0 and anchor in editable_nodes(object):
		status.emit("There’s already a node here.")
		return
	if anchor < 0 and points.size() >= 100000:
		status.emit("This path has reached its node limit.")
		return

	document.checkpoint()
	var anchors: Array = object.get("node_anchors", []).duplicate()
	if anchor < 0:
		anchor = segment.first + 1
		var projected: Vector2 = segment.position
		var sample := [projected.x, projected.y]
		var stroke: bool = object.kind == "stroke"
		if stroke:
			var first: Array = points[segment.first]
			var last: Array = points[segment.last]
			var pigment := Color(first[3]).lerp(Color(last[3]), segment.weight)
			sample.append(lerpf(first[2], last[2], segment.weight))
			sample.append("#" + pigment.to_html(pigment.a < 1.0))
		for index in anchors.size():
			if int(anchors[index]) >= anchor: anchors[index] = int(anchors[index]) + 1
		var updated := points.duplicate()
		updated.insert(anchor, sample)
		if stroke: object.points = updated
		else: object.vertices = updated

	anchors.append(anchor)
	anchors.sort()
	object.node_anchors = anchors
	pigment.entries.erase(object.id)
	document.selection = object.id
	selected_area.clear()
	set_add_node_mode(false)
	document.commit()
	selected.emit(object)
	refresh_selection()
	status.emit("Node added. Drag it to reshape the line.")

func nearest_node_segment(object: Dictionary, point: Vector2) -> Dictionary:
	var local := Art.local_point(object, point)
	if not Art.point_inside_clip(object, local): return {}
	var points := node_points(object)
	if points.size() < 2: return {}
	var hit_radius: float = float(object.size) * 0.5 if object.kind == "stroke" else Art.outline_width(object) * 0.5
	var nearest := pow(12.0 / (zoom * float(object.scale)) + hit_radius, 2.0)
	var segment := {}
	var count := points.size() if object.kind == "polygon" else points.size() - 1
	var bridges := Art.Compound.bridge_edges(Art.polygon(object)) if object.get("compound", false) else {}
	for index in count:
		if bridges.has(index): continue
		var next := (index + 1) % points.size()
		var first := Art.v(points[index])
		var last := Art.v(points[next])
		var offset := last - first
		var length := offset.length_squared()
		if length <= 0.000001: continue
		var weight := clampf((local - first).dot(offset) / length, 0.0, 1.0)
		var projected := first + offset * weight
		var distance := local.distance_squared_to(projected)
		if distance < nearest:
			nearest = distance
			segment = {"first": index, "last": next, "position": projected, "weight": weight}
	if not segment.is_empty() and not Art.point_inside_clip(object, segment.position): return {}
	return segment

func node_points(object: Dictionary) -> Array:
	return object.points if object.kind == "stroke" else object.vertices

func nearest_editable_node(object: Dictionary, point: Vector2) -> int:
	if object.get("kind") not in ["stroke", "path", "polygon"]: return -1
	var points := node_points(object)
	var best := -1
	var distance := 12.0 / float(zoom)
	for index in editable_nodes(object):
		var node_point := Art.v(points[index]) * float(object.scale) + Art.v(object.pos)
		var next := node_point.distance_to(point)
		if next >= distance: continue
		best = index
		distance = next
	return best

func node_spread_for(object: Dictionary) -> float:
	return stroke_node_spread if object.get("kind") == "stroke" else path_node_spread

func start_node_drag(object: Dictionary, point: Vector2) -> bool:
	var index := nearest_editable_node(object, point)
	if index < 0: return false
	original = object.duplicate(true)
	edit_started = false
	node_index = index
	node_arc.clear()
	node_cycle = 0.0
	var points := node_points(original)
	node_twins.clear()
	if object.get("compound", false):
		var copies := {}
		for i in points.size():
			var position := Art.v(points[i])
			if not copies.has(position): copies[position] = []
			copies[position].append(i)
		for indices in copies.values():
			if indices.size() > 1: node_twins.append(indices)
	var distance := 0.0
	node_arc.append(distance)
	for i in range(1, points.size()):
		distance += Art.v(points[i - 1]).distance_to(Art.v(points[i]))
		node_arc.append(distance)
	var gap := Art.v(points[0]).distance_to(Art.v(points[-1]))
	var stroke: bool = object.kind == "stroke"
	if object.kind == "polygon" or (stroke and points.size() > 3 and distance > float(object.size) * 2.0 and gap <= float(object.size) * 0.5):
		node_cycle = distance + gap
	node_reach = node_influence_radius(object, maxf(distance, node_cycle))
	refresh_selection()
	return true

func node_influence_radius(object: Dictionary, length: float) -> float:
	var spread := node_spread_for(object)
	if spread <= 0.0: return 0.0
	var scale_in_view: float = zoom * float(object.scale)
	var local := lerpf(20.0, 92.0, spread) / scale_in_view
	if object.kind == "stroke":
		local = maxf(local, minf(float(object.size), 44.0 / scale_in_view))
	return lerpf(minf(local, length * 0.3), maxf(local, length * 0.75), spread * spread * spread)

func deform_node(object: Dictionary, point: Vector2) -> void:
	var points := node_points(object)
	var delta: Vector2 = (point - start) / float(object.scale)
	var center := node_arc[node_index]
	# The range is set by Spread and the original curve, independent of drag distance.
	var span := maxf(node_reach, 0.0001)
	if node_cycle > 0.0 and span >= node_cycle * 0.5:
		deform_node_span(points, 0.0, node_arc[-1], delta)
	else:
		deform_node_span(points, center - span, center + span, delta)
		if node_cycle > 0.0:
			if center - span < 0.0:
				deform_node_span(points, node_cycle + center - span, node_arc[-1], delta)
			if center + span > node_cycle:
				deform_node_span(points, 0.0, center + span - node_cycle, delta)
	# Both ends of each artificial seam must keep their paired vertices.
	for copies in node_twins:
		var weight := 0.0
		for index in copies: weight = maxf(weight, node_weight(index))
		var moved := Art.v(original.vertices[copies[0]]) + delta * weight
		for index in copies: points[index] = [moved.x, moved.y]

func node_weight(index: int) -> float:
	if index >= node_arc.size() or node_index < 0: return 0.0
	var distance := absf(node_arc[index] - node_arc[node_index])
	if node_cycle > 0.0: distance = minf(distance, node_cycle - distance)
	if node_reach <= 0.0: return 1.0 if distance <= 0.0001 else 0.0
	return 1.0 - smoothstep(0.0, node_reach, distance)

func deform_node_span(points: Array, low: float, high: float, delta: Vector2) -> void:
	var first := node_arc.bsearch(low)
	var stop := node_arc.bsearch(high, false)
	var previous := node_points(original)
	for index in range(first, stop):
		var place := Art.v(previous[index]) + delta * node_weight(index)
		points[index][0] = place.x
		points[index][1] = place.y

func hit(point: Vector2, include_interior: bool) -> Dictionary:
	for layer_index in range(document.layers.size() - 1, -1, -1):
		var layer = document.layers[layer_index]
		if not layer_is_visible(layer) or layer.locked: continue
		for i in range(layer.objects.size() - 1, -1, -1):
			var object: Dictionary = layer.objects[i]
			if object.get("paint_tile", false): continue
			if Art.contains(object, point, 6 / zoom) or (include_interior and contains_selectable_interior(object, point)):
				document.active = layer_index
				return object
	return {}

func contains_selectable_interior(object: Dictionary, point: Vector2) -> bool:
	if Art.shape_interior_contains(object, point): return true
	if object.kind != "stroke": return false
	var local := Art.local_point(object, point)
	if not Art.point_inside_clip(object, local): return false
	var outline := Art.closed_stroke_outline(object)
	return not outline.is_empty() and Geometry2D.is_point_in_polygon(local, outline)

func tool_unavailable_reason(name: String) -> String:
	if document == null or document.layers.is_empty(): return ""
	var shapes := name == "shapes" or name == "path" or name in SHAPE_TOOLS
	if not shapes and name not in ["brush", "erase", "text", "nodes", "fill"]: return ""
	var layer: Dictionary = document.layers[document.active]
	var pixels: bool = document.paints_pixels()
	if name == "nodes" and pixels: return "Nodes are unavailable on paint layers."
	if not layer_is_visible(layer): return "Show this layer to use this tool."
	if layer.locked: return "Unlock this layer to use this tool."
	if layer.get("alpha_locked", false):
		if (pixels and name == "erase") or (not pixels and (shapes or name in ["fill", "text"])):
			return "Turn off Alpha Lock to use this tool."
	if name == "fill" and not pixels:
		if layer.get("opacity", 1.0) <= 0.0: return "Raise this layer’s opacity to fill it."
		for object in layer.objects:
			if object.opacity > 0.0 and (object.kind in Art.SHAPES or object.kind == "stroke"): return ""
		return "Vector Fill needs a shape or enclosed lines on this layer."
	return ""

func fill_at(point: Vector2) -> void:
	var layer_index: int = document.active
	var layer: Dictionary = document.layers[layer_index]
	if not layer_is_visible(layer) or layer.get("opacity", 1.0) <= 0.0: return
	for index in range(layer.objects.size() - 1, -1, -1):
		var object: Dictionary = layer.objects[index]
		if object.opacity <= 0.0: continue
		var outline := PackedVector2Array()
		if object.kind == "stroke":
			var local := Art.local_point(object, point)
			if object.has("paint_mask") or not Art.point_inside_clip(object, local): continue
			outline = Art.closed_stroke_outline(object)
			if outline.is_empty(): continue
			if not Geometry2D.is_point_in_polygon(local, outline) and not Art.contains(object, point, 2.0 / zoom): continue
			if Geometry2D.triangulate_polygon(outline).is_empty(): continue
		elif object.kind in ["rect", "ellipse", "polygon"]:
			if not Art.shape_interior_contains(object, point) and not Art.contains(object, point, 2.0 / zoom): continue
		else:
			continue
		var target := object if outline.is_empty() else outline_fill(layer, index, outline)
		apply_vector_fill(layer_index, index, target)
		return
	var region := VectorFill.find_region(layer.objects, point)
	if not region.is_empty():
		var target := {"kind": "polygon", "vertices": Art.pack_contours([region.vertices])[0],
			"opacity": 1.0, "pos": [0.0, 0.0], "scale": 1.0}
		apply_vector_fill(layer_index, region.index, target)
		return
	status.emit("Tap inside a closed shape or where lines meet to enclose an area.")

func apply_vector_fill(layer_index: int, index: int, target: Dictionary) -> void:
	var layer: Dictionary = document.layers[layer_index]
	if layer.locked or layer.get("alpha_locked", false):
		status.emit("Unlock this layer to fill it." if layer.locked else "Turn off alpha lock on this layer to fill it.")
		return
	var hex := "#" + color.to_html(color.a < 1.0)
	var new_fill := not target.has("id")
	var changed: bool = new_fill or target.color != hex or not Art.has_fill(target)
	if changed:
		document.checkpoint()
		target.color = hex
		target.fill_enabled = true
		if new_fill:
			target.id = document.uid()
			layer.objects.insert(index, target)
	document.active = layer_index
	document.selection = target.id
	selected_area.clear()
	if changed:
		document.commit()
		color_used.emit(color)
	selected.emit(target)
	refresh_selection()

func outline_fill(layer: Dictionary, index: int, outline: PackedVector2Array) -> Dictionary:
	var stroke: Dictionary = layer.objects[index]
	var vertices := []
	for point in outline: vertices.append([point.x, point.y])
	# Recolor an existing fill immediately below this outline.
	if index > 0:
		var below: Dictionary = layer.objects[index - 1]
		if below.kind == "polygon" and below.pos == stroke.pos and below.scale == stroke.scale \
				and Art.outline_vertices(below.vertices) == outline and below.get("clip", []) == stroke.get("clip", []) \
				and below.get("opacity_groups", []) == stroke.get("opacity_groups", []):
			return below
	var fill := {"kind": "polygon", "vertices": vertices, "opacity": 1.0, "pos": stroke.pos.duplicate(), "scale": stroke.scale}
	for property in ["clip", "opacity_groups"]:
		if stroke.has(property): fill[property] = stroke[property].duplicate(true)
	return fill

func _gui_input(event: InputEvent) -> void:
	if document == null or exporting: return
	if event is InputEventMouseButton:
		if touch_points.is_empty(): metrics_pointer = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom_at(1.15, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom_at(1 / 1.15, event.position)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not touch_points.is_empty():
				if not touch_navigating:
					accept_event()
					return
				if event.pressed: reset_touch()
			if event.pressed:
				begin_pointer(event)
			else:
				dragging = false
				metrics_pressure = -1.0
				if marquee_active: update_marquee(to_document(event.position))
				finish()
	elif event is InputEventMouseMotion:
		if touch_points.is_empty():
			metrics_pointer = event.position
			metrics_pressure = event.pressure if drawing and event.pressure > 0.0 else -1.0
		if event.pressure > 0: last_pressure = event.pressure
		else: last_pressure = 0.55
		if dragging:
			pan_by(event.relative)
		elif drawing or moving or resizing or node_index >= 0 or marquee_active:
			update_stroke(event.position, event.pressure if event.pressure > 0 else 0.55)
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		begin_contact(event.index, event.position)
	accept_event()

func begin_pointer(event: InputEventMouseButton) -> void:
	var shortcut := ""
	if not pen_button_tools.is_empty() and event.device != InputEvent.DEVICE_ID_EMULATION and pen_shortcut_contact.is_valid():
		shortcut = pen_button_tools.get(int(pen_shortcut_contact.call()), "")
	if Input.is_physical_key_pressed(KEY_SPACE) or shortcut == "hand" or (shortcut.is_empty() and tool == "hand"):
		dragging = true
		return
	begin(event.position, last_pressure, shortcut)

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag): return
	if not touch_points.has(event.index): return
	if event is InputEventScreenTouch and event.pressed: return
	# Keep ownership of a canvas gesture when fingers cross a panel or leave the canvas.
	var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	if event is InputEventScreenDrag:
		move_contact(event.index, local_position, event.pressure)
	else:
		end_contact(event.index, local_position, event.canceled)
	get_viewport().set_input_as_handled()

func begin_contact(index: int, point: Vector2) -> void:
	if touch_points.has(index): return
	if touch_points.is_empty() and (drawing or moving or resizing or node_index >= 0 or dragging or marquee_active):
		return
	touch_points[index] = point
	set_process_input(true)
	if touch_points.size() == 1:
		clear_pointer_metrics()
		var node_touch := false
		var adding_with_touch := tool == "nodes" and adding_node
		if tool == "nodes" and not adding_with_touch:
			var object: Dictionary = document.find_object(document.selection)
			node_touch = (not object.is_empty() and document.can_edit(object.id)
				and nearest_editable_node(object, to_document(point)) >= 0)
		var touches_selection := false
		if tool == "select":
			var bounds := Rect2()
			if document.area_selection.is_empty():
				var object := editable_selected_object()
				if not object.is_empty(): bounds = Art.bounds(object)
			else:
				bounds = items_bounds(document.selected_items())
			touches_selection = selection_box_hit(bounds, to_document(point))
		touch_navigating = (not touch_paints and not node_touch and not adding_with_touch and tool not in AREA_TOOLS
			and tool not in ["fill", "picker", "select"]) or tool == "hand"
		touch_start = point
		touch_tap_moved = false
		if not touch_navigating:
			metrics_pointer = point
			if adding_with_touch:
				touch_tap_tool = "add_node"
			elif (tool == "select" and not touches_selection) or tool in ["picker", "fill", "text", "path"] or (tool == "erase" and not document.paints_pixels()):
				touch_tap_tool = tool
			else:
				begin(point, 0.55)
	elif not touch_navigating:
		clear_pointer_metrics()
		cancel()
		touch_tap_tool = ""
		touch_navigating = true

func move_contact(index: int, point: Vector2, pressure: float) -> void:
	var previous: Vector2 = touch_points[index]
	if not touch_navigating:
		touch_points[index] = point
		metrics_pointer = point
		metrics_pressure = pressure if drawing and pressure > 0.0 else -1.0
		if touch_tap_tool.is_empty():
			update_stroke(point, pressure if pressure > 0 else 0.55)
		elif touch_start.distance_to(point) > 8.0:
			touch_tap_moved = true
			if touch_tap_tool in ["fill", "picker", "add_node", "select"]:
				touch_navigating = true
				touch_tap_tool = ""
				pan_by(point - touch_start)
		return

	var pair := touch_points.keys()
	if pair.size() == 1:
		touch_points[index] = point
		pan_by(point - previous)
		return

	var first: Vector2 = touch_points[pair[0]]
	var second: Vector2 = touch_points[pair[1]]
	touch_points[index] = point
	if index != pair[0] and index != pair[1]: return
	var old_span := first.distance_to(second)
	var anchor := to_document((first + second) * 0.5)
	first = touch_points[pair[0]]
	second = touch_points[pair[1]]
	var new_span := first.distance_to(second)
	var old_zoom: float = zoom
	if old_span > 1.0 and new_span > 1.0:
		zoom = clampf(zoom * new_span / old_span, 0.05 / ui_scale, 12.0 / ui_scale)
	view_fitted = false
	origin = (first + second) * 0.5 - anchor * zoom
	redraw_view()
	if zoom != old_zoom: view_changed.emit()

func end_contact(index: int, point: Vector2, canceled: bool) -> void:
	touch_points.erase(index)
	if not touch_points.is_empty(): return
	clear_pointer_metrics()
	set_process_input(false)
	if not touch_navigating:
		if canceled:
			cancel()
		elif touch_tap_tool.is_empty():
			if marquee_active: update_marquee(to_document(point))
			finish()
		elif not touch_tap_moved and touch_start.distance_to(point) <= 8.0:
			if touch_tap_tool == tool or (touch_tap_tool == "add_node" and tool == "nodes" and adding_node):
				begin(point, 0.55)
				if tool == "select": finish()
	touch_navigating = false
	touch_tap_tool = ""

func clear_pointer_metrics() -> void:
	metrics_pointer = Vector2.INF
	metrics_pressure = -1.0

func reset_touch() -> void:
	clear_pointer_metrics()
	touch_points.clear()
	touch_navigating = false
	touch_tap_tool = ""
	set_process_input(false)

func begin(screen: Vector2, pressure: float, shortcut: String = "") -> void:
	if drawing: return
	# Document signals can refresh the toolbar while an eraser tap runs.
	# Keep the selected tool separate from this contact's action.
	var action: String = tool if shortcut.is_empty() else shortcut
	var point = to_document(screen)
	start = point
	if action == "select" or action in AREA_TOOLS:
		if begin_selection_transform(point): return
		if action in AREA_TOOLS:
			marquee_active = true
			marquee_end = point
			lasso_points = PackedVector2Array([point])
			refresh_selection()
			return
	if not Rect2(0, 0, document.width, document.height).has_point(point): return
	var unavailable := tool_unavailable_reason(action)
	if not unavailable.is_empty():
		status.emit(unavailable)
		return
	if action == "path":
		if path_points.size() >= 3 and point.distance_to(path_points[0]) * zoom < 12:
			commit_path(true)
		elif path_points.is_empty() or point.distance_to(path_points[-1]) * zoom >= 3:
			path_points.append(point)
			selection_overlay.queue_redraw()
			path_changed.emit()
		return
	if action == "picker":
		color = sample_visible_color(screen, point)
		status.emit("Picked #%s" % color.to_html(false))
		selected.emit({"picked_color": color})
		return
	if action == "fill":
		if document.paints_pixels():
			match document.fill_paint(Vector2i(point.floor()), color):
				OK: color_used.emit(color)
				ERR_UNAVAILABLE: status.emit("Choose a visible, unlocked paint layer.")
				_: status.emit("The project has reached its embedded paint size limit.")
		else:
			fill_at(point)
		return
	if action == "nodes" and adding_node:
		add_node_at(point)
		return
	var raster_erase: bool = action == "erase" and document.paints_pixels()
	if action in ["select", "nodes", "erase"] and not raster_erase:
		var object = document.find_object(document.selection)
		if not object.is_empty() and not document.can_edit(object.id): object = {}
		if action == "nodes" and start_node_drag(object, point): return
		selected_area.clear()
		object = hit(point, action == "select")
		if action == "select" and object.has("artwork_group"):
			var ids: Array[String] = [object.id]
			var blocked: bool = document.select_artwork(ids, solo_layer_id)
			selected.emit({})
			if blocked:
				status.emit("Show and unlock the group’s layers to select it.")
				refresh_selection()
				return
			if not document.area_selection.is_empty():
				begin_selection_move(point)
				refresh_selection()
				return
		document.selection = object.get("id", "")
		selected.emit(object)
		refresh_selection()
		if object.is_empty(): return
		if action == "erase":
			document.delete_selected()
			status.emit("Object erased · undo to restore")
		elif action == "nodes":
			start_node_drag(object, point)
		elif action == "select":
			edit_started = false
			original = object.duplicate(true)
			moving = true
		return
	var layer: Dictionary = document.layers[document.active]
	var mask := []
	if layer.get("alpha_locked", false) and not document.paints_pixels():
		mask = Art.vector_paint_mask(layer)
		if mask.is_empty():
			status.emit("Alpha lock needs solid vector artwork on this layer.")
			return
	if (action == "brush" or raster_erase) and clip_enabled and clip_regions.size() > 1:
		mask = clip_regions if mask.is_empty() else Art.intersect_masks(clip_regions, mask)
		if not Document.valid_paint_mask(mask):
			status.emit("The paint limit and this layer’s alpha lock need a shared area.")
			return
	if action == "text":
		var text_object := {"kind": "text", "text": text_content, "font_size": text_size,
			"color": "#" + color.to_html(false), "opacity": opacity, "pos": [point.x, point.y]}
		Art.Fonts.apply_to_text(text_object, text_font)
		if not document.append_vector_object(text_object):
			status.emit("The project has reached its layer limit.")
			return
		color_used.emit(color)
		selected.emit(document.find_object(document.selection))
		return
	if action == "brush" or raster_erase:
		stroke_pigment = color
		stroke_pigment_hex = "#" + color.to_html(false)
		stroke_mixing = blending
		stroke_smoothing = smoothing
		var physical_scale := get_screen_transform().get_scale().x
		stroke_lag_limit = 2.0 / (zoom * maxf(physical_scale, 0.01))
		current = {"id": document.uid(), "kind": "stroke", "color": stroke_pigment_hex, "opacity": opacity, "pos": [0.0, 0.0], "scale": 1.0}
		raw_point = point
		if manage_input_accumulation:
			input_was_accumulated = Input.use_accumulated_input
			Input.use_accumulated_input = false
			request_android_unbuffered_pointer()
		last_brush_activity = Time.get_ticks_msec()
		pigment_spacing_squared = pow(float(brush_size) * WET_PIGMENT_SPACING, 2.0)
		current.merge({"points": [], "brush": brush, "size": brush_size})
		if raster_erase:
			current.brush = "ink"
			current.opacity = 1.0
			current.erasing = true
		else:
			current.merge(brush_profile)
			if current.get("taper_end", 0.0) > 0.0: current.live_stroke = true
			if brush in ["paint", "mix"] and is_equal_approx(float(current.get("tip_ratio", 1.0)), 1.0):
				current.continuous_edges = true
		if clip_enabled and clip_regions.size() == 1: current.clip = clip_regions[0].duplicate(true)
		if not mask.is_empty(): current.paint_mask = mask.duplicate(true)
		raw_pressure = BrushLibrary.map_pressure(pressure, current)
		append_point(point, raw_pressure, true)
	elif action in SHAPE_TOOLS:
		current = new_shape(SHAPE_TOOLS[action], point)
		update_drag_shape(point)
	else:
		return
	drawing = true
	mount_preview()
	redraw_preview()

func shape_outline_color() -> Color:
	return shape_settings.outline_color if shape_settings.outline_color != null else color

func new_shape(kind: String, position: Vector2) -> Dictionary:
	var object := {"id": document.uid(), "kind": kind, "pos": [position.x, position.y], "scale": 1.0,
		"color": "#" + color.to_html(), "opacity": shape_settings.opacity,
		"fill_enabled": kind != "path" and shape_settings.fill_enabled}
	if kind == "path" or shape_settings.outline_enabled:
		object.outline_color = "#" + shape_outline_color().to_html()
		object.outline_width = shape_settings.outline_width
	return object

func update_drag_shape(point: Vector2) -> void:
	var delta: Vector2 = point - start
	if current.kind == "path":
		current.vertices = [[0.0, 0.0], [delta.x, delta.y]]
		if tool == "arrow": current.arrow = true
		return
	if tool in ["square", "circle"] or Input.is_physical_key_pressed(KEY_SHIFT):
		var side := minf(absf(delta.x), absf(delta.y))
		delta = Vector2(-side if delta.x < 0 else side, -side if delta.y < 0 else side)
	var corner: Vector2 = start.min(start + delta)
	var dimensions := delta.abs().max(Vector2.ONE)
	current.pos = [corner.x, corner.y]
	if current.kind == "polygon":
		current.vertices = preset_vertices(tool, dimensions)
	else:
		current.extent = [dimensions.x, dimensions.y]
		if tool == "rounded_rect": current.corner_radius = minf(dimensions.x, dimensions.y) * 0.2

func preset_vertices(shape: String, dimensions: Vector2) -> Array:
	var unit_vertices: Array
	match shape:
		"triangle": unit_vertices = [Vector2(0.5, 0), Vector2(1, 1), Vector2(0, 1)]
		"diamond": unit_vertices = [Vector2(0.5, 0), Vector2(1, 0.5), Vector2(0.5, 1), Vector2(0, 0.5)]
		_:
			unit_vertices = []
			for index in 10:
				var radius := 0.5 if index % 2 == 0 else 0.23
				unit_vertices.append(Vector2(0.5, 0.5) + Vector2.from_angle(index * PI / 5 - PI / 2) * radius)
	var vertices := []
	for unit_point in unit_vertices:
		var point: Vector2 = unit_point * dimensions
		vertices.append([point.x, point.y])
	return vertices

func commit_path(closed: bool) -> void:
	if path_points.size() < (3 if closed else 2) or not document.editable(): return
	if not document.paints_pixels() and document.layers[document.active].get("alpha_locked", false): return
	var position := path_points[0]
	var object := new_shape("polygon" if closed else "path", position)
	var vertices := []
	for point in path_points:
		var local := point - position
		vertices.append([local.x, local.y])
	if closed:
		var polygon := Art.polygon({"kind": "polygon", "vertices": vertices})
		if Geometry2D.triangulate_polygon(polygon).is_empty():
			status.emit("Close a shape with a simple outline that doesn’t cross itself.")
			return
	object.vertices = vertices
	if not document.append_vector_object(object):
		status.emit("The project has reached its layer limit.")
		return
	color_used.emit(color if Art.has_fill(object) else shape_outline_color())
	clear_path()

func clear_path() -> void:
	if path_points.is_empty(): return
	path_points.clear()
	selection_overlay.queue_redraw()
	path_changed.emit()

func append_point(point: Vector2, pressure: float, first := false) -> void:
	var p = clampf(pressure, 0.01, 1.0) if pressure_enabled else 0.7
	var pigment_hex := stroke_pigment_hex
	if current.brush in BrushLibrary.WET_ENGINES:
		# Closely spaced dabs share a pickup sample. Pressure and color
		# deposition still apply to every dab along the stroke.
		if first or pigment_sample_point.distance_squared_to(point) >= pigment_spacing_squared:
			sampled_pigment = sample_pigment(point)
			pigment_sample_point = point
		if first: carry = sampled_pigment
		carry = BrushLibrary.mix_pigment(stroke_pigment, sampled_pigment, carry, p,
			current.brush, stroke_mixing, current)
		pigment_hex = "#" + carry.to_html(false)
	current.points.append([point.x, point.y, p, pigment_hex])

func update_stroke(screen: Vector2, pressure: float) -> void:
	var point = to_document(screen)
	if marquee_active:
		update_marquee(point)
		return
	if not moving_selection.is_empty():
		update_selection_move(point)
		return
	if moving or resizing or node_index >= 0:
		var object = document.find_object(document.selection)
		if object.is_empty(): return
		if not edit_started:
			if point.distance_to(start) < 1.0 / zoom: return
			edit_future = document.future.duplicate(true)
			document.checkpoint()
			if moving or resizing: selected_area.clear()
			edit_started = true
		if moving:
			object.pos = [original.pos[0] + point.x - start.x, original.pos[1] + point.y - start.y]
		elif resizing:
			var old_distance = Art.bounds(original).end.distance_to(Art.v(original.pos))
			object.scale = clampf(float(original.scale) * point.distance_to(Art.v(original.pos)) / maxf(1, old_distance), 0.02, 100)
		else:
			deform_node(object, point)
		var entry: Dictionary = retained_marks.get(object.id, {})
		if not entry.is_empty(): entry.mark.queue_redraw()
		if paint_cache: paint_cache.invalidate_cache()
		if node_index >= 0: pigment.entries.erase(object.id)
		refresh_selection()
		return
	if not drawing: return
	point = point.clamp(Vector2.ZERO, Vector2(document.width, document.height))
	if current.kind == "stroke":
		var previous_count: int = current.points.size()
		append_motion(point, pressure)
		if current.points.size() == previous_count: return
	else:
		update_drag_shape(point)
	redraw_preview()

func append_motion(point: Vector2, pressure: float, finishing := false) -> void:
	if current.points.size() >= 100000: return
	raw_point = point
	if not finishing: pressure = BrushLibrary.map_pressure(pressure, current)
	raw_pressure = pressure
	var previous := Art.v(current.points[-1])
	var previous_pressure: float = current.points[-1][2] if pressure_enabled else pressure
	var distance := previous.distance_to(point)
	# Keep the filter close to the stylus even on a fast motion. The tail
	# catches up to the last real sample on release without predicting input.
	if not finishing and distance > 0.0:
		point = BrushLibrary.stabilize(point, previous, distance, stroke_smoothing, stroke_lag_limit)
		distance = previous.distance_to(point)
	if distance < (0.03 if finishing else 0.45 / zoom): return
	var spacing := maxf(1.5, float(current.size) * float(current.get("spacing", 0.16)))
	if current.brush == "ink": spacing = maxf(spacing, 0.7 / zoom)
	var count := mini(100000 - current.points.size(), mini(120, maxi(1, ceili(distance / spacing))))
	for i in range(1, count + 1):
		var t := float(i) / count
		append_point(previous.lerp(point, t), lerpf(previous_pressure, pressure, t))

func finish() -> void:
	if marquee_active: finish_marquee()
	if drawing and not current.is_empty():
		if current.kind == "stroke":
			append_motion(raw_point, raw_pressure, true)
			current.erase("live_stroke")
		if document.editable():
			if current.kind == "stroke" and document.paints_pixels():
				var erasing: bool = current.get("erasing", false)
				if document.commit_paint(current, erasing) != OK:
					status.emit("The project has reached its embedded paint size limit.")
				elif not erasing: color_used.emit(stroke_pigment)
			else:
				var has_paint := (not current.has("paint_mask") and not current.has("clip")) or Art.clipped_stroke_has_paint(current)
				if has_paint and (current.kind != "path" or Art.v(current.vertices[-1]).length() > 0.01):
					var physical_zoom: float = zoom * get_screen_transform().get_scale().x
					var ink_gap := clampf(Document.VectorUnion.TIP_GAP / maxf(physical_zoom, 0.01), 0.25, 4.0)
					if document.append_vector_object(current, ink_gap):
						color_used.emit(Color(current.outline_color if current.get("fill_enabled", true) == false else current.color))
					else:
						status.emit("The project has reached its layer limit.")
	elif edit_started:
		document.commit()
	edit_started = false
	end_preview()
	current = {}
	drawing = false
	moving = false
	moving_selection.clear()
	resizing = false
	node_index = -1
	node_arc.clear()
	refresh_selection()

func cancel() -> void:
	clear_path()
	if document != null and not marquee_active and (not selected_area.is_empty() or not document.area_selection.is_empty()):
		clear_selection()
	marquee_active = false
	lasso_points.clear()
	if edit_started:
		if not document.history.is_empty(): document.restore(document.history.pop_back())
		document.future = edit_future
		document.changed.emit()
	edit_started = false
	end_preview()
	current = {}
	drawing = false
	moving = false
	moving_selection.clear()
	resizing = false
	node_index = -1
	node_arc.clear()
	refresh_selection()

func set_clip_from_selection() -> bool:
	var contours: Array[PackedVector2Array] = []
	if selected_area.size() >= 3:
		contours.append(selected_area)
	else:
		for item in document.selected_items():
			if not layer_is_visible(item.layer): continue
			for outline in Art.selection_contours(item.object):
				Art.add_selection_contour(contours, outline)
	if contours.is_empty(): return false
	var packed := Art.pack_contours(contours)
	if packed.size() > 1 and not Document.valid_paint_mask(packed):
		status.emit("This selection is too detailed. Draw an area around the part you want to paint.")
		return false
	clip_regions = packed
	clip_enabled = true
	refresh_selection()
	return true

func clear_paint_limit() -> void:
	clip_enabled = false
	clip_regions.clear()
	refresh_selection()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		finish()
		restore_android_pointer_buffering()
		dragging = false
		reset_touch()
	elif what == NOTIFICATION_APPLICATION_RESUMED and paint_cache:
		paint_cache.invalidate_cache()
