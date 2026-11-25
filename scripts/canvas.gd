extends Control
const Art = preload("res://scripts/artwork.gd")
const VectorFill = preload("res://scripts/vector_fill.gd")
const Document = preload("res://scripts/document.gd")
const PigmentIndex = preload("res://scripts/pigment_index.gd")
const BrushLibrary = preload("res://scripts/brush_library.gd")
const OpacityStack = preload("res://scripts/opacity_stack.gd")
const IsolatedOpacity = preload("res://scripts/isolated_opacity.gd")
const AreaSelection = preload("res://scripts/area_selection.gd")
const Symmetry = preload("res://scripts/drawing_symmetry.gd")
const AREA_TOOLS := AreaSelection.TOOLS
const SELECTION_PADDING := 5.0
const RESIZE_HIT_RADIUS := 16.0
const ROTATION_HANDLE_GAP := 26.0
const ROTATION_HANDLE_RADIUS := 14.0
const SNAP_DISTANCE := 8.0
const PAINT_CACHE_THRESHOLD := 1200
const DOCUMENT_CACHE_THRESHOLD := 2000
const MAX_PAINT_CACHES := 4
const CACHE_NAVIGATION_SETTLE := 0.12
const PICK_GRID_THRESHOLD := 160
const PICK_CELL_SIZE := 96.0
const MAX_PICK_CELLS := 64
const WET_MESH_SAMPLE_BUDGET := 26000
const MAX_WET_MESH_SAMPLES := 2048
const INK_MESH_BYTE_BUDGET := 64 * 1024 * 1024
const DENSE_INK_MESH_THRESHOLD := 50000
const MAX_CACHED_INK_POINTS := 8192
const INK_MESH_BYTES := &"_ink_mesh_bytes"
const STROKE_REDO_MESH_LIMIT := 6
const STROKE_REDO_SAMPLE_LIMIT := 900
const WET_PIGMENT_SPACING := 0.26
const INK_SAMPLES_PER_MOTION := 16
const PAINT_STAGING_USEC := 4500
const ANDROID_POINTER_IDLE := 0.18
const DEFAULT_STROKE_NODE_SPREAD := 0.25
const SHAPE_TOOLS := {
	"rect": "rect", "square": "rect", "rounded_rect": "rect", "ellipse": "ellipse", "circle": "ellipse",
	"triangle": "polygon", "diamond": "polygon", "star": "polygon", "line": "path", "arrow": "path", "path": "path",
}
signal path_changed
signal node_mode_changed
signal status(message)
signal fill_requested(point: Vector2)
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
var transform_caches: Array[IsolatedOpacity] = []
var navigation_caches: Array[IsolatedOpacity] = []
var cache_navigation_timer: Timer
var select_across_layers := false
var keep_selecting := false
var selection_move_bounds := Rect2()
var selection_rotating := false
var selection_rotation_delta := 0.0
var snap_rotation := false
var snap_to_canvas := false
var drag_guides := Vector2.INF
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
var staged_paint: Document.PaintTiles
var staged_paint_layer := ""
var staged_paint_revision := -1
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
var page_clip: Control
var artwork_root: Node2D
var preview_root: Node2D
var preview_surface: IsolatedOpacity
var selection_overlay: Node2D
var retained_marks: Dictionary = {}
var layer_renderers: Dictionary = {}
var pick_grids := {}
var solo_layer_id := ""
var merge_renderers: Dictionary = {}
var cache_completed_paint := OS.has_feature("android")
var cache_extra_layers := OS.has_feature("android")
var cache_recent_strokes := OS.has_feature("android")
var paint_cache: IsolatedOpacity
var layer_cache_costs := {}
var wet_mesh_samples := 0
var ink_mesh_bytes := 0
var stroke_redo_meshes := {}
var overview_cache := false
var opacity_preview_layer := ""
var opacity_preview_value := 1.0
static var checker_texture: ImageTexture
static var grid_texture: ImageTexture
var live_batch: Node2D
var live_symmetry_batches: Array[Node2D] = []
var live_first := 0
var symmetry_mode := Symmetry.Mode.OFF
var symmetry_arms := 6
var symmetry_guides := true
var symmetry_anchor := Vector2(0.5, 0.5)
var placing_symmetry_center := false
var symmetry_instances: Array[Dictionary] = []
var cut_target := ""
var cut_points := PackedVector2Array()
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
	set_process(false)
	mouse_exited.connect(clear_pointer_metrics)
	resized.connect(resize_view)
	page_clip = Control.new()
	page_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_clip.clip_contents = true
	add_child(page_clip)
	artwork_root = Node2D.new()
	page_clip.add_child(artwork_root)
	if not exporting and cache_extra_layers:
		cache_navigation_timer = Timer.new()
		cache_navigation_timer.one_shot = true
		cache_navigation_timer.timeout.connect(finish_cache_navigation)
		add_child(cache_navigation_timer)
	if not exporting and OS.has_feature("android"):
		android_pointer_idle = Timer.new()
		android_pointer_idle.one_shot = true
		android_pointer_idle.timeout.connect(restore_android_pointer_buffering)
		add_child(android_pointer_idle)
	if not exporting:
		preview_root = Node2D.new()
		page_clip.add_child(preview_root)
		selection_overlay = Node2D.new()
		selection_overlay.draw.connect(draw_selection)
		add_child(selection_overlay)
	sync_artwork()

func _process(_delta: float) -> void:
	if staged_paint: staged_paint.stage_stroke(current, PAINT_STAGING_USEC)

func _exit_tree() -> void:
	end_paint_staging()

func stage_wide_paint(layer: Dictionary) -> void:
	# Stage final brush footprints in private tiles. The document receives
	# one edit when the pen lifts.
	if layer.get("type", "vector") != "paint" or current.brush not in ["soft", "paint", "mix"] or current.size < 96.0 \
			or current.get("taper_start", 0.0) > 0.0 or current.get("taper_end", 0.0) > 0.0 \
			or current.get("erasing", false) or layer.get("alpha_locked", false): return
	staged_paint = Document.PaintTiles.new()
	staged_paint.prepare_layer(layer, Vector2i(ceili(document.width), ceili(document.height)))
	staged_paint.begin_android_stage()
	staged_paint_layer = layer.id
	staged_paint_revision = document.revision
	set_process(true)

func end_paint_staging() -> void:
	if staged_paint: staged_paint.cancel_stage()
	staged_paint = null
	set_process(false)

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
	defer_navigation_cache_rebuilds()
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
	defer_navigation_cache_rebuilds()
	redraw_view()

func to_document(point: Vector2) -> Vector2:
	return (point - origin) / zoom

func page_bounds() -> Rect2:
	return Rect2(0, 0, document.width, document.height)

func _draw() -> void:
	if document == null: return
	if not exporting:
		if grid_texture == null:
			var tile := Image.create_empty(28, 28, false, Image.FORMAT_RGB8)
			tile.fill(Color("#111111"))
			tile.set_pixel(18, 18, Color("#252525"))
			grid_texture = ImageTexture.create_from_image(tile)
		draw_texture_rect(grid_texture, Rect2(Vector2.ZERO, size), true)
		draw_rect(Rect2(origin + Vector2(6, 9), Vector2(document.width, document.height) * zoom), Color(0, 0, 0, 0.24))
	var page := Rect2(origin, page_bounds().size * zoom)
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
	if symmetry_mode != Symmetry.Mode.OFF and (placing_symmetry_center or (symmetry_guides and tool in ["brush", "erase"])):
		draw_symmetry_guides()
	if not cut_points.is_empty():
		var trace := PackedVector2Array()
		for point in cut_points: trace.append(origin + point * zoom)
		if trace.size() >= 2:
			selection_overlay.draw_polyline(trace, Color("#172b28"), 3.5, true)
			selection_overlay.draw_polyline(trace, Color("#a4f0d2"), 1.5, true)
		if trace.size() >= 3:
			selection_overlay.draw_dashed_line(trace[-1], trace[0], Color("#a4f0d2"), 1.3, 6.0)
		return
	if drawing and current.get("erasing", false):
		var radius := maxf(1.5, float(current.size) * zoom * 0.5)
		selection_overlay.draw_circle(origin + raw_point * zoom, radius, Color("#a4f0d2"), false, 1.2, true)
		for copy in symmetry_instances:
			var point := Art.object_transform(copy) * raw_point
			if page_bounds().has_point(point):
				selection_overlay.draw_circle(origin + point * zoom, radius, Color("#a4f0d2"), false, 1.2, true)
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
	if selection_rotating and edit_started:
		draw_rotation_preview()
		return
	if moving and edit_started: draw_drag_guides()
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
	var bounds = Art.bounds(object) if moving_selection.is_empty() else selection_preview_bounds
	var box = Rect2(origin + bounds.position * zoom, bounds.size * zoom)
	selection_overlay.draw_rect(box.grow(SELECTION_PADDING), Color("#67d6b0"), false, 1.2)
	if tool != "nodes":
		if not keep_selecting:
			selection_overlay.draw_rect(Rect2(box.end - Vector2(5, 5), Vector2(10, 10)), Color("#a1f2d4"))
			draw_rotation_handle(bounds)
	elif object.kind in ["stroke", "polygon", "path"]:
		var points: Array = node_points(object)
		var added: Array = object.get("node_anchors", [])
		var pose := Art.object_transform(object)
		for index in editable_nodes(object):
			var point = origin + (pose * Art.v(points[index])) * zoom
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
	if not keep_selecting:
		var handle: Vector2 = origin + bounds.end * zoom
		selection_overlay.draw_rect(Rect2(handle - Vector2(5, 5), Vector2(10, 10)), Color("#a1f2d4"))
		draw_rotation_handle(bounds)

func rotation_handle(bounds: Rect2) -> Vector2:
	var handle := Vector2(bounds.get_center().x, bounds.position.y - ROTATION_HANDLE_GAP / zoom)
	if origin.y + handle.y * zoom < ROTATION_HANDLE_RADIUS:
		handle.y = bounds.end.y + ROTATION_HANDLE_GAP / zoom
	return handle

func draw_rotation_handle(bounds: Rect2, radians := 0.0) -> void:
	var center := bounds.get_center()
	var handle := rotation_handle(bounds)
	var edge := Vector2(center.x, bounds.position.y if handle.y < center.y else bounds.end.y)
	var grip: Vector2 = origin + (center + (handle - center).rotated(radians)) * zoom
	var stem: Vector2 = origin + (center + (edge - center).rotated(radians)) * zoom
	selection_overlay.draw_line(stem, grip, Color("#67d6b0"), 1.4, true)
	selection_overlay.draw_circle(grip, 6.0, Color("#172a21"), true, -1.0, true)
	selection_overlay.draw_circle(grip, 6.0, Color("#a1f2d4"), false, 1.5, true)

func draw_rotation_preview() -> void:
	var center := selection_move_bounds.get_center()
	var corners := PackedVector2Array()
	for point in AreaSelection.corners(selection_move_bounds):
		corners.append(origin + (center + (point - center).rotated(selection_rotation_delta)) * zoom)
	selection_overlay.draw_polyline(Art.close_points(corners), Color("#a1f2d4"), 1.4, true)
	draw_rotation_handle(selection_move_bounds, selection_rotation_delta)

func draw_drag_guides() -> void:
	var ink := Color("#56beb4")
	if is_finite(drag_guides.x):
		var top: Vector2 = origin + Vector2(drag_guides.x * zoom, 0.0)
		selection_overlay.draw_line(top, top + Vector2(0, document.height * zoom), ink, 1.0, true)
	if is_finite(drag_guides.y):
		var left: Vector2 = origin + Vector2(0.0, drag_guides.y * zoom)
		selection_overlay.draw_line(left, left + Vector2(document.width * zoom, 0), ink, 1.0, true)

func snap_canvas_move(offset: Vector2) -> Vector2:
	drag_guides = Vector2.INF
	var correction := Vector2.ZERO
	var box := Rect2(selection_move_bounds.position + offset, selection_move_bounds.size)
	var page := Vector2(document.width, document.height)
	for axis in 2:
		var closest: float = SNAP_DISTANCE / zoom
		for target in [0.0, page[axis] * 0.5, page[axis]]:
			for edge in [box.position[axis], box.get_center()[axis], box.end[axis]]:
				var gap: float = target - edge
				if absf(gap) >= closest: continue
				closest = absf(gap)
				correction[axis] = gap
				drag_guides[axis] = target
	return offset + correction

func items_bounds(items: Array[Dictionary]) -> Rect2:
	var bounds := Rect2()
	for item in items:
		if not layer_is_visible(item.layer): continue
		var box := pick_bounds(item.object)
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
		if not keep_selecting: clear_selection()
		refresh_selection()
		return
	var bounds := Art.polygon_bounds(region)
	if bounds.size.x * zoom < 4 or bounds.size.y * zoom < 4:
		if not keep_selecting: clear_selection()
		refresh_selection()
		return
	if tool == "select_lasso" and Geometry2D.triangulate_polygon(region).is_empty():
		status.emit("Draw a single loop to make a freehand selection.")
		return
	selected_area = region
	var ids: Array[String] = []
	var previously_selected := {}
	if keep_selecting:
		for item in transformable_items():
			ids.append(item.object.id)
			previously_selected[item.object.id] = true
	var page := page_bounds()
	for layer_index in document.layers.size():
		var layer: Dictionary = document.layers[layer_index]
		if not selectable_layer(layer_index): continue
		for object in layer.objects:
			if object.get("paint_tile", false): continue
			var visible_bounds := pick_bounds(object).intersection(page)
			if visible_bounds.has_area() and AreaSelection.encloses(tool, region, bounds, visible_bounds):
				if not previously_selected.has(object.id): ids.append(object.id)
				if select_across_layers: document.active = layer_index
	var blocked: bool = document.select_artwork(ids, solo_layer_id)
	var count: int = document.area_selection.size() + (0 if document.selection.is_empty() else 1)
	if keep_selecting and count > 0: selected_area.clear()
	selected.emit({})
	if blocked and count == 0: status.emit("Show and unlock the group’s layers to select it.")
	elif ids.is_empty(): status.emit("Area selected. Use Paint inside selection to keep brush marks inside it.")
	else:
		status.emit("%d selected · Draw another area to add more." % count if keep_selecting
			else "%d selected · Drag the box to move or the corner to resize." % count)
	refresh_selection()

func toggle_object_pick(point: Vector2) -> void:
	var target := hit(point, true)
	if target.is_empty(): return
	var ids: Array[String] = []
	var picked := false
	var group: String = target.get("artwork_group", "")
	for item in transformable_items():
		var object: Dictionary = item.object
		if object.id == target.id or (not group.is_empty() and object.get("artwork_group", "") == group):
			picked = true
		else:
			ids.append(object.id)
	if not picked: ids.append(target.id)
	var blocked: bool = document.select_artwork(ids, solo_layer_id)
	selected_area.clear()
	selected.emit({})
	if blocked: status.emit("Show and unlock the group’s layers to select it.")
	else: status.emit("Tap objects or groups to add or remove them. Turn off Keep selecting to move them.")
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
		or selection_resize_hit(bounds, point) or selection_rotation_hit(bounds, point))

func selection_rotation_hit(bounds: Rect2, point: Vector2) -> bool:
	return rotation_handle(bounds).distance_to(point) <= ROTATION_HANDLE_RADIUS / zoom

func transformable_items() -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	for item in document.selected_items():
		if layer_is_visible(item.layer) and not item.object.get("paint_tile", false): picked.append(item)
	return picked

func turn_selection(radians: float, flip := 0) -> bool:
	var items := transformable_items()
	if items.is_empty(): return false
	var center := exact_selection_bounds(items).get_center()
	var changes: Array[Dictionary] = []
	for item in items:
		var captured := Document.capture_transform_item(item)
		Document.turn_object(captured, center, radians, flip)
		changes.append(captured)
	keep_transformed_items_on_page(changes)
	selected_area.clear()
	document.record_transform(changes)
	return true

func place_selection(fit_page: bool) -> void:
	var items := transformable_items()
	if items.is_empty(): return
	var bounds := exact_selection_bounds(items)
	var page := page_bounds()
	var ratio := 1.0
	if fit_page and bounds.has_area():
		ratio = minf(page.size.x / bounds.size.x, page.size.y / bounds.size.y)
	apply_precise_transform(page.get_center() - bounds.get_center(), ratio, 0.0)

func apply_precise_transform(offset: Vector2, ratio: float, radians: float) -> void:
	var items := transformable_items()
	if items.is_empty(): return
	var pivot := exact_selection_bounds(items).get_center()
	var minimum := 0.0
	var maximum := INF
	for item in items:
		var scale: float = item.object.scale
		minimum = maxf(minimum, minf(1.0, 0.02 / scale))
		maximum = minf(maximum, 1000.0 / scale)
	var rotated_bounds := Transform2D(radians, Vector2.ZERO) * Rect2(Vector2.ZERO, exact_selection_bounds(items).size)
	var page := page_bounds()
	for axis in 2:
		if rotated_bounds.size[axis] > 0.0:
			maximum = minf(maximum, maxf(1.0, page.size[axis] / rotated_bounds.size[axis]))
	ratio = clampf(ratio, minimum, maximum)
	var changes: Array[Dictionary] = []
	for item in items:
		var captured := Document.capture_transform_item(item)
		Document.turn_object(captured, pivot, radians, 0)
		var object: Dictionary = item.object
		var position := pivot + (Art.v(object.pos) - pivot) * ratio + offset
		object.pos = [position.x, position.y]
		object.scale *= ratio
		changes.append(captured)
	keep_transformed_items_on_page(changes)
	selected_area.clear()
	document.record_transform(changes)

func keep_transformed_items_on_page(items: Array[Dictionary], bounds := Rect2()) -> void:
	if not bounds.has_area(): bounds = exact_selection_bounds(items)
	var page := page_bounds()
	var shift := Vector2.ZERO
	for axis in 2:
		if bounds.size[axis] <= page.size[axis]:
			shift[axis] = clampf(0.0, -bounds.position[axis], page.end[axis] - bounds.end[axis])
		else:
			shift[axis] = page.get_center()[axis] - bounds.get_center()[axis]
	if shift.is_zero_approx(): return
	for item in items:
		var position := Art.v(item.object.pos) + shift
		item.object.pos = [position.x, position.y]

func exact_selection_bounds(items: Array[Dictionary]) -> Rect2:
	var bounds := Art.bounds(items[0].object)
	for index in range(1, items.size()): bounds = bounds.merge(Art.bounds(items[index].object))
	return bounds

func editable_selected_object() -> Dictionary:
	for item in document.selected_items():
		if layer_is_visible(item.layer): return item.object
	return {}

func begin_selection_transform(point: Vector2) -> bool:
	return begin_selection_move(point)

func prepare_position_edit(item: Dictionary) -> void:
	var captured := Document.capture_transform_item(item)
	captured.preview_pos = item.object.pos.duplicate()
	moving_selection.append(captured)

func begin_selection_move(point: Vector2) -> bool:
	var items := transformable_items()
	if items.is_empty(): return false
	var bounds := Art.bounds(items[0].object) if items.size() == 1 else items_bounds(items)
	if not selection_box_hit(bounds, point): return false
	selection_scale_min = 0.0
	selection_scale_max = 1000.0
	for item in items:
		if layer_is_visible(item.layer):
			var scale := float(item.object.scale)
			prepare_position_edit(item)
			selection_scale_min = maxf(selection_scale_min, minf(1.0, 0.02 / scale))
			selection_scale_max = minf(selection_scale_max, 1000.0 / scale)
	selection_move_bounds = bounds
	selection_preview_bounds = bounds
	edit_started = false
	selection_rotating = selection_rotation_hit(bounds, point)
	selection_rotation_delta = 0.0
	resizing = not selection_rotating and selection_resize_hit(bounds, point)
	moving = not resizing
	return true

func update_selection_move(point: Vector2) -> void:
	var offset: Vector2 = point - start
	if not edit_started:
		if offset.length() < 1.0 / zoom: return
		selected_area.clear()
		edit_started = true
		for item in moving_selection:
			var holder: Node2D = layer_renderers.get(item.layer_id)
			if is_artwork_cache(holder) and holder not in transform_caches:
				transform_caches.append(holder)
				holder.show_live_marks()
	if selection_rotating:
		var center := selection_move_bounds.get_center()
		var delta := (start - center).angle_to(point - center)
		if snap_rotation: delta = snappedf(delta, PI / 12.0)
		selection_rotation_delta = delta
		for item in moving_selection:
			Document.turn_object(item, center, delta, 0)
		var rotated_bounds := Transform2D(delta, center) * Rect2(selection_move_bounds.position - center, selection_move_bounds.size)
		keep_transformed_items_on_page(moving_selection, rotated_bounds)
		for item in moving_selection:
			update_mark_pose(item.object)
		refresh_selection()
		return
	var ratio := 1.0
	var pivot := selection_move_bounds.position
	if resizing:
		if moving_selection.size() == 1:
			pivot = moving_selection[0].position
			ratio = point.distance_to(pivot) / maxf(1.0, selection_move_bounds.end.distance_to(pivot))
		else:
			var diagonal := selection_move_bounds.size
			ratio = 1.0 + offset.dot(diagonal) / diagonal.length_squared()
		ratio = clampf(ratio, selection_scale_min, selection_scale_max)
		var relative_start := selection_move_bounds.position - pivot
		var relative_end := selection_move_bounds.end - pivot
		for axis in 2:
			if relative_start[axis] < 0.0:
				ratio = minf(ratio, maxf(1.0, pivot[axis] / -relative_start[axis]))
			if relative_end[axis] > 0.0:
				ratio = minf(ratio, maxf(1.0, (page_bounds().end[axis] - pivot[axis]) / relative_end[axis]))
		offset = Vector2.ZERO
	elif snap_to_canvas:
		offset = snap_canvas_move(offset)
	if not resizing:
		offset = offset.clamp((-selection_move_bounds.position).min(Vector2.ZERO),
			(page_bounds().end - selection_move_bounds.end).max(Vector2.ZERO))
	selection_preview_bounds = Rect2(pivot + (selection_move_bounds.position - pivot) * ratio + offset,
		selection_move_bounds.size * ratio)
	for item in moving_selection:
		var position: Vector2 = pivot + (item.position - pivot) * ratio + offset
		item.preview_pos[0] = position.x
		item.preview_pos[1] = position.y
		item.object.pos = item.original_pos if position == item.position else item.preview_pos
		if resizing: item.object.scale = item.scale if ratio == 1.0 else item.scale * ratio
		update_mark_pose(item.object)
	refresh_selection()

func refresh_transform_cache() -> void:
	for holder in transform_caches:
		if is_instance_valid(holder): holder.resume_cache()
	transform_caches.clear()

func defer_navigation_cache_rebuilds() -> void:
	if not cache_navigation_timer or drawing: return
	var density := maxf(0.01, get_screen_transform().get_scale().x)
	for holder in layer_renderers.values():
		if not is_artwork_cache(holder) or not holder.visible: continue
		if holder.uses_document_cache(zoom, density): continue
		if holder == paint_cache and holder.opacity >= 1.0: continue
		if holder in navigation_caches or holder in transform_caches: continue
		holder.show_live_marks()
		navigation_caches.append(holder)
	if not navigation_caches.is_empty(): cache_navigation_timer.start(CACHE_NAVIGATION_SETTLE)

func finish_cache_navigation() -> void:
	if cache_navigation_timer: cache_navigation_timer.stop()
	for holder in navigation_caches:
		if is_instance_valid(holder): holder.resume_cache()
	navigation_caches.clear()

func redraw_view() -> void:
	if artwork_root and document != null:
		var density := 1.0 if exporting else maxf(0.01, get_screen_transform().get_scale().x)
		var overview := cache_completed_paint and not exporting and IsolatedOpacity.use_overview(size, zoom, density, overview_cache)
		if overview != overview_cache:
			overview_cache = overview
			if not drawing: # Switch once when crossing the zoom band.
				sync_artwork()
				return
		page_clip.position = origin
		page_clip.size = page_bounds().size * zoom
		artwork_root.scale = Vector2.ONE * zoom
		if preview_root and preview_root.get_parent() == page_clip:
			preview_root.scale = Vector2.ONE * zoom
		for holder in layer_renderers.values():
			if holder is IsolatedOpacity and holder.visible: holder.update_view(size, origin, zoom, density)
		for holder in merge_renderers.values():
			if holder is IsolatedOpacity: holder.update_view(size, origin, zoom, density)
	refresh_selection()
	queue_redraw()

func refresh_selection() -> void:
	if selection_overlay: selection_overlay.queue_redraw()

func symmetry_center() -> Vector2:
	return symmetry_anchor * page_bounds().size

func configure_symmetry(mode: int, arms: int, show_guides: bool) -> void:
	finish()
	symmetry_mode = mode
	symmetry_arms = clampi(arms, 2, 12)
	symmetry_guides = show_guides
	placing_symmetry_center = false
	refresh_selection()

func draw_symmetry_guides() -> void:
	var center: Vector2 = origin + symmetry_center() * zoom
	var visible := Rect2(origin, page_bounds().size * zoom).intersection(Rect2(Vector2.ZERO, size))
	if not visible.has_area(): return
	if symmetry_mode == Symmetry.Mode.RADIAL:
		for arm in symmetry_arms:
			draw_symmetry_line(center, Vector2.from_angle(TAU * arm / symmetry_arms), visible, true)
	else:
		if symmetry_mode in [Symmetry.Mode.VERTICAL, Symmetry.Mode.FOUR_WAY]:
			draw_symmetry_line(center, Vector2.DOWN, visible, false)
		if symmetry_mode in [Symmetry.Mode.HORIZONTAL, Symmetry.Mode.FOUR_WAY]:
			draw_symmetry_line(center, Vector2.RIGHT, visible, false)
	if visible.has_point(center):
		selection_overlay.draw_circle(center, 5.0, Color("#175343"))
		selection_overlay.draw_circle(center, 3.0, Color("#bbf1dd"))

func draw_symmetry_line(center: Vector2, direction: Vector2, box: Rect2, ray: bool) -> void:
	var first := 0.0 if ray else -INF
	var last := INF
	for axis in 2:
		if absf(direction[axis]) < 0.00001:
			if center[axis] < box.position[axis] or center[axis] > box.end[axis]: return
			continue
		var left := (box.position[axis] - center[axis]) / direction[axis]
		var right := (box.end[axis] - center[axis]) / direction[axis]
		first = maxf(first, minf(left, right))
		last = minf(last, maxf(left, right))
	if first >= last: return
	var a := center + direction * first
	var b := center + direction * last
	selection_overlay.draw_dashed_line(a, b, Color(0.09, 0.35, 0.28, 0.62), 2.2, 8.0, true, true)
	selection_overlay.draw_dashed_line(a, b, Color(0.53, 0.91, 0.76, 0.78), 1.0, 8.0, true, true)

func validate_solo_layer() -> void:
	if solo_layer_id.is_empty(): return
	var index: int = document.layer_index(solo_layer_id)
	if index < 0 or not document.layers[index].visible: solo_layer_id = ""

func set_solo_layer(layer_id: String) -> void:
	if solo_layer_id == layer_id: return
	solo_layer_id = layer_id
	refresh_layer_visibility()

func refresh_layer_visibility() -> void:
	validate_solo_layer()
	var missing: Array[String] = []
	for layer in document.layers:
		var shown := layer_is_visible(layer)
		var holder: Node2D = layer_renderers.get(layer.id)
		if holder:
			var revealing := shown and not holder.visible
			holder.visible = shown
			if revealing and holder is IsolatedOpacity:
				var density := maxf(0.01, get_screen_transform().get_scale().x)
				holder.update_view(size, origin, zoom, density)
		elif shown:
			missing.append(layer.id)
	if not missing.is_empty():
		sync_artwork(missing[0] if missing.size() == 1 else "")
		return
	pigment_dirty = true
	refresh_selection()

func layer_is_visible(layer: Dictionary) -> bool:
	return layer.visible and (solo_layer_id.is_empty() or layer.id == solo_layer_id)

func update_content_marks(change: Dictionary) -> bool:
	if not change.has("layer"): return false
	var holder: Node2D = layer_renderers.get(change.layer)
	if change.has("redraw"):
		var object: Dictionary = change.redraw
		var entry: Dictionary = retained_marks.get(object.id, {})
		if not entry.is_empty():
			entry.appearance = object.duplicate()
			if change.get("geometry", false): entry.erase("bounds")
			entry.mark.queue_redraw()
			if is_artwork_cache(holder): holder.invalidate_mark(entry.mark)
		return true
	var cached := is_artwork_cache(holder)
	if not holder or (holder is IsolatedOpacity and not cached): return false
	var parent := holder_artwork(holder)
	var redraw_recent := false
	var redraw_base := false
	for id in change.remove:
		if not retained_marks.has(id): continue
		var entry: Dictionary = retained_marks[id]
		var mark: Node2D = entry.mark
		if mark.get_parent() == parent:
			redraw_base = true
		elif cached and holder.is_recent_mark(mark):
			redraw_recent = true
		else:
			return false
		if layer_cache_costs.has(change.layer):
			layer_cache_costs[change.layer] -= cache_sample_cost(entry.object)
		if change.get("undo_append", false): remember_redo_mesh(entry)
		remove_mark(mark)
		retained_marks.erase(id)
	for object in change.add:
		retained_marks[object.id] = mount_mark(parent, object, change.layer)
	if cached:
		if redraw_base or not change.add.is_empty(): holder.invalidate_cache()
		if redraw_recent: holder.invalidate_recent()
	return true

func on_artwork_changed() -> void:
	finish_cache_navigation()
	if not cut_target.is_empty() and (document.selection != cut_target
			or not document.cut_target_reason(cut_selection()).is_empty()):
		stop_cutting()
	var resync: Array = document.content_on_commit.get("resync", [])
	if not resync.is_empty() and resync.size() <= 3:
		for id in resync: sync_artwork(id)
		return
	if document.content_on_commit.get("layer_order", false):
		var order := 0
		for layer in document.layers:
			var holder: Node2D = layer_renderers.get(layer.id)
			if not holder: continue
			if holder.get_index() != order: artwork_root.move_child(holder, order)
			order += 1
		pigment_dirty = true
		refresh_selection()
		return
	if document.content_on_commit.has("group_ids"):
		for id in document.content_on_commit.group_ids:
			var entry: Dictionary = retained_marks.get(id, {})
			if entry.is_empty(): continue
			if entry.object.has("artwork_group"): entry.appearance.artwork_group = entry.object.artwork_group
			else: entry.appearance.erase("artwork_group")
		refresh_selection()
		return
	var flag: String = document.content_on_commit.get("layer_flag", "")
	if not flag.is_empty():
		if flag == "visible": refresh_layer_visibility()
		else: refresh_selection()
		return
	var page_resize: bool = document.content_on_commit.get("page_resize", false)
	if page_resize or not document.transformed_on_commit.is_empty():
		for layer_id in document.content_on_commit.get("layers", []): pick_grids.erase(layer_id)
		for transformed in document.transformed_on_commit:
			var mark := update_mark_pose(transformed)
			if mark:
				var holder: Node2D = layer_renderers.get(retained_marks[transformed.id].layer)
				if is_artwork_cache(holder): holder.invalidate_mark(mark)
		pigment_dirty = true
		if page_resize:
			last_page_size = Vector2(document.width, document.height)
			for holder in layer_renderers.values():
				if is_artwork_cache(holder) and holder.document_bounds.has_area():
					holder.document_bounds = page_bounds().grow(4.0)
			if view_fitted and not exporting: fit()
			else: redraw_view()
		else:
			refresh_selection()
		return
	var content: Dictionary = document.content_on_commit
	if content.has("append_set") and append_vector_marks(content.layer, content.append_set):
		return
	if not content.is_empty() and update_content_marks(content):
		pick_grids.erase(content.layer)
		if not pigment_dirty and content.has("remove") and content.get("add", []).is_empty():
			for id in content.remove: pigment.erase_entry(id)
		else:
			pigment_dirty = true
		refresh_selection()
		return
	var object: Dictionary = document.appended_on_commit
	var layer: Dictionary = document.layers[document.active] if not document.layers.is_empty() else {}
	var holder: Node2D = layer_renderers.get(layer.get("id"))
	if not object.is_empty() and holder and not object.has("opacity_groups") and not retained_marks.has(object.id) \
			and not layer.objects.is_empty() and is_same(layer.objects.back(), object):
		if should_promote_cache(layer, object):
			sync_artwork()
			return
		var entry := mount_mark(holder_artwork(holder), object, layer.id)
		retained_marks[object.id] = entry
		if pick_grids.has(layer.id): index_pick_bounds(pick_grids[layer.id], layer.objects.size() - 1, object)
		if is_artwork_cache(holder): holder.append_mark(entry.mark)
		if not pigment_dirty and layer_is_visible(layer):
			pigment_dirty = not pigment.append_latest(layer, document.active, object)
		refresh_selection()
		return
	sync_artwork()

func append_vector_marks(layer_id: String, strokes: Array) -> bool:
	var holder: Node2D = layer_renderers.get(layer_id)
	if not holder: return false
	if strokes.any(func(stroke): return stroke.has("opacity_groups")): return false
	var layer: Dictionary = document.layers[document.active]
	for stroke in strokes:
		if should_promote_cache(layer, stroke):
			sync_artwork()
			return true
	var first: int = layer.objects.size() - strokes.size()
	var shared_mesh: ArrayMesh
	var shared_style := {}
	if (not strokes.is_empty() and strokes[0].kind == "stroke" and not strokes[0].has("clip") and not strokes[0].has("paint_mask")
			and Art.uses_stroke_mesh(strokes[0])):
		shared_style = Art.local_stroke_style(strokes[0])
	for index in strokes.size():
		var stroke: Dictionary = strokes[index]
		var entry := mount_mark(holder_artwork(holder), stroke, layer_id)
		var mark: Node2D = entry.mark
		if (not shared_style.is_empty() and mark.has_meta(Art.WET_MESH_SAMPLES)
				and Art.local_stroke_style(stroke) == shared_style):
			if not shared_mesh:
				shared_mesh = mark.get_meta(Art.WET_MESH) if mark.has_meta(Art.WET_MESH) else Art.build_wet_mesh(stroke, 0, stroke.points.size())
			if shared_mesh: mark.set_meta(Art.WET_MESH, shared_mesh)
		retained_marks[stroke.id] = entry
		if is_artwork_cache(holder): holder.append_mark(entry.mark)
		if pick_grids.has(layer_id): index_pick_bounds(pick_grids[layer_id], first + index, stroke)
	pigment_dirty = true
	refresh_selection()
	return true

func should_promote_cache(layer: Dictionary, object: Dictionary) -> bool:
	var layer_id: String = layer.id
	if not cache_completed_paint or not layer_cache_costs.has(layer_id): return false
	var cost: int = layer_cache_costs[layer_id] + cache_sample_cost(object)
	layer_cache_costs[layer_id] = cost
	if float(layer.get("opacity", 1.0)) < 1.0: return false
	# Build additional surfaces on artwork synchronization, outside the
	# append path. Allocating one automatically stalls a pen lift.
	return not paint_cache and (cost >= PAINT_CACHE_THRESHOLD or overview_cache)

func remember_redo_mesh(entry: Dictionary) -> void:
	var mark: Node2D = entry.mark
	if mark.has_meta(INK_MESH_BYTES): return
	if not mark.has_meta(Art.WET_MESH) or int(mark.get_meta(Art.WET_MESH_SAMPLES, 0)) > STROKE_REDO_SAMPLE_LIMIT: return
	if stroke_redo_meshes.size() >= STROKE_REDO_MESH_LIMIT:
		stroke_redo_meshes.erase(stroke_redo_meshes.keys()[0])
	stroke_redo_meshes[entry.object.id] = {"object": entry.appearance, "geometry": mark.get_meta(Art.WET_MESH)}

func inherit_wet_geometry(mark: Node2D, object: Dictionary) -> void:
	if stroke_redo_meshes.has(object.id):
		var entry: Dictionary = stroke_redo_meshes[object.id]
		stroke_redo_meshes.erase(object.id)
		if entry.object == object:
			mark.set_meta(Art.WET_MESH, entry.geometry)

func mount_mark(holder: Node2D, object: Dictionary, layer_id: String) -> Dictionary:
	var mark := Node2D.new()
	if object.kind == "image": mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	Art.use_screen_edges(mark, object)
	var cache_ink: bool = not exporting and object.kind == "stroke" and Art.uses_ink_outline(object) \
		and object.points.size() <= MAX_CACHED_INK_POINTS and (object.points.size() > MAX_WET_MESH_SAMPLES \
		or (object.points.size() >= 128 and layer_cache_costs.get(layer_id, 0) >= DENSE_INK_MESH_THRESHOLD))
	if not cache_ink and not exporting and object.kind == "stroke" and Art.uses_stroke_mesh(object):
		var samples: int = object.points.size()
		# Soft dabs carry several feather rings, unlike the wet ribbon brushes.
		var cost := samples * (4 if object.brush == "soft" else 1)
		if samples <= MAX_WET_MESH_SAMPLES and wet_mesh_samples + cost <= WET_MESH_SAMPLE_BUDGET:
			wet_mesh_samples += cost
			mark.set_meta(Art.WET_MESH_SAMPLES, cost)
			inherit_wet_geometry(mark, object)
	if cache_ink: mark.draw.connect(draw_cached_ink.bind(mark, object))
	else: mark.draw.connect(Art.draw_object.bind(mark, object, Vector2.ZERO, 1.0, true))
	mark.transform = Art.object_transform(object)
	holder.add_child(mark)
	return {"mark": mark, "object": object, "appearance": object.duplicate(), "layer": layer_id}

func draw_cached_ink(mark: Node2D, object: Dictionary) -> void:
	if not mark.has_meta(INK_MESH_BYTES) and ink_mesh_bytes < INK_MESH_BYTE_BUDGET:
		var geometry := Art.wet_batch_geometry(object, 0, object.points.size())
		# Positions and UVs are vec2, colors are RGBA8, and indices are 32-bit.
		var bytes: int = geometry.vertices.size() * 20 + geometry.indices.size() * 4
		if bytes > 0 and ink_mesh_bytes + bytes <= INK_MESH_BYTE_BUDGET:
			var mesh := Art.stroke_mesh_from_geometry(geometry)
			if mesh:
				ink_mesh_bytes += bytes
				mark.set_meta(INK_MESH_BYTES, bytes)
				mark.set_meta(Art.WET_MESH, mesh)
	if mark.has_meta(INK_MESH_BYTES):
		mark.draw_mesh(mark.get_meta(Art.WET_MESH), null)
	else:
		Art.draw_object(mark, object, Vector2.ZERO, 1.0, true)

func invalidate_stroke_mesh(mark: Node2D) -> void:
	if mark.has_meta(INK_MESH_BYTES):
		ink_mesh_bytes -= int(mark.get_meta(INK_MESH_BYTES))
		mark.remove_meta(INK_MESH_BYTES)
	if mark.has_meta(Art.WET_MESH): mark.remove_meta(Art.WET_MESH)

func update_mark_pose(object: Dictionary) -> Node2D:
	var entry: Dictionary = retained_marks.get(object.id, {})
	if entry.is_empty(): return null
	var mark: Node2D = entry.mark
	mark.transform = Art.object_transform(object)
	entry.appearance.pos = object.pos
	entry.appearance.scale = object.scale
	Document.set_orientation(entry.appearance, object.get("angle"), object.get("mirrored"))
	entry.erase("bounds")
	return mark

func pick_bounds(object: Dictionary) -> Rect2:
	var entry: Dictionary = retained_marks.get(object.id, {})
	if not entry.is_empty() and is_same(entry.object, object) and entry.appearance.pos == object.pos \
			and entry.appearance.scale == object.scale and entry.appearance.get("angle") == object.get("angle") \
			and entry.appearance.get("mirrored") == object.get("mirrored"):
		if not entry.has("bounds"): entry.bounds = Art.coverage_bounds(object)
		return entry.bounds
	return Art.coverage_bounds(object)

func sync_artwork(only_layer_id := "") -> void:
	if not artwork_root or document == null: return
	finish_cache_navigation()
	refresh_transform_cache()
	validate_solo_layer()
	detach_preview()
	var full_sync := only_layer_id.is_empty()
	if paint_cache and (full_sync or layer_renderers.get(only_layer_id) == paint_cache):
		paint_cache.flush_recent()
	if full_sync:
		stroke_redo_meshes.clear()
		pick_grids.clear()
	else:
		pick_grids.erase(only_layer_id)
	var next_layers := {} if full_sync else layer_renderers
	var next_merge_renderers := {} if full_sync else merge_renderers
	var next_marks := {} if full_sync else retained_marks
	var previous_marks := {}
	var previous_scopes := {}
	if not full_sync:
		for id in retained_marks:
			if retained_marks[id].layer == only_layer_id: previous_marks[id] = true
		for key in merge_renderers:
			if key.begins_with(only_layer_id + ":"): previous_scopes[key] = true
	var stale_layers: Array[Node2D] = []
	var layer_index := 0
	var keep_cache := is_artwork_cache(layer_renderers.get(only_layer_id))
	var cache_layers := select_paint_cache_layers() if full_sync else ([only_layer_id] if keep_cache else [])
	if full_sync: paint_cache = null
	for layer in document.layers:
		var shown := layer_is_visible(layer)
		if not shown and not layer_renderers.has(layer.id): continue
		if not full_sync and layer.id != only_layer_id:
			if layer_renderers.has(layer.id): layer_index += 1
			continue
		var layer_alpha: float = opacity_preview_value if layer.id == opacity_preview_layer else layer.get("opacity", 1.0)
		var holder: Node2D = layer_renderers.get(layer.id)
		var use_group := layer_alpha < 1.0
		var nesting := find_nested_scopes(layer)
		var isolate_layer: bool = use_group and nesting.has_groups
		var cache_layer_marks: bool = layer.id in cache_layers and not nesting.has_groups and layer_alpha > 0.0
		var needs_surface := isolate_layer or cache_layer_marks
		if keep_cache and not cache_layer_marks and holder == paint_cache: paint_cache = null
		if not full_sync and layer_cache_costs.has(layer.id):
			if nesting.has_groups:
				layer_cache_costs.erase(layer.id)
			else:
				var cost := 0
				for object in layer.objects: cost += cache_sample_cost(object)
				layer_cache_costs[layer.id] = cost
		if not holder or (holder is IsolatedOpacity) != needs_surface or (
				holder is IsolatedOpacity and holder.cache_finished_marks != cache_layer_marks) or (
				holder is CanvasGroup) != (use_group and not isolate_layer):
			if holder: stale_layers.append(holder)
			holder = make_opacity_holder(use_group, needs_surface)
			if holder is IsolatedOpacity:
				holder.cache_finished_marks = cache_layer_marks
				holder.overview = cache_layer_marks and overview_cache
			artwork_root.add_child(holder)
		holder.visible = shown
		if cache_layer_marks:
			var cost: int = layer_cache_costs.get(layer.id, 0)
			var use_document_cache := use_group or cost >= DOCUMENT_CACHE_THRESHOLD
			if full_sync and layer.id == cache_layers[0]: paint_cache = holder
			holder.allow_overview = holder == paint_cache
			holder.document_bounds = page_bounds().grow(4.0) if use_document_cache else Rect2()
			holder.keep_recent_marks = holder == paint_cache and cache_recent_strokes \
				and (not overview_cache or use_document_cache) and cost >= PAINT_CACHE_THRESHOLD
		if use_group: set_holder_opacity(holder, layer_alpha)
		if holder.get_index() != layer_index: artwork_root.move_child(holder, layer_index)
		layer_index += 1
		next_layers[layer.id] = holder

		var scopes := []
		var holders: Array[Node2D] = [holder_artwork(holder)]
		var positions: Array[int] = [0]
		var cache_changed: bool = cache_layer_marks and holders[0].get_child_count() != layer.objects.size()
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
					previous_scopes.erase(key)
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
					cache_changed = true
			else:
				if not entry.is_empty(): remove_mark(entry.mark)
				entry = mount_mark(mark_holder, object, layer.id)
				mark = entry.mark
				cache_changed = true
			entry.layer = layer.id
			if mark.get_index() != object_index:
				mark_holder.move_child(mark, object_index)
				cache_changed = true
			next_marks[object.id] = entry
			previous_marks.erase(object.id)
			positions[-1] += 1
		if cache_layer_marks and cache_changed: holder.invalidate_cache()

	if full_sync:
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
	else:
		for id in previous_marks:
			remove_mark(retained_marks[id].mark)
			retained_marks.erase(id)
		for key in previous_scopes:
			remove_mark(merge_renderers[key])
			merge_renderers.erase(key)
		for holder in stale_layers: remove_mark(holder)
	if drawing: mount_preview()
	pigment_dirty = true
	var page_size := Vector2(document.width, document.height)
	var was_resized := last_page_size != Vector2.ZERO and page_size != last_page_size
	last_page_size = page_size
	if view_fitted and was_resized and not exporting: fit()
	else: redraw_view()

func cache_sample_cost(object: Dictionary) -> int:
	match object.kind:
		"stroke": return object.points.size() * (5 if object.brush in ["soft", "pencil", "chalk"] else 1)
		"ellipse": return 16
		"polygon", "path": return maxi(4, object.vertices.size() / 4)
		"rect": return 4
	return 0

func is_artwork_cache(holder: Node2D) -> bool:
	return holder is IsolatedOpacity and holder.cache_finished_marks

func select_paint_cache_layers() -> Array:
	layer_cache_costs.clear()
	if exporting or not cache_completed_paint: return []
	var heavy_layers := []
	var limit := MAX_PAINT_CACHES if cache_extra_layers else 1
	var overview_layer := ""
	for index in document.layers.size():
		var layer: Dictionary = document.layers[index]
		if layer.id == opacity_preview_layer \
				or layer.get("type", "vector") == "paint": continue
		var dabs := 0
		var isolated := false
		for object in layer.objects:
			if object.has("opacity_groups"):
				isolated = true
				break
			dabs += cache_sample_cost(object)
		if isolated: continue
		layer_cache_costs[layer.id] = dabs
		if not layer_is_visible(layer): continue
		var alpha: float = layer.get("opacity", 1.0)
		if alpha <= 0.0: continue
		if heavy_layers.size() < limit and dabs >= PAINT_CACHE_THRESHOLD: heavy_layers.append(layer.id)
		if overview_cache and alpha == 1.0 and index == document.active and not layer.objects.is_empty(): overview_layer = layer.id
	if heavy_layers.is_empty() and not overview_layer.is_empty(): heavy_layers.append(overview_layer)
	return heavy_layers

func refresh_background_cache(previous_layer_id: String) -> void:
	if not cache_completed_paint or previous_layer_id == document.layers[document.active].id: return
	var index: int = document.layer_index(previous_layer_id)
	if index < 0 or int(layer_cache_costs.get(previous_layer_id, 0)) < PAINT_CACHE_THRESHOLD: return
	var layer: Dictionary = document.layers[index]
	if float(layer.get("opacity", 1.0)) <= 0.0 or not layer_is_visible(layer) \
			or is_artwork_cache(layer_renderers.get(previous_layer_id)): return
	var capacity := MAX_PAINT_CACHES if cache_extra_layers else 1
	var occupied := 0
	for holder in layer_renderers.values():
		if is_artwork_cache(holder) and holder.visible:
			occupied += 1
			if occupied >= capacity: return
	sync_artwork()

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
	wet_mesh_samples -= int(mark.get_meta(Art.WET_MESH_SAMPLES, 0))
	ink_mesh_bytes -= int(mark.get_meta(INK_MESH_BYTES, 0))
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
	var id: String = document.layers[document.active].id
	var holder: Node2D = layer_renderers.get(id)
	if not holder: return
	if is_artwork_cache(holder):
		preview_surface = holder
		holder = preview_surface.preview_parent()
	else:
		holder = holder_artwork(holder)
	if preview_root.get_parent() != holder: preview_root.reparent(holder, false)
	preview_root.position = Vector2.ZERO
	preview_root.scale = Vector2.ONE
	preview_root.move_to_front()

func sample_pigment(point: Vector2) -> Color:
	if pigment_dirty:
		pigment.rebuild(document, solo_layer_id, pick_bounds)
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
	detach_preview()
	live_batch = null
	live_symmetry_batches.clear()
	live_first = 0

func detach_preview() -> void:
	if preview_root and preview_root.get_parent() != page_clip:
		preview_root.reparent(page_clip, false)
		preview_root.position = Vector2.ZERO
		preview_root.scale = Vector2.ONE * zoom
	if is_instance_valid(preview_surface): preview_surface.release_preview()
	preview_surface = null

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
		for instance in live_symmetry_batches:
			preview_root.remove_child(instance)
			instance.queue_free()
		live_symmetry_batches.clear()
		mount_stroke_preview_batch(live_first, live_first + batch_size)
		live_first += batch_size
	if live_first >= end: return
	if not live_batch:
		live_batch = mount_stroke_preview_batch(live_first, -1)
	live_batch.queue_redraw()
	for instance in live_symmetry_batches: instance.queue_redraw()

func mount_stroke_preview_batch(first: int, end: int) -> Node2D:
	# Unclipped arms differ only by pose. Keep one buffer for all of their
	# draw commands; masks stay in document space and need separate geometry.
	var shared := {}
	if (not symmetry_instances.is_empty() and not current.has("clip") and not current.has("paint_mask")
			and (Art.uses_stroke_mesh(current) or Art.uses_grain_instances(current))):
		shared = {"end": -1, "resource": null, "grain": Art.uses_grain_instances(current)}
	var mark := add_stroke_preview(current, first, end, shared)
	for copy in symmetry_instances:
		var arm := add_stroke_preview(copy, first, end, shared)
		if end < 0: live_symmetry_batches.append(arm)
	return mark

func add_stroke_preview(stroke: Dictionary, first: int, end: int, shared: Dictionary) -> Node2D:
	var mark := Node2D.new()
	mark.transform = Art.object_transform(stroke)
	Art.use_screen_edges(mark, stroke)
	if not shared.is_empty(): mark.draw.connect(draw_shared_preview.bind(mark, stroke, first, end, shared))
	elif end < 0: mark.draw.connect(draw_live_batch.bind(mark, stroke, first))
	else: mark.draw.connect(Art.draw_stroke_range.bind(mark, stroke, first, end))
	preview_root.add_child(mark)
	return mark

func draw_shared_preview(mark: Node2D, stroke: Dictionary, first: int, end: int, shared: Dictionary) -> void:
	var limit: int = stroke.points.size() if end < 0 else end
	if shared.end != limit:
		shared.end = limit
		if shared.grain:
			shared.resource = Art.update_grain_multimesh(stroke, first, limit, shared.resource)
		else:
			shared.resource = Art.build_wet_mesh(stroke, first, limit)
	if shared.resource is MultiMesh: mark.draw_multimesh(shared.resource, null)
	elif shared.resource is ArrayMesh: mark.draw_mesh(shared.resource, null)

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
	var pose := Art.object_transform(object)
	for index in editable_nodes(object):
		var node_point := pose * Art.v(points[index])
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
	var delta := Art.local_point(object, point) - Art.local_point(object, start)
	var pose := Art.object_transform(object)
	var center := node_arc[node_index]
	# The range is set by Spread and the original curve, independent of drag distance.
	var span := maxf(node_reach, 0.0001)
	if node_cycle > 0.0 and span >= node_cycle * 0.5:
		deform_node_span(points, 0.0, node_arc[-1], delta, pose)
	else:
		deform_node_span(points, center - span, center + span, delta, pose)
		if node_cycle > 0.0:
			if center - span < 0.0:
				deform_node_span(points, node_cycle + center - span, node_arc[-1], delta, pose)
			if center + span > node_cycle:
				deform_node_span(points, 0.0, center + span - node_cycle, delta, pose)
	# Both ends of each artificial seam must keep their paired vertices.
	for copies in node_twins:
		var weight := 0.0
		for index in copies: weight = maxf(weight, node_weight(index))
		var moved := bounded_node_position(pose, Art.v(original.vertices[copies[0]]), delta * weight)
		for index in copies: points[index] = [moved.x, moved.y]

func node_weight(index: int) -> float:
	if index >= node_arc.size() or node_index < 0: return 0.0
	var distance := absf(node_arc[index] - node_arc[node_index])
	if node_cycle > 0.0: distance = minf(distance, node_cycle - distance)
	if node_reach <= 0.0: return 1.0 if distance <= 0.0001 else 0.0
	return 1.0 - smoothstep(0.0, node_reach, distance)

func deform_node_span(points: Array, low: float, high: float, delta: Vector2, pose: Transform2D) -> void:
	var first := node_arc.bsearch(low)
	var stop := node_arc.bsearch(high, false)
	var previous := node_points(original)
	for index in range(first, stop):
		var place := bounded_node_position(pose, Art.v(previous[index]), delta * node_weight(index))
		points[index][0] = place.x
		points[index][1] = place.y

func bounded_node_position(pose: Transform2D, local: Vector2, delta: Vector2) -> Vector2:
	var from := pose * local
	var moved := pose * (local + delta)
	var clamped := moved.clamp(Vector2.ZERO.min(from), page_bounds().end.max(from))
	return local + delta if clamped == moved else pose.affine_inverse() * clamped

func selectable_layer(index: int) -> bool:
	var layer: Dictionary = document.layers[index]
	return (select_across_layers or index == document.active) and layer_is_visible(layer) and not layer.locked

func pick_cell(point: Vector2) -> Vector2i:
	return Vector2i((point / PICK_CELL_SIZE).floor())

func build_pick_grid(layer: Dictionary) -> Dictionary:
	var grid := {"cells": {}, "broad": []}
	for index in layer.objects.size():
		var object: Dictionary = layer.objects[index]
		index_pick_bounds(grid, index, object)
	return grid

func index_pick_bounds(grid: Dictionary, index: int, object: Dictionary) -> void:
	if object.get("paint_tile", false): return
	var bounds := pick_bounds(object)
	var first := pick_cell(bounds.position)
	var last := pick_cell(bounds.end)
	if (last.x - first.x + 1) * (last.y - first.y + 1) > MAX_PICK_CELLS:
		grid.broad.append(index)
		return
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var cell := Vector2i(x, y)
			if not grid.cells.has(cell): grid.cells[cell] = []
			grid.cells[cell].append(index)

func pick_candidate_indices(layer: Dictionary, point: Vector2, tolerance: float) -> Array:
	if not pick_grids.has(layer.id): pick_grids[layer.id] = build_pick_grid(layer)
	var grid: Dictionary = pick_grids[layer.id]
	var first := pick_cell(point - Vector2.ONE * tolerance)
	var last := pick_cell(point + Vector2.ONE * tolerance)
	var candidates := {}
	for index in grid.broad: candidates[index] = true
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			for index in grid.cells.get(Vector2i(x, y), []): candidates[index] = true
	var ordered := candidates.keys()
	ordered.sort()
	ordered.reverse()
	return ordered

func hit(point: Vector2, include_interior: bool) -> Dictionary:
	var page := page_bounds()
	if not page.has_point(point): return {}
	var tolerance: float = 6.0 / zoom
	var top: int = document.layers.size() - 1 if select_across_layers and include_interior else document.active
	var bottom: int = -1 if select_across_layers and include_interior else document.active - 1
	for layer_index in range(top, bottom, -1):
		if not selectable_layer(layer_index): continue
		var layer: Dictionary = document.layers[layer_index]
		var indices := pick_candidate_indices(layer, point, tolerance) if layer.objects.size() >= PICK_GRID_THRESHOLD \
			else range(layer.objects.size() - 1, -1, -1)
		for i in indices:
			var object: Dictionary = layer.objects[i]
			if object.get("paint_tile", false): continue
			var bounds := pick_bounds(object)
			if not bounds.grow(tolerance).has_point(point) or not bounds.intersects(page): continue
			if Art.contains(object, point, tolerance) or (include_interior and contains_selectable_interior(object, point)):
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
	var page := page_bounds()
	if not page.has_point(point): return
	var layer_index: int = document.active
	var layer: Dictionary = document.layers[layer_index]
	if not layer_is_visible(layer) or layer.get("opacity", 1.0) <= 0.0: return
	var hollow_index := -1
	for index in range(layer.objects.size() - 1, -1, -1):
		var object: Dictionary = layer.objects[index]
		if object.opacity <= 0.0: continue
		if object.kind not in ["rect", "ellipse", "polygon", "stroke"]: continue
		var bounds := pick_bounds(object)
		if not bounds.grow(2.0 / zoom).has_point(point) or not bounds.intersects(page): continue
		var outline := PackedVector2Array()
		if object.kind == "stroke":
			var local := Art.local_point(object, point)
			if object.has("paint_mask") or not Art.point_inside_clip(object, local): continue
			outline = Art.closed_stroke_outline(object)
			if outline.is_empty(): continue
			if not Geometry2D.is_point_in_polygon(local, outline) and not Art.contains(object, point, 2.0 / zoom): continue
			if Geometry2D.triangulate_polygon(outline).is_empty(): continue
		elif object.kind in ["rect", "ellipse", "polygon"]:
			var interior := Art.shape_interior_contains(object, point)
			var hits_outline := Art.contains(object, point, 2.0 / zoom)
			if not interior and not hits_outline: continue
			if interior and (not Art.has_fill(object) or Color(object.color).a <= 0.0):
				if hollow_index < 0: hollow_index = index
				continue
		else:
			continue
		var target := object if outline.is_empty() else outline_fill(layer, index, outline)
		apply_vector_fill(layer_index, index, target)
		return
	var region := VectorFill.find_region(layer.objects, point, page, pick_bounds)
	if hollow_index >= 0 and (region.is_empty() or region.get("single_boundary", -1) == hollow_index):
		apply_vector_fill(layer_index, hollow_index, layer.objects[hollow_index])
		return
	if not region.is_empty():
		var target := {"kind": "polygon", "vertices": Art.pack_contours([region.vertices])[0],
			"opacity": 1.0, "pos": [0.0, 0.0], "scale": 1.0}
		if region.get("compound", false): target.compound = true
		apply_vector_fill(layer_index, region.index, target)
		return
	status.emit("Tap inside an area enclosed by shapes, lines, or the canvas edge.")

func apply_vector_fill(layer_index: int, index: int, target: Dictionary) -> void:
	var layer: Dictionary = document.layers[layer_index]
	if layer.locked or layer.get("alpha_locked", false):
		status.emit("Unlock this layer to fill it." if layer.locked else "Turn off alpha lock on this layer to fill it.")
		return
	var hex := "#" + color.to_html(color.a < 1.0)
	var new_fill := not target.has("id")
	var changed: bool = new_fill or target.color != hex or not Art.has_fill(target)
	if changed:
		if new_fill:
			target.id = document.uid()
			target.color = hex
			target.fill_enabled = true
			document.replace_layer_span(layer_index, index, 0, [target], target.id)
		else:
			document.recolor_shape(layer_index, target, hex)
		color_used.emit(color)
	document.active = layer_index
	document.selection = target.id
	selected_area.clear()
	selected.emit(target)
	refresh_selection()

func outline_fill(layer: Dictionary, index: int, outline: PackedVector2Array) -> Dictionary:
	var stroke: Dictionary = layer.objects[index]
	var vertices := []
	for point in outline: vertices.append([point.x, point.y])
	# Recolor an existing fill immediately below this outline.
	if index > 0:
		var below: Dictionary = layer.objects[index - 1]
		if below.kind == "polygon" and Art.object_transform(below) == Art.object_transform(stroke) \
				and Art.outline_vertices(below.vertices) == outline and below.get("clip", []) == stroke.get("clip", []) \
				and below.get("opacity_groups", []) == stroke.get("opacity_groups", []):
			return below
	var fill := {"kind": "polygon", "vertices": vertices, "opacity": 1.0, "pos": stroke.pos.duplicate(), "scale": stroke.scale}
	for property in ["clip", "opacity_groups"]:
		if stroke.has(property): fill[property] = stroke[property].duplicate(true)
	Document.set_orientation(fill, stroke.get("angle"), stroke.get("mirrored"))
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
				finish_at(event.position)
	elif event is InputEventMouseMotion:
		if touch_points.is_empty():
			metrics_pointer = event.position
			metrics_pressure = event.pressure if drawing and event.pressure > 0.0 else -1.0
		if event.pressure > 0: last_pressure = event.pressure
		else: last_pressure = 0.55
		if dragging:
			pan_by(event.relative)
		elif drawing or moving or resizing or node_index >= 0 or marquee_active or not cut_points.is_empty():
			update_stroke(event.position, event.pressure if event.pressure > 0 else 0.55)
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		begin_contact(event.index, event.position)
	accept_event()

func begin_pointer(event: InputEventMouseButton) -> void:
	var shortcut := ""
	if not pen_button_tools.is_empty() and event.device != InputEvent.DEVICE_ID_EMULATION and pen_shortcut_contact.is_valid():
		shortcut = pen_button_tools.get(int(pen_shortcut_contact.call()), "")
	if not placing_symmetry_center and cut_target.is_empty() and (
			Input.is_physical_key_pressed(KEY_SPACE) or shortcut == "hand" or (shortcut.is_empty() and tool == "hand")):
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
		if placing_symmetry_center or not cut_target.is_empty():
			touch_navigating = false
			touch_start = point
			touch_tap_moved = false
			begin(point, 0.55)
			return
		var node_touch := false
		var adding_with_touch := tool == "nodes" and adding_node
		if tool == "nodes" and not adding_with_touch:
			var object: Dictionary = document.find_object(document.selection)
			node_touch = (not object.is_empty() and document.can_edit(object.id)
				and nearest_editable_node(object, to_document(point)) >= 0)
		var touches_selection := false
		if tool == "select" and not keep_selecting:
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
		if cut_target.is_empty():
			cancel(keep_selecting and (tool == "select" or tool in AREA_TOOLS))
		else:
			cut_points.clear()
			refresh_selection()
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
	defer_navigation_cache_rebuilds()
	redraw_view()
	if zoom != old_zoom: view_changed.emit()

func end_contact(index: int, point: Vector2, canceled: bool) -> void:
	touch_points.erase(index)
	if not touch_points.is_empty(): return
	clear_pointer_metrics()
	set_process_input(false)
	if not touch_navigating:
		if canceled:
			if cut_target.is_empty(): cancel()
			else:
				cut_points.clear()
				refresh_selection()
		elif touch_tap_tool.is_empty():
			finish_at(point)
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
	finish_cache_navigation()
	if drawing: return
	# Document signals can refresh the toolbar while an eraser tap runs.
	# Keep the selected tool separate from this contact's action.
	var action: String = tool if shortcut.is_empty() else shortcut
	var point = to_document(screen)
	start = point
	if placing_symmetry_center:
		if not page_bounds().has_point(point): return
		symmetry_anchor = point / page_bounds().size
		placing_symmetry_center = false
		refresh_selection()
		status.emit("Symmetry center placed.")
		return
	if not cut_target.is_empty():
		cut_points = PackedVector2Array([point])
		refresh_selection()
		return
	if action == "select" or action in AREA_TOOLS:
		if not keep_selecting and begin_selection_transform(point): return
		if action in AREA_TOOLS:
			marquee_active = true
			marquee_end = point
			lasso_points = PackedVector2Array([point])
			refresh_selection()
			return
	if not page_bounds().has_point(point): return
	if action == "select" and keep_selecting:
		toggle_object_pick(point)
		return
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
		if fill_requested.has_connections(): fill_requested.emit(point)
		else: apply_fill(point)
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
			prepare_position_edit({"object": object, "layer": document.layers[document.active]})
			selection_move_bounds = Art.bounds(object)
			selection_preview_bounds = selection_move_bounds
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
		if symmetry_mode != Symmetry.Mode.OFF:
			for pose in Symmetry.poses(symmetry_mode, symmetry_arms, symmetry_center()):
				symmetry_instances.append(Symmetry.stroke_instance(current, pose))
		if symmetry_instances.is_empty(): stage_wide_paint(layer)
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
	if not cut_points.is_empty():
		update_cut_trace(point)
		return
	if marquee_active:
		update_marquee(point)
		return
	if not moving_selection.is_empty():
		update_selection_move(point)
		return
	if node_index >= 0:
		var object = document.find_object(document.selection)
		if object.is_empty(): return
		if not edit_started:
			if point.distance_to(start) < 1.0 / zoom: return
			edit_future = document.future.duplicate()
			document.checkpoint()
			edit_started = true
		deform_node(object, point)
		var entry: Dictionary = retained_marks.get(object.id, {})
		if not entry.is_empty():
			entry.erase("bounds")
			invalidate_stroke_mesh(entry.mark)
			entry.mark.queue_redraw()
		if not entry.is_empty():
			var holder: Node2D = layer_renderers.get(entry.layer)
			if is_artwork_cache(holder): holder.invalidate_mark(entry.mark)
		pigment.entries.erase(object.id)
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
	# Interpolated samples lie on one straight segment. Limit their count
	# for solid ink so a fast event does not flood the outline renderer.
	var limit := INK_SAMPLES_PER_MOTION if Art.uses_ink_outline(current) else 120
	var count := mini(100000 - current.points.size(), mini(limit, maxi(1, ceili(distance / spacing))))
	for i in range(1, count + 1):
		var t := float(i) / count
		append_point(previous.lerp(point, t), lerpf(previous_pressure, pressure, t))

func apply_fill(point: Vector2) -> void:
	if not document.paints_pixels():
		fill_at(point)
		return
	match document.fill_paint(Vector2i(point.floor()), color):
		OK: color_used.emit(color)
		ERR_UNAVAILABLE: status.emit("Choose a visible, unlocked paint layer.")
		_: status.emit("The project has reached its embedded paint size limit.")

func finish_at(screen: Vector2) -> void:
	var point := to_document(screen)
	if not cut_points.is_empty():
		update_cut_trace(point)
		finish_cut_trace()
	if marquee_active: update_marquee(point)
	if drawing and current.get("brush") == "ink":
		raw_point = point.clamp(Vector2.ZERO, Vector2(document.width, document.height))
	finish()

func finish() -> void:
	cut_points.clear()
	if marquee_active: finish_marquee()
	if drawing and not current.is_empty():
		if current.kind == "stroke":
			append_motion(raw_point, raw_pressure, true)
			current.erase("live_stroke")
		if document.editable():
			if not symmetry_instances.is_empty():
				commit_symmetric_stroke()
			elif current.kind == "stroke" and document.paints_pixels():
				var erasing: bool = current.get("erasing", false)
				var stable: bool = staged_paint != null and staged_paint_revision == document.revision \
					and staged_paint_layer == document.layers[document.active].id
				if document.commit_paint(current, erasing, staged_paint if stable else null) != OK:
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
		if not moving_selection.is_empty(): document.record_transform(moving_selection)
		else: document.commit()
	end_paint_staging()
	refresh_transform_cache()
	edit_started = false
	end_preview()
	symmetry_instances.clear()
	current = {}
	drawing = false
	moving = false
	moving_selection.clear()
	selection_rotating = false
	drag_guides = Vector2.INF
	resizing = false
	node_index = -1
	node_arc.clear()
	refresh_selection()

func cancel(keep_picks := false) -> void:
	end_paint_staging()
	cancel_drawing_actions()
	clear_path()
	if document != null and not keep_picks and not marquee_active and (not selected_area.is_empty() or not document.area_selection.is_empty()):
		clear_selection()
	marquee_active = false
	lasso_points.clear()
	if edit_started:
		if not moving_selection.is_empty():
			for item in moving_selection:
				item.object.pos = item.original_pos
				item.object.scale = item.scale
				Document.set_orientation(item.object, item.angle, item.mirrored)
				update_mark_pose(item.object)
		else:
			if not document.history.is_empty(): document.restore(document.history.pop_back())
			document.future = edit_future
			document.changed.emit()
	refresh_transform_cache()
	edit_started = false
	end_preview()
	symmetry_instances.clear()
	current = {}
	drawing = false
	moving = false
	moving_selection.clear()
	selection_rotating = false
	drag_guides = Vector2.INF
	resizing = false
	node_index = -1
	node_arc.clear()
	refresh_selection()

func cancel_drawing_actions() -> void:
	placing_symmetry_center = false
	stop_cutting()

func stop_cutting() -> void:
	cut_target = ""
	cut_points.clear()
	refresh_selection()

func cut_selection() -> Dictionary:
	var items := transformable_items()
	return items[0] if items.size() == 1 else {}

func symmetry_copy_reason() -> String:
	return document.symmetry_copy_reason(transformable_items())

func copy_selection_with_symmetry(mode: int, arms: int, use_selection_center: bool) -> String:
	var items := transformable_items()
	var reason: String = document.symmetry_copy_reason(items)
	if not reason.is_empty(): return reason
	var center := exact_selection_bounds(items).get_center() if use_selection_center else symmetry_center()
	return document.copy_with_symmetry(items, Symmetry.poses(mode, arms, center))

func radial_repeat_source() -> Dictionary:
	var items := transformable_items()
	if items.size() != 1: return {}
	var item := items[0]
	if item.layer.get("type", "vector") != "vector" or item.layer.get("alpha_locked", false): return {}
	var object: Dictionary = item.object
	if object.kind == "stroke" and object.points.size() >= 2: return item
	if object.kind == "path" and object.vertices.size() >= 2: return item
	return {}

func arm_cut() -> void:
	finish()
	var target := cut_selection()
	var reason: String = document.cut_target_reason(target)
	if not reason.is_empty():
		status.emit(reason)
		return
	cancel_drawing_actions()
	cut_target = target.object.id
	status.emit("Draw a loop to cut. Choose Transform → Finish cutting when done.")

func update_cut_trace(point: Vector2) -> void:
	if cut_points[-1].distance_to(point) < maxf(0.2, 2.5 / zoom): return
	if cut_points.size() == 512:
		var compact := PackedVector2Array()
		for index in range(0, cut_points.size(), 2): compact.append(cut_points[index])
		cut_points = compact
	cut_points.append(point)
	refresh_selection()

func finish_cut_trace() -> void:
	var trace := cut_points
	cut_points = PackedVector2Array()
	if trace.size() > 3 and trace[-1].distance_to(trace[0]) < maxf(0.2, 3.0 / zoom):
		trace.resize(trace.size() - 1)
	var target := cut_selection()
	if target.is_empty() or target.object.id != cut_target:
		cancel_drawing_actions()
		status.emit("Select the shape again.")
		return
	var reason: String = document.cut_vector_shape(target, trace)
	if not reason.is_empty(): status.emit(reason)
	elif cut_target.is_empty(): status.emit("The whole shape was removed.")
	else: status.emit("Cut added. Draw another loop or choose Transform → Finish cutting.")

func commit_symmetric_stroke() -> void:
	var instances: Array[Dictionary] = []
	var bounds := Rect2(Art.v(current.points[0]), Vector2.ZERO)
	for sample in current.points: bounds = bounds.expand(Art.v(sample))
	bounds = bounds.grow(float(current.size) * 1.5)
	if Art.clipped_stroke_has_paint(current): instances.append(current)
	for example in symmetry_instances:
		var pose := Art.object_transform(example)
		if not page_bounds().intersects(pose * bounds, true): continue
		if current.points.all(func(sample):
			var point := Art.v(sample)
			return (pose * point).distance_squared_to(point) < 0.000001):
			continue
		example.erase("live_stroke")
		if not Art.clipped_stroke_has_paint(example): continue
		example.id = document.uid()
		if not document.paints_pixels(): example.points = example.points.duplicate(true)
		instances.append(example)
	if instances.is_empty(): return
	var erasing: bool = current.get("erasing", false)
	if document.paints_pixels():
		if document.commit_symmetric_paint(instances, erasing) != OK:
			status.emit("The project has reached its embedded paint size limit.")
			return
	else:
		var physical_zoom: float = zoom * get_screen_transform().get_scale().x
		var gap := clampf(Document.VectorUnion.TIP_GAP / maxf(physical_zoom, 0.01), 0.25, 4.0)
		if not document.append_symmetric_strokes(instances, gap):
			status.emit("The project has reached its vector object limit.")
			return
	if not erasing: color_used.emit(stroke_pigment)

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
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		for holder in layer_renderers.values():
			if is_artwork_cache(holder):
				holder.invalidate_cache()
				holder.invalidate_recent()
