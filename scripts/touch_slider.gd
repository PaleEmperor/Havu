extends HSlider

var touch := -1
var start_value := 0.0

func _ready() -> void:
	set_process_input(false)
	gui_input.connect(begin_touch)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): end_touch(true))

func begin_touch(event: InputEvent) -> void:
	if not editable or touch >= 0 or not event is InputEventScreenTouch or not event.pressed or event.canceled: return
	touch = event.index
	start_value = value
	set_process_input(true)
	drag_started.emit()
	move_touch(event.position)
	accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag and event.index == touch:
		move_touch(get_global_transform_with_canvas().affine_inverse() * event.position)
	elif event is InputEventScreenTouch and event.index == touch and not event.pressed:
		if not event.canceled: move_touch(get_global_transform_with_canvas().affine_inverse() * event.position)
		end_touch(event.canceled)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		end_touch(true)
	else:
		return
	get_viewport().set_input_as_handled()

func move_touch(point: Vector2) -> void:
	value = lerpf(min_value, max_value, clampf(point.x / size.x, 0, 1))

func end_touch(canceled: bool) -> void:
	if touch < 0: return
	touch = -1
	set_process_input(false)
	if canceled: value = start_value
	drag_ended.emit(not canceled and not is_equal_approx(value, start_value))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: end_touch(true)
