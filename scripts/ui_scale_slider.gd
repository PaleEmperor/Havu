extends Control
## The scale changes the slider's own position. Keep the track under the
## gesture fixed in screen coordinates until the user lifts their finger.
signal scale_changed(value: int)
signal scale_committed

const MINIMUM := 80
const MAXIMUM := 130
const STEP := 5

var value := 100
var track: HSlider
var dragging := false
var touch := -1
var start_value := 100
var screen_to_track := Transform2D.IDENTITY
var drag_width := 1.0

func _ready() -> void:
	set_process_input(false)
	focus_mode = FOCUS_ALL
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	custom_minimum_size.y = 42
	track = HSlider.new()
	track.min_value = MINIMUM
	track.max_value = MAXIMUM
	track.step = STEP
	track.value = value
	track.focus_mode = FOCUS_NONE
	track.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(track)
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): end_drag(true))

func _draw() -> void:
	if has_focus(): draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("#53796a"), false, 1)

func _gui_input(event: InputEvent) -> void:
	if dragging: return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT, KEY_DOWN: choose_percent(value - STEP)
			KEY_RIGHT, KEY_UP: choose_percent(value + STEP)
			KEY_HOME: choose_percent(MINIMUM)
			KEY_END: choose_percent(MAXIMUM)
			_: return
		scale_committed.emit()
		accept_event()
		return
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		touch = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		touch = -1
	else:
		return
	grab_focus()
	dragging = true
	start_value = value
	screen_to_track = get_screen_transform().affine_inverse()
	drag_width = maxf(1, size.x)
	set_process_input(true)
	update_drag(get_screen_transform() * event.position)
	accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		end_drag(true)
	elif (event is InputEventScreenDrag and event.index == touch) or (event is InputEventMouseMotion and touch < 0):
		update_drag(viewport_to_screen(event.position))
	elif event is InputEventScreenTouch and event.index == touch and not event.pressed:
		if not event.canceled: update_drag(viewport_to_screen(event.position))
		end_drag(event.canceled)
	elif event is InputEventMouseButton and touch < 0 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		update_drag(viewport_to_screen(event.position))
		end_drag(false)
	else:
		return
	get_viewport().set_input_as_handled()

func viewport_to_screen(point: Vector2) -> Vector2:
	return get_screen_transform() * (get_global_transform_with_canvas().affine_inverse() * point)

func update_drag(screen: Vector2) -> void:
	var local := screen_to_track * screen
	choose_percent(roundi(lerpf(MINIMUM, MAXIMUM, clampf(local.x / drag_width, 0, 1))))

func end_drag(canceled: bool) -> void:
	if not dragging: return
	dragging = false
	set_process_input(false)
	if canceled: choose_percent(start_value)
	else: scale_committed.emit()

func choose_percent(next: int) -> void:
	next = clampi(roundi(float(next) / STEP) * STEP, MINIMUM, MAXIMUM)
	if value == next: return
	value = next
	if track: track.set_value_no_signal(value)
	scale_changed.emit(value)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: end_drag(true)
