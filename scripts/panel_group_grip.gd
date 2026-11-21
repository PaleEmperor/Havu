extends Panel

signal move_started
signal moved(pointer: Vector2, delta: Vector2)
signal move_finished(canceled: bool)

var origin := Vector2.ZERO
var touch := -1
var active := false
var dragging := false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	set_process_input(false)

func _gui_input(event: InputEvent) -> void:
	if active: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not event.canceled:
		touch = -1
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		touch = event.index
	else:
		return
	origin = get_global_transform_with_canvas() * event.position
	active = true
	dragging = false
	set_process_input(true)
	move_started.emit()
	accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		end_move(true)
	elif (event is InputEventMouseMotion and touch < 0) or (event is InputEventScreenDrag and event.index == touch):
		track_pointer(event.position)
	elif (event is InputEventMouseButton and touch < 0 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) or (
			event is InputEventScreenTouch and event.index == touch and not event.pressed):
		if not event.canceled: track_pointer(event.position)
		end_move(event.canceled)
		return
	else:
		return
	get_viewport().set_input_as_handled()

func track_pointer(pointer: Vector2) -> void:
	var delta := pointer - origin
	if not dragging and delta.length() < 6.0: return
	dragging = true
	moved.emit(pointer, delta)

func end_move(canceled := false) -> void:
	if not active: return
	active = false
	set_process_input(false)
	move_finished.emit(canceled)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		end_move(true)
