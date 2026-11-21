extends ScrollContainer

const SWIPE_THRESHOLD := 9.0

# Android reports S Pen contact as a primary mouse button.
var swipe_with_mouse := OS.has_feature("android")
var mouse_swipe := false
var swipe_index := -1
var swipe_start := Vector2.ZERO
var swipe_previous := Vector2.ZERO
var swipe_axis := VERTICAL
var swipe_owner: ScrollContainer
var swipe_chain: Array[ScrollContainer] = []
var swipe_speed := 0.0
var last_motion_ms := 0
var fling: Tween

func _ready() -> void:
	set_process_input(false)
	watch_content(self)
	get_window().focus_exited.connect(clear_swipe)

func watch_content(node: Node) -> void:
	if node != self and node is ScrollContainer: return
	# Subscribe at the hit control. Buttons stop GUI propagation, while sliders,
	# drawing surfaces and drag handles keep their own direct touch gestures.
	if not (node is Container or node is BaseButton or node is Panel or node is Label): return
	var observe := watch_press.bind(node)
	if not node.gui_input.is_connected(observe): node.gui_input.connect(observe)
	if node is OptionButton: node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	if node is BaseButton: return
	if not node.child_entered_tree.is_connected(watch_content): node.child_entered_tree.connect(watch_content)
	for child in node.get_children(): watch_content(child)

func watch_press(event: InputEvent, source: Control) -> void:
	if source != self and not is_ancestor_of(source): return
	if mouse_swipe and event is InputEventScreenTouch and event.pressed and not event.canceled:
		end_swipe(false)
	if swipe_index >= 0 or mouse_swipe: return
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		swipe_index = event.index
	elif swipe_with_mouse and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_swipe = true
	else:
		return
	var ancestor: Node = self
	while ancestor != null and not ancestor is Window:
		if ancestor is ScrollContainer and ancestor.has_method("stop_fling"):
			ancestor.stop_fling()
			swipe_chain.append(ancestor)
		ancestor = ancestor.get_parent()
	swipe_start = source.get_global_transform_with_canvas() * event.position
	swipe_previous = swipe_start
	swipe_speed = 0.0
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if mouse_swipe:
		if event is InputEventMouseMotion:
			if move_swipe(event.position, event.velocity): get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			end_swipe(not event.canceled)
	elif event is InputEventScreenDrag and event.index == swipe_index:
		if move_swipe(event.position, event.velocity): get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.index == swipe_index and not event.pressed:
		end_swipe(not event.canceled)

func move_swipe(position_in_viewport: Vector2, velocity_in_viewport: Vector2) -> bool:
	if not is_instance_valid(swipe_owner):
		var displacement := position_in_viewport - swipe_start
		if displacement.length() < SWIPE_THRESHOLD: return false
		swipe_axis = HORIZONTAL if absf(displacement.x) > absf(displacement.y) else VERTICAL
		if not swipe_chain.any(can_scroll_axis):
			swipe_axis = VERTICAL if swipe_axis == HORIZONTAL else HORIZONTAL
		for candidate in swipe_chain:
			var bar := scroll_bar(candidate)
			var limit := bar.max_value - bar.page
			if not can_scroll_axis(candidate): continue
			if (displacement[swipe_axis] < 0.0 and bar.value < limit) or (
					displacement[swipe_axis] > 0.0 and bar.value > bar.min_value):
				swipe_owner = candidate
				break
		if not is_instance_valid(swipe_owner):
			# Even at the edge, a swipe over a row must not activate its button.
			swipe_owner = self
		swipe_owner.propagate_notification(NOTIFICATION_SCROLL_BEGIN)
		swipe_owner.scroll_started.emit()
	var transform_to_owner := swipe_owner.get_global_transform_with_canvas().affine_inverse()
	var movement := transform_to_owner.basis_xform(position_in_viewport - swipe_previous)
	var bar := scroll_bar(swipe_owner)
	if scroll_axis_enabled(swipe_owner): bar.value -= movement[swipe_axis]
	swipe_previous = position_in_viewport
	swipe_speed = -transform_to_owner.basis_xform(velocity_in_viewport)[swipe_axis]
	last_motion_ms = Time.get_ticks_msec()
	return true

func scroll_bar(owner: ScrollContainer) -> ScrollBar:
	return owner.get_h_scroll_bar() if swipe_axis == HORIZONTAL else owner.get_v_scroll_bar()

func scroll_axis_enabled(owner: ScrollContainer) -> bool:
	var mode := owner.horizontal_scroll_mode if swipe_axis == HORIZONTAL else owner.vertical_scroll_mode
	return mode != ScrollContainer.SCROLL_MODE_DISABLED

func can_scroll_axis(owner: ScrollContainer) -> bool:
	var bar := scroll_bar(owner)
	return owner.is_visible_in_tree() and scroll_axis_enabled(owner) and bar.max_value - bar.page > bar.min_value

func end_swipe(allow_fling: bool) -> void:
	var owner := swipe_owner
	var velocity := swipe_speed
	swipe_owner = null
	mouse_swipe = false
	swipe_index = -1
	swipe_chain.clear()
	set_process_input(false)
	if not is_instance_valid(owner): return
	if allow_fling and scroll_axis_enabled(owner) and Time.get_ticks_msec() - last_motion_ms <= 90:
		owner.start_fling(scroll_bar(owner), velocity)
	owner.propagate_notification(NOTIFICATION_SCROLL_END)
	owner.scroll_ended.emit()

func start_fling(bar: ScrollBar, velocity: float) -> void:
	var target := clampf(bar.value + clampf(velocity * 0.14, -400.0, 400.0), bar.min_value, bar.max_value - bar.page)
	if absf(target - bar.value) < 4.0: return
	stop_fling()
	fling = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fling.tween_property(bar, "value", target, 0.32)

func stop_fling() -> void:
	if fling != null:
		fling.kill()
		fling = null

func clear_swipe() -> void:
	end_swipe(false)
	stop_fling()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		clear_swipe()
