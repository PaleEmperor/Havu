extends Button

const HOLD_DELAY := 0.36
const REPEAT_DELAY := 0.18

var repeat_timer: Timer
var held := false
var touch_index := -1

func _ready() -> void:
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	repeat_timer = Timer.new()
	repeat_timer.one_shot = true
	repeat_timer.timeout.connect(repeat_undo)
	add_child(repeat_timer)
	gui_input.connect(watch_press)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): stop_hold())
	get_window().focus_exited.connect(stop_hold)
	set_process_input(false)

func watch_press(event: InputEvent) -> void:
	if disabled or held: return
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		touch_index = event.index
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		touch_index = -1
	else:
		return
	held = true
	set_process_input(true)
	repeat_timer.start(HOLD_DELAY)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.index == touch_index and not event.pressed:
		stop_hold()
	elif touch_index < 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		stop_hold()
	elif (event is InputEventScreenDrag and event.index == touch_index) or (touch_index < 0 and event is InputEventMouseMotion):
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, size).grow(10).has_point(local): stop_hold()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		stop_hold()

func repeat_undo() -> void:
	if not held or disabled or not is_visible_in_tree():
		stop_hold()
		return
	pressed.emit()
	if held and not disabled: repeat_timer.start(REPEAT_DELAY)
	else: stop_hold()

func stop_hold() -> void:
	held = false
	touch_index = -1
	set_process_input(false)
	if repeat_timer: repeat_timer.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: stop_hold()
