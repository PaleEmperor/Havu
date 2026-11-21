extends PanelContainer

signal raise_requested
signal layout_changed
signal dock_changed(edge: String, align_orientation: bool)
signal close_requested
signal merge_requested(target: Control)
signal merge_preview_changed(target: Control)
signal drop_preview_changed
signal move_committed
signal resize_started
signal group_resize_dragged(delta: Vector2)
signal resize_finished(committed: bool)

const INSET := 8.0
const TOP := 84.0
const BOTTOM := 64.0
const SNAP_DISTANCE := 30.0
const ORIENTATION_DISTANCE := 10.0
const MIN_BODY_HEIGHT := 54.0
const FRAME_HEIGHT := 69.0

var dock_corner := ""
var dock := "":
	set(value):
		dock = value
		if value.is_empty(): dock_corner = ""
		refresh_corner_style()
var group_docked := false
var square_panel_style: StyleBoxFlat
var edge_docking_enabled := true
var drag_to_hide_enabled := true
var preferred_size := Vector2.ZERO
var body_scroll: ScrollContainer
var body: VBoxContainer
var resize_grip: Control
var base_width := 68.0
var content_height_reserve := 0.0
var minimum_panel_width := 64.0
var gesture := ""
var touch_index := -1
var initial_pointer := Vector2.ZERO
var initial_position := Vector2.ZERO
var initial_size := Vector2.ZERO
var moved := false
var pending_dock := ""
var pending_dock_corner := ""
var pending_dock_slot := Rect2()
var pending_dock_alignment := false
var close_target: Control
var over_close_target := false
var initial_preference := Vector2.ZERO
var find_merge_target: Callable
var merge_target: Control
var group_cell := Rect2()

func _ready() -> void:
	set_process_input(false)
	get_window().focus_exited.connect(end_gesture.bind(true))
	square_panel_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if square_panel_style:
		square_panel_style.set_corner_radius_all(0)
		refresh_corner_style()

func refresh_corner_style() -> void:
	if not square_panel_style: return
	if not dock.is_empty() or group_docked:
		add_theme_stylebox_override("panel", square_panel_style)
	else:
		remove_theme_stylebox_override("panel")

func configure_content(scroll: ScrollContainer, content: VBoxContainer, resize_handle: Control) -> void:
	body_scroll = scroll
	body = content
	resize_grip = resize_handle
	body.minimum_size_changed.connect(apply_preferred_size)
	resize_handle.gui_input.connect(func(event):
		if start_gesture(event, "resize", resize_handle): resize_handle.accept_event())
	apply_preferred_size()

func raise_on_press(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed and not event.canceled and event.device != InputEvent.DEVICE_ID_EMULATION:
			if event is InputEventScreenTouch or event.button_index == MOUSE_BUTTON_LEFT:
				raise_requested.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.position.y < 44 and start_gesture(event, "move", self): accept_event()

func start_gesture(event: InputEvent, action: String, source: Control) -> bool:
	if not gesture.is_empty(): return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		touch_index = -1
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		touch_index = event.index
	else:
		return false
	gesture = action
	initial_pointer = source.get_global_transform_with_canvas() * event.position
	initial_position = position
	initial_size = size
	initial_preference = preferred_size
	moved = false
	raise_requested.emit()
	set_process_input(true)
	if gesture == "resize": resize_started.emit()
	return true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		end_gesture(true)
	elif touch_index < 0 and event is InputEventMouseMotion:
		track_gesture(event.position)
	elif touch_index < 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		end_gesture()
	elif event is InputEventScreenDrag and event.index == touch_index:
		track_gesture(event.position)
	elif event is InputEventScreenTouch and event.index == touch_index and not event.pressed:
		end_gesture(event.canceled)
	else:
		return
	get_viewport().set_input_as_handled()

func track_gesture(pointer: Vector2) -> void:
	var delta := pointer - initial_pointer
	if not moved and delta.length() < 6: return
	moved = true
	if gesture == "move":
		position = initial_position + delta
		if close_target and drag_to_hide_enabled:
			close_target.show()
			close_target.move_to_front()
			over_close_target = close_target.get_global_rect().has_point(pointer)
			close_target.modulate.a = 1.0 if over_close_target else 0.72
		var candidate: Control
		if not over_close_target and find_merge_target.is_valid():
			candidate = find_merge_target.call(pointer)
		if candidate != merge_target:
			merge_target = candidate
			merge_preview_changed.emit(candidate)
		pending_dock = ""
		pending_dock_corner = ""
		pending_dock_slot = Rect2()
		pending_dock_alignment = false
		if edge_docking_enabled and not over_close_target and not merge_target:
			var local_pointer := pointer - get_parent_control().global_position
			var area := work_area(get_parent_control(), true)
			pending_dock = edge_at(area, local_pointer)
			if not pending_dock.is_empty():
				pending_dock_alignment = edge_distance(area, pending_dock, local_pointer) <= ORIENTATION_DISTANCE
				pending_dock_corner = corner_at(area, pending_dock, local_pointer)
		queue_redraw()
		constrain()
		drop_preview_changed.emit()
	else:
		if group_cell.has_area():
			group_resize_dragged.emit(delta)
			queue_redraw()
			return
		var adjusted := delta
		if dock == "right" or dock_corner == "right": adjusted.x = -adjusted.x
		if dock == "bottom" or dock_corner == "bottom": adjusted.y = -adjusted.y
		var available := work_area(get_parent_control(), not dock.is_empty()).size
		preferred_size = (initial_size + adjusted).clamp(
			Vector2(minimum_panel_width, FRAME_HEIGHT + MIN_BODY_HEIGHT),
			available.max(Vector2(minimum_panel_width, FRAME_HEIGHT + MIN_BODY_HEIGHT)))
		apply_preferred_size()
		constrain()

func end_gesture(canceled := false) -> void:
	if gesture.is_empty(): return
	var previous_gesture := gesture
	gesture = ""
	set_process_input(false)
	var should_close := moved and not canceled and previous_gesture == "move" and over_close_target
	var drop_target := merge_target if moved and not canceled and previous_gesture == "move" else null
	merge_target = null
	merge_preview_changed.emit(null)
	if close_target: close_target.hide()
	if is_instance_valid(drop_target):
		pending_dock = ""
		queue_redraw()
		drop_preview_changed.emit()
		merge_requested.emit(drop_target)
		return
	if moved and not canceled and previous_gesture == "move" and not should_close:
		move_committed.emit()
		dock = pending_dock if pending_dock_slot.has_area() else ""
		if not dock.is_empty():
			dock_corner = pending_dock_corner
			position = pending_dock_slot.position
		dock_changed.emit(dock, pending_dock_alignment)
	elif previous_gesture == "move" and (canceled or should_close):
		position = initial_position
	elif canceled:
		preferred_size = initial_preference
		apply_preferred_size()
	if previous_gesture == "resize": resize_finished.emit(moved and not canceled)
	over_close_target = false
	pending_dock = ""
	pending_dock_corner = ""
	pending_dock_slot = Rect2()
	pending_dock_alignment = false
	queue_redraw()
	constrain()
	drop_preview_changed.emit()
	if should_close: close_requested.emit()
	elif moved and not canceled: layout_changed.emit()

static func edge_at(area: Rect2, pointer: Vector2) -> String:
	var nearest := SNAP_DISTANCE
	var edge := ""
	for side in ["left", "right", "top", "bottom"]:
		var distance := edge_distance(area, side, pointer)
		if distance < nearest:
			nearest = distance
			edge = side
	return edge

static func corner_at(area: Rect2, edge: String, pointer: Vector2) -> String:
	var perpendicular := ["left", "right"] if edge in ["top", "bottom"] else ["top", "bottom"]
	for side in perpendicular:
		if edge_distance(area, side, pointer) < SNAP_DISTANCE: return side
	return ""

static func edge_distance(area: Rect2, edge: String, pointer: Vector2) -> float:
	match edge:
		"left": return maxf(0, pointer.x - area.position.x)
		"right": return maxf(0, area.end.x - pointer.x)
		"top": return maxf(0, pointer.y - area.position.y)
		"bottom": return maxf(0, area.end.y - pointer.y)
	return INF

static func work_area(host: Control, docked: bool) -> Rect2:
	# Top and bottom docks meet the workspace bars. Floating panels leave a margin.
	var header := host.get_node_or_null("TopBar") as Control
	var footer := host.get_node_or_null("BottomBar") as Control
	var top := header.get_rect().end.y if header else TOP
	var bottom := footer.position.y if footer else host.size.y - BOTTOM
	var margin := 0.0 if docked else INSET
	if not docked and header: top += INSET
	if not docked and footer: bottom -= INSET
	return Rect2(margin, top, maxf(0.0, host.size.x - margin * 2.0), maxf(0.0, bottom - top))

static func dock_rect(area: Rect2, origin: Vector2, dimensions: Vector2, edge := "", corner := "") -> Rect2:
	var last := (area.end - dimensions).max(area.position)
	var anchor := origin.clamp(area.position, last)
	for side in [edge, corner]:
		match side:
			"left": anchor.x = area.position.x
			"right": anchor.x = last.x
			"top": anchor.y = area.position.y
			"bottom": anchor.y = last.y
	return Rect2(anchor, dimensions)

static func valid_corner(edge: String, corner: Variant) -> String:
	if (edge in ["left", "right"] and corner in ["top", "bottom"]) or (
			edge in ["top", "bottom"] and corner in ["left", "right"]):
		return corner
	return ""

func expand_content(control: Control, initial_height: float) -> void:
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Default room for the main editor, beyond its minimum usable height.
	content_height_reserve = maxf(0, initial_height - control.get_combined_minimum_size().y)
	apply_preferred_size()

func group_minimum() -> Vector2:
	return Vector2(minimum_panel_width, FRAME_HEIGHT + MIN_BODY_HEIGHT + 4)

func default_body_size() -> Vector2:
	return body.get_combined_minimum_size() + Vector2(0, content_height_reserve)

func group_preferred() -> Vector2:
	var natural := default_body_size() + Vector2(0, FRAME_HEIGHT + 4)
	var desired := Vector2(preferred_size.x if preferred_size.x > 0 else maxf(base_width, natural.x),
		preferred_size.y if preferred_size.y > 0 else natural.y)
	return desired.max(group_minimum())

func set_group_cell(cell: Rect2, docked := false) -> void:
	if group_cell == cell and group_docked == docked: return
	group_cell = cell
	group_docked = docked
	refresh_corner_style()
	apply_preferred_size()

func apply_preferred_size() -> void:
	if not is_instance_valid(body_scroll): return
	if group_cell.has_area() and gesture != "move":
		body_scroll.custom_minimum_size = Vector2(0, MIN_BODY_HEIGHT)
		custom_minimum_size.x = minimum_panel_width
		size = group_cell.size
		position = group_cell.position
		return

	var natural := default_body_size()
	var available := work_area(get_parent_control(), not dock.is_empty()).size
	var max_body_height := maxf(MIN_BODY_HEIGHT, available.y - FRAME_HEIGHT)
	var requested_height := preferred_size.y - FRAME_HEIGHT if preferred_size.y > 0 else natural.y
	var viewport_height := clampf(requested_height, MIN_BODY_HEIGHT, max_body_height)
	var scrollbar_width := body_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var content_width := natural.x
	if body.get_combined_minimum_size().y > viewport_height:
		content_width += scrollbar_width
	var requested_width := preferred_size.x if preferred_size.x > 0 else maxf(base_width, content_width)

	body_scroll.custom_minimum_size = Vector2(0, viewport_height)
	custom_minimum_size.x = clampf(requested_width, minimum_panel_width, maxf(minimum_panel_width, available.x))
	reset_size()
	constrain.call_deferred()

func constrain() -> void:
	if group_cell.has_area() and gesture != "move":
		position = group_cell.position
		return
	var actively_moving := gesture == "move"
	var edge := "" if actively_moving else dock
	# Reflow resolves the corner against other docks. During resizing the preview
	# can stay anchored in the corner until the final placement is calculated.
	var corner := dock_corner if gesture == "resize" else ""
	position = dock_rect(work_area(get_parent_control(), not edge.is_empty()), position, size, edge, corner).position
	if actively_moving: return
	if is_instance_valid(resize_grip):
		var footer := resize_grip.get_parent()
		var grip_index := 0 if dock == "right" or dock_corner == "right" else footer.get_child_count() - 1
		if resize_grip.get_index() != grip_index: footer.move_child(resize_grip, grip_index)

func dock_preview_rect(edge: String, dimensions: Vector2, corner := "") -> Rect2:
	return dock_rect(work_area(get_parent_control(), true), position, dimensions, edge, corner)

func _draw() -> void:
	var resizing_group := gesture == "resize" and moved and group_cell.has_area()
	if not resizing_group and pending_dock.is_empty() and not over_close_target and not merge_target: return
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color("#79d7b4"), false, 2)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		end_gesture(true)
