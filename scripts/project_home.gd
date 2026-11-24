extends PanelContainer

signal new_requested
signal open_requested
signal sample_requested
signal resume_requested
signal project_requested(path: String)
signal folder_project_requested(path: String)
signal folder_picker_requested
signal folder_refresh_requested
signal folder_clear_requested

const Art = preload("res://scripts/artwork.gd")
const SwipeScroll = preload("res://scripts/swipe_scroll.gd")
const PopupTouch = preload("res://scripts/popup_touch.gd")
const BRAND_LOGO = preload("res://assets/havu-logo.svg")
const PROJECTS_MARK = preload("res://assets/projects-duck-and-bear-symbol.svg")
const OUTER_MARGIN := 26
const CONTENT_WIDTH := 850.0
const ACCENT = Color("#79d7b4")
const MUTED = Color("#a8a8a8")
const FOREGROUND = Color("#f1f3f1")

var content: VBoxContainer
var heading: Label
var projects_mark: TextureRect
var recent_rows: VBoxContainer
var folder_panel: VBoxContainer
var folder_rows: GridContainer
var folder_title: Label
var folder_status: Label
var folder_choose: Button
var open_folder_button: Button
var folder_refresh: Button
var folder_clear: Button
var folder_tab: Button
var recent_tab: Button
var resume_button: Button
var resume_title: Label
var resume_strip: PanelContainer
var recovery_button: Button
var recovery_menu: PopupMenu
var recovery_paths: Array[String] = []

func _ready() -> void:
	name = "ProjectHome"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background = StyleBoxFlat.new()
	background.bg_color = Color("#111413")
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
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var masthead := HBoxContainer.new()
	masthead.add_theme_constant_override("separation", 16)
	content.add_child(masthead)
	var heading_stack := VBoxContainer.new()
	heading_stack.add_theme_constant_override("separation", 0)
	heading_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_child(heading_stack)

	var brand := TextureRect.new()
	brand.texture = BRAND_LOGO
	brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.custom_minimum_size = Vector2(108, 36)
	brand.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading_stack.add_child(brand)

	heading = make_label("Projects", 56, FOREGROUND)
	heading.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	heading.add_theme_font_override("font", Art.SERIF)
	heading_stack.add_child(heading)

	projects_mark = TextureRect.new()
	projects_mark.name = "DuckAndBearMark"
	projects_mark.texture = PROJECTS_MARK
	projects_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	projects_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	projects_mark.texture_filter = Control.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	projects_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	projects_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	masthead.add_child(projects_mark)

	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 12)
	var new_button = make_button("New illustration", new_requested.emit)
	new_button.add_theme_stylebox_override("normal", surface(ACCENT))
	new_button.add_theme_stylebox_override("hover", surface(Color("#a5ebd0")))
	new_button.add_theme_stylebox_override("pressed", surface(Color("#61bc98")))
	new_button.add_theme_color_override("font_color", Color("#12291c"))
	new_button.add_theme_color_override("font_hover_color", Color("#12291c"))
	new_button.add_theme_color_override("font_pressed_color", Color("#12291c"))
	actions.add_child(new_button)
	actions.add_child(make_button("Open project…", open_requested.emit))
	open_folder_button = make_button("Open folder…", folder_picker_requested.emit)
	actions.add_child(open_folder_button)
	content.add_child(actions)

	resume_strip = PanelContainer.new()
	resume_strip.add_theme_stylebox_override("panel", surface(Color("#1a201d"), Color("#313c35"), 12, 4))
	content.add_child(resume_strip)
	var resume_row := HBoxContainer.new()
	resume_row.add_theme_constant_override("separation", 12)
	resume_strip.add_child(resume_row)
	resume_title = make_label("", 15, FOREGROUND)
	resume_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	resume_row.add_child(resume_title)
	resume_button = make_button("Resume", resume_requested.emit)
	resume_button.tooltip_text = "Resume last session"
	resume_button.accessibility_name = "Resume last session"
	resume_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	resume_row.add_child(resume_button)
	recovery_menu = PopupMenu.new()
	recovery_menu.id_pressed.connect(func(index): project_requested.emit(recovery_paths[index]))
	add_child(recovery_menu)
	recovery_button = make_button("Recovered edits…", func():
		recovery_menu.position = Vector2i(recovery_button.get_screen_position() + Vector2(0, recovery_button.size.y))
		recovery_menu.popup())
	PopupTouch.watch_launcher(recovery_button)
	recovery_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(recovery_button)

	var browser := PanelContainer.new()
	browser.add_theme_stylebox_override("panel", surface(Color("#171b19"), Color("#29332d"), 12, 12))
	content.add_child(browser)
	var shelf := VBoxContainer.new()
	shelf.add_theme_constant_override("separation", 10)
	browser.add_child(shelf)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	shelf.add_child(tabs)
	var tab_group := ButtonGroup.new()
	folder_tab = make_button("Working folder", func(): show_folder_tab(true))
	recent_tab = make_button("Recent projects", func(): show_folder_tab(false))
	for tab in [folder_tab, recent_tab]:
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.add_theme_stylebox_override("normal", surface(Color.TRANSPARENT))
		tab.add_theme_stylebox_override("hover", surface(Color("#232c27")))
		tab.add_theme_stylebox_override("pressed", surface(Color("#24352c"), Color("#3e5e4d")))
		tab.add_theme_color_override("font_pressed_color", ACCENT)
		tabs.add_child(tab)

	folder_panel = VBoxContainer.new()
	folder_panel.add_theme_constant_override("separation", 8)
	shelf.add_child(folder_panel)
	var folder_actions := HFlowContainer.new()
	folder_actions.add_theme_constant_override("h_separation", 6)
	folder_actions.add_theme_constant_override("v_separation", 5)
	folder_panel.add_child(folder_actions)
	folder_title = make_label("", 20, FOREGROUND)
	folder_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	folder_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	folder_title.custom_minimum_size.x = 116
	folder_actions.add_child(folder_title)
	folder_choose = make_button("Change folder…", folder_picker_requested.emit)
	folder_refresh = make_button("Refresh", folder_refresh_requested.emit)
	folder_clear = make_button("Disconnect", folder_clear_requested.emit)
	folder_clear.tooltip_text = "Remove this folder from Projects"
	for action in [folder_choose, folder_refresh, folder_clear]:
		action.size_flags_horizontal = Control.SIZE_SHRINK_END
		folder_actions.add_child(action)
	folder_status = make_label("", 15, MUTED)
	folder_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	folder_panel.add_child(folder_status)
	folder_rows = GridContainer.new()
	folder_rows.add_theme_constant_override("h_separation", 8)
	folder_rows.add_theme_constant_override("v_separation", 6)
	folder_panel.add_child(folder_rows)

	recent_rows = VBoxContainer.new()
	shelf.add_child(recent_rows)
	show_folder_tab(false)
	if not OS.has_feature("tablet_beta"):
		var sample_button = make_button("Open editable café example", sample_requested.emit)
		sample_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		content.add_child(sample_button)
	resized.connect(layout_projects_header)
	layout_projects_header()

func layout_projects_header() -> void:
	var width := clampf(size.x - OUTER_MARGIN * 2.0, 240.0, CONTENT_WIDTH)
	content.custom_minimum_size.x = width
	var compact := width < 360.0
	heading.add_theme_font_size_override("font_size", 40 if compact else 56)
	projects_mark.custom_minimum_size = Vector2(72, 42) if compact else Vector2(154, 76)
	folder_rows.columns = 2 if width >= 580.0 else 1

func update_projects(recent: Array, recovered: Array, session_title: String, session_available: bool) -> void:
	resume_strip.visible = session_available
	resume_button.visible = session_available
	resume_title.text = session_title if not session_title.is_empty() else "Last session"
	recovery_button.visible = not recovered.is_empty()
	recovery_menu.clear()
	recovery_paths.clear()
	for entry in recovered:
		recovery_menu.add_item(entry.title, recovery_paths.size())
		recovery_paths.append(entry.path)
	clear_rows(recent_rows)
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

func update_folder(path: String, result: Dictionary, active_path: String) -> void:
	var connected := not path.is_empty()
	folder_title.text = result.get("title", path)
	folder_title.tooltip_text = folder_title.text if path.begins_with("content://") else path
	folder_title.visible = connected
	open_folder_button.visible = not connected
	folder_choose.visible = connected
	folder_refresh.visible = connected
	folder_clear.visible = connected
	clear_rows(folder_rows)
	var entries: Array = result.get("entries", [])
	folder_status.text = str(result.get("error", ""))
	if not connected: folder_status.text = "Projects from the folder you open will appear here."
	elif folder_status.text.is_empty() and entries.is_empty(): folder_status.text = "This folder has no Havu projects yet."
	folder_status.visible = not folder_status.text.is_empty()
	for entry in entries:
		var project_path: String = entry.path
		var current := project_path == active_path
		var title: String = entry.name.get_basename()
		var row := make_button(title + ("  ·  Open" if current else ""),
			func(): folder_project_requested.emit(project_path))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.tooltip_text = entry.name
		if current:
			row.add_theme_color_override("font_color", ACCENT)
			row.add_theme_stylebox_override("normal", surface(Color("#22342b"), Color("#385443")))
		folder_rows.add_child(row)

func show_folder_tab(show_folder: bool) -> void:
	folder_tab.set_pressed_no_signal(show_folder)
	recent_tab.set_pressed_no_signal(not show_folder)
	folder_panel.visible = show_folder
	recent_rows.visible = not show_folder

func clear_rows(rows: Container) -> void:
	for row in rows.get_children():
		rows.remove_child(row)
		row.queue_free()

func make_label(value: String, font_size: int, color: Color) -> Label:
	var result = Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

func make_button(value: String, action: Callable) -> Button:
	var result = Button.new()
	result.text = value
	result.custom_minimum_size.y = 46
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_stylebox_override("normal", surface(Color("#202622"), Color("#2b352e")))
	result.add_theme_stylebox_override("hover", surface(Color("#2b3630"), Color("#415246")))
	result.add_theme_stylebox_override("pressed", surface(Color("#304337"), Color("#50725e")))
	result.pressed.connect(action)
	return result

func surface(fill: Color, border := Color.TRANSPARENT, horizontal := 12, vertical := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box
