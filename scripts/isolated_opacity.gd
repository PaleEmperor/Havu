extends Node2D
## Nested CanvasGroups share a backbuffer. Render the outer scope to its own
## transparent surface so that each inner scope composites independently.
const SURFACE_SHADER := preload("res://assets/opacity_surface.gdshader")
const CACHE_MAX_EDGE := 3072.0
const CACHE_PIXEL_BUDGET := 5500000.0
const OVERVIEW_ENTER_ZOOM := 0.80
const OVERVIEW_EXIT_ZOOM := 0.95

var surface: SubViewport
var artwork: Node2D
var display: Sprite2D
var opacity := 1.0
var cache_finished_marks := false
var overview := false
var rebuild_pending := false
var pending_marks: Array[Node2D] = []
var live_move: Node2D

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
	if display: display.self_modulate.a = value

func update_view(view_size: Vector2, view_origin: Vector2, zoom: float, density: float) -> void:
	if not surface: return
	var largest_edge := maxf(1.0, maxf(view_size.x, view_size.y))
	var sampling := minf(density, 4096.0 / largest_edge)
	if cache_finished_marks:
		overview = use_overview(view_size, zoom, density, overview)
		# Keep the one finished-art cache sharp on high-density displays.
		# At overview zoom, use spare pixels for antialiasing thin edges.
		sampling = cache_sampling(view_size, density * (2.0 if overview else 1.0))
		var material := display.material as ShaderMaterial
		material.set_shader_parameter("filter_overview", overview and sampling > density * 1.05)
	var pixels := Vector2i((view_size * sampling).ceil()).max(Vector2i(2, 2))
	if surface.size != pixels or artwork.position != view_origin * sampling or artwork.scale.x != zoom * sampling:
		invalidate_cache()
	surface.size = pixels
	artwork.position = view_origin * sampling
	artwork.scale = Vector2.ONE * zoom * sampling
	display.position = -view_origin / zoom
	display.scale = Vector2.ONE / (zoom * sampling)

static func cache_sampling(view_size: Vector2, desired: float) -> float:
	var largest_edge := maxf(1.0, maxf(view_size.x, view_size.y))
	var area := maxf(1.0, view_size.x * view_size.y)
	return minf(desired, minf(CACHE_MAX_EDGE / largest_edge, sqrt(CACHE_PIXEL_BUDGET / area)))

static func use_overview(view_size: Vector2, zoom: float, density: float, previous: bool) -> bool:
	return (zoom * density < (OVERVIEW_EXIT_ZOOM if previous else OVERVIEW_ENTER_ZOOM)
		and cache_sampling(view_size, density * 2.0) > density * 1.05)

func show_live_marks() -> void:
	if live_move: return
	if RenderingServer.frame_post_draw.is_connected(finish_cache_frame):
		RenderingServer.frame_post_draw.disconnect(finish_cache_frame)
	pending_marks.clear()
	rebuild_pending = false
	surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	live_move = Node2D.new()
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
	if not rebuild_pending: pending_marks.append(mark)
	request_cache_frame()

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
