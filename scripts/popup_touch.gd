extends Node
## Godot PopupMenu handles mouse buttons but not raw finger contacts.
## Route a completed tap through the menu's embedder without turning on
## global touch-to-mouse emulation, which would also affect the canvas.
const TAP_SLOP := 10.0
const HEADER_MENU_LAUNCHERS := &"header_menu_launchers"

var menu: PopupMenu
var finger := -1
var start := Vector2.ZERO
var previous := Vector2.ZERO
var swiping := false
var opening := 0

static func watch_launcher(button: BaseButton, header_menu: PopupMenu = null) -> void:
	if header_menu:
		button.add_to_group(HEADER_MENU_LAUNCHERS)
		header_menu.set_meta("header_launcher", button)
	var recover := recover_launcher_press.bind(button)
	if not button.gui_input.is_connected(recover):
		button.gui_input.connect(recover)

static func recover_launcher_press(event: InputEvent, button: BaseButton) -> void:
	if not event is InputEventScreenTouch or not event.pressed or event.canceled: return
	if event.device == InputEvent.DEVICE_ID_EMULATION: return
	# A popup can take focus before the previous finger release reaches
	# its launcher. Clear that press as BaseButton does when a scroll starts.
	button.notification(Control.NOTIFICATION_SCROLL_BEGIN)

func _ready() -> void:
	menu = get_parent() as PopupMenu
	menu.window_input.connect(on_window_input)
	menu.visibility_changed.connect(reset_contact)
	menu.focus_exited.connect(reset_contact)

func reset_contact() -> void:
	finger = -1
	opening += 1

func on_window_input(event: InputEvent) -> void:
	if not menu.visible or not menu.is_embedded() or event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			finger = event.index
			start = event.position
			previous = start
			swiping = false
		elif event.index == finger:
			finger = -1
			if not event.canceled and not swiping and start.distance_to(event.position) <= TAP_SLOP:
				deliver_tap.call_deferred(start, event.position, opening)
	elif event is InputEventScreenDrag and event.index == finger:
		if not swiping and start.distance_to(event.position) > TAP_SLOP: swiping = true
		if swiping:
			var delta: float = event.position.y - previous.y
			if not is_zero_approx(delta): scroll.call_deferred(event.position, delta, opening)
			previous = event.position
	elif event is InputEventMouseButton and event.pressed:
		reset_contact()

func deliver_tap(down: Vector2, point: Vector2, session: int) -> void:
	if not menu.visible or session != opening: return
	var parent := menu.get_parent().get_viewport()
	var bounds := Rect2(Vector2.ZERO, Vector2(menu.size))
	if not bounds.has_point(point):
		var offset := Vector2(menu.position)
		menu.hide()
		if not bounds.has_point(down):
			switch_header_menu(parent, down + offset, point + offset)
		return
	var click := mouse_button(point, MOUSE_BUTTON_LEFT)
	click.pressed = true
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	parent.push_input(click, true)
	if not menu.visible or session != opening: return
	var release := mouse_button(point, MOUSE_BUTTON_LEFT)
	parent.push_input(release, true)

func switch_header_menu(parent: Viewport, down: Vector2, up: Vector2) -> void:
	# A finger can move between the header menus with one tap. Other
	# outside taps only dismiss the popup, including taps over the artwork.
	for button: Button in get_tree().get_nodes_in_group(HEADER_MENU_LAUNCHERS):
		if button.get_viewport() != parent or not button.is_visible_in_tree() or button.disabled: continue
		var bounds := button.get_global_rect()
		if bounds.has_point(down) and bounds.has_point(up):
			if menu.has_meta("header_launcher") and button == menu.get_meta("header_launcher"): return
			button.pressed.emit()
			return

func scroll(point: Vector2, delta: float, session: int) -> void:
	if not menu.visible or session != opening: return
	if not Rect2(Vector2.ZERO, Vector2(menu.size)).has_point(point): return
	var wheel := mouse_button(point, MOUSE_BUTTON_WHEEL_UP if delta > 0 else MOUSE_BUTTON_WHEEL_DOWN)
	wheel.pressed = true
	wheel.factor = absf(delta) / 16.0
	menu.get_parent().get_viewport().push_input(wheel, true)

func mouse_button(point: Vector2, button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.position = Vector2(menu.position) + point
	event.global_position = event.position
	event.button_index = button
	return event
