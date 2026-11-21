extends PanelContainer

signal new_requested
signal open_requested
signal sample_requested
signal resume_requested
signal project_requested(path: String)

const Art = preload("res://scripts/artwork.gd")
const SwipeScroll = preload("res://scripts/swipe_scroll.gd")
const PopupTouch = preload("res://scripts/popup_touch.gd")
const BRAND_LOGO = preload("res://assets/havu-logo.svg")
const PROJECTS_MARK = preload("res://assets/projects-duck-and-bear-symbol.svg")
const OUTER_MARGIN := 32
const CONTENT_WIDTH := 744.0
const ACCENT = Color("#79d7b4")
const MUTED = Color("#a8a8a8")

var content: VBoxContainer
var heading: Label
var projects_mark: TextureRect
var recent_rows: VBoxContainer
var resume_button: Button
var resume_title: Label
var recovery_button: Button
var recovery_menu: PopupMenu
var recovery_paths: Array[String] = []

func _ready() -> void:
	name = "ProjectHome"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background = StyleBoxFlat.new()
	background.bg_color = Color("#151515")
	add_theme_stylebox_override("panel", background)
	var scroll = SwipeScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin = MarginContainer.new()
	for side in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, OUTER_MARGIN)
	center.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)

	var heading_stack := VBoxContainer.new()
	heading_stack.add_theme_constant_override("separation", 4)
	content.add_child(heading_stack)

	var brand := TextureRect.new()
	brand.texture = BRAND_LOGO
	brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.custom_minimum_size = Vector2(132, 46)
	brand.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading_stack.add_child(brand)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	heading_stack.add_child(title_row)
	heading = make_label("Projects", 52, Color("#f2f2f2"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_override("font", Art.SERIF)
	title_row.add_child(heading)

	projects_mark = TextureRect.new()
	projects_mark.name = "DuckAndBearMark"
	projects_mark.texture = PROJECTS_MARK
	projects_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	projects_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	projects_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(projects_mark)

	resized.connect(layout_projects_header)
	layout_projects_header()

	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 12)
	var new_button = make_button("New illustration", new_requested.emit)
	var primary = StyleBoxFlat.new()
	primary.bg_color = ACCENT
	primary.set_corner_radius_all(8)
	new_button.add_theme_stylebox_override("normal", primary)
	new_button.add_theme_color_override("font_color", Color("#12291c"))
	actions.add_child(new_button)
	actions.add_child(make_button("Open project…", open_requested.emit))
	content.add_child(actions)

	resume_title = make_label("", 14, MUTED)
	resume_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(resume_title)
	resume_button = make_button("Resume last session", resume_requested.emit)
	content.add_child(resume_button)
	recovery_menu = PopupMenu.new()
	recovery_menu.id_pressed.connect(func(index): project_requested.emit(recovery_paths[index]))
	add_child(recovery_menu)
	recovery_button = make_button("Recovered edits…", func():
		recovery_menu.position = Vector2i(recovery_button.get_screen_position() + Vector2(0, recovery_button.size.y))
		recovery_menu.popup())
	PopupTouch.watch_launcher(recovery_button)
	content.add_child(recovery_button)
	content.add_child(HSeparator.new())
	content.add_child(make_label("Recent projects", 20, Color("#f2f2f2")))
	recent_rows = VBoxContainer.new()
	content.add_child(recent_rows)
	if not OS.has_feature("tablet_beta"):
		var sample_button = make_button("Open editable café example", sample_requested.emit)
		sample_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		content.add_child(sample_button)

func layout_projects_header() -> void:
	var width := clampf(size.x - OUTER_MARGIN * 2.0, 240.0, CONTENT_WIDTH)
	content.custom_minimum_size.x = width
	var compact := width < 360.0
	heading.add_theme_font_size_override("font_size", 40 if compact else 52)
	projects_mark.custom_minimum_size.x = 80.0 if compact else 108.0

func update_projects(recent: Array, recovered: Array, session_title: String, session_available: bool) -> void:
	resume_button.visible = session_available
	resume_title.visible = session_available and not session_title.is_empty()
	resume_title.text = session_title
	recovery_button.visible = not recovered.is_empty()
	recovery_menu.clear()
	recovery_paths.clear()
	for entry in recovered:
		recovery_menu.add_item(entry.title, recovery_paths.size())
		recovery_paths.append(entry.path)
	for row in recent_rows.get_children():
		recent_rows.remove_child(row)
		row.queue_free()
	if recent.is_empty():
		var empty_notice := make_label("Projects you open or save will appear here.", 15, MUTED)
		empty_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		recent_rows.add_child(empty_notice)
		return
	for entry in recent:
		var path: String = entry.path
		var row = make_button(entry.title, func(): project_requested.emit(path))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.tooltip_text = path if not path.begins_with("content://") else entry.title
		recent_rows.add_child(row)

func make_label(value: String, font_size: int, color: Color) -> Label:
	var result = Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

func make_button(value: String, action: Callable) -> Button:
	var result = Button.new()
	result.text = value
	result.custom_minimum_size.y = 48
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(action)
	return result
