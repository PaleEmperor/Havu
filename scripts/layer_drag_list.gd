extends "res://scripts/swipe_scroll.gd"

signal reorder_requested(layer_id: String, slot: int)

const MARKER_COLOR = Color("#79d7b4")
const DRAG_THRESHOLD = 7.0

var rows: VBoxContainer
var marker: Node2D
var layer_id := ""
var source_row: Control
var touch_index := -1
var start_position := Vector2.ZERO
var pointer_position := Vector2.ZERO
var dragging := false
var drop_slot := -1
var scroll_remainder := 0.0

func _ready() -> void:
	super._ready()
	get_window().focus_exited.connect(cancel_drag)
	marker = Node2D.new()
	marker.z_index = 1
	marker.draw.connect(draw_marker)
	add_child(marker)
	set_process(false)
	set_process_input(false)

func watch_reorder_surface(surface: Control, source_id: String, row: Control) -> void:
	surface.gui_input.connect(func(event: InputEvent):
		var finger_press: bool = event is InputEventScreenTouch and event.pressed and not event.canceled
		if not layer_id.is_empty() and touch_index < 0 and finger_press:
			cancel_drag()
		if not layer_id.is_empty() or row.get_meta("locked", false): return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not event.canceled:
			touch_index = -1
		elif finger_press:
			touch_index = event.index
		else:
			return
		layer_id = source_id
		end_swipe(false)
		stop_fling()
		source_row = row
		start_position = surface.get_global_transform_with_canvas() * event.position
		pointer_position = start_position
		set_process_input(true)
		if not surface is BaseButton: surface.accept_event())

func watch_press(event: InputEvent, source: Control) -> void:
	if layer_id.is_empty(): super.watch_press(event, source)

func _input(event: InputEvent) -> void:
	if layer_id.is_empty():
		super._input(event)
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag()
	elif touch_index < 0 and event is InputEventMouseMotion:
		update_pointer(event.position)
	elif touch_index < 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if event.canceled: cancel_drag()
		else: finish_drag(event.position)
		return
	elif event is InputEventScreenDrag and event.index == touch_index:
		update_pointer(event.position)
	elif event is InputEventScreenTouch and event.index == touch_index and not event.pressed:
		if event.canceled: cancel_drag()
		else: finish_drag(event.position)
		return
	else:
		return
	get_viewport().set_input_as_handled()

func update_pointer(point: Vector2) -> void:
	pointer_position = point
	if not dragging and point.distance_to(start_position) >= DRAG_THRESHOLD:
		dragging = true
		if is_instance_valid(source_row):
			# Let a tap select the layer, and cancel that press when it becomes a drag.
			source_row.propagate_notification(NOTIFICATION_DRAG_BEGIN)
			source_row.modulate.a = 0.48
		set_process(true)
	if dragging:
		drop_slot = slot_at(point)
		marker.queue_redraw()

func slot_at(point: Vector2) -> int:
	if not get_global_rect().has_point(point): return -1
	for index in rows.get_child_count():
		var bounds: Rect2 = rows.get_child(index).get_global_rect()
		if point.y < bounds.get_center().y: return index
	return rows.get_child_count()

func finish_drag(point: Vector2) -> void:
	var slot := slot_at(point) if dragging else -1
	var source := layer_id
	cancel_drag()
	if slot >= 0: reorder_requested.emit(source, slot)

func cancel_drag() -> void:
	if is_instance_valid(source_row): source_row.modulate.a = 1.0
	source_row = null
	layer_id = ""
	drop_slot = -1
	dragging = false
	scroll_remainder = 0.0
	set_process(false)
	set_process_input(swipe_index >= 0)
	if is_instance_valid(marker): marker.queue_redraw()

func _process(delta: float) -> void:
	var bounds := get_global_rect()
	if not bounds.has_point(pointer_position): return
	var edge := 30.0
	var top := clampf((bounds.position.y + edge - pointer_position.y) / edge, 0.0, 1.0)
	var bottom := clampf((pointer_position.y - bounds.end.y + edge) / edge, 0.0, 1.0)
	scroll_remainder += (bottom - top) * 420.0 * delta
	var step := int(scroll_remainder)
	if step == 0: return
	scroll_remainder -= step
	scroll_vertical += step
	drop_slot = slot_at(pointer_position)
	marker.queue_redraw()

func draw_marker() -> void:
	if drop_slot < 0 or rows.get_child_count() == 0: return
	var row: Control = rows.get_child(mini(drop_slot, rows.get_child_count() - 1))
	var y := row.get_global_rect().position.y - get_global_rect().position.y - 2.0
	if drop_slot == rows.get_child_count():
		y += row.size.y + 4.0
	if y < -2.0 or y > size.y + 2.0: return
	y = clampf(y, 2.0, size.y - 2.0)
	marker.draw_line(Vector2(5, y), Vector2(rows.size.x - 5, y), MARKER_COLOR, 2.0, true)
	marker.draw_circle(Vector2(5, y), 3, MARKER_COLOR, true, -1, true)
	marker.draw_circle(Vector2(rows.size.x - 5, y), 3, MARKER_COLOR, true, -1, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_drag()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_drag()
