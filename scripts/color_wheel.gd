extends Control

signal color_changed(value: Color)
signal preview_changed(value: Color)

const TEXTURE_SIZE := 256
const INNER_RADIUS := 0.77
static var ring_texture: ImageTexture

var hue := 0.0
var saturation := 0.0
var brightness := 1.0
var color := Color.WHITE:
	set(value):
		color = value
		if value.s > 0.0001: hue = value.h
		saturation = value.s
		brightness = value.v
		queue_redraw()

var active_part := ""
var active_touch := -1
var saved_hue := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(136, 136)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(false)
	if ring_texture == null: ring_texture = build_ring()
	resized.connect(queue_redraw)

static func build_ring() -> ImageTexture:
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var radius := TEXTURE_SIZE * 0.5
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var offset := Vector2(x + 0.5 - radius, y + 0.5 - radius)
			var distance := offset.length()
			var alpha := clampf(radius - distance, 0, 1) * clampf(distance - radius * INNER_RADIUS, 0, 1)
			if alpha > 0.0:
				image.set_pixel(x, y, Color.from_hsv(fposmod(offset.angle() / TAU, 1.0), 1, 1, alpha))
	return ImageTexture.create_from_image(image)

func outer_radius() -> float:
	return minf(size.x, size.y) * 0.5 - 4.0

func shade_rect() -> Rect2:
	var half := outer_radius() * 0.52
	return Rect2(size * 0.5 - Vector2.ONE * half, Vector2.ONE * half * 2.0)

func _draw() -> void:
	if ring_texture == null: return
	var center := size * 0.5
	var radius := outer_radius()
	draw_texture_rect(ring_texture, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), false)
	var square := shade_rect()
	var corners := PackedVector2Array([square.position, Vector2(square.end.x, square.position.y), square.end, Vector2(square.position.x, square.end.y)])
	var hue_color := Color.from_hsv(hue, 1, 1)
	draw_polygon(corners, PackedColorArray([Color.WHITE, hue_color, hue_color, Color.WHITE]))
	draw_polygon(corners, PackedColorArray([Color.TRANSPARENT, Color.TRANSPARENT, Color.BLACK, Color.BLACK]))
	draw_rect(square, Color(1, 1, 1, 0.24), false, 1, true)
	var ring_cursor := center + Vector2.from_angle(hue * TAU) * radius * (1.0 + INNER_RADIUS) * 0.5
	var square_cursor := square.position + square.size * Vector2(saturation, 1.0 - brightness)
	draw_cursor(ring_cursor, hue_color)
	draw_cursor(square_cursor, Color.from_hsv(hue, saturation, brightness))

func draw_cursor(point: Vector2, value: Color) -> void:
	draw_circle(point, 6.5, Color("#141414"), true, -1, true)
	draw_circle(point, 5.0, value, true, -1, true)
	draw_circle(point, 5.0, Color.WHITE, false, 1.25, true)

func _gui_input(event: InputEvent) -> void:
	if not active_part.is_empty(): return
	var point: Vector2
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		point = event.position
		active_touch = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		point = event.position
		active_touch = -1
	else:
		return
	if shade_rect().grow(3).has_point(point):
		active_part = "shade"
	elif point.distance_to(size * 0.5) >= outer_radius() * INNER_RADIUS - 4.0 and point.distance_to(size * 0.5) <= outer_radius() + 4.0:
		active_part = "hue"
	else:
		return
	saved_hue = hue
	set_process_input(true)
	move_picker(point)
	accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		finish_picker(true)
		get_viewport().set_input_as_handled()
		return
	var point: Vector2
	var released := false
	var canceled := false
	if active_touch >= 0 and event is InputEventScreenDrag and event.index == active_touch:
		point = event.position
	elif active_touch >= 0 and event is InputEventScreenTouch and event.index == active_touch and not event.pressed:
		point = event.position
		released = true
		canceled = event.canceled
	elif active_touch < 0 and event is InputEventMouseMotion:
		point = event.position
	elif active_touch < 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		point = event.position
		released = true
	else:
		return
	if not canceled: move_picker(get_global_transform_with_canvas().affine_inverse() * point)
	if released: finish_picker(canceled)
	get_viewport().set_input_as_handled()

func move_picker(point: Vector2) -> void:
	if active_part == "hue":
		hue = fposmod((point - size * 0.5).angle() / TAU, 1.0)
	else:
		var square := shade_rect()
		var uv := ((point - square.position) / square.size).clamp(Vector2.ZERO, Vector2.ONE)
		saturation = uv.x
		brightness = 1.0 - uv.y
	queue_redraw()
	preview_changed.emit(Color.from_hsv(hue, saturation, brightness, color.a))

func finish_picker(canceled: bool) -> void:
	if active_part.is_empty(): return
	active_part = ""
	set_process_input(false)
	if canceled:
		saturation = color.s
		brightness = color.v
		hue = saved_hue
		queue_redraw()
		preview_changed.emit(color)
	else:
		color = Color.from_hsv(hue, saturation, brightness, color.a)
		color_changed.emit(color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		finish_picker(true)
