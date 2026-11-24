extends Node2D
## Nested CanvasGroups share a backbuffer. Render the outer scope to its own
## transparent surface so that each inner scope composites independently.
const SURFACE_SHADER := preload("res://assets/opacity_surface.gdshader")
const CACHE_MAX_EDGE := 3072.0
const CACHE_PIXEL_BUDGET := 5500000.0
const SECONDARY_CACHE_PIXEL_BUDGET := 3400000.0
const OVERVIEW_ENTER_ZOOM := 0.80
const OVERVIEW_EXIT_ZOOM := 0.95
const RECENT_MARK_LIMIT := 12

var surface: SubViewport
var artwork: Node2D
var display: Sprite2D
var opacity := 1.0
var cache_finished_marks := false
var overview := false
var rebuild_pending := false
var pending_marks: Array[Node2D] = []
var live_move: Node2D
var preview_group: CanvasGroup
var keep_recent_marks := false
var allow_overview := true
var document_bounds := Rect2()
var recent
var current_view_size := Vector2.ZERO
var current_view_origin := Vector2.ZERO
var current_zoom := 1.0
var current_density := 1.0

func _ready() -> void:
	surface = SubViewport.new()
	surface.world_2d = World2D.new()
	surface.transparent_bg = true
	surface.disable_3d = true
	surface.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(surface)
	artwork = Node2D.new()
	surface.add_child(artwork)
	display = Sprite2D.new()
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	display.texture = surface.get_texture()
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	display.material = material
	add_child(display)
	set_opacity(opacity)
	if cache_finished_marks: invalidate_cache()

func set_opacity(value: float) -> void:
	opacity = value
	if display: display.self_modulate.a = 1.0 if preview_group else value
	if preview_group: preview_group.self_modulate.a = value
	if live_move: live_move.self_modulate.a = value

func preview_parent() -> Node2D:
	if opacity >= 1.0: return self
	if not preview_group:
		preview_group = CanvasGroup.new()
		var position_in_layer := display.get_index()
		add_child(preview_group)
		move_child(preview_group, position_in_layer)
		display.reparent(preview_group, false)
		set_opacity(opacity)
	return preview_group

func release_preview() -> void:
	if not preview_group: return
	var position_in_layer := preview_group.get_index()
	display.reparent(self, false)
	move_child(display, position_in_layer)
	remove_child(preview_group)
	preview_group.queue_free()
	preview_group = null
	set_opacity(opacity)

func update_view(view_size: Vector2, view_origin: Vector2, zoom: float, density: float) -> void:
	if not surface: return
	current_view_size = view_size
	current_view_origin = view_origin
	current_zoom = zoom
	current_density = density
	if uses_document_cache(zoom, density):
		var sampling := document_cache_sampling()
		var material := display.material as ShaderMaterial
		material.set_shader_parameter("filter_overview", sampling > zoom * density * 1.05)
		set_surface_view(document_bounds.size * sampling, -document_bounds.position * sampling,
			sampling, document_bounds.position)
		update_recent_view()
		return
	var largest_edge := maxf(1.0, maxf(view_size.x, view_size.y))
	var sampling := minf(density, 4096.0 / largest_edge)
	if cache_finished_marks:
		overview = allow_overview and use_overview(view_size, zoom, density, overview)
		# Keep the one finished-art cache sharp on high-density displays.
		# At overview zoom, use spare pixels for antialiasing thin edges.
		sampling = cache_sampling(view_size, density * (2.0 if overview else 1.0),
			CACHE_PIXEL_BUDGET if allow_overview else SECONDARY_CACHE_PIXEL_BUDGET)
		var material := display.material as ShaderMaterial
		material.set_shader_parameter("filter_overview", overview and sampling > density * 1.05)
	set_surface_view(view_size * sampling, view_origin * sampling, zoom * sampling, -view_origin / zoom)
	update_recent_view()

func update_recent_view() -> void:
	if recent and recent.visible:
		recent.allow_overview = not document_bounds.has_area()
		recent.update_view(current_view_size, current_view_origin, current_zoom, current_density)

func set_surface_view(extent: Vector2, offset: Vector2, scale_factor: float, placement: Vector2) -> void:
	var pixels := Vector2i(extent.ceil()).max(Vector2i(2, 2))
	if surface.size != pixels or not artwork.position.is_equal_approx(offset) or not is_equal_approx(artwork.scale.x, scale_factor):
		invalidate_cache()
	surface.size = pixels
	artwork.position = offset
	artwork.scale = Vector2.ONE * scale_factor
	display.position = placement
	display.scale = Vector2.ONE / scale_factor

func document_cache_sampling() -> float:
	return cache_sampling(document_bounds.size, 2.0,
		CACHE_PIXEL_BUDGET if allow_overview else SECONDARY_CACHE_PIXEL_BUDGET)

func uses_document_cache(zoom: float, density: float) -> bool:
	return document_bounds.has_area() and zoom * density <= document_cache_sampling()

static func cache_sampling(view_size: Vector2, desired: float, budget := CACHE_PIXEL_BUDGET) -> float:
	var largest_edge := maxf(1.0, maxf(view_size.x, view_size.y))
	var area := maxf(1.0, view_size.x * view_size.y)
	return minf(desired, minf(CACHE_MAX_EDGE / largest_edge, sqrt(budget / area)))

static func use_overview(view_size: Vector2, zoom: float, density: float, previous: bool) -> bool:
	return (zoom * density < (OVERVIEW_EXIT_ZOOM if previous else OVERVIEW_ENTER_ZOOM)
		and cache_sampling(view_size, density * 2.0) > density * 1.05)

func show_live_marks() -> void:
	if live_move: return
	flush_recent()
	if RenderingServer.frame_post_draw.is_connected(finish_cache_frame):
		RenderingServer.frame_post_draw.disconnect(finish_cache_frame)
	pending_marks.clear()
	rebuild_pending = false
	surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	live_move = CanvasGroup.new() if opacity < 1.0 else Node2D.new()
	live_move.self_modulate.a = opacity
	add_child(live_move)
	for mark in artwork.get_children():
		mark.reparent(live_move, false)
		mark.show()
	display.hide()

func resume_cache() -> void:
	if not live_move: return
	for mark in live_move.get_children(): mark.reparent(artwork, false)
	remove_child(live_move)
	live_move.queue_free()
	live_move = null
	display.show()
	invalidate_cache()

func invalidate_cache() -> void:
	if not cache_finished_marks or not surface or live_move: return
	if not rebuild_pending:
		rebuild_pending = true
		for mark in artwork.get_children(): mark.show()
	pending_marks.clear()
	surface.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	request_cache_frame()

func append_mark(mark: Node2D) -> void:
	if keep_recent_marks:
		if not recent:
			recent = get_script().new()
			recent.cache_finished_marks = true
			recent.overview = overview
			recent.hide()
			add_child(recent)
			move_child(recent, display.get_index() + 1)
		if recent.artwork.get_child_count() >= RECENT_MARK_LIMIT: flush_recent()
		if not recent.visible:
			recent.show()
			update_recent_view()
			recent.invalidate_cache()
		mark.reparent(recent.artwork, false)
		recent.append_mark(mark)
		return
	enqueue_base_mark(mark)

func enqueue_base_mark(mark: Node2D) -> void:
	if not rebuild_pending: pending_marks.append(mark)
	request_cache_frame()

func is_recent_mark(mark: Node2D) -> bool:
	return recent != null and mark != null and mark.get_parent() == recent.artwork

func invalidate_recent() -> void:
	if recent and recent.visible: recent.invalidate_cache()

func invalidate_mark(mark: Node2D) -> void:
	if is_recent_mark(mark): invalidate_recent()
	elif mark.get_parent() == artwork: invalidate_cache()

func flush_recent() -> void:
	if not recent or not recent.visible: return
	if RenderingServer.frame_post_draw.is_connected(recent.finish_cache_frame):
		RenderingServer.frame_post_draw.disconnect(recent.finish_cache_frame)
	recent.pending_marks.clear()
	recent.rebuild_pending = false
	recent.surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for mark in recent.artwork.get_children():
		mark.reparent(artwork, false)
		mark.show()
		enqueue_base_mark(mark)
	recent.hide()

func request_cache_frame() -> void:
	surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not RenderingServer.frame_post_draw.is_connected(finish_cache_frame):
		RenderingServer.frame_post_draw.connect(finish_cache_frame, CONNECT_ONE_SHOT)

func finish_cache_frame() -> void:
	# These marks are now in the display texture. Keep the vector nodes
	# for edits and redraw them only if the cache is explicitly rebuilt.
	if rebuild_pending:
		for mark in artwork.get_children(): mark.hide()
	else:
		for mark in pending_marks:
			if is_instance_valid(mark): mark.hide()
	rebuild_pending = false
	pending_marks.clear()
	surface.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
