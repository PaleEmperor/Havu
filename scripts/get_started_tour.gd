extends Control
## A short, modal walkthrough anchored to the actual workspace controls.

const ACCENT := Color("#79d7b4")
const VEIL := Color(0.0, 0.0, 0.0, 0.56)
const EDGE := 14.0
const GAP := 12.0

var steps: Array[Dictionary] = []
var step_index := 0
var target: Control
var spotlight := Rect2()
var card: PanelContainer
var progress: Label
var heading: Label
var description: Label
var skip_button: Button
var back_button: Button
var next_button: Button

func _ready() -> void:
	name = "GetStartedTour"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	card = PanelContainer.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("#1c211e")
	skin.border_color = Color("#527669")
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(12)
	for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
		skin.set_content_margin(side, 16)
	card.add_theme_stylebox_override("panel", skin)
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	progress = make_label(13, ACCENT)
	heading = make_label(22, Color("#f2f2f2"))
	description = make_label(16, Color("#d4dcd7"))
	for control in [progress, heading, description]: column.add_child(control)

	var actions := HBoxContainer.new()
	column.add_child(actions)
	skip_button = add_button(actions, "Skip tour", close)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	back_button = add_button(actions, "Back", func(): show_step(step_index - 1))
	next_button = add_button(actions, "Next", advance)
	var next_skin := skin.duplicate() as StyleBoxFlat
	next_skin.bg_color = ACCENT
	for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
		next_skin.set_content_margin(side, 8)
	next_button.add_theme_stylebox_override("normal", next_skin)
	var next_hover := next_skin.duplicate() as StyleBoxFlat
	next_hover.bg_color = Color("#98e4c6")
	next_button.add_theme_stylebox_override("hover", next_hover)
	var next_pressed := next_skin.duplicate() as StyleBoxFlat
	next_pressed.bg_color = Color("#65b395")
	next_button.add_theme_stylebox_override("pressed", next_pressed)
	for state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		next_button.add_theme_color_override(state, Color("#133023"))
	resized.connect(layout_card)
	card.minimum_size_changed.connect(layout_card.call_deferred)
	set_process_input(false)
	hide()

func make_label(font_size: int, ink: Color) -> Label:
	var control := Label.new()
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", ink)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control

func add_button(row: HBoxContainer, caption: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = caption
	control.custom_minimum_size.y = 44
	control.pressed.connect(action)
	row.add_child(control)
	return control

func start(new_steps: Array[Dictionary]) -> void:
	steps = new_steps
	set_process_input(true)
	show()
	show_step(0)
	next_button.grab_focus.call_deferred()

func show_step(index: int) -> void:
	step_index = index
	watch_target(steps[index].target)
	progress.text = "Getting started · %d of %d" % [index + 1, steps.size()]
	heading.text = steps[index].title
	description.text = steps[index].text
	back_button.visible = index > 0
	next_button.text = "Done" if index == steps.size() - 1 else "Next"
	var focus_order := [skip_button, back_button, next_button] if back_button.visible else [skip_button, next_button]
	for i in focus_order.size():
		var control: Button = focus_order[i]
		control.focus_next = focus_order[(i + 1) % focus_order.size()].get_path()
		control.focus_previous = focus_order[posmod(i - 1, focus_order.size())].get_path()
	if not back_button.visible and get_viewport().gui_get_focus_owner() == null:
		next_button.grab_focus()
	layout_card()

func watch_target(control: Control) -> void:
	if is_instance_valid(target):
		target.item_rect_changed.disconnect(layout_card)
	target = control
	if is_instance_valid(target):
		target.item_rect_changed.connect(layout_card)

func advance() -> void:
	if step_index == steps.size() - 1: close()
	else: show_step(step_index + 1)

func close() -> void:
	watch_target(null)
	hide()
	set_process_input(false)

func layout_card() -> void:
	if not visible or not card: return
	spotlight = Rect2()
	if is_instance_valid(target) and target.is_visible_in_tree():
		spotlight = target.get_global_rect().grow(5).intersection(Rect2(Vector2.ZERO, size))

	card.size = Vector2(minf(398.0, maxf(1.0, size.x - EDGE * 2)), card.get_combined_minimum_size().y)
	var location := (size - card.size) / 2.0
	if spotlight.has_area():
		location.x = spotlight.get_center().x - card.size.x / 2.0
		location.y = spotlight.end.y + GAP
		if location.y + card.size.y > size.y - EDGE:
			location.y = spotlight.position.y - card.size.y - GAP
	card.position = location.clamp(Vector2.ONE * EDGE, (size - card.size - Vector2.ONE * EDGE).max(Vector2.ONE * EDGE))
	queue_redraw()

func _draw() -> void:
	if not spotlight.has_area():
		draw_rect(Rect2(Vector2.ZERO, size), VEIL)
		return
	draw_rect(Rect2(0, 0, size.x, spotlight.position.y), VEIL)
	draw_rect(Rect2(0, spotlight.end.y, size.x, size.y - spotlight.end.y), VEIL)
	draw_rect(Rect2(0, spotlight.position.y, spotlight.position.x, spotlight.size.y), VEIL)
	draw_rect(Rect2(spotlight.end.x, spotlight.position.y, size.x - spotlight.end.x, spotlight.size.y), VEIL)
	draw_rect(spotlight, ACCENT, false, 2)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
