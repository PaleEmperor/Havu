extends Control

signal project_load_finished(success: bool)
const PngExport = preload("res://scripts/png_export.gd")
const Raster = preload("res://scripts/raster_asset.gd")
const Document = preload("res://scripts/document.gd")
const Canvas = preload("res://scripts/canvas.gd")
const Art = preload("res://scripts/artwork.gd")
const LayerDragList = preload("res://scripts/layer_drag_list.gd")
const ColorWheel = preload("res://scripts/color_wheel.gd")
const ColorChannels = preload("res://scripts/color_channels.gd")
const GroupLayout = preload("res://scripts/panel_group_layout.gd")
const GroupGrip = preload("res://scripts/panel_group_grip.gd")
const FloatingPanel = preload("res://scripts/floating_panel.gd")
const BrushPreview = preload("res://scripts/brush_preview.gd")
const BrushLibrary = preload("res://scripts/brush_library.gd")
const MyPaintBrush = preload("res://scripts/mypaint_brush.gd")
const MAX_BRUSH_FILE_BYTES := 256 * 1024
const Sample = preload("res://scripts/sample.gd")
const ProjectHome = preload("res://scripts/project_home.gd")
const GetStartedTour = preload("res://scripts/get_started_tour.gd")
const PanelRevealTabs = preload("res://scripts/panel_reveal_tabs.gd")
const LayerThumbnail = preload("res://scripts/layer_thumbnail.gd")
const UIScaleSlider = preload("res://scripts/ui_scale_slider.gd")
const TouchSlider = preload("res://scripts/touch_slider.gd")
const PopupTouch = preload("res://scripts/popup_touch.gd")
const TouchTextEntry = preload("res://scripts/touch_text_entry.gd")
const CanvasNumberPad = preload("res://scripts/canvas_number_pad.gd")
const Fonts = preload("res://scripts/font_library.gd")
const UndoButton = preload("res://scripts/undo_button.gd")
const SwipeScroll = preload("res://scripts/swipe_scroll.gd")
const BRAND_MARK = preload("res://assets/havu-mark.svg")
const BRAND_LOGO = preload("res://assets/havu-logo.svg")
const RECOVERY_PATH = "user://recovery.havu"
const CANVAS_PRESETS := [
	["Illustration", Vector2i(900, 1100)], ["A5 menu", Vector2i(1748, 2480)],
	["A4 page", Vector2i(2480, 3508)], ["US Letter", Vector2i(2550, 3300)],
	["Square", Vector2i(1600, 1600)], ["Wide screen", Vector2i(1920, 1080)],
	["Tall screen", Vector2i(1080, 1920)],
]
const ACCENT = Color("#79d7b4")
const MUTED = Color("#a0a0a0")
var document = Document.new()
var show_shortcut_hints := not OS.has_feature("android") and not OS.has_feature("ios")
var canvas
var panels = {}
var tool_buttons = {}
var layer_list: VBoxContainer
var layer_scroll
var layer_rows := {}
var highlighted_layer_id := ""
var layer_rows_solo_id := ""
var layer_icons := {}
var layer_row_styles: Array[StyleBoxFlat] = []
var layer_preview_refresh_queued := false
var title_edit: LineEdit
var text_entry: TouchTextEntry
var save_label: Label
var status_label: Label
var selection_actions: BoxContainer
var union_button: Button
var transform_button: Button
var transform_menu: PopupMenu
var arrange_menu: PopupMenu
var arrange_to_canvas := false
var paint_actions: HBoxContainer
var paint_inside_button: Button
var node_actions: BoxContainer
var add_node_button: Button
var node_spread_slider: TouchSlider
var node_spread_readout: Label
var node_spread_dragging := false
var selection_tray: PanelContainer
var group_artwork_button: Button
var ungroup_artwork_button: Button
var shape_actions: BoxContainer
var selected_shape_style: Button
var finish_path_button: Button
var close_path_button: Button
var shape_menu: PopupPanel
var selection_menu: PopupPanel
var shape_icons: Array[Button] = []
var selection_icons: Array[Button] = []
var select_across_toggle: CheckButton
var keep_selecting_toggle: CheckButton
var merge_on_group_toggle: CheckButton
var merge_on_group := false
var selection_move_button: Button
var selection_move_dialog: ConfirmationDialog
var selection_move_targets: OptionButton
var deselect_button: Button
var shape_style_dialog: ConfirmationDialog
var shape_fill_switch: CheckBox
var shape_outline_switch: CheckBox
var shape_fill_picker: ColorPickerButton
var shape_outline_picker: ColorPickerButton
var shape_line_width: SpinBox
var shape_style_opacity: HSlider
var shape_edit_id := ""
var shape_style_open_path := false
const SHAPE_OPTIONS := [
	["rect", "Rectangle", "M3 7H23V19H3Z"],
	["square", "Square", "M5 5H21V21H5Z"],
	["rounded_rect", "Rounded rectangle", "M7 6H19Q23 6 23 10V16Q23 20 19 20H7Q3 20 3 16V10Q3 6 7 6Z"],
	["ellipse", "Ellipse", "M3 13a10 6.5 0 1 0 20 0a10 6.5 0 1 0-20 0"],
	["circle", "Circle", "M5 13a8 8 0 1 0 16 0a8 8 0 1 0-16 0"],
	["triangle", "Triangle", "M13 4L23 21H3Z"],
	["diamond", "Diamond", "M13 3L22 13L13 23L4 13Z"],
	["star", "Star", "M13 3l2.7 6.5 7 .6-5.3 4.6 1.6 6.8-6-3.6-6 3.6 1.6-6.8-5.3-4.6 7-.6Z"],
	["line", "Line", "M5 21L21 5"],
	["arrow", "Arrow", "M5 21L21 5M13 5H21V13"],
	["path", "Pen path", "M5 19L12 6L21 14M3 17H7V21H3ZM10 4H14V8H10ZM19 12H23V16H19Z"],
]
const SELECTION_OPTIONS := [
	["select", "Select object", "M5 4L21 15L14 16L11 22Z"],
	["select_rect", "Rectangle selection", "M3 11V7H7M11 7H15M19 7H23V11M23 15V19H19M15 19H11M7 19H3V15"],
	["select_ellipse", "Ellipse selection", "M3 12Q4 9 8 8M11 7H15M18 8Q22 9 23 12M23 14Q22 17 18 18M15 19H11M8 18Q4 17 3 14"],
	["select_lasso", "Freehand selection", "M5 17C1 14 4 7 9 6M12 5C16 4 21 6 22 9M23 12C22 17 17 20 12 20M9 20C5 20 3 17 4 16C6 13 11 16 8 22"],
	["select_square", "Square selection", "M5 9V5H9M12 5H14M17 5H21V9M21 12V14M21 17V21H17M14 21H12M9 21H5V17M5 14V12"],
	["select_circle", "Circle selection", "M5 11Q6 6 11 5M15 5Q20 6 21 11M21 15Q20 20 15 21M11 21Q6 20 5 15"],
]
var tool_grid: GridContainer
var tools_horizontal := false
const FOOTER_HEIGHT := 40.0
const FOOTER_PADDING := 5.0
const ZOOM_PRESETS = [25, 50, 75, 100, 150, 200, 400, 800]
var zoom_button: Button
var pointer_x: Label
var pointer_y: Label
var pointer_pressure: Label
var page_dimensions: Label
var footer_metrics: HBoxContainer
var brand_button: Button
var brush_library_button: Button
var header_layers_button: Button
var get_started_tour: GetStartedTour
var previous_workspace_size := Vector2.ZERO
var metrics_elapsed := 0.0
var input_settings_dialog: AcceptDialog
const RECENT_COLOR_LIMIT := 6
const SAVED_COLOR_LIMIT := 32
var color_picker: Control
var color_channels: VBoxContainer
var color_preview_style: StyleBoxFlat
var color_panel_tabs: Array[Button] = []
var palette_page: VBoxContainer
var palette_swatches: HFlowContainer
var saved_swatches: HFlowContainer
var remove_swatch: Button
var color_hex: LineEdit
var recent_swatches: HFlowContainer
var recent_colors: Array[String] = []
var saved_swatches_hex: Array[String] = []
var history_preferences_dirty := false
var font_choice: Button
var fonts_dialog: ConfirmationDialog
var font_import_dialog: FileDialog
var font_search: LineEdit
var font_category: OptionButton
var font_results: VBoxContainer
var font_preview: Label
var font_preview_id := ""
var text_edit: TextEdit
var font_size: SpinBox
var brush_choice: OptionButton
var brush_rows: VBoxContainer
const BRUSH_LIBRARY_PANEL := "Brushes"
const BRUSH_SETTINGS_PANEL := "Brush settings"
const BRUSH_TAB_KEYS := [BRUSH_LIBRARY_PANEL, BRUSH_SETTINGS_PANEL]
var brush_tab_buttons: Array[Button] = []
var brush_pages: TabContainer
var legacy_brush_layout_key := BRUSH_LIBRARY_PANEL
var restoring_workspace := true
var active_brush_tab := BRUSH_LIBRARY_PANEL
var group_preview: PanelContainer
var group_preview_text: Label
var group_preview_outlines: Node2D
var group_preview_cells: Dictionary = {}
var panel_groups: Array = []
var group_grips: Dictionary = {}
var group_move: Dictionary = {}
var panel_reveal_tabs: Control
var group_resize: Dictionary = {}
var pending_group_drop: Dictionary = {}
var group_serial := 0
var dock_preview: PanelContainer
var dock_preview_label: Label
const DOCK_GAP := 10.0
var dock_reflow_queued := false
var dock_reflow_last: Control
var current_brush_preview
var brush_editor_preview
var brush_editor_name: Label
var brush_revert: Button
var brush_update: Button
var brush_manage: Button
var brush_menu: PopupMenu
var brush_profile_controls := {}
var brush_editor_sections := {}
var brush_editor_section := ""
var brush_editor_loading := false
var brush_pressure_graph: Control
var brush_tuning_scroll: ScrollContainer
var brush_test_canvas
var top_color: Button
var builtin_brushes := BrushLibrary.builtins()
var active_brush: Dictionary = builtin_brushes[0]
var brush_category: OptionButton
var brush_favorite_button: Button
var favorite_brushes: Array[String] = []
var recent_brushes: Array[String] = []
var brush_drafts: Dictionary = {}
const RECENT_BRUSH_LIMIT := 12
const MAX_FAVORITES := 256
var brush_search: LineEdit
var brush_scroll: ScrollContainer
var brush_row_buttons: Array[Button] = []
var brush_preview_refresh_queued := false
var file_menu: PopupMenu
var workspace_menu: PopupMenu
var workspace_settings_dialog: AcceptDialog
const PEN_BUTTON_TOOLS := ["", "picker", "erase", "hand"]
var pen_bridge
var pen_button_selector: OptionButton
var pen_action_selector: OptionButton
var pen_detection_dialog: ConfirmationDialog
var pen_test_target: PanelContainer
var pen_test_feedback: Label
var pen_detection_contact := Callable()
var detected_pen_slot := 0
var ui_scale_percent := 100
var ui_scale_slider: Control
var ui_scale_label: Label
var reset_ui_scale_button: Button
var header_tools: HBoxContainer
var header_panels_button: Button
var header_brush_settings: Button
var header_panels_icon: Texture2D
var horizontal_toolbar_check: CheckBox
const WORKSPACE_OPTIONS = {
	"edge_docking": ["Snap panels to edges", "Dock a panel by dropping it near an edge. Existing docks stay in place."],
	"auto_orientation": ["Rotate toolbar when dragged closer to an edge", "The first dock preview keeps the current orientation. Move closer to switch to vertical at the sides or horizontal at the top and bottom."],
	"drag_to_hide": ["Show bin while dragging panels", "Drop a panel on the bin to hide it. Reopen it from Panels."],
	"contextual_actions": ["Show actions beside Select", "Show selection actions beside the toolbar. They’re also available from the workspace menu when this is off."],
	"footer_metrics": ["Show canvas metrics in the footer", "Show X and Y, pressure, and page dimensions."],
	"panel_groups": ["Group panels by dragging", "Drop near a panel edge to join it as a row or column."],
	"avoid_panel_overlap": ["Keep newly opened panels clear", "Find space for a panel when it opens."],
	"panel_reveal_tabs": ["Show grab tabs for covered panels", "Tap a tab to bring its panel forward, or drag it to move the panel."],
}
var workspace_options: Dictionary = {}
var panels_menu: PopupMenu
const PANEL_NAMES = ["Tools", BRUSH_LIBRARY_PANEL, "Color", "Layers", "Typography"]
var size_slider: HSlider
var opacity_slider: HSlider
var blending_slider: HSlider
var smooth_slider: HSlider
var clip_check: CheckBox
var save_dialog: FileDialog
var import_image_dialog: FileDialog
var layer_actions: PopupMenu
var layer_actions_button: Button
var layer_opacity_slider: HSlider
var layer_opacity_label: Label
var alpha_lock_button: Button
var layer_solo_button: Button
var opacity_drag_layer := ""
var open_dialog: FileDialog
var export_dialog: FileDialog
var export_menu: PopupMenu
var undo_button: UndoButton
var redo_button: Button
var autosave_timer: Timer
var toast_timer: Timer
var toast: PanelContainer
var toast_label: Label
var file_path = ""
var exporting_png = false
var export_type = "svg"
var export_layer_id := ""
var settings = ConfigFile.new()
var presets: Array = []
var palette = ["#183e32", "#226451", "#4b9277", "#79d7b4", "#54b8b1", "#c5e6d8", "#f9f7ef", "#dacdb0", "#bc9271", "#9b5b48", "#607c69", "#202624"]
var developer_panel: PanelContainer
var developer_label: Label
var new_dialog: ConfirmationDialog
var resizing_canvas := false
var canvas_artwork_mode: OptionButton
var new_width: Button
var new_height: Button
var canvas_number_pad: CanvasNumberPad
var dimension_target: Button
var new_preset: OptionButton
var new_transparent: CheckBox
var new_preview: Control
var new_swap: Button
var new_dimensions_note: Label
var rebuilding = false
var project_home
var project_loading_overlay: ColorRect
var project_loading_label: Label
const BUSY_FEEDBACK_MS := 120.0
var operation_time_per_unit := {}
var session_active = false
var recovered_revision := -1
var recent_projects: Array = []
var recovered_projects: Array = []

func _ready() -> void:
	name = "HavuStudio"
	get_tree().node_added.connect(watch_workspace_input)
	text_entry = TouchTextEntry.new()
	add_child(text_entry)
	text_entry.watch(self)
	text_entry.accepted.connect(func(field):
		if field == title_edit: rename_document()
		elif field == color_hex: apply_color_hex())
	if OS.has_feature("android"):
		get_window().size_changed.connect(adapt_android_content_scale)
		adapt_android_content_scale()
	settings.load("user://preferences.cfg")
	var saved_scale = settings.get_value("workspace", "ui_scale_percent", 100)
	if Document.numeric(saved_scale):
		ui_scale_percent = clampi(roundi(float(saved_scale) / UIScaleSlider.STEP) * UIScaleSlider.STEP,
			UIScaleSlider.MINIMUM, UIScaleSlider.MAXIMUM)
	get_window().content_scale_factor = ui_scale_percent / 100.0
	recent_colors = read_swatch_history("recent", RECENT_COLOR_LIMIT)
	saved_swatches_hex = read_swatch_history("saved", SAVED_COLOR_LIMIT)
	var stored_presets = settings.get_value("brushes", "presets", [])
	if stored_presets is Array:
		for preset in stored_presets:
			if valid_preset(preset):
				preset.local_id = validated_brush_id(preset.get("local_id", ""))
				presets.append(preset)
	favorite_brushes = read_brush_shelf("favorites", MAX_FAVORITES)
	recent_brushes = read_brush_shelf("recent", RECENT_BRUSH_LIMIT)
	tools_horizontal = bool(settings.get_value("workspace", "horizontal_tools", false))
	for key in WORKSPACE_OPTIONS:
		workspace_options[key] = bool(settings.get_value("workspace", key, true))
	build_theme()
	build_workspace()
	build_input_settings()
	build_workspace_settings()
	build_file_dialogs()
	build_new_dialog()
	build_toast()
	build_developer_panel()
	document.changed.connect(on_document_changed)
	canvas.document = document
	canvas.snap_rotation = settings.get_value("input", "snap_rotation", false) == true
	canvas.snap_to_canvas = settings.get_value("input", "snap_to_canvas", false) == true
	document.blank()
	title_edit.text = document.title
	rebuild_layers()
	resized.connect(layout_workspace)
	layout_workspace()
	restore_layout()
	rebuild_brush_rows()
	autosave_timer = Timer.new()
	autosave_timer.wait_time = 12
	autosave_timer.timeout.connect(autosave)
	add_child(autosave_timer)
	autosave_timer.start()
	get_tree().auto_accept_quit = false
	build_project_home()
	build_project_loading()
	show_project_home()
	if not "--test" in OS.get_cmdline_user_args(): show_splash()
	canvas.fit.call_deferred()

func watch_workspace_input(node: Node) -> void:
	if not is_ancestor_of(node): return
	if node is PopupMenu:
		attach_popup_touch.call_deferred(node)
	elif node is OptionButton:
		node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		PopupTouch.watch_launcher(node)

	# Observe the control that actually received the press, including buttons
	# and sliders that stop GUI input before it reaches the panel frame.
	if node is Control:
		var ancestor: Node = node
		while ancestor is Control and ancestor != self:
			if ancestor is FloatingPanel:
				if not node.gui_input.is_connected(ancestor.raise_on_press):
					node.gui_input.connect(ancestor.raise_on_press)
				break
			ancestor = ancestor.get_parent()

func attach_popup_touch(menu: PopupMenu) -> void:
	if not is_instance_valid(menu) or not menu.is_inside_tree() or menu.has_node("HavuPopupTouch"): return
	var adapter := PopupTouch.new()
	adapter.name = "HavuPopupTouch"
	menu.add_child(adapter)

func style(color: Color, radius = 10, border = Color.TRANSPARENT, padding = 10) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

func build_theme() -> void:
	var t = Theme.new()
	t.default_font = Art.SANS
	t.default_font_size = 16
	t.set_color("font_color", "Label", Color("#edf3ee"))
	t.set_color("font_color", "Button", Color("#dce8df"))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_stylebox("normal", "Button", style(Color("#242424"), 7, Color("#333333"), 9))
	t.set_stylebox("hover", "Button", style(Color("#303030"), 7, Color("#555555"), 9))
	t.set_stylebox("pressed", "Button", style(Color("#303333"), 7, Color("#79d7b4"), 9))
	t.set_stylebox("focus", "Button", style(Color.TRANSPARENT, 7, ACCENT, 9))
	t.set_stylebox("disabled", "Button", style(Color("#191919"), 7, Color("#292929"), 9))
	t.set_type_variation("FooterButton", "Button")
	t.set_font_size("font_size", "FooterButton", 14)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var compact := t.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		compact.content_margin_top = 3
		compact.content_margin_bottom = 3
		t.set_stylebox(state, "FooterButton", compact)
	t.set_stylebox("panel", "PanelContainer", style(Color("#1b1b1b"), 12, Color("#343434"), 0))
	for type_name in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", type_name, style(Color("#111111"), 6, Color("#343434"), 8))
		t.set_color("font_color", type_name, Color("#e1ece3"))
	t.set_stylebox("background", "TextEdit", style(Color("#111111"), 6, Color("#343434"), 8))
	t.set_color("accent_color", "ColorPicker", ACCENT)
	t.set_stylebox("slider", "HSlider", style(Color("#414141"), 4, Color.TRANSPARENT, 2))
	t.set_stylebox("grabber_area", "HSlider", style(Color("#aab7b0"), 4, Color.TRANSPARENT, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", style(ACCENT, 4, Color.TRANSPARENT, 2))
	t.set_constant("separation", "VBoxContainer", 9)
	t.set_constant("separation", "HBoxContainer", 8)
	theme = t

func label(text: String, font_size_value = 14, color_value = Color("#e8efe9")) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size_value)
	node.add_theme_color_override("font_color", color_value)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func button(text: String, callback: Callable, tooltip = "") -> Button:
	var node = Button.new()
	node.text = text
	node.custom_minimum_size.y = 42
	node.tooltip_text = tooltip
	node.pressed.connect(callback)
	return node

func shortcut_hint(hint: String, keys: String) -> String:
	return "%s · %s" % [hint, keys] if show_shortcut_hints and not keys.is_empty() else hint

func primary(node: Button) -> void:
	node.add_theme_stylebox_override("normal", style(ACCENT, 8, Color.TRANSPARENT, 11))
	node.add_theme_color_override("font_color", Color("#12291c"))

func margin(parent: Node, amount = 14) -> VBoxContainer:
	var wrapper = MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: wrapper.add_theme_constant_override("margin_" + side, amount)
	parent.add_child(wrapper)
	var box = VBoxContainer.new()
	wrapper.add_child(box)
	return box

func build_workspace() -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color("#111111")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	canvas = Canvas.new()
	canvas.name = "IllustrationCanvas"
	var stroke_spread = settings.get_value("workspace", "stroke_node_spread", Canvas.DEFAULT_STROKE_NODE_SPREAD)
	var path_spread = settings.get_value("workspace", "path_node_spread", 0.0)
	if Document.numeric(stroke_spread): canvas.stroke_node_spread = clampf(stroke_spread, 0.0, 1.0)
	if Document.numeric(path_spread): canvas.path_node_spread = clampf(path_spread, 0.0, 1.0)
	add_child(canvas)
	canvas.set_ui_scale(ui_scale_percent / 100.0)
	canvas.status.connect(notify)
	canvas.fill_requested.connect(apply_canvas_fill)
	canvas.selected.connect(on_selected)
	canvas.color_used.connect(remember_color)
	canvas.view_changed.connect(update_zoom_readout)
	build_header()
	var tools = make_panel("Tools", Vector2(16, 103), 68)
	var tool_center = CenterContainer.new()
	tool_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools.add_child(tool_center)
	var grid = GridContainer.new()
	tool_grid = grid
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 3)
	tool_center.add_child(grid)
	var paths = {
		"select": "M5 3L20 14L12 15L9 22Z", "nodes": "M4 18Q12 1 21 6M3 16h4v4H3zM19 4h4v4h-4zM12 7v4M10 9h4",
		"brush": "M7 16L17 4Q20 1 22 4L12 16M7 16Q2 16 3 22Q10 23 12 16Z", "erase": "M4 15L14 3L22 10L11 22H7ZM9 9L17 16M12 22H23",
		"fill": "M4 12L13 3L22 12L13 21ZM6 12H20M5 2L13 10M22 17Q18 22 22 23Q26 22 22 17", "picker": "M6 16L17 5L21 9L10 20L4 22ZM15 3L23 11",
		"shapes": "M3 4H16V9M3 4V17H9M23 16A7 7 0 1 1 9 16A7 7 0 1 1 23 16", "text": "M4 6V3H22V6M13 3V23M8 23H18", "hand": "M7 13V7Q7 4 10 7V13V4Q10 1 13 4V12V5Q13 2 16 5V13V8Q16 5 19 8V18Q19 24 12 24Q9 24 6 20L2 15Q1 11 4 12Z"}
	for spec in [["select", "Object and area selection", "V"], ["nodes", "Nodes", "A"], ["brush", "Brush", "B"],
		["erase", "Eraser", "E"], ["fill", "Fill", "G"], ["picker", "Picker", "I"],
		["shapes", "Shapes and paths", ""], ["text", "Text", "T"], ["hand", "Hand", "H"]]:
		var key = spec[0]
		var b = button("", press_tool.bind(key), shortcut_hint(spec[1], spec[2]))
		b.icon = make_icon(paths[key])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.expand_icon = false
		b.custom_minimum_size = Vector2(44, 44)
		b.add_theme_font_size_override("font_size", 10)
		b.toggle_mode = true
		b.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 6, Color.TRANSPARENT, 7))
		tool_buttons[key] = b
		grid.add_child(b)
	grid.columns = grid.get_child_count() if tools_horizontal else 1
	build_shape_menu()
	build_selection_menu()
	build_brush_panel()
	build_color_panel()
	build_layer_panel()
	build_type_panel()
	connect_panel_grouping()
	var bottom = PanelContainer.new()
	bottom.name = "BottomBar"
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -FOOTER_HEIGHT
	var footer_style := style(Color("#161616"), 0, Color("#303030"), 9)
	footer_style.content_margin_top = FOOTER_PADDING
	footer_style.content_margin_bottom = FOOTER_PADDING
	bottom.add_theme_stylebox_override("panel", footer_style)
	add_child(bottom)
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bottom.add_child(bar)
	undo_button = UndoButton.new()
	undo_button.text = "↶"
	undo_button.tooltip_text = shortcut_hint("Undo · Hold to repeat", "Ctrl+Z")
	undo_button.pressed.connect(apply_history_step.bind(false))
	redo_button = button("↷", apply_history_step.bind(true), shortcut_hint("Redo", "Ctrl+Shift+Z"))
	bar.add_child(undo_button)
	bar.add_child(redo_button)
	bar.add_child(VSeparator.new())
	bar.add_child(button("−", func(): canvas.zoom_at(1 / 1.25, canvas.size * 0.5), "Zoom out"))
	bar.add_child(button("Fit", func(): canvas.fit(), shortcut_hint("Fit page", "Ctrl+0")))
	bar.add_child(button("+", func(): canvas.zoom_at(1.25, canvas.size * 0.5), "Zoom in"))
	build_zoom_menu(bar)
	footer_metrics = HBoxContainer.new()
	footer_metrics.name = "CanvasMetrics"
	footer_metrics.add_theme_constant_override("separation", 5)
	footer_metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(footer_metrics)
	footer_metrics.add_child(VSeparator.new())
	pointer_x = footer_readout(footer_metrics, "X —", 53, "Horizontal position from the page’s left edge")
	pointer_y = footer_readout(footer_metrics, "Y —", 53, "Vertical position from the page’s top edge")
	pointer_pressure = footer_readout(footer_metrics, "Pressure —", 93, "Raw pressure reported during a stroke")
	footer_metrics.add_child(VSeparator.new())
	page_dimensions = footer_readout(footer_metrics, "— × —", 95, "Canvas size in document units")
	footer_metrics.visible = workspace_options.footer_metrics
	status_label = label("A little room to create.", 14, MUTED)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(status_label)
	bar.add_child(button("⠿", reset_layout, "Reset panel layout"))
	bar.add_child(button("?", show_help, "Tools and keyboard shortcuts" if show_shortcut_hints else "Tools and gestures"))
	for control in bar.get_children():
		if control is Button:
			control.theme_type_variation = &"FooterButton"
			control.custom_minimum_size = Vector2(maxf(36.0, control.custom_minimum_size.x), FOOTER_HEIGHT - 2.0 * FOOTER_PADDING)
	build_selection_tray()
	build_panel_close_target()
	panel_reveal_tabs = PanelRevealTabs.new()
	panel_reveal_tabs.name = "PanelRevealTabs"
	add_child(panel_reveal_tabs)
	var grip_icon := make_icon("M10 7h.1M16 7h.1M10 13h.1M16 13h.1M10 19h.1M16 19h.1")
	panel_reveal_tabs.configure(panels, group_grips, grip_icon, style(Color("#1b1b1b"), 7, Color("#527769"), 0))
	update_panel_reveal_visibility()
	panels.Tools.item_rect_changed.connect(position_selection_tray)
	tool_buttons.select.item_rect_changed.connect(position_selection_tray)
	tool_buttons.shapes.item_rect_changed.connect(position_selection_tray)
	tool_buttons.nodes.item_rect_changed.connect(position_selection_tray)
	set_tool("brush")

func build_zoom_menu(bar: HBoxContainer) -> void:
	var menu := PopupMenu.new()
	menu.name = "ZoomPresets"
	menu.add_item("Fit page", 0)
	menu.add_separator()
	for percent in ZOOM_PRESETS:
		menu.add_item("%d%%" % percent, percent)
	menu.id_pressed.connect(func(id):
		if id == 0:
			canvas.fit()
		else:
			canvas.zoom_at((float(id) / 100.0) / canvas.visible_zoom(), canvas.size * 0.5))
	add_child(menu)
	zoom_button = Button.new()
	zoom_button.name = "ZoomPercent"
	zoom_button.text = "100% ▾"
	zoom_button.tooltip_text = "Choose a zoom level"
	zoom_button.custom_minimum_size.x = 76
	PopupTouch.watch_launcher(zoom_button)
	zoom_button.pressed.connect(func():
		menu.reset_size()
		var top_left := zoom_button.get_screen_position()
		menu.position = Vector2i(top_left - Vector2(0, menu.size.y + 6))
		menu.popup())
	bar.add_child(zoom_button)
	update_zoom_readout()

func update_zoom_readout() -> void:
	if zoom_button: zoom_button.text = "%d%% ▾" % roundi(canvas.visible_zoom() * 100)

func footer_readout(bar: HBoxContainer, initial: String, width: float, hint: String) -> Label:
	var readout = label(initial, 13, MUTED)
	readout.custom_minimum_size.x = width
	readout.mouse_filter = Control.MOUSE_FILTER_PASS
	readout.tooltip_text = hint
	bar.add_child(readout)
	return readout

func update_pointer_readouts() -> void:
	if not pointer_x: return
	var point := Vector2.INF
	if canvas.metrics_pointer.is_finite():
		point = canvas.to_document(canvas.metrics_pointer)
	var on_page := Rect2(0, 0, document.width, document.height).has_point(point)
	var x_text := "X %d" % roundi(point.x) if on_page else "X —"
	var y_text := "Y %d" % roundi(point.y) if on_page else "Y —"
	var pressure_text := "Pressure %d%%" % roundi(canvas.metrics_pressure * 100) if on_page and canvas.metrics_pressure >= 0 else "Pressure —"
	if pointer_x.text != x_text: pointer_x.text = x_text
	if pointer_y.text != y_text: pointer_y.text = y_text
	if pointer_pressure.text != pressure_text: pointer_pressure.text = pressure_text

func make_icon(path: String, color := "#c7ddce", edge := 26) -> ImageTexture:
	var image = Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 26 26"><path d="%s" stroke="%s" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" fill="none"/></svg>' % [edge, edge, path, color])
	return ImageTexture.create_from_image(image)

func make_panel(title: String, at: Vector2, panel_width: float) -> VBoxContainer:
	var panel = FloatingPanel.new()
	panel.name = title.replace(" ", "") + "Panel"
	panel.position = at
	panel.base_width = panel_width
	panel.minimum_panel_width = 64.0 if title == "Tools" else 144.0
	panel.edge_docking_enabled = workspace_options.edge_docking
	panel.drag_to_hide_enabled = workspace_options.drag_to_hide
	panel.custom_minimum_size.x = panel_width
	panel.size.x = panel_width
	panel.raise_requested.connect(raise_panel.bind(title))
	panel.layout_changed.connect(func():
		queue_dock_reflow(panel)
		save_layout())
	panel.move_committed.connect(func(): detach_group_member(title))
	panel.resize_started.connect(func(): begin_group_resize(title))
	panel.group_resize_dragged.connect(func(delta): preview_group_resize(title, delta))
	panel.resize_finished.connect(func(committed): finish_group_resize(title, committed))
	panel.close_requested.connect(panel.hide)
	if title == "Tools":
		panel.dock_changed.connect(func(edge, align_orientation):
			if edge.is_empty() or not workspace_options.auto_orientation or not align_orientation: return
			set_tool_orientation(edge in ["top", "bottom"]))
	add_child(panel)
	panels[title] = panel
	var all = VBoxContainer.new()
	all.add_theme_constant_override("separation", 0)
	all.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(all)
	var header = HBoxContainer.new()
	header.custom_minimum_size.y = 44
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	all.add_child(header)
	if title == "Tools":
		var grip = TextureRect.new()
		grip.texture = make_icon("M10 8h.1M16 8h.1M10 13h.1M16 13h.1M10 18h.1M16 18h.1")
		grip.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		grip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grip.modulate.a = 0.7
		grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(grip)
	else:
		var heading = label("   " + title, 14)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(heading)
		header.add_child(label("⠿  ", 20, MUTED))
	var line = HSeparator.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	all.add_child(line)
	var scroll = SwipeScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	all.add_child(scroll)
	var body_wrapper = VBoxContainer.new()
	body_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(body_wrapper)
	var content = margin(body_wrapper, 6)
	content.add_theme_constant_override("separation", 7)
	content.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var footer = HBoxContainer.new()
	all.add_child(footer)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var resize_handle = label("◢", 13, MUTED)
	resize_handle.custom_minimum_size = Vector2(30, 24)
	resize_handle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resize_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	resize_handle.tooltip_text = "Drag to resize panel"
	footer.add_child(resize_handle)
	panel.configure_content(scroll, body_wrapper, resize_handle)
	panel.visibility_changed.connect(func():
		cancel_group_resize(find_panel_group(title))
		if selection_tray: update_selection_actions()
		if is_node_ready() and not restoring_workspace:
			if panel.visible: place_opened_panel(title)
			if not panel.dock.is_empty() or not find_panel_group(title).is_empty(): queue_dock_reflow(panel)
			save_layout())
	panel.resized.connect(func():
		if panel.visible and not panel.dock.is_empty() and panel.gesture.is_empty():
			queue_dock_reflow(panel))
	return content

func raise_panel(key: String) -> void:
	var group := find_panel_group(key)
	if group.is_empty():
		raise_panel_stack([key])
	else:
		raise_panel_stack(GroupLayout.leaves(group.tree), group_grips.get(group.id))

func raise_panel_stack(keys: Array, grip: Control = null) -> void:
	var stack: Array[Control] = []
	for key in keys:
		if panels[key].is_visible_in_tree(): stack.append(panels[key])
	if is_instance_valid(grip) and grip.is_visible_in_tree(): stack.append(grip)

	var last_other := -1
	for control: Control in panels.values() + group_grips.values():
		if control.is_visible_in_tree() and control not in stack:
			last_other = maxi(last_other, control.get_index())
	if stack.any(func(control): return control.get_index() < last_other):
		for control in stack: control.move_to_front()

func place_opened_panel(key: String) -> void:
	if not workspace_options.avoid_panel_overlap or (is_instance_valid(project_home) and project_home.visible): return
	var panel: FloatingPanel = panels[key]
	var group := find_panel_group(key)
	var members := [key] if group.is_empty() else GroupLayout.leaves(group.tree)
	var occupied: Array[Rect2] = []
	var headers: Array[Rect2] = []
	for other in panels:
		if other in members or not panels[other].visible: continue
		var box: Rect2 = panels[other].get_rect()
		occupied.append(box)
		headers.append(Rect2(box.position, Vector2(box.size.x, minf(44.0, box.size.y))))
	for id in group_grips:
		if not group.is_empty() and id == group.id: continue
		var grip: Control = group_grips[id]
		if grip.visible:
			occupied.append(grip.get_rect())
			headers.append(grip.get_rect())

	var placement := {} if group.is_empty() else group_placement(group)
	var edge: String = panel.dock if group.is_empty() else group.dock
	var desired: Rect2 = placement.get("bounds", panel.get_rect())
	var slot := Rect2()
	if not edge.is_empty():
		slot = find_dock_slot(edge, FloatingPanel.dock_rect(FloatingPanel.work_area(self, true),
			desired.position, desired.size, edge), occupied)
	else:
		var work := FloatingPanel.work_area(self, false)
		slot = PanelRevealTabs.find_slot(work, desired, occupied, DOCK_GAP)
		if not slot.has_area(): slot = PanelRevealTabs.find_slot(work, desired, occupied, 0.0)
		if not slot.has_area(): slot = PanelRevealTabs.find_slot(work, desired, occupied, 0.0, headers, true)

	for member in members:
		if panels[member].visible: panels[member].move_to_front()
	if placement.is_empty():
		if slot.has_area() and group.is_empty():
			panel.position = slot.position
	else:
		if slot.has_area():
			var delta: Vector2 = slot.position - placement.bounds.position
			placement.bounds = slot
			for member in placement.cells: placement.cells[member].position += delta
		apply_group_placement(group, placement)


func add_slider(parent: VBoxContainer, text: String, minimum: float, maximum: float, value: float, suffix: String,
		callback: Callable, editable_value := false) -> HSlider:
	var row = HBoxContainer.new()
	var name_label = label(text, 12, Color("#d0d0d0"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	parent.add_child(row)
	var slider := TouchSlider.new()
	slider.custom_minimum_size.y = 26
	slider.step = 1
	slider.min_value = minimum
	slider.max_value = maximum
	slider.value = value
	if editable_value:
		var number := SpinBox.new()
		number.min_value = minimum
		number.max_value = maximum
		number.value = value
		number.suffix = suffix.strip_edges()
		number.custom_minimum_size.x = 76
		number.get_line_edit().accessibility_name = text
		number.get_line_edit().add_theme_font_size_override("font_size", 12)
		row.add_child(number)
		number.value_changed.connect(func(next): slider.value = next)
		slider.value_changed.connect(func(next): number.set_value_no_signal(next))
	else:
		var output := label("%d%s" % [value, suffix], 12, MUTED)
		row.add_child(output)
		slider.value_changed.connect(func(next): output.text = "%d%s" % [next, suffix])
	slider.value_changed.connect(callback)
	parent.add_child(slider)
	return slider

func build_brush_panel() -> void:
	var box := make_panel(BRUSH_LIBRARY_PANEL, Vector2(98, 103), 250)
	box.add_theme_constant_override("separation", 6)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	box.add_child(tabs)
	var tab_group := ButtonGroup.new()
	for index in BRUSH_TAB_KEYS.size():
		var tab := button("Library" if index == 0 else "Settings", func(): select_brush_tab(BRUSH_TAB_KEYS[index]))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.add_theme_font_size_override("font_size", 13)
		tab.add_theme_stylebox_override("pressed", style(Color("#2c3531"), 6, Color("#53796a"), 5))
		tabs.add_child(tab)
		brush_tab_buttons.append(tab)
	brush_pages = TabContainer.new()
	brush_pages.name = "BrushPages"
	brush_pages.tabs_visible = false
	brush_pages.use_hidden_tabs_for_min_size = true
	brush_pages.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	box.add_child(brush_pages)
	for title in ["Library", "Settings"]:
		var page := VBoxContainer.new()
		page.name = title
		page.add_theme_constant_override("separation", 6)
		brush_pages.add_child(page)
	build_brush_library(brush_pages.get_tab_control(0))
	build_brush_settings_panel(brush_pages.get_tab_control(1))
	panels.Brushes.expand_content(brush_pages, 355)
	select_brush_tab(BRUSH_LIBRARY_PANEL)
	panels.Brushes.hide()

func build_brush_library(box: VBoxContainer) -> void:
	brush_category = OptionButton.new()
	brush_category.custom_minimum_size.y = 44
	brush_category.add_item("All brushes")
	for category in BrushLibrary.CATEGORIES: brush_category.add_item(category)
	brush_category.add_item("Favorites")
	brush_category.add_item("Recent")
	brush_category.add_item("My brushes")
	brush_category.select(1)
	brush_category.item_selected.connect(func(_index): rebuild_brush_rows(true))
	var shelf_bar := HBoxContainer.new()
	shelf_bar.add_theme_constant_override("separation", 4)
	box.add_child(shelf_bar)
	brush_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf_bar.add_child(brush_category)
	brush_favorite_button = icon_button("M13 3L16 10L24 11L18 16L20 24L13 20L6 24L8 16L2 11L10 10Z", toggle_favorite_brush, "Favorite the active brush")
	brush_favorite_button.name = "FavoriteBrush"
	brush_favorite_button.toggle_mode = true
	shelf_bar.add_child(brush_favorite_button)
	brush_search = LineEdit.new()
	brush_search.placeholder_text = "Search this category"
	brush_search.accessibility_name = "Search brushes"
	brush_search.clear_button_enabled = true
	brush_search.max_length = 120
	brush_search.custom_minimum_size.y = 42
	brush_search.text_changed.connect(func(_query): rebuild_brush_rows(true))
	brush_search.text_submitted.connect(func(_query): brush_search.release_focus())
	box.add_child(brush_search)

	brush_scroll = SwipeScroll.new()
	brush_scroll.custom_minimum_size = Vector2(198, 94)
	brush_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(brush_scroll)
	brush_scroll.get_v_scroll_bar().value_changed.connect(func(_value): queue_brush_preview_refresh())
	brush_scroll.item_rect_changed.connect(queue_brush_preview_refresh)
	brush_scroll.visibility_changed.connect(queue_brush_preview_refresh)
	brush_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brush_rows = VBoxContainer.new()
	brush_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brush_rows.add_theme_constant_override("separation", 2)
	brush_scroll.add_child(brush_rows)
	brush_rows.sort_children.connect(queue_brush_preview_refresh)
	var files = HBoxContainer.new()
	files.add_child(button("+", import_brush, "Import brushes"))
	files.add_child(button("↗", export_brush, "Share selected custom brush"))
	files.add_child(button("↓", show_brush_resources, "Free brush resources and compatibility"))
	box.add_child(files)
func open_brush_editor() -> void:
	show_brush_tab(BRUSH_SETTINGS_PANEL)

func build_brush_settings_panel(box: VBoxContainer) -> void:

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 5)
	box.add_child(heading)
	brush_editor_name = label(active_brush.name, 14)
	brush_editor_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	brush_editor_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(brush_editor_name)
	brush_revert = button("Reset", func(): apply_brush(active_brush, false), "Discard the current edits and reload the saved preset")
	brush_revert.add_theme_font_size_override("font_size", 12)
	heading.add_child(brush_revert)
	brush_editor_preview = BrushPreview.new()
	brush_editor_preview.detailed = true
	brush_editor_preview.ink = canvas.color
	brush_editor_preview.clip_contents = true
	brush_editor_preview.custom_minimum_size.y = 72
	box.add_child(brush_editor_preview)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	box.add_child(actions)
	var save_copy := button("Save as", save_brush_preset, "Save this brush as a new preset in My brushes")
	save_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_copy.add_theme_font_size_override("font_size", 13)
	actions.add_child(save_copy)
	brush_update = button("Update", update_saved_brush, "Save changes to this brush in My brushes")
	brush_update.add_theme_font_size_override("font_size", 13)
	actions.add_child(brush_update)
	brush_manage = icon_button("M5 13h1M12 13h1M19 13h1", open_brush_menu, "Rename, share, or delete this saved brush")
	PopupTouch.watch_launcher(brush_manage)
	actions.add_child(brush_manage)
	brush_menu = PopupMenu.new()
	brush_menu.add_item("Rename…", 0)
	brush_menu.add_item("Share…", 1)
	brush_menu.add_separator()
	brush_menu.add_item("Delete brush…", 2)
	brush_menu.id_pressed.connect(func(id):
		match id:
			0: rename_saved_brush()
			1: export_brush()
			2: delete_saved_brush()
	)
	add_child(brush_menu)

	brush_tuning_scroll = SwipeScroll.new()
	brush_tuning_scroll.custom_minimum_size.y = 90
	brush_tuning_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(brush_tuning_scroll)
	var tuning := VBoxContainer.new()
	tuning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tuning.add_theme_constant_override("separation", 5)
	brush_tuning_scroll.add_child(tuning)
	brush_tuning_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	brush_choice = OptionButton.new()
	brush_choice.tooltip_text = "Brush engine"
	for engine_name in ["Ink", "Paint", "Mixer", "Soft", "Pencil", "Chalk", "Marker"]:
		brush_choice.add_item(engine_name)
	brush_choice.custom_minimum_size.y = 40
	brush_choice.item_selected.connect(func(index):
		canvas.finish()
		canvas.brush = BrushLibrary.ENGINES[index]
		canvas.brush_profile = {}
		load_brush_profile_controls()
		refresh_brush_editor()
		set_tool("brush"))
	tuning.add_child(brush_choice)
	size_slider = add_slider(tuning, "Size", 1, 150, 18, " px", func(value): change_brush_value("brush_size", value), true)
	opacity_slider = add_slider(tuning, "Opacity", 1, 100, 100, "%", func(value): change_brush_value("opacity", value / 100.0), true)
	smooth_slider = add_slider(tuning, "Stabilization", 0, 90, 35, "%", func(value): change_brush_value("smoothing", value / 100.0), true)
	add_brush_tuning(tuning, "Spacing", "spacing", 100, "%", [], "Distance between brush samples as a percentage of brush size")

	var pressure := add_brush_editor_section(tuning, "Pressure")
	add_brush_tuning(pressure, "Light threshold", "pressure_floor", 100, "%", [], "Pen pressure below this level uses the brush’s minimum response")
	add_brush_tuning(pressure, "Full response at", "pressure_ceiling", 100, "%", [], "Reach full response sooner without pressing as hard")
	add_brush_tuning(pressure, "Width curve", "pressure_curve", 100, "%", [], "Below 100% widens under light pressure. Above 100% needs firmer pressure.")
	add_brush_tuning(pressure, "Minimum width", "minimum_width", 100, "%", [], "Sets the starting width at very light pressure")
	add_brush_tuning(pressure, "Opacity response", "opacity_pressure", 100, "%", [], "Controls how much pen pressure changes opacity")
	add_brush_tuning(pressure, "Opacity curve", "opacity_curve", 100, "%", [], "With opacity response enabled, lower values make a light touch more opaque")
	brush_pressure_graph = Control.new()
	brush_pressure_graph.custom_minimum_size.y = 58
	brush_pressure_graph.tooltip_text = "Green shows stroke width and gray shows opacity as pen pressure increases"
	brush_pressure_graph.draw.connect(draw_brush_pressure)
	brush_pressure_graph.resized.connect(brush_pressure_graph.queue_redraw)
	pressure.add_child(brush_pressure_graph)

	var taper := add_brush_editor_section(tuning, "Taper")
	add_brush_tuning(taper, "Start length", "taper_start", 100, "%", [], "Length of the start taper as a percentage of brush size")
	add_brush_tuning(taper, "End length", "taper_end", 100, "%", [], "Length of the taper applied when you lift the pen, as a percentage of brush size")
	add_brush_tuning(taper, "Tip width", "taper_tip", 100, "%", [], "Width at tapered ends as a percentage of the untapered stroke")

	var tip := add_brush_editor_section(tuning, "Tip & texture")
	var angled_engines := ["marker", "paint", "mix", "soft"]
	add_brush_tuning(tip, "Tip roundness", "tip_ratio", 100, "%", angled_engines, "Lower values make a flatter tip")
	add_brush_tuning(tip, "Tip angle", "tip_angle", 1, "°", angled_engines, "Rotates the brush tip")
	add_brush_tuning(tip, "Edge feather", "feather", 100, "%", ["soft"], "Softens the outer edge")
	add_brush_tuning(tip, "Grain density", "grain", 100, "%", BrushLibrary.DRY_ENGINES, "Controls the number of texture marks")
	add_brush_tuning(tip, "Grain size", "grain_size", 100, "%", BrushLibrary.DRY_ENGINES, "Scales the texture marks")
	add_brush_tuning(tip, "Grain spread", "grain_spread", 100, "%", BrushLibrary.DRY_ENGINES, "Scatters texture marks around the stroke")

	var mixing := add_brush_editor_section(tuning, "Mixing")
	blending_slider = add_slider(mixing, "Color pickup", 0, 100, 0, "%", func(value): change_brush_value("blending", value / 100.0), true)
	add_brush_tuning(mixing, "Pigment load", "pigment_load", 100, "%", BrushLibrary.WET_ENGINES, "Set to 0% to mix colors already on the canvas without adding the selected color")
	add_brush_tuning(mixing, "Pickup curve", "pickup_curve", 100, "%", BrushLibrary.WET_ENGINES, "Lower values mix in more canvas color at medium pressure")
	add_brush_tuning(mixing, "Color carry", "pigment_carry", 100, "%", BrushLibrary.WET_ENGINES, "Carries mixed color farther along the stroke")
	add_brush_tuning(mixing, "Deposit curve", "deposit_curve", 100, "%", BrushLibrary.WET_ENGINES, "Lower values deposit more selected color with a light touch")

	var test_pad := add_brush_editor_section(tuning, "Test pad")
	brush_test_canvas = Canvas.new()
	brush_test_canvas.name = "BrushTestCanvas"
	brush_test_canvas.custom_minimum_size = Vector2(148, 112)
	brush_test_canvas.fit_padding = Vector2(6, 6)
	brush_test_canvas.clip_contents = true
	brush_test_canvas.touch_paints = true
	brush_test_canvas.manage_input_accumulation = false
	test_pad.add_child(brush_test_canvas)
	clear_brush_test_pad()
	brush_test_canvas.visibility_changed.connect(func():
		if not brush_test_canvas.is_visible_in_tree():
			brush_test_canvas.cancel()
			brush_test_canvas.reset_touch())
	test_pad.add_child(button("Clear test strokes", clear_brush_test_pad))

	load_brush_editor(active_brush)

func add_brush_editor_section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var toggle := button("▸  " + title, func():
		brush_editor_section = "" if brush_editor_section == title else title
		refresh_brush_editor_sections())
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", 13)
	parent.add_child(toggle)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	parent.add_child(content)
	content.hide()
	brush_editor_sections[title] = {"button": toggle, "content": content}
	return content

func add_brush_tuning(parent: VBoxContainer, title: String, key: String, units: float, suffix: String, engines: Array, hint: String) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	parent.add_child(block)
	var bounds: Array = BrushLibrary.PROFILE_LIMITS[key]
	var slider := add_slider(block, title, bounds[0] * units, bounds[1] * units,
		BrushLibrary.profile_default(key, canvas.brush) * units, suffix,
		func(value): change_brush_profile(key, value / units), true)
	slider.tooltip_text = hint
	brush_profile_controls[key] = {"slider": slider, "block": block, "units": units, "engines": engines}

func load_brush_profile_controls() -> void:
	var loading := brush_editor_loading
	brush_editor_loading = true
	for key in brush_profile_controls:
		var control: Dictionary = brush_profile_controls[key]
		control.slider.value = canvas.brush_profile.get(key, BrushLibrary.profile_default(key, canvas.brush)) * control.units
	brush_editor_loading = loading

func change_brush_value(property: String, value: float) -> void:
	if brush_editor_loading: return
	canvas.set(property, value)
	refresh_brush_editor()

func change_brush_profile(key: String, value: float) -> void:
	if brush_editor_loading: return
	if not active_brush.has(key) and is_equal_approx(value, BrushLibrary.profile_default(key, canvas.brush)):
		canvas.brush_profile.erase(key)
	else:
		canvas.brush_profile[key] = value
	refresh_brush_editor()

func refresh_brush_editor_sections() -> void:
	for title in brush_editor_sections:
		var available: bool = (title != "Tip & texture" or canvas.brush != "ink") and (
			title != "Mixing" or canvas.brush in BrushLibrary.WET_ENGINES)
		var section: Dictionary = brush_editor_sections[title]
		var expanded: bool = available and brush_editor_section == title
		section.button.visible = available
		section.content.visible = expanded
		section.button.text = ("▾  " if expanded else "▸  ") + title
	for control in brush_profile_controls.values():
		control.block.visible = control.engines.is_empty() or canvas.brush in control.engines

func draw_brush_pressure() -> void:
	var graph := brush_pressure_graph
	var area := Rect2(Vector2(1, 1), graph.size - Vector2(2, 2))
	graph.draw_rect(area, Color("#171717"))
	graph.draw_rect(area, Color("#393939"), false, 1)
	var curve: float = canvas.brush_profile.get("pressure_curve", 1.0)
	var minimum: float = canvas.brush_profile.get("minimum_width", 0.12)
	var opacity_response: float = canvas.brush_profile.get("opacity_pressure", 0.0)
	var opacity_curve: float = canvas.brush_profile.get("opacity_curve", 1.0)
	var width_points := PackedVector2Array()
	var opacity_points := PackedVector2Array()
	for index in 33:
		var raw := index / 32.0
		var pressure := BrushLibrary.map_pressure(raw, canvas.brush_profile)
		var x := raw * area.size.x
		var width := Art.stroke_radius(1, pressure, curve, minimum)
		var alpha := Art.stroke_alpha(pressure, opacity_response, opacity_curve)
		width_points.append(area.position + Vector2(x, (1.0 - width) * area.size.y))
		opacity_points.append(area.position + Vector2(x, (1.0 - alpha) * area.size.y))
	graph.draw_polyline(opacity_points, Color("#aaaaaa"), 1.6, true)
	graph.draw_polyline(width_points, ACCENT, 1.6, true)

func clear_brush_test_pad() -> void:
	if not brush_test_canvas: return
	brush_test_canvas.cancel()
	var sample := Document.new()
	sample.blank(268, 132)
	sample.paper = "#f0ece2"
	sample.add({"kind": "rect", "pos": [134, 0], "extent": [134, 132], "color": "#8ecac1", "opacity": 1.0})
	sample.layers[0].name = "Mixing surface"
	sample.layers[0].locked = true
	sample.layers[0].visible = canvas.brush in BrushLibrary.WET_ENGINES
	sample.layers.append(sample.new_layer("Test strokes"))
	sample.active = 1
	sample.selection = ""
	brush_test_canvas.document = sample
	brush_test_canvas.fit()

func load_brush_editor(preset: Dictionary) -> void:
	brush_editor_loading = true
	canvas.brush = preset.brush
	canvas.brush_profile = BrushLibrary.profile_from(preset)
	canvas.brush_size = preset.size
	canvas.opacity = preset.opacity
	canvas.blending = preset.blend
	canvas.smoothing = preset.smoothing
	brush_choice.select(BrushLibrary.ENGINES.find(preset.brush))
	size_slider.value = preset.size
	opacity_slider.value = preset.opacity * 100
	blending_slider.value = preset.blend * 100
	smooth_slider.value = preset.smoothing * 100
	load_brush_profile_controls()
	brush_editor_loading = false
	refresh_brush_editor()

func draft_brush(name_text: String) -> Dictionary:
	var preset := BrushLibrary.preset(name_text, canvas.brush, canvas.brush_size,
		canvas.opacity, canvas.blending, canvas.smoothing)
	preset.merge(canvas.brush_profile)
	if active_brush.has("import_source"):
		preset.import_source = active_brush.import_source.duplicate(true)
	return preset

func brush_draft_changed(draft: Dictionary) -> bool:
	if draft.brush != active_brush.brush or BrushLibrary.profile_from(draft) != BrushLibrary.profile_from(active_brush): return true
	for key in ["size", "opacity", "smoothing", "blend"]:
		if not is_equal_approx(draft[key], active_brush[key]): return true
	return false

func refresh_brush_editor() -> void:
	var draft := draft_brush(active_brush.name)
	var edited := brush_draft_changed(draft)
	var custom := saved_brush_index(active_brush) >= 0
	brush_editor_name.text = draft.name + (" · Edited" if edited else "")
	brush_editor_name.tooltip_text = brush_editor_name.text
	brush_revert.disabled = not edited
	brush_update.visible = custom
	brush_update.disabled = not edited
	brush_manage.visible = custom
	current_brush_preview.preset = draft
	current_brush_preview.rebuild()
	brush_editor_preview.preset = draft
	brush_editor_preview.rebuild()
	brush_pressure_graph.queue_redraw()
	brush_test_canvas.brush = draft.brush
	brush_test_canvas.brush_profile = BrushLibrary.profile_from(draft)
	brush_test_canvas.brush_size = draft.size
	brush_test_canvas.opacity = draft.opacity
	brush_test_canvas.blending = draft.blend
	brush_test_canvas.smoothing = draft.smoothing
	brush_test_canvas.color = canvas.color
	brush_test_canvas.pressure_enabled = canvas.pressure_enabled
	var show_mixing: bool = draft.brush in BrushLibrary.WET_ENGINES
	if brush_test_canvas.document.layers[0].visible != show_mixing:
		brush_test_canvas.document.layers[0].visible = show_mixing
		brush_test_canvas.sync_artwork()
	refresh_brush_editor_sections()

func connect_panel_grouping() -> void:
	group_preview_outlines = Node2D.new()
	group_preview_outlines.draw.connect(func():
		for bounds in group_preview_cells.values():
			group_preview_outlines.draw_rect(bounds, Color(0.48, 0.84, 0.72, 0.72), false, 2, true))
	add_child(group_preview_outlines)
	group_preview_outlines.hide()
	group_preview = PanelContainer.new()
	group_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := style(Color(0.15, 0.35, 0.29, 0.45), 8, ACCENT, 8)
	outline.set_border_width_all(2)
	group_preview.add_theme_stylebox_override("panel", outline)
	group_preview_text = label("", 14, Color("#e4f5ef"))
	group_preview_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	group_preview.add_child(group_preview_text)
	add_child(group_preview)
	group_preview.hide()
	for key in panels:
		var panel = panels[key]
		panel.find_merge_target = func(pointer: Vector2) -> Control: return preview_panel_drop(key, pointer)
		panel.merge_preview_changed.connect(func(target):
			if not target:
				group_preview.hide()
				group_preview_outlines.hide())
		panel.merge_requested.connect(func(_target):
			if not pending_group_drop.is_empty(): commit_group_drop())

func preview_panel_drop(source: String, pointer: Vector2) -> Control:
	pending_group_drop = {}
	group_preview.hide()
	group_preview_outlines.hide()
	if not workspace_options.panel_groups: return null
	# Prefer window docking at the very edge. It still works when an edge has panels.
	if pointer.x < 20 or pointer.x > size.x - 20 or pointer.y < 94 or pointer.y > size.y - 76: return null
	var target_key := ""
	var target_rect := Rect2()
	var topmost := -1
	for key in panels:
		var candidate = panels[key]
		if key == source or not candidate.visible or candidate.get_index() <= topmost: continue
		var bounds: Rect2 = candidate.get_global_rect()
		if not bounds.has_point(pointer): continue
		topmost = candidate.get_index()
		target_key = key
		target_rect = bounds
	if target_key.is_empty(): return null
	var offset := pointer - target_rect.position
	var target_group := find_panel_group(target_key)
	var distances := [offset.x / target_rect.size.x, 1.0 - offset.x / target_rect.size.x,
		offset.y / target_rect.size.y, 1.0 - offset.y / target_rect.size.y]
	var nearest := distances.find(distances.min())
	if distances[nearest] > 0.32: return null
	var side: String = ["left", "right", "top", "bottom"][nearest]
	var target = panels[target_key]
	var tree = target_key if target_group.is_empty() else GroupLayout.without(target_group.tree, source)
	var record := {
		"tree": GroupLayout.insert(tree, target_key, source, side),
		"position": target.position - Vector2(0, GroupLayout.GRIP_HEIGHT) if target_group.is_empty() else target_group.position,
		"dock": target.dock if target_group.is_empty() else target_group.dock,
		"corner": target.dock_corner if target_group.is_empty() else target_group.get("corner", ""),
		"id": target_group.get("id", -1),
		"sizes": target_group.get("sizes", {}).duplicate(),
	}
	var placement := group_placement(record)
	if placement.is_empty() and not record.dock.is_empty():
		record.dock = ""
		record.corner = ""
		placement = group_placement(record)
	if placement.is_empty(): return null
	pending_group_drop = record
	var preview: Rect2 = placement.cells[source]
	group_preview_text.text = ["Join left", "Join right", "Join above", "Join below"][nearest]
	group_preview_cells = placement.cells.duplicate()
	group_preview_cells.erase(source)
	group_preview_outlines.queue_redraw()
	group_preview_outlines.show()
	group_preview_outlines.move_to_front()
	group_preview.position = preview.position
	group_preview.size = preview.size
	group_preview.show()
	group_preview.move_to_front()
	return target

func find_panel_group(key: String) -> Dictionary:
	for group in panel_groups:
		if key in GroupLayout.leaves(group.tree): return group
	return {}

func commit_group_drop() -> void:
	var record := pending_group_drop
	pending_group_drop = {}
	# Both originals may already belong to different groups.
	var members := GroupLayout.leaves(record.tree)
	for key in members: detach_group_member(key)
	group_serial += 1
	record.id = group_serial
	for key in members: panels[key].dock = ""
	panel_groups.append(record)
	reflow_panel_groups()
	queue_dock_reflow()
	save_layout()

func detach_group_member(key: String) -> void:
	var group := find_panel_group(key)
	if group.is_empty(): return
	if is_same(group, group_move.get("group")): group_grips[group.id].end_move(true)
	cancel_group_resize(group)
	var panel = panels[key]
	var detached_position: Vector2 = panel.position
	panel.set_group_cell(Rect2())
	panel.position = detached_position
	group.tree = GroupLayout.without(group.tree, key)
	group.get("sizes", {}).erase(key)
	var remaining := GroupLayout.leaves(group.tree)
	if remaining.size() < 2:
		for survivor in remaining:
			var remaining_panel = panels[survivor]
			remaining_panel.set_group_cell(Rect2())
			remaining_panel.dock = group.dock
			remaining_panel.dock_corner = group.get("corner", "")
			remaining_panel.constrain()
		panel_groups.erase(group)
		var grip: Control = group_grips.get(group.id)
		if grip: grip.queue_free()
		group_grips.erase(group.id)
	queue_dock_reflow()

func restore_panel_groups() -> void:
	if not workspace_options.panel_groups: return
	var saved = settings.get_value("workspace", "panel_group_layouts", [])
	if not saved is Array: return
	var used: Array = []
	for entry in saved:
		if not entry is Dictionary or not entry.get("position") is Vector2 or not entry.position.is_finite(): continue
		var tree = entry.get("tree")
		var old_names: Array = []
		if not GroupLayout.valid_tree(tree, PANEL_NAMES + [BRUSH_SETTINGS_PANEL], old_names): continue
		var brush_size_key := BRUSH_LIBRARY_PANEL
		if BRUSH_SETTINGS_PANEL in old_names:
			if BRUSH_LIBRARY_PANEL in old_names and legacy_brush_layout_key == BRUSH_LIBRARY_PANEL:
				tree = GroupLayout.without(tree, BRUSH_SETTINGS_PANEL)
			else:
				tree = GroupLayout.without(tree, BRUSH_LIBRARY_PANEL)
				tree = GroupLayout.replace(tree, BRUSH_SETTINGS_PANEL, BRUSH_LIBRARY_PANEL)
				brush_size_key = BRUSH_SETTINGS_PANEL
		if BRUSH_LIBRARY_PANEL in used and BRUSH_LIBRARY_PANEL in GroupLayout.leaves(tree):
			tree = GroupLayout.without(tree, BRUSH_LIBRARY_PANEL)
		var names := used.duplicate()
		if not GroupLayout.valid_tree(tree, PANEL_NAMES, names) or names.size() - used.size() < 2: continue
		used = names
		var dock: String = entry.get("dock", "") if entry.get("dock") in ["left", "right", "top", "bottom"] else ""
		group_serial += 1
		var saved_sizes = entry.get("sizes", {})
		var dimensions := {}
		if saved_sizes is Dictionary:
			for key in GroupLayout.leaves(tree):
				var dimensions_for_panel = saved_sizes.get(brush_size_key if key == BRUSH_LIBRARY_PANEL else key)
				if dimensions_for_panel is Vector2 and dimensions_for_panel.is_finite():
					dimensions[key] = dimensions_for_panel.max(Vector2.ZERO)
		panel_groups.append({"id": group_serial, "tree": tree, "position": entry.position, "dock": dock,
			"corner": FloatingPanel.valid_corner(dock, entry.get("corner", "")), "sizes": dimensions})
	for key in used: panels[key].dock = ""

func group_placement(group: Dictionary) -> Dictionary:
	var minimum := {}
	var preferred := {}
	var dimensions_by_panel: Dictionary = group.get("sizes", {})
	for key in GroupLayout.leaves(group.tree):
		var panel = panels[key]
		if panel.visible:
			minimum[key] = panel.group_minimum()
			var desired: Vector2 = dimensions_by_panel.get(key, panel.group_preferred())
			preferred[key] = desired.max(minimum[key])
	if minimum.is_empty(): return {}
	var work := FloatingPanel.work_area(self, not group.dock.is_empty())
	var grip_height := GroupLayout.GRIP_HEIGHT if minimum.size() > 1 else 0.0
	var grip_size := Vector2(0, grip_height)
	var tree = group.tree
	var minimum_size := GroupLayout.measure(tree, minimum) + grip_size
	if minimum_size.x > work.size.x:
		tree = GroupLayout.vertical_stack(GroupLayout.leaves(tree))
		minimum_size = GroupLayout.measure(tree, minimum) + grip_size
	if minimum_size.x > work.size.x or minimum_size.y > work.size.y: return {}
	var dimensions := (GroupLayout.measure(tree, preferred) + grip_size).min(work.size)
	var bounds := group_bounds(group, group.position, dimensions, work, minimum)
	if not bounds.has_area(): return {}
	var cells := {}
	GroupLayout.place(tree, Rect2(bounds.position + grip_size, bounds.size - grip_size), minimum, preferred, cells)
	return {"bounds": bounds, "cells": cells, "grip_height": grip_height, "tree": tree, "minimum": minimum}

func group_bounds(group: Dictionary, origin: Vector2, dimensions: Vector2, work: Rect2, members: Dictionary) -> Rect2:
	var edge: String = group.dock
	var bounds := FloatingPanel.dock_rect(work, origin, dimensions, edge, group.get("corner", ""))
	if not edge.is_empty():
		var occupied := docked_group_rects("", group.get("id", -1))
		for key in panels:
			var panel = panels[key]
			if not members.has(key) and panel.visible and not panel.dock.is_empty():
				occupied.append(panel.get_rect())
		return find_dock_slot(edge, bounds, occupied)
	return bounds

func begin_group_resize(key: String) -> void:
	var group := find_panel_group(key)
	if group.is_empty() or not panels[key].group_cell.has_area(): return
	if not group_resize.is_empty(): panels[group_resize.key].end_gesture(true)
	var placement := group_placement(group)
	if placement.is_empty() or not placement.cells.has(key): return
	# Responsive controls can change the preferred size after a group was placed.
	# Use the cells actually on screen as the starting point of the gesture.
	var visible_bounds: Rect2 = group.get("bounds", Rect2())
	if not visible_bounds.has_area(): return
	placement.bounds = visible_bounds
	var dimensions := {}
	for member in placement.cells:
		var cell: Rect2 = panels[member].group_cell
		if not cell.has_area(): return
		placement.cells[member] = cell
		dimensions[member] = cell.size
	var splits := [
		GroupLayout.resize_split(placement.tree, key, 0, placement.minimum),
		GroupLayout.resize_split(placement.tree, key, 1, placement.minimum),
	]
	group_resize = {"key": key, "group": group, "start": placement, "sizes": dimensions, "splits": splits, "preview": placement}

func cancel_group_resize(group: Dictionary) -> void:
	if is_same(group, group_resize.get("group")):
		panels[group_resize.key].end_gesture(true)

func preview_group_resize(key: String, delta: Vector2) -> void:
	if group_resize.get("key") != key: return
	var group: Dictionary = group_resize.group
	var start: Dictionary = group_resize.start
	var original: Rect2 = start.bounds
	var grip_size := Vector2(0, start.grip_height)
	var work := FloatingPanel.work_area(self, not group.dock.is_empty())
	var dimensions := original.size
	var maximum := work.end - original.position
	var corner: String = group.get("corner", "")
	if group.dock == "right" or corner == "right": maximum.x = work.size.x
	if group.dock == "bottom" or corner == "bottom": maximum.y = work.size.y
	# A handle at an outside edge grows the group. An inside handle moves its divider.
	for axis in 2:
		if group_resize.splits[axis].is_empty():
			var side := "right" if axis == 0 else "bottom"
			var anchored: bool = group.dock == side or corner == side
			dimensions[axis] += -delta[axis] if anchored else delta[axis]
	dimensions = dimensions.clamp(GroupLayout.measure(start.tree, start.minimum) + grip_size, maximum)
	var bounds := original if dimensions == original.size else group_bounds(group, original.position, dimensions, work, start.minimum)
	if not bounds.has_area(): return
	var cells := {}
	var adjustment := {"splits": group_resize.splits, "delta": delta}
	GroupLayout.place(start.tree, Rect2(bounds.position + grip_size, bounds.size - grip_size), start.minimum, group_resize.sizes, cells, adjustment)
	if group_resize.preview.cells == cells: return
	var preview := {"bounds": bounds, "cells": cells, "grip_height": start.grip_height}
	group_resize.preview = preview
	apply_group_placement(group, preview)

func finish_group_resize(key: String, committed: bool) -> void:
	if group_resize.get("key") != key: return
	var group: Dictionary = group_resize.group
	if committed:
		var dimensions: Dictionary = group.get("sizes", {})
		for member in group_resize.preview.cells:
			dimensions[member] = group_resize.preview.cells[member].size
		group.sizes = dimensions
	else:
		apply_group_placement(group, group_resize.start)
	group_resize = {}

func docked_group_rects(excluding_member := "", excluding_group := -1) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for group in panel_groups:
		if group.id == excluding_group or group.dock.is_empty() or excluding_member in GroupLayout.leaves(group.tree): continue
		var bounds: Rect2 = group.get("bounds", Rect2())
		if bounds.has_area(): result.append(bounds)
	return result

func reflow_panel_groups() -> void:
	var changed := false
	for group in panel_groups.duplicate():
		if is_same(group, group_resize.get("group")) or is_same(group, group_move.get("group")): continue
		var names := GroupLayout.leaves(group.tree)
		if names.any(func(key): return panels[key].gesture == "move"): continue
		var placement := group_placement(group)
		if placement.is_empty() and not group.dock.is_empty():
			group.dock = ""
			group.corner = ""
			changed = true
			placement = group_placement(group)
		if placement.is_empty():
			group.bounds = Rect2()
			var grip: Control = group_grips.get(group.id)
			if grip: grip.hide()
			for key in names: panels[key].set_group_cell(Rect2())
			continue
		if group.position != placement.bounds.position: changed = true
		apply_group_placement(group, placement)
	if changed: save_layout()

func apply_group_placement(group: Dictionary, placement: Dictionary) -> void:
	group.bounds = placement.bounds
	group.position = placement.bounds.position
	for key in GroupLayout.leaves(group.tree):
		var panel = panels[key]
		panel.dock = ""
		panel.set_group_cell(placement.cells.get(key, Rect2()), not group.dock.is_empty())
	var grip = group_grips.get(group.id)
	if placement.grip_height > 0:
		if not grip: grip = build_group_grip(group)
		var grip_style: StyleBoxFlat = grip.get_theme_stylebox("panel")
		var radius := 6 if group.dock.is_empty() else 0
		if grip_style.get_corner_radius(CORNER_TOP_LEFT) != radius: grip_style.set_corner_radius_all(radius)
		grip.position = placement.bounds.position
		grip.size = Vector2(placement.bounds.size.x, placement.grip_height - 2)
		grip.visible = not is_instance_valid(project_home) or not project_home.visible
		if grip.visible: grip.move_to_front()
	elif grip:
		grip.hide()

func build_group_grip(group: Dictionary) -> Control:
	var grip = GroupGrip.new()
	grip.tooltip_text = "Drag to move or dock the group. Drag a panel’s own header to take it out."
	grip.add_theme_stylebox_override("panel", style(Color("#26322d"), 6, Color("#537166"), 0))
	var caption = label("⠿  Move group", 13, ACCENT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grip.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grip)
	group_grips[group.id] = grip
	grip.move_started.connect(begin_group_move.bind(group))
	grip.moved.connect(preview_group_move.bind(group))
	grip.move_finished.connect(finish_group_move.bind(group))
	return grip

func begin_group_move(group: Dictionary) -> void:
	if not group_move.is_empty(): group_grips[group_move.group.id].end_move(true)
	cancel_group_resize(group)
	raise_panel_stack(GroupLayout.leaves(group.tree), group_grips.get(group.id))
	group_move = {"group": group}

func preview_group_move(pointer: Vector2, delta: Vector2, group: Dictionary) -> void:
	if not is_same(group, group_move.get("group")): return
	group_move.erase("drop")
	var candidate := group.duplicate()
	candidate.position += delta
	candidate.dock = ""
	candidate.corner = ""
	var floating := group_placement(candidate)
	if not floating.is_empty():
		for key in floating.cells: panels[key].move_to_front()
		apply_group_placement(candidate, floating)
		group_move.drop = {"group": candidate, "placement": floating}

	dock_preview.hide()
	if not workspace_options.edge_docking: return
	var area := FloatingPanel.work_area(self, true)
	var local_pointer := get_global_transform_with_canvas().affine_inverse() * pointer
	var edge := FloatingPanel.edge_at(area, local_pointer)
	if edge.is_empty(): return
	var docked := candidate.duplicate()
	docked.dock = edge
	docked.corner = FloatingPanel.corner_at(area, edge, local_pointer)
	var placement := group_placement(docked)
	if placement.is_empty():
		var hint := FloatingPanel.dock_rect(area, candidate.position, Vector2(220, 54), edge)
		show_dock_placement(hint, "No room · group will float", false)
		return

	var bounds: Rect2 = placement.bounds
	var desired := FloatingPanel.dock_rect(area, bounds.position, bounds.size, edge, docked.corner)
	if bounds.position != desired.position: docked.corner = ""
	var side := dock_location_label(edge, docked.corner)
	show_dock_placement(bounds, "Dock group %s" % side)
	group_move.drop = {"group": docked, "placement": placement}

func finish_group_move(canceled: bool, group: Dictionary) -> void:
	if not is_same(group, group_move.get("group")): return
	var drop: Dictionary = group_move.get("drop", {})
	group_move = {}
	dock_preview.hide()
	if not canceled and not drop.is_empty():
		group.dock = drop.group.dock
		group.corner = drop.group.corner
		apply_group_placement(group, drop.placement)
		save_layout()
	queue_dock_reflow()

func select_brush_tab(key: String) -> void:
	var index := BRUSH_TAB_KEYS.find(key)
	if index < 0: return
	var changed := active_brush_tab != key
	brush_pages.current_tab = index
	active_brush_tab = key
	for tab in brush_tab_buttons.size(): brush_tab_buttons[tab].set_pressed_no_signal(tab == index)
	if changed and is_node_ready() and not restoring_workspace: save_layout()

func show_brush_tab(key: String) -> void:
	select_brush_tab(key)
	panels.Brushes.show()
	panels.Brushes.move_to_front()

func toggle_brush_panel(key: String) -> void:
	if active_brush_tab == key and panels.Brushes.visible: panels.Brushes.hide()
	else: show_brush_tab(key)

func read_swatch_history(key: String, limit: int) -> Array[String]:
	var result: Array[String] = []
	var stored = settings.get_value("colors", key, [])
	if stored is Array:
		for hex in stored:
			if Document.valid_color(hex) and hex.length() == 7 and hex.to_lower() not in result:
				result.append(hex.to_lower())
			if result.size() == limit: break
	return result

func build_color_panel() -> void:
	var box = make_panel("Color", Vector2(98, 110), 252)
	box.add_theme_constant_override("separation", 6)
	var header := BoxContainer.new()
	header.vertical = true
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)
	box.resized.connect(func(): header.vertical = box.size.x < 350)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 3)
	modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(modes)
	var mode_group := ButtonGroup.new()
	for title in ["Wheel", "Sliders", "Palette"]:
		var index := color_panel_tabs.size()
		var tab := button(title, func(): show_color_view(index))
		tab.toggle_mode = true
		tab.button_group = mode_group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 12)
		tab.add_theme_stylebox_override("normal", style(Color("#242424"), 6, Color.TRANSPARENT, 4))
		tab.add_theme_stylebox_override("pressed", style(Color("#2c3531"), 6, Color("#53796a"), 4))
		modes.add_child(tab)
		color_panel_tabs.append(tab)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(controls)
	var preview := Panel.new()
	preview.name = "ColorPreview"
	preview.custom_minimum_size = Vector2(33, 40)
	preview.tooltip_text = "Current color"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_preview_style = style(canvas.color, 7, Color("#ffffff52"), 0)
	preview.add_theme_stylebox_override("panel", color_preview_style)
	controls.add_child(preview)
	color_hex = LineEdit.new()
	color_hex.placeholder_text = "#RRGGBB"
	color_hex.max_length = 7
	color_hex.custom_minimum_size = Vector2(78, 40)
	color_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_hex.alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_hex.add_theme_font_size_override("font_size", 14)
	color_hex.tooltip_text = "Hex color"
	color_hex.text_submitted.connect(func(_text): color_hex.release_focus())
	color_hex.focus_exited.connect(apply_color_hex)
	controls.add_child(color_hex)
	controls.add_child(icon_button("M6 16L17 5L21 9L10 20L4 22ZM15 3L23 11", func(): set_tool("picker"), shortcut_hint("Pick from canvas", "I")))

	color_picker = ColorWheel.new()
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.color_changed.connect(func(value): set_color(value, true))
	color_picker.preview_changed.connect(func(value): color_preview_style.bg_color = value)
	box.add_child(color_picker)
	panels.Color.expand_content(color_picker, 136)

	color_channels = ColorChannels.new()
	box.add_child(color_channels)
	color_channels.adjusted.connect(func(value, hue, commit):
		color_picker.hue = hue
		set_color(value, commit)
		color_picker.queue_redraw())

	palette_page = VBoxContainer.new()
	palette_page.add_theme_constant_override("separation", 6)
	box.add_child(palette_page)
	palette_page.add_child(label("Pine & Tide", 13, MUTED))
	palette_swatches = new_swatch_row()
	palette_page.add_child(palette_swatches)
	for hex in palette: palette_swatches.add_child(make_color_swatch(hex))
	var saved_header := HBoxContainer.new()
	saved_header.add_theme_constant_override("separation", 4)
	palette_page.add_child(saved_header)
	var saved_caption := label("Saved swatches", 13, MUTED)
	saved_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved_header.add_child(saved_caption)
	saved_header.add_child(icon_button("M13 5V21M5 13H21", func(): edit_saved_swatch(true), "Save the current color"))
	remove_swatch = icon_button("M5 13H21", func(): edit_saved_swatch(false), "Remove the current color from Saved swatches")
	saved_header.add_child(remove_swatch)
	saved_swatches = new_swatch_row()
	palette_page.add_child(saved_swatches)

	box.add_child(label("Recent colors", 13, MUTED))
	recent_swatches = new_swatch_row()
	recent_swatches.custom_minimum_size.y = 36
	box.add_child(recent_swatches)
	update_recent_swatches()
	refill_swatch_row(saved_swatches, saved_swatches_hex, "Save a color with +.")
	show_color_view(0)
	set_color(canvas.color)
	panels.Color.hide()

func show_color_view(index: int) -> void:
	color_picker.visible = index == 0
	color_channels.visible = index == 1
	palette_page.visible = index == 2
	color_panel_tabs[index].set_pressed_no_signal(true)
	if index == 1: color_channels.set_color(canvas.color, color_picker.hue)

func new_swatch_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 5)
	row.add_theme_constant_override("v_separation", 5)
	return row

func make_color_swatch(hex: String) -> Button:
	var swatch = button("", func(): set_color(Color(hex), true), hex.to_upper())
	swatch.custom_minimum_size = Vector2(31, 36)
	swatch.toggle_mode = true
	swatch.set_meta("hex", hex)
	swatch.add_theme_stylebox_override("normal", style(Color(hex), 7, Color("#ffffff33"), 0))
	swatch.add_theme_stylebox_override("hover", style(Color(hex), 7, ACCENT, 0))
	var selected := style(Color(hex), 7, Color("#eeeeee") if Color(hex).get_luminance() < 0.45 else Color("#202020"), 0)
	selected.set_border_width_all(2)
	swatch.add_theme_stylebox_override("pressed", selected)
	swatch.add_theme_stylebox_override("hover_pressed", selected)
	return swatch

func refill_swatch_row(row: HFlowContainer, colors: Array[String], empty_text: String) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	if colors.is_empty():
		row.add_child(label(empty_text, 12, MUTED))
	else:
		for hex in colors: row.add_child(make_color_swatch(hex))

func update_recent_swatches() -> void:
	refill_swatch_row(recent_swatches, recent_colors, "Colors you use appear here.")
	update_swatch_selection()

func update_swatch_selection() -> void:
	var hex: String = "#" + canvas.color.to_html(false)
	for row in [recent_swatches, palette_swatches, saved_swatches]:
		for child in row.get_children():
			if child is Button: child.set_pressed_no_signal(child.get_meta("hex") == hex)
	remove_swatch.disabled = hex not in saved_swatches_hex

func edit_saved_swatch(add: bool) -> void:
	var hex: String = "#" + canvas.color.to_html(false)
	if add:
		if hex in saved_swatches_hex: return
		if saved_swatches_hex.size() >= SAVED_COLOR_LIMIT:
			notify("Saved swatches is full. Remove a color to add another.")
			return
		saved_swatches_hex.append(hex)
	else:
		if hex not in saved_swatches_hex: return
		saved_swatches_hex.erase(hex)
	settings.set_value("colors", "saved", saved_swatches_hex)
	if settings.save("user://preferences.cfg") != OK: notify("Could not save the palette for the next launch.")
	refill_swatch_row(saved_swatches, saved_swatches_hex, "Save a color with +.")
	update_swatch_selection()

func remember_color(value: Color) -> void:
	var hex := "#" + value.to_html(false)
	if not recent_colors.is_empty() and recent_colors[0] == hex: return
	recent_colors.erase(hex)
	recent_colors.push_front(hex)
	if recent_colors.size() > RECENT_COLOR_LIMIT: recent_colors.resize(RECENT_COLOR_LIMIT)
	settings.set_value("colors", "recent", recent_colors)
	history_preferences_dirty = true
	update_recent_swatches()

func apply_color_hex() -> void:
	var hex := color_hex.text.strip_edges()
	if not hex.begins_with("#"): hex = "#" + hex
	if hex.length() == 7 and Document.valid_color(hex):
		var next := Color(hex)
		set_color(next, next.to_html(false) != canvas.color.to_html(false))
	else:
		color_hex.text = "#" + canvas.color.to_html(false).to_upper()

func toggle_color_panel() -> void:
	var panel = panels.Color
	panel.visible = not panel.visible
	if panel.visible: panel.move_to_front()

func build_layer_panel() -> void:
	var box = make_panel("Layers", Vector2(1174, 411), 248)
	box.add_theme_constant_override("separation", 7)
	layer_icons = {
		"eye": make_icon("M2 13Q13 2 24 13Q13 24 2 13ZM16 13a3 3 0 1 1 -6 0a3 3 0 1 1 6 0", "#dedede", 20),
		"hidden": make_icon("M3 4L23 22M4 11L2 13Q13 24 20 17M8 7Q16 4 24 13L23 14", "#969696", 20),
		"locked": make_icon("M6 12H20V22H6ZM9 12V8a4 4 0 0 1 8 0v4M13 16v2", "#c9d8d0", 19),
		"unlocked": make_icon("M6 12H20V22H6ZM9 12V8a4 4 0 0 1 7 -2M13 16v2", "#969696", 19),
		"grip": make_icon("M10 7h.1M16 7h.1M10 13h.1M16 13h.1M10 19h.1M16 19h.1", "#a2a2a2", 19),
	}
	layer_row_styles = [style(Color("#222222"), 8, Color("#323232"), 3),
		style(Color("#292e2b"), 8, Color("#4c685a"), 3)]
	layer_row_styles[1].set_border_width(SIDE_LEFT, 2)
	layer_row_styles[0].content_margin_left = 4
	layer_row_styles[1].content_margin_left = 4
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	box.add_child(actions)
	var add_layer := button("New vector", add_document_layer, "Add an editable vector layer")
	add_layer.name = "NewLayerButton"
	add_layer.icon = make_icon("M13 5V21M5 13H21", "#dbe6df", 18)
	add_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_layer.add_theme_font_size_override("font_size", 13)
	add_layer.add_theme_stylebox_override("normal", style(Color("#292929"), 7, Color("#3c3c3c"), 6))
	actions.add_child(add_layer)
	layer_solo_button = icon_button("M6 3H3V6M20 3H23V6M23 20V23H20M6 23H3V20M9 9H17V17H9Z",
		toggle_active_layer_solo, "Solo the active layer")
	layer_solo_button.name = "SoloLayer"
	layer_solo_button.toggle_mode = true
	actions.add_child(layer_solo_button)
	layer_actions_button = icon_button("M5 13h1M12 13h1M19 13h1", open_layer_actions, "Layer actions")
	layer_actions_button.name = "LayerActionsButton"
	PopupTouch.watch_launcher(layer_actions_button)
	actions.add_child(layer_actions_button)
	build_layer_opacity_bar(box)
	layer_scroll = LayerDragList.new()
	layer_scroll.custom_minimum_size = Vector2(186, 86)
	layer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(layer_scroll)
	panels.Layers.expand_content(layer_scroll, 214)
	layer_list = VBoxContainer.new()
	layer_list.add_theme_constant_override("separation", 5)
	layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_scroll.add_child(layer_list)
	layer_scroll.rows = layer_list
	layer_scroll.reorder_requested.connect(drop_layer)
	layer_scroll.get_v_scroll_bar().value_changed.connect(func(_value): queue_layer_preview_refresh())
	layer_scroll.item_rect_changed.connect(queue_layer_preview_refresh)
	layer_scroll.visibility_changed.connect(queue_layer_preview_refresh)
	layer_list.sort_children.connect(queue_layer_preview_refresh)
	layer_actions = PopupMenu.new()
	layer_actions.name = "LayerActions"
	layer_actions.add_item("Layer opacity…", 0)
	layer_actions.add_item("New paint layer", 11)
	layer_actions.add_check_item("Alpha lock", 10)
	layer_actions.add_check_item("Merge touching", 12)
	layer_actions.add_item("Import image as layer…", 1)
	layer_actions.add_item("Export active layer as PNG…", 2)
	layer_actions.add_separator()
	layer_actions.add_item("Rename layer…", 3)
	layer_actions.add_item("Duplicate layer", 5)
	layer_actions.add_item("Move layer up", 6)
	layer_actions.add_item("Move layer down", 7)
	layer_actions.add_separator()
	layer_actions.add_item("Merge Down", 8)
	layer_actions.add_item("Merge Visible", 9)
	layer_actions.add_item("Delete layer…", 4)
	layer_actions.id_pressed.connect(func(id):
		match id:
			0: edit_layer_opacity()
			1: show_image_import()
			2: choose_layer_export()
			3: rename_layer()
			4: delete_layer()
			5:
				canvas.finish()
				if not document.duplicate_layer(document.active):
					notify("The project has reached its layer or embedded image limit.")
			6: reorder_layer(1)
			7: reorder_layer(-1)
			8: merge_layer_stack(false)
			9: merge_layer_stack(true)
			10: toggle_alpha_lock()
			11: add_document_layer("paint")
			12: toggle_merge_touching()
	)
	add_child(layer_actions)
	clip_check = CheckBox.new()
	clip_check.text = "Paint inside selection"
	clip_check.add_theme_font_size_override("font_size", 12)
	clip_check.toggled.connect(set_paint_limit)
	box.add_child(clip_check)

func set_paint_limit(enabled: bool) -> void:
	canvas.finish()
	if not enabled:
		canvas.clear_paint_limit()
	elif canvas.set_clip_from_selection():
		set_tool("brush")
	else:
		notify("Select artwork or draw a selection area first.")
	clip_check.set_pressed_no_signal(canvas.clip_enabled)
	update_selection_actions()

func build_layer_opacity_bar(box: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	box.add_child(bar)
	layer_opacity_label = label("Opacity 100%", 12, MUTED)
	layer_opacity_label.custom_minimum_size.x = 76
	bar.add_child(layer_opacity_label)
	layer_opacity_slider = TouchSlider.new()
	layer_opacity_slider.name = "LayerOpacitySlider"
	layer_opacity_slider.max_value = 100
	layer_opacity_slider.step = 1
	layer_opacity_slider.custom_minimum_size.y = 37
	layer_opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_opacity_slider.tooltip_text = "Active layer opacity"
	layer_opacity_slider.drag_started.connect(begin_layer_opacity_drag)
	layer_opacity_slider.drag_ended.connect(end_layer_opacity_drag)
	layer_opacity_slider.value_changed.connect(change_layer_opacity)
	bar.add_child(layer_opacity_slider)
	alpha_lock_button = icon_button("M4 4H22V22H4ZM10 4V10H4M16 4V10H22M10 10V16H16V10ZM4 16H10V22M22 16H16V22",
		toggle_alpha_lock, "Alpha lock · Keep the layer’s existing transparency")
	alpha_lock_button.name = "AlphaLock"
	alpha_lock_button.toggle_mode = true
	bar.add_child(alpha_lock_button)

func add_document_layer(layer_type := "vector") -> void:
	canvas.finish()
	if document.layers.size() >= 100:
		notify("This project already has 100 layers.")
		return
	document.checkpoint()
	var name_text := "Paint" if layer_type == "paint" else "Vector"
	document.layers.append(document.new_layer("%s %d" % [name_text, document.layers.size() + 1], layer_type))
	document.active = document.layers.size() - 1
	document.selection = ""
	document.commit()

func build_type_panel() -> void:
	var box = make_panel("Typography", Vector2(924, 110), 250)
	text_edit = TextEdit.new()
	text_edit.text = canvas.text_content
	text_edit.custom_minimum_size = Vector2(168, 72)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.accessibility_name = "Illustration text"
	text_edit.text_changed.connect(func(): canvas.text_content = text_edit.text)
	box.add_child(text_edit)
	panels.Typography.expand_content(text_edit, 100)
	font_choice = button("", show_fonts, "Browse and preview fonts")
	font_choice.name = "ChooseFont"
	font_choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(font_choice)
	box.add_child(button("Add fonts…", show_font_import, "Import TrueType or OpenType fonts"))
	build_font_browser()
	choose_typography_font(canvas.text_font)
	var size_row = HBoxContainer.new()
	size_row.add_child(label("Text size", 13, MUTED))
	font_size = SpinBox.new()
	font_size.min_value = 4
	font_size.max_value = 500
	font_size.value = 42
	font_size.custom_minimum_size.x = 130
	font_size.get_line_edit().accessibility_name = "Text size"
	font_size.value_changed.connect(func(value): canvas.text_size = value)
	size_row.add_child(font_size)
	box.add_child(size_row)
	var apply = button("Apply to selected text", apply_text)
	primary(apply)
	box.add_child(apply)
	box.add_child(label("Tap canvas to place new text.", 11, MUTED))
	panels.Typography.hide()

func build_font_browser() -> void:
	fonts_dialog = ConfirmationDialog.new()
	fonts_dialog.name = "FontBrowser"
	fonts_dialog.title = "Fonts"
	fonts_dialog.ok_button_text = "Use font"
	var content := margin(fonts_dialog, 14)
	content.custom_minimum_size.x = 410
	var controls := HBoxContainer.new()
	content.add_child(controls)
	font_search = LineEdit.new()
	font_search.placeholder_text = "Search fonts"
	font_search.accessibility_name = "Search fonts"
	font_search.custom_minimum_size.y = 44
	font_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_search.select_all_on_focus = true
	font_search.text_changed.connect(func(_value): rebuild_font_results())
	controls.add_child(font_search)
	font_category = OptionButton.new()
	font_category.add_item("All fonts")
	for category in Fonts.CATEGORIES: font_category.add_item(category)
	font_category.item_selected.connect(func(_index): rebuild_font_results())
	controls.add_child(font_category)
	var scroll = SwipeScroll.new()
	scroll.custom_minimum_size.y = 222
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	font_results = VBoxContainer.new()
	font_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(font_results)
	font_preview = label("", 26)
	font_preview.custom_minimum_size.y = 46
	font_preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(font_preview)
	fonts_dialog.confirmed.connect(func(): choose_typography_font(font_preview_id))
	add_child(fonts_dialog)
	primary(fonts_dialog.get_ok_button())
	fonts_dialog.get_ok_button().custom_minimum_size.y = 44
	fonts_dialog.get_cancel_button().custom_minimum_size.y = 44

	font_import_dialog = FileDialog.new()
	font_import_dialog.title = "Add fonts"
	font_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	font_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	font_import_dialog.filters = PackedStringArray(["*.ttf,*.otf ; Font files", "* ; All files"])
	font_import_dialog.use_native_dialog = true
	font_import_dialog.files_selected.connect(import_fonts)
	add_child(font_import_dialog)

func choose_typography_font(id: String, known_name := "") -> void:
	var face := Fonts.entry(id)
	canvas.text_font = id
	font_choice.text = face.get("name", "Missing font" if known_name.is_empty() else "Missing · " + known_name)
	var face_font := Fonts.font_for(id)
	font_choice.add_theme_font_override("font", face_font)
	text_edit.add_theme_font_override("font", face_font)

func show_fonts() -> void:
	font_search.text = ""
	font_category.select(0)
	font_preview_id = canvas.text_font
	rebuild_font_results()
	fonts_dialog.popup_centered()

func rebuild_font_results() -> void:
	for row in font_results.get_children():
		font_results.remove_child(row)
		row.queue_free()
	var query := font_search.text.strip_edges().to_lower()
	var category := font_category.get_item_text(font_category.selected)
	var group := ButtonGroup.new()
	var first := ""
	var has_selection := false
	for face in Fonts.entries():
		if font_category.selected > 0 and face.category != category: continue
		if not query.is_empty() and not query in face.name.to_lower(): continue
		var id: String = face.id
		if first.is_empty(): first = id
		var row := button(face.name, func(): select_font_preview(id), "%s · %s" % [face.name, face.category])
		row.add_theme_font_override("font", Fonts.font_for(id))
		row.add_theme_font_size_override("font_size", 19)
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.toggle_mode = true
		row.button_group = group
		row.set_pressed_no_signal(id == font_preview_id)
		if id == font_preview_id: has_selection = true
		font_results.add_child(row)
	if first.is_empty(): font_results.add_child(label("No matching fonts.", 14, MUTED))
	elif not has_selection: font_results.get_child(0).set_pressed_no_signal(true)
	select_font_preview(font_preview_id if has_selection else first)

func select_font_preview(id: String) -> void:
	font_preview_id = id
	fonts_dialog.get_ok_button().disabled = id.is_empty()
	var sample := text_edit.text.strip_edges().split("\n", false, 1)
	font_preview.text = "" if id.is_empty() else ("Coffee & cardamom" if sample.is_empty() else sample[0].left(100))
	if not id.is_empty(): font_preview.add_theme_font_override("font", Fonts.font_for(id))

func show_font_import() -> void:
	font_import_dialog.popup_centered_ratio(0.75)

func import_fonts(paths: PackedStringArray) -> void:
	var added := 0
	var error := ""
	var selected_id := ""
	for path in paths:
		var face := Fonts.import_font(path)
		if face.has("error"):
			if error.is_empty(): error = face.error
			continue
		added += 1
		if selected_id.is_empty(): selected_id = face.id
	if added > 0:
		choose_typography_font(selected_id)
		var message := "Added %s" % font_choice.text if added == 1 else "Added %d fonts" % added
		if not error.is_empty(): message += " · Some files could not be imported."
		notify(message)
	elif not error.is_empty():
		notify(error)

func adapt_android_content_scale() -> void:
	var window := get_window()
	var base := android_content_base(window.size)
	if window.content_scale_size != base: window.content_scale_size = base

func android_content_base(window_size: Vector2i) -> Vector2i:
	if window_size.y >= window_size.x: return Vector2i(800, 1050)
	return Vector2i(1050, 720)

func compact_workspace() -> bool:
	return size.x < 1000.0 or size.y > size.x

func update_workspace_chrome() -> void:
	var narrow := size.x < 900
	var tight := size.x < 690
	brand_button.icon = BRAND_MARK if tight else BRAND_LOGO
	brand_button.custom_minimum_size.x = 44 if tight else 102
	brand_button.add_theme_constant_override("icon_max_width", 28 if tight else 90)
	title_edit.custom_minimum_size.x = 74 if tight else (108 if narrow else 240)
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	save_label.visible = not narrow
	brush_library_button.custom_minimum_size.x = 54 if tight else (72 if narrow else 112)
	header_tools.add_theme_constant_override("separation", 4 if tight else 8)
	header_panels_button.text = "" if tight else "Panels"
	header_panels_button.icon = header_panels_icon if tight else null
	header_brush_settings.visible = not tight
	status_label.visible = size.x >= 1000
	footer_metrics.visible = workspace_options.footer_metrics and size.x >= 720

func default_panel_position(key: String) -> Vector2:
	match key:
		"Tools": return Vector2(16, 103)
		BRUSH_LIBRARY_PANEL: return Vector2(98, 103)
		"Typography":
			return Vector2(size.x - (266 if compact_workspace() else 516), 103)
		"Color": return Vector2(98 if compact_workspace() else size.x - 540, 110)
		"Layers":
			return Vector2(size.x - 246, minf(411, size.y * 0.48))
	return Vector2(100, 100)

func layout_workspace() -> void:
	if not is_instance_valid(canvas): return
	if not group_move.is_empty(): group_grips[group_move.group.id].end_move(true)
	if not group_resize.is_empty(): panels[group_resize.key].end_gesture(true)
	var compact := compact_workspace()
	var old_size := previous_workspace_size
	previous_workspace_size = size
	update_workspace_chrome()
	# Portrait has no permanent rail on the right. Its floating panels can
	# cover the drawing area when open and otherwise leave that width usable.
	var right_inset := 18.0 if compact else 266.0
	canvas.position = Vector2(98, 90)
	canvas.size = Vector2(maxf(1, size.x - 98 - right_inset), maxf(1, size.y - canvas.position.y - FOOTER_HEIGHT - 10.0))
	if old_size != Vector2.ZERO and old_size != size:
		var scale_factor := size / old_size
		for panel in panels.values():
			panel.position *= scale_factor
		for group in panel_groups:
			group.position *= scale_factor
	elif old_size == Vector2.ZERO:
		for key in panels:
			if not settings.has_section_key("layout_minimal_v2", key): panels[key].position = default_panel_position(key)
	for panel in panels.values():
		panel.apply_preferred_size()
		panel.constrain()
	position_selection_tray()
	queue_dock_reflow()
	if workspace_settings_dialog.visible: fit_workspace_settings.call_deferred()

func reset_layout() -> void:
	restoring_workspace = true
	for key in panels: detach_group_member(key)
	reflow_panel_groups()
	select_brush_tab(BRUSH_LIBRARY_PANEL)
	for panel in panels.values():
		panel.dock = ""
		panel.preferred_size = Vector2.ZERO
		panel.apply_preferred_size()
	set_tool_orientation(false)
	panels.Tools.show()
	panels.Layers.show()
	panels.Brushes.hide()
	panels.Color.hide()
	panels.Typography.visible = canvas.tool == "text"
	for key in panels:
		panels[key].position = default_panel_position(key)
		panels[key].constrain()
	restoring_workspace = false
	save_layout()
	notify("Workspace restored. Drag a panel heading to rearrange it.")

func save_layout() -> void:
	settings.set_value("workspace", "panel_group_layouts", panel_groups)
	settings.set_value("workspace", "unified_brush_panel", true)
	settings.set_value("workspace", "active_brush_tab", active_brush_tab)
	for key in panels:
		var panel = panels[key]
		settings.set_value("layout_minimal_v2", key, panel.position / size)
		settings.set_value("panel_dock", key, panel.dock)
		settings.set_value("panel_dock_corner", key, panel.dock_corner)
		settings.set_value("panel_size", key, panel.preferred_size)
		if key != "Typography": settings.set_value("panel_visible", key, panel.visible)
	settings.save("user://preferences.cfg")

func restore_layout() -> void:
	var saved_tab = settings.get_value("workspace", "active_brush_tab", BRUSH_LIBRARY_PANEL)
	var unified: bool = settings.get_value("workspace", "unified_brush_panel", false) == true
	var old_settings_visible: bool = settings.get_value("panel_visible", BRUSH_SETTINGS_PANEL, false) == true
	var old_library_visible: bool = settings.get_value("panel_visible", BRUSH_LIBRARY_PANEL, false) == true
	if not unified:
		var was_merged: bool = settings.get_value("workspace", "brush_panels_merged", false) == true
		if (was_merged and saved_tab == BRUSH_SETTINGS_PANEL) or (old_settings_visible and not old_library_visible):
			legacy_brush_layout_key = BRUSH_SETTINGS_PANEL
			saved_tab = BRUSH_SETTINGS_PANEL
	if saved_tab in BRUSH_TAB_KEYS: select_brush_tab(saved_tab)
	for key in panels:
		var layout_key: String = legacy_brush_layout_key if key == BRUSH_LIBRARY_PANEL else key
		var panel = panels[key]
		var position_value = settings.get_value("layout_minimal_v2", layout_key, Vector2.INF)
		if position_value is Vector2 and position_value.is_finite(): panel.position = position_value * size
		var edge = settings.get_value("panel_dock", layout_key, "")
		if edge in ["left", "right", "top", "bottom"]:
			panel.dock = edge
			panel.dock_corner = FloatingPanel.valid_corner(edge, settings.get_value("panel_dock_corner", layout_key, ""))
		var saved_size = settings.get_value("panel_size", layout_key, Vector2.ZERO)
		if saved_size is Vector2 and saved_size.is_finite(): panel.preferred_size = saved_size
		if key != "Typography": panel.visible = bool(settings.get_value("panel_visible", layout_key, panel.visible))
		panel.apply_preferred_size()
		panel.constrain.call_deferred()
	queue_dock_reflow()
	restore_panel_groups()
	restoring_workspace = false

func press_tool(key: String) -> void:
	if reject_unavailable_tool(key): return
	if key == "brush" and canvas.tool == "brush": toggle_brush_panel(active_brush_tab)
	elif key == "shapes": show_shape_menu()
	elif key == "select": show_selection_menu()
	else: set_tool(key)

func reject_unavailable_tool(key: String) -> bool:
	var reason: String = canvas.tool_unavailable_reason(key)
	if reason.is_empty(): return false
	refresh_tool_buttons()
	notify(reason)
	return true

func set_tool(next: String) -> void:
	canvas.finish()
	if not reject_unavailable_tool(next): activate_tool(next)

func refresh_tool_buttons() -> void:
	for key in tool_buttons:
		var control: Button = tool_buttons[key]
		control.set_pressed_no_signal(key == canvas.tool or (key == "shapes" and canvas.tool in Canvas.SHAPE_TOOLS)
			or (key == "select" and canvas.tool in Canvas.AREA_TOOLS))
		# Keep dimmed buttons clickable so they can explain the restriction.
		control.self_modulate.a = 1.0 if canvas.tool_unavailable_reason(key).is_empty() else 0.38

func activate_tool(next: String) -> void:
	if next != canvas.tool: canvas.clear_path()
	canvas.tool = next
	if next != "nodes": canvas.set_add_node_mode(false)
	refresh_tool_buttons()
	if panels.has("Typography"): panels.Typography.visible = next == "text"
	if next == "erase" and status_label:
		status_label.text = "Drag to erase on a paint layer. Tap to remove a vector object."
	elif status_label and next in Canvas.AREA_TOOLS:
		status_label.text = "Draw around whole objects to select them. Two fingers pan and zoom."
	elif status_label: status_label.text = {"brush": "Light pressure blends. Firm pressure adds color.", "select": "Drag to move. Use the square to resize or the round handle to rotate.", "nodes": "Select a stroke or path, then drag its points.", "fill": "Tap inside a shape or where the lines enclose an area.", "text": "Type your text, then tap the canvas to place it.", "hand": "Drag to pan. Pinch or scroll to zoom.", "path": "Tap to add points. Tap the first point to close the path."}.get(next, "Drag on the canvas to create a shape.")
	update_selection_actions()
	canvas.refresh_selection()

func build_selection_menu() -> void:
	selection_menu = PopupPanel.new()
	selection_menu.name = "SelectionMenu"
	add_child(selection_menu)
	var content := build_tool_picker(selection_menu, SELECTION_OPTIONS, selection_icons, 3)
	select_across_toggle = CheckButton.new()
	select_across_toggle.text = "Select across visible layers"
	select_across_toggle.custom_minimum_size.y = 44
	select_across_toggle.toggled.connect(func(enabled):
		canvas.select_across_layers = enabled
		canvas.clear_selection())
	content.add_child(select_across_toggle)
	keep_selecting_toggle = CheckButton.new()
	keep_selecting_toggle.text = "Keep selecting"
	keep_selecting_toggle.tooltip_text = "Tap to add or remove objects and groups"
	keep_selecting_toggle.custom_minimum_size.y = 44
	keep_selecting_toggle.toggled.connect(func(enabled):
		canvas.keep_selecting = enabled
		if enabled: status_label.text = "Tap objects or groups to add or remove them."
		else: status_label.text = "Drag the selection to move it."
		canvas.refresh_selection())
	content.add_child(keep_selecting_toggle)
	merge_on_group_toggle = CheckButton.new()
	merge_on_group_toggle.text = "Merge vectors on grouping"
	merge_on_group_toggle.tooltip_text = "When possible, Group joins the selection into one vector shape"
	merge_on_group_toggle.custom_minimum_size.y = 44
	merge_on_group_toggle.toggled.connect(func(enabled):
		merge_on_group = enabled
		update_selection_actions())
	content.add_child(merge_on_group_toggle)
	PopupTouch.watch_launcher(tool_buttons.select)

func show_selection_menu() -> void:
	tool_buttons.select.set_pressed_no_signal(canvas.tool == "select" or canvas.tool in Canvas.AREA_TOOLS)
	select_across_toggle.set_pressed_no_signal(canvas.select_across_layers)
	keep_selecting_toggle.set_pressed_no_signal(canvas.keep_selecting)
	merge_on_group_toggle.set_pressed_no_signal(merge_on_group)
	show_tool_picker(selection_menu, tool_buttons.select, selection_icons)

func build_selection_move_dialog() -> void:
	selection_move_dialog = ConfirmationDialog.new()
	selection_move_dialog.name = "MoveSelectionToLayer"
	selection_move_dialog.title = "Move selection to layer"
	selection_move_dialog.ok_button_text = "Move"
	selection_move_dialog.dialog_hide_on_ok = false
	var content := margin(selection_move_dialog, 14)
	content.custom_minimum_size.x = 294
	selection_move_targets = OptionButton.new()
	selection_move_targets.accessibility_name = "Destination layer"
	selection_move_targets.custom_minimum_size.y = 44
	selection_move_targets.fit_to_longest_item = false
	selection_move_targets.clip_text = true
	content.add_child(selection_move_targets)
	selection_move_dialog.confirmed.connect(move_selection_to_chosen_layer)
	add_child(selection_move_dialog)

func show_selection_move() -> void:
	canvas.finish()
	var items: Array[Dictionary] = document.layer_transfer_items(canvas.solo_layer_id)
	if items.is_empty():
		notify("Select editable artwork to move it to a layer.")
		return
	selection_move_targets.clear()
	for index in range(document.layers.size() - 1, -1, -1):
		var layer: Dictionary = document.layers[index]
		if not document.can_receive_selection(layer, items): continue
		selection_move_targets.add_item(layer.name)
		selection_move_targets.set_item_metadata(selection_move_targets.item_count - 1, layer.id)
	if document.can_create_selection_layer(items):
		selection_move_targets.add_item("New vector layer")
		selection_move_targets.set_item_metadata(selection_move_targets.item_count - 1, "")
	if selection_move_targets.item_count == 0:
		notify("No compatible destination layer.")
		return
	selection_move_targets.select(0)
	selection_move_dialog.popup_centered(Vector2i.ONE)

func move_selection_to_chosen_layer() -> void:
	var index := selection_move_targets.selected
	if index < 0: return
	var destination: String = selection_move_targets.get_item_metadata(index)
	if not document.move_selection_to_layer(destination, canvas.solo_layer_id):
		notify("Choose a visible, unlocked layer with Alpha Lock off.")
		return
	canvas.selected_area.clear()
	canvas.refresh_selection()
	selection_move_dialog.hide()
	notify("Selection moved to %s." % document.layers[document.active].name)

func build_shape_menu() -> void:
	shape_menu = PopupPanel.new()
	shape_menu.name = "ShapesMenu"
	add_child(shape_menu)
	var content := build_tool_picker(shape_menu, SHAPE_OPTIONS, shape_icons, 4)
	content.add_child(button("Shape style…", func():
		shape_menu.hide()
		open_shape_style()))
	PopupTouch.watch_launcher(tool_buttons.shapes)

func show_shape_menu() -> void:
	tool_buttons.shapes.set_pressed_no_signal(canvas.tool in Canvas.SHAPE_TOOLS)
	show_tool_picker(shape_menu, tool_buttons.shapes, shape_icons)

func build_tool_picker(menu: PopupPanel, options: Array, icons: Array[Button], columns: int) -> VBoxContainer:
	menu.theme = theme
	menu.add_theme_stylebox_override("panel", style(Color("#1b1b1b"), 10, Color("#343434"), 0))
	var content := margin(menu, 8)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	content.add_child(grid)
	for entry in options:
		var mode: String = entry[0]
		var choice := icon_button(entry[2], func():
			menu.hide()
			set_tool(mode), entry[1])
		choice.set_meta("tool", mode)
		choice.accessibility_name = entry[1]
		choice.toggle_mode = true
		choice.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		choice.custom_minimum_size = Vector2(52, 48)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(choice)
		icons.append(choice)
	content.add_child(HSeparator.new())
	return content

func show_tool_picker(menu: PopupPanel, anchor: Button, icons: Array[Button]) -> void:
	for choice in icons: choice.set_pressed_no_signal(choice.get_meta("tool") == canvas.tool)
	menu.reset_size()
	var offset := Vector2(0, anchor.size.y + 6) if tools_horizontal else Vector2(anchor.size.x + 6, 0)
	menu.position = Vector2i(anchor.get_screen_position() + offset)
	menu.popup()

func build_shape_style() -> void:
	shape_style_dialog = ConfirmationDialog.new()
	shape_style_dialog.name = "ShapeStyle"
	shape_style_dialog.ok_button_text = "Apply"
	add_child(shape_style_dialog)
	var content := margin(shape_style_dialog, 16)
	content.custom_minimum_size.x = 310
	var fill_row := HBoxContainer.new()
	content.add_child(fill_row)
	shape_fill_switch = CheckBox.new()
	shape_fill_switch.text = "Fill"
	shape_fill_switch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_row.add_child(shape_fill_switch)
	shape_fill_picker = ColorPickerButton.new()
	shape_fill_picker.edit_alpha = true
	shape_fill_picker.custom_minimum_size = Vector2(62, 42)
	shape_fill_picker.tooltip_text = "Fill color and transparency"
	fill_row.add_child(shape_fill_picker)
	var outline_row := HBoxContainer.new()
	content.add_child(outline_row)
	shape_outline_switch = CheckBox.new()
	shape_outline_switch.text = "Outline"
	shape_outline_switch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outline_row.add_child(shape_outline_switch)
	shape_outline_picker = ColorPickerButton.new()
	shape_outline_picker.edit_alpha = true
	shape_outline_picker.custom_minimum_size = Vector2(62, 42)
	shape_outline_picker.tooltip_text = "Outline color and transparency"
	outline_row.add_child(shape_outline_picker)
	var width_row := HBoxContainer.new()
	content.add_child(width_row)
	var caption := label("Outline width", 13, MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	width_row.add_child(caption)
	shape_line_width = SpinBox.new()
	shape_line_width.get_line_edit().accessibility_name = "Outline width"
	shape_line_width.min_value = 1
	shape_line_width.max_value = 300
	shape_line_width.suffix = "px"
	shape_line_width.custom_minimum_size.x = 96
	width_row.add_child(shape_line_width)
	shape_style_opacity = add_slider(content, "Shape opacity", 0, 100, 100, "%", func(_value): pass)
	shape_fill_switch.toggled.connect(func(_enabled): update_shape_style_controls())
	shape_outline_switch.toggled.connect(func(_enabled): update_shape_style_controls())
	shape_style_dialog.confirmed.connect(apply_shape_style)

func update_shape_style_controls() -> void:
	shape_fill_picker.disabled = not shape_fill_switch.button_pressed
	shape_outline_picker.disabled = not shape_outline_switch.button_pressed
	shape_line_width.editable = shape_outline_switch.button_pressed
	shape_style_dialog.get_ok_button().disabled = not (shape_fill_switch.button_pressed or shape_outline_switch.button_pressed)

func open_shape_style() -> void:
	canvas.finish()
	var object: Dictionary = document.find_object(document.selection)
	var editing: bool = canvas.tool in ["select", "nodes"] and object.get("kind") in Art.SHAPES and document.can_edit(document.selection)
	shape_edit_id = object.id if editing else ""
	shape_style_open_path = object.kind == "path" if editing else canvas.tool in ["line", "arrow"]
	shape_style_dialog.title = "Shape style" if editing else "New shape style"
	var has_outline: bool = Art.outline_width(object) > 0 if editing else canvas.shape_settings.outline_enabled
	shape_fill_switch.disabled = shape_style_open_path
	shape_outline_switch.disabled = shape_style_open_path
	shape_fill_switch.set_pressed_no_signal(not shape_style_open_path and (Art.has_fill(object) if editing else canvas.shape_settings.fill_enabled))
	shape_outline_switch.set_pressed_no_signal(shape_style_open_path or has_outline)
	shape_fill_picker.color = Color(object.color) if editing else canvas.color
	shape_outline_picker.color = Color(object.get("outline_color", object.color)) if editing else canvas.shape_outline_color()
	shape_line_width.value = Art.outline_width(object) if editing and has_outline else canvas.shape_settings.outline_width
	shape_style_opacity.value = (float(object.opacity) if editing else float(canvas.shape_settings.opacity)) * 100
	update_shape_style_controls()
	shape_style_dialog.popup_centered()

func apply_shape_style() -> void:
	var fill_enabled := shape_fill_switch.button_pressed
	var outline_enabled := shape_outline_switch.button_pressed
	if not fill_enabled and not outline_enabled: return
	var opacity := shape_style_opacity.value / 100.0
	if shape_edit_id.is_empty():
		if not shape_style_open_path:
			canvas.shape_settings.fill_enabled = fill_enabled
			canvas.shape_settings.outline_enabled = outline_enabled
			if fill_enabled: set_color(shape_fill_picker.color)
		canvas.shape_settings.outline_color = shape_outline_picker.color if outline_enabled else null
		canvas.shape_settings.outline_width = shape_line_width.value
		canvas.shape_settings.opacity = opacity
		return
	var object: Dictionary = document.find_object(shape_edit_id)
	if object.is_empty() or not document.can_edit(shape_edit_id): return
	document.checkpoint()
	object.fill_enabled = fill_enabled
	object.color = "#" + shape_fill_picker.color.to_html()
	object.opacity = opacity
	if outline_enabled:
		object.outline_color = "#" + shape_outline_picker.color.to_html()
		object.outline_width = shape_line_width.value
	else:
		object.erase("outline_color")
		object.erase("outline_width")
	document.commit()

func build_selection_tray() -> void:
	selection_tray = PanelContainer.new()
	selection_tray.name = "SelectionActions"
	selection_tray.add_theme_stylebox_override("panel", style(Color("#1b1b1b"), 10, Color("#343434"), 6))
	add_child(selection_tray)
	selection_actions = BoxContainer.new()
	selection_actions.vertical = not tools_horizontal
	selection_tray.add_child(selection_actions)
	selection_actions.add_child(button("Duplicate", document.duplicate_selected, shortcut_hint("Duplicate selection", "Ctrl+D")))
	selection_actions.add_child(button("Delete", document.delete_selected, "Delete selection"))
	selection_move_button = button("Move to layer…", show_selection_move, "Move selected artwork to another layer")
	selection_actions.add_child(selection_move_button)
	build_selection_move_dialog()
	for action in selection_actions.get_children():
		action.custom_minimum_size = Vector2(92, 44)
	group_artwork_button = button("Group", change_artwork_group.bind(false), shortcut_hint("Group selected vectors", "Ctrl+G"))
	ungroup_artwork_button = button("Ungroup", change_artwork_group.bind(true), shortcut_hint("Ungroup selected vectors", "Ctrl+Shift+G"))
	selection_actions.add_child(group_artwork_button)
	selection_actions.add_child(ungroup_artwork_button)
	union_button = button("Merge vectors", union_artwork, "Join compatible artwork into one editable shape")
	union_button.custom_minimum_size.y = 44
	selection_actions.add_child(union_button)
	build_transform_menus()
	transform_button = button("Transform", show_transform_menu, "Rotate, mirror, align, space, or reorder the selection")
	transform_button.custom_minimum_size.y = 44
	selection_actions.add_child(transform_button)
	PopupTouch.watch_launcher(transform_button)
	selected_shape_style = button("Style", open_shape_style, "Edit the selected shape’s fill, outline, and opacity")
	selection_actions.add_child(selected_shape_style)
	paint_inside_button = button("Paint inside", func(): set_paint_limit(true), "Limit brushwork to this selection")
	selection_actions.add_child(paint_inside_button)
	deselect_button = icon_button("M4 9V4H9M17 4H22V9M22 17V22H17M9 22H4V17M9 9L17 17M17 9L9 17",
		canvas.clear_selection, "Deselect")
	selection_actions.add_child(deselect_button)
	shape_actions = BoxContainer.new()
	shape_actions.vertical = not tools_horizontal
	selection_tray.add_child(shape_actions)
	shape_actions.add_child(button("Style", open_shape_style, "Set fill, outline, and opacity for new shapes"))
	finish_path_button = button("Finish", func(): canvas.commit_path(false), shortcut_hint("Finish an open path", "Enter"))
	close_path_button = button("Close", func(): canvas.commit_path(true), shortcut_hint("Close and fill the path", "Shift+Enter"))
	shape_actions.add_child(finish_path_button)
	shape_actions.add_child(close_path_button)
	paint_actions = HBoxContainer.new()
	selection_tray.add_child(paint_actions)
	paint_actions.add_child(button("Paint freely", func(): set_paint_limit(false), "Turn off the selection’s paint limit"))
	node_actions = BoxContainer.new()
	node_actions.vertical = not tools_horizontal
	selection_tray.add_child(node_actions)
	add_node_button = button("Add node", toggle_add_node, "Tap an edge to add a node")
	add_node_button.toggle_mode = true
	add_node_button.custom_minimum_size = Vector2(96, 44)
	node_actions.add_child(add_node_button)
	node_actions.add_child(label("Spread", 13, MUTED))
	node_spread_slider = TouchSlider.new()
	node_spread_slider.name = "NodeSpread"
	node_spread_slider.accessibility_name = "Node spread"
	node_spread_slider.tooltip_text = "At 0%, move just the selected node. Raise Spread to bend nearby points."
	node_spread_slider.custom_minimum_size = Vector2(100, 44)
	node_spread_slider.max_value = 100
	node_spread_slider.step = 5
	node_spread_slider.value_changed.connect(change_node_spread)
	node_spread_slider.drag_started.connect(func(): node_spread_dragging = true)
	node_spread_slider.drag_ended.connect(func(changed):
		node_spread_dragging = false
		if changed: save_node_spread())
	node_actions.add_child(node_spread_slider)
	node_spread_readout = label("—", 13, MUTED)
	node_spread_readout.custom_minimum_size.x = 40
	node_spread_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	node_actions.add_child(node_spread_readout)
	canvas.path_changed.connect(update_selection_actions)
	canvas.node_mode_changed.connect(update_selection_actions)
	build_shape_style()
	selection_tray.hide()

func toggle_add_node() -> void:
	canvas.set_add_node_mode(not canvas.adding_node)
	if canvas.adding_node: notify("Tap an edge of a path, polygon, or brush stroke.")

func change_node_spread(percent: float) -> void:
	var object: Dictionary = document.find_object(document.selection)
	if object.get("kind") not in ["stroke", "path", "polygon"] or not document.can_edit(document.selection): return
	if object.kind == "stroke": canvas.stroke_node_spread = percent / 100.0
	else: canvas.path_node_spread = percent / 100.0
	node_spread_readout.text = "%d%%" % roundi(percent)
	if not node_spread_dragging: save_node_spread()

func save_node_spread() -> void:
	settings.set_value("workspace", "stroke_node_spread", canvas.stroke_node_spread)
	settings.set_value("workspace", "path_node_spread", canvas.path_node_spread)
	if settings.save("user://preferences.cfg") != OK:
		notify("Could not save the Spread setting.")

func refresh_node_spread() -> void:
	var object: Dictionary = document.find_object(document.selection)
	var available: bool = object.get("kind") in ["stroke", "path", "polygon"] and document.can_edit(document.selection)
	node_spread_slider.editable = available
	if available:
		var percent: int = roundi(canvas.node_spread_for(object) * 100.0)
		node_spread_slider.set_value_no_signal(percent)
		node_spread_readout.text = "%d%%" % percent
	else:
		node_spread_readout.text = "—"

func change_artwork_group(ungroup: bool) -> void:
	if project_loading_overlay.visible: return
	if canvas.tool != "select" and canvas.tool not in Canvas.AREA_TOOLS: return
	canvas.finish()
	var merge_reason := ""
	if not ungroup and merge_on_group:
		merge_reason = await merge_vector_selection()
		if merge_reason.is_empty():
			finish_vector_merge()
			return
	var changed: bool = document.ungroup_selected() if ungroup else document.group_selected()
	if changed:
		canvas.selected_area.clear()
		canvas.refresh_selection()
		update_selection_actions()
		notify("Grouped. " + merge_reason if not merge_reason.is_empty() else (
			"Artwork ungrouped." if ungroup else "Grouped. Drag the corner to resize."))
	else:
		notify("Select grouped artwork first." if ungroup else "Select at least two separate vector objects or groups.")

func build_transform_menus() -> void:
	transform_menu = PopupMenu.new()
	transform_menu.name = "TransformMenu"
	for entry in [["Rotate 90° clockwise", 0], ["Rotate 90° counterclockwise", 1],
		["Flip horizontally", 2], ["Flip vertically", 3]]:
		transform_menu.add_item(entry[0], entry[1])
	transform_menu.add_separator()
	transform_menu.add_check_item("Snap rotation to 15°", 4)
	transform_menu.add_check_item("Snap moves to canvas", 6)
	transform_menu.add_item("Align & arrange…", 5)
	transform_menu.add_theme_constant_override("v_separation", 16)
	transform_menu.id_pressed.connect(transform_action)
	add_child(transform_menu)

	arrange_menu = PopupMenu.new()
	arrange_menu.name = "ArrangeMenu"
	arrange_menu.add_theme_constant_override("v_separation", 16)
	arrange_menu.add_check_item("Align to canvas", 10)
	arrange_menu.add_separator()
	var labels := ["Align left", "Center horizontally", "Align right", "Align top",
		"Center vertically", "Align bottom", "Space horizontally", "Space vertically"]
	for index in labels.size(): arrange_menu.add_item(labels[index], index)
	arrange_menu.add_separator()
	for entry in [["Bring to front", 20], ["Send to back", 21], ["Bring forward", 22], ["Send backward", 23]]:
		arrange_menu.add_item(entry[0], entry[1])
	arrange_menu.hide_on_checkable_item_selection = false
	arrange_menu.id_pressed.connect(arrange_action)
	add_child(arrange_menu)

func show_transform_menu() -> void:
	if canvas.transformable_items().is_empty(): return
	transform_menu.set_item_checked(transform_menu.get_item_index(4), canvas.snap_rotation)
	transform_menu.set_item_checked(transform_menu.get_item_index(6), canvas.snap_to_canvas)
	show_edit_popup(transform_menu)

func show_edit_popup(menu: PopupMenu) -> void:
	menu.reset_size()
	var anchor := transform_button.get_screen_position() if transform_button.is_visible_in_tree() else get_screen_position() + Vector2(20, 75)
	if transform_button.is_visible_in_tree():
		anchor += Vector2(0.0, transform_button.size.y + 4) if tools_horizontal else Vector2(transform_button.size.x + 4, 0.0)
	menu.position = Vector2i(anchor)
	menu.popup()

func transform_action(id: int) -> void:
	canvas.finish()
	match id:
		0: canvas.turn_selection(PI / 2.0)
		1: canvas.turn_selection(-PI / 2.0)
		2: canvas.turn_selection(0.0, 1)
		3: canvas.turn_selection(0.0, 2)
		4:
			canvas.snap_rotation = not canvas.snap_rotation
			save_input_preference("snap_rotation", canvas.snap_rotation)
		5: show_arrange_menu.call_deferred()
		6:
			canvas.snap_to_canvas = not canvas.snap_to_canvas
			save_input_preference("snap_to_canvas", canvas.snap_to_canvas)

func update_arrange_actions() -> void:
	var units := {}
	for item in canvas.transformable_items(): units[document.layout_unit(item.object)] = true
	arrange_menu.set_item_checked(arrange_menu.get_item_index(10), arrange_to_canvas)
	for id in range(8):
		var minimum := 3 if id >= 6 else (1 if arrange_to_canvas else 2)
		arrange_menu.set_item_disabled(arrange_menu.get_item_index(id), units.size() < minimum)

func show_arrange_menu() -> void:
	update_arrange_actions()
	show_edit_popup(arrange_menu)

func arrange_action(id: int) -> void:
	if id == 10:
		arrange_to_canvas = not arrange_to_canvas
		update_arrange_actions()
		return
	canvas.finish()
	var items: Array[Dictionary] = canvas.transformable_items()
	var changed := false
	if id < 6:
		changed = document.align_items(items, id, arrange_to_canvas)
		if not changed: notify("The selection is already aligned.")
	elif id < 8:
		changed = document.distribute_items(items, id - 6)
		if not changed: notify("The selection already has even spacing.")
	else:
		changed = document.stack_items(items, id - 20)
		if not changed: notify("No change to drawing order. Stack commands work on ordinary vector layers.")
	if changed:
		canvas.selected_area.clear()
		canvas.refresh_selection()

func union_artwork() -> void:
	if project_loading_overlay.visible: return
	canvas.finish()
	var reason: String = await merge_vector_selection()
	if not reason.is_empty():
		notify(reason)
		return
	finish_vector_merge()

func merge_vector_selection() -> String:
	var items: Array[Dictionary] = document.selected_items()
	var reason: String = document.union_selection_reason(items)
	if not reason.is_empty(): return reason
	var units := items.size() * items.size()
	for item in items: units += object_work_units(item.object)
	return await run_indicated_operation("merge", "Merging vectors…", units, 5500,
		document.union_selected.bind(canvas.solo_layer_id))

func finish_vector_merge() -> void:
	canvas.selected_area.clear()
	canvas.refresh_selection()
	notify("Joined into one vector shape.")

func update_selection_actions() -> void:
	var selection_tool: bool = canvas.tool == "select" or canvas.tool in Canvas.AREA_TOOLS
	var items: Array[Dictionary] = []
	if selection_tool: items = document.selected_items()
	var can_act := not items.is_empty()
	var grouping: Dictionary = document.grouping_actions(items)
	for id in [8, 9, 11, 12, 14, 15, 16]:
		var index := workspace_menu.get_item_index(id)
		var available: bool = grouping.group if id == 11 else grouping.ungroup if id == 12 else (items.size() > 1 if id == 15 else can_act)
		if index >= 0: workspace_menu.set_item_disabled(index, not available)
	var is_select: bool = workspace_options.contextual_actions and selection_tool and panels.Tools.visible
	var is_shape: bool = canvas.tool in Canvas.SHAPE_TOOLS and panels.Tools.visible
	var is_paint: bool = workspace_options.contextual_actions and canvas.tool == "brush" and canvas.clip_enabled and panels.Tools.visible
	selection_actions.visible = is_select
	group_artwork_button.visible = grouping.group
	group_artwork_button.text = "Group & merge" if merge_on_group else "Group"
	ungroup_artwork_button.visible = grouping.ungroup
	union_button.visible = items.size() > 1
	var merge_reason: String = document.union_selection_reason(items)
	union_button.tooltip_text = merge_reason if not merge_reason.is_empty() else "Join compatible artwork into one editable shape"
	shape_actions.visible = is_shape
	paint_actions.visible = is_paint
	node_actions.visible = canvas.tool == "nodes" and panels.Tools.visible
	if node_actions.visible: refresh_node_spread()
	add_node_button.set_pressed_no_signal(canvas.adding_node)
	selection_tray.visible = is_select or is_shape or is_paint or node_actions.visible
	paint_inside_button.visible = can_act or (selection_tool and not canvas.selected_area.is_empty())
	selected_shape_style.visible = can_act and canvas.tool == "select" and document.find_object(document.selection).get("kind") in Art.SHAPES
	deselect_button.visible = selection_tool and (not canvas.selected_area.is_empty() or not document.area_selection.is_empty())
	selection_actions.get_child(0).disabled = not can_act
	selection_actions.get_child(1).disabled = not can_act
	selection_move_button.disabled = not can_act
	transform_button.visible = can_act
	var pen_path: bool = canvas.tool == "path"
	finish_path_button.visible = pen_path
	close_path_button.visible = pen_path
	finish_path_button.disabled = canvas.path_points.size() < 2
	close_path_button.disabled = canvas.path_points.size() < 3
	if selection_tray.visible:
		selection_tray.reset_size()
		position_selection_tray()

func position_selection_tray() -> void:
	if not is_instance_valid(selection_tray) or not selection_tray.visible: return
	var rail: Rect2 = panels.Tools.get_global_rect()
	var active_button: Control = tool_buttons.shapes if shape_actions.visible else (
		tool_buttons.brush if paint_actions.visible else tool_buttons.select)
	if node_actions.visible: active_button = tool_buttons.nodes
	var anchor := active_button.get_global_rect()
	var tray_size := selection_tray.get_combined_minimum_size()
	var inset := 8.0
	var top := 80.0
	var bottom := size.y - FOOTER_HEIGHT - 4.0
	var target: Vector2
	if tools_horizontal:
		var below := bottom - rail.end.y
		var above := rail.position.y - top
		target = Vector2(anchor.position.x, rail.end.y + inset if below >= above else rail.position.y - tray_size.y - inset)
	else:
		var right := size.x - rail.end.x
		var left := rail.position.x
		target = Vector2(rail.end.x + inset if right >= left else rail.position.x - tray_size.x - inset, anchor.get_center().y - tray_size.y * 0.5)
	target -= global_position
	selection_tray.position = target.clamp(
		Vector2(inset, top),
		Vector2(maxf(inset, size.x - tray_size.x - inset), maxf(top, bottom - tray_size.y)))

func set_manual_tool_orientation(horizontal: bool) -> void:
	set_tool_orientation(horizontal)
	queue_dock_reflow(panels.Tools)
	save_layout()

func set_tool_orientation(horizontal: bool) -> void:
	if tools_horizontal == horizontal: return
	tools_horizontal = horizontal
	tool_grid.columns = tool_grid.get_child_count() if tools_horizontal else 1
	selection_actions.vertical = not horizontal
	shape_actions.vertical = not horizontal
	node_actions.vertical = not horizontal
	selection_tray.reset_size()
	panels.Tools.preferred_size = Vector2.ZERO
	panels.Tools.apply_preferred_size.call_deferred()
	position_selection_tray.call_deferred()
	settings.set_value("workspace", "horizontal_tools", tools_horizontal)
	if horizontal_toolbar_check: horizontal_toolbar_check.set_pressed_no_signal(horizontal)

func set_color(value: Color, remember := false) -> void:
	canvas.color = value
	if is_instance_valid(brush_test_canvas): brush_test_canvas.color = value
	if is_instance_valid(brush_editor_preview):
		brush_editor_preview.ink = value
		brush_editor_preview.rebuild()
	if color_picker.color != value: color_picker.color = value
	color_preview_style.bg_color = value
	if color_channels.visible: color_channels.set_color(value, color_picker.hue)
	var hex := "#" + value.to_html(false).to_upper()
	color_hex.text = hex
	top_color.tooltip_text = "Color · " + hex
	top_color.add_theme_stylebox_override("normal", style(value, 9, Color("#ffffff66"), 0))
	top_color.add_theme_stylebox_override("hover", style(value, 9, ACCENT, 0))
	if remember: remember_color(value)
	update_swatch_selection()

func on_selected(object: Dictionary) -> void:
	if object.has("picked_color"):
		set_color(object.picked_color, true)
		return
	refresh_layer_selection()
	if object.get("kind") == "text":
		text_edit.text = object.text
		canvas.text_content = object.text
		choose_typography_font(object.font, object.get("font_label", ""))
		font_size.value = object.font_size
		set_color(Color(object.color))
		panels.Typography.show()
	else:
		panels.Typography.visible = canvas.tool == "text"

func apply_text() -> void:
	var object = document.find_object(document.selection)
	if object.is_empty() or object.kind != "text" or not document.can_edit(document.selection):
		notify("Select existing text first, or tap the canvas to add new text.")
		return
	document.checkpoint()
	object.text = text_edit.text
	Fonts.apply_to_text(object, canvas.text_font)
	object.font_size = canvas.text_size
	object.color = "#" + canvas.color.to_html(false)
	document.commit()
	remember_color(canvas.color)

func rename_document() -> void:
	var next = title_edit.text.strip_edges()
	if next.is_empty(): title_edit.text = document.title; return
	if next == document.title: return
	document.checkpoint()
	document.title = next
	document.commit()

func on_document_changed() -> void:
	if not canvas: return
	canvas.refresh_selection()
	if document.content_on_commit.has("layer_flag"):
		refresh_layer_selection(document.content_on_commit.layer)
	elif document.content_on_commit.has("group_ids"):
		update_selection_actions()
	elif document.content_on_commit.has("layer_order"):
		rebuild_layers([], false)
	else:
		page_dimensions.text = "%d × %d" % [roundi(document.width), roundi(document.height)]
		title_edit.text = document.title
		var previews: Array = document.content_on_commit.get("layers", [])
		if document.content_on_commit.has("layer"): previews = [document.content_on_commit.layer]
		if not document.appended_on_commit.is_empty(): previews = [document.layers[document.active].id]
		if document.content_on_commit.get("page_resize", false): previews = []
		if not previews.is_empty() and layer_rows.size() == document.layers.size() \
				and previews.all(func(id): return layer_rows.has(id)):
			refresh_layer_selection("", previews)
			queue_layer_preview_refresh()
		else:
			rebuild_layers(previews)
	undo_button.disabled = document.history.is_empty()
	redo_button.disabled = document.future.is_empty()
	save_label.text = "Unsaved changes" if document.dirty else "Saved locally"

func refresh_layer_selection(changed_id := "", previews: Array = []) -> void:
	var current: Dictionary = document.layers[document.active]
	sync_active_solo_layer()
	canvas.refresh_background_cache(highlighted_layer_id)
	var affected := {highlighted_layer_id: true, current.id: true, changed_id: true}
	for id in previews: affected[id] = true
	if layer_rows_solo_id != canvas.solo_layer_id:
		for layer in document.layers:
			if layer_rows.has(layer.id): update_layer_row(layer_rows[layer.id], layer, layer.id == current.id, layer.id in previews)
	else:
		for id in affected:
			if not layer_rows.has(id): continue
			var index := find_layer_index(id)
			if index >= 0: update_layer_row(layer_rows[id], document.layers[index], id == current.id, id in previews)
	highlighted_layer_id = current.id
	layer_rows_solo_id = canvas.solo_layer_id
	refresh_layer_tool_state()
	refresh_layer_controls()

func sync_active_solo_layer() -> void:
	canvas.validate_solo_layer()
	if not canvas.solo_layer_id.is_empty():
		var layer: Dictionary = document.layers[document.active]
		canvas.set_solo_layer(layer.id if layer.visible else "")

func refresh_layer_tool_state() -> void:
	if canvas.tool_unavailable_reason(canvas.tool).is_empty():
		refresh_tool_buttons()
		update_selection_actions()
	else:
		activate_tool("brush" if canvas.tool_unavailable_reason("brush").is_empty() else "select")

func rebuild_layers(previews: Array = [], refresh_all_previews := true) -> void:
	if not layer_list: return
	sync_active_solo_layer()
	refresh_layer_tool_state()
	layer_scroll.cancel_drag()
	var current_rows := {}
	for index in range(document.layers.size() - 1, -1, -1):
		var layer: Dictionary = document.layers[index]
		var row: PanelContainer = layer_rows.get(layer.id)
		var refresh_preview: bool = not row or layer.id in previews or (previews.is_empty() and refresh_all_previews)
		if not row: row = create_layer_row(layer.id)
		current_rows[layer.id] = row
		var position_in_list: int = document.layers.size() - 1 - index
		if row.get_index() != position_in_list: layer_list.move_child(row, position_in_list)
		update_layer_row(row, layer, index == document.active, refresh_preview)
	for layer_id in layer_rows:
		if current_rows.has(layer_id): continue
		layer_list.remove_child(layer_rows[layer_id])
		layer_rows[layer_id].queue_free()
	layer_rows = current_rows
	highlighted_layer_id = document.layers[document.active].id
	layer_rows_solo_id = canvas.solo_layer_id
	refresh_layer_controls()
	queue_layer_preview_refresh()

func refresh_layer_controls() -> void:
	if document.layers.is_empty() or not opacity_drag_layer.is_empty(): return
	var layer: Dictionary = document.layers[document.active]
	var percent := roundi(float(layer.get("opacity", 1.0)) * 100.0)
	layer_opacity_slider.set_value_no_signal(percent)
	layer_opacity_label.text = "Opacity %d%%" % percent
	layer_opacity_slider.editable = not layer.locked
	alpha_lock_button.disabled = layer.locked
	alpha_lock_button.set_pressed_no_signal(layer.get("alpha_locked", false))
	var is_solo: bool = canvas.solo_layer_id == layer.id
	layer_solo_button.set_pressed_no_signal(is_solo)
	layer_solo_button.disabled = not layer.visible
	layer_solo_button.tooltip_text = "Restore layer visibility" if is_solo else "Solo the active layer for editing"

func toggle_active_layer_solo() -> void:
	canvas.finish()
	var layer: Dictionary = document.layers[document.active]
	if not layer.visible: return
	canvas.set_solo_layer("" if canvas.solo_layer_id == layer.id else layer.id)
	document.selection = ""
	refresh_layer_selection()
	canvas.refresh_selection()

func begin_layer_opacity_drag() -> void:
	canvas.finish()
	if not document.layers[document.active].locked:
		opacity_drag_layer = document.layers[document.active].id

func change_layer_opacity(percent: float) -> void:
	layer_opacity_label.text = "Opacity %d%%" % roundi(percent)
	if opacity_drag_layer.is_empty():
		document.set_layer_opacity(document.active, percent / 100.0)
		refresh_layer_controls()
	else:
		canvas.preview_layer_opacity(opacity_drag_layer, percent / 100.0)

func end_layer_opacity_drag(changed: bool) -> void:
	if opacity_drag_layer.is_empty(): return
	var index: int = document.layer_index(opacity_drag_layer)
	var opacity := layer_opacity_slider.value / 100.0
	opacity_drag_layer = ""
	canvas.preview_layer_opacity("", 1.0)
	if changed: document.set_layer_opacity(index, opacity)
	refresh_layer_controls()

func toggle_alpha_lock() -> void:
	canvas.finish()
	var layer: Dictionary = document.layers[document.active]
	if layer.locked: return
	document.set_alpha_lock(document.active, not layer.get("alpha_locked", false))
	if layer.get("alpha_locked", false):
		notify("Alpha lock is on. Brush strokes stay inside solid vector artwork on this layer.")

func merge_layer_stack(visible: bool) -> void:
	canvas.finish()
	var indices: Array[int]
	if visible: indices = document.visible_layers()
	else: indices = [document.active - 1, document.active]
	if document.merge_layers(indices):
		notify("Merged %d layers. Undo restores the stack." % indices.size())
	else:
		notify("Choose at least two visible, unlocked layers to merge.")

func create_layer_row(layer_id: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var content := HBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 1)
	row.add_child(content)

	var select := layer_icon_button(func(): select_layer(layer_id), 84)
	select.name = "SelectLayer"
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var identity := HBoxContainer.new()
	identity.name = "Identity"
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_theme_constant_override("separation", 8)
	select.add_child(identity)
	identity.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var thumb := LayerThumbnail.new()
	thumb.name = "Thumbnail"
	thumb.custom_minimum_size = Vector2(38, 38)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_child(thumb)
	var labels := VBoxContainer.new()
	labels.name = "Labels"
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("separation", 2)
	identity.add_child(labels)
	var title := label("", 13, Color("#efefef"))
	title.name = "Title"
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(title)
	var detail := label("", 11, Color("#ababab"))
	detail.name = "Detail"
	detail.clip_text = true
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(detail)
	content.add_child(select)

	var visibility := layer_icon_button(func(): toggle_layer_flag(layer_id, "visible"), 32)
	visibility.name = "Visibility"
	content.add_child(visibility)
	var lock := layer_icon_button(func(): toggle_layer_flag(layer_id, "locked"), 32)
	lock.name = "Lock"
	content.add_child(lock)
	var handle := TextureRect.new()
	handle.name = "DragHandle"
	handle.texture = layer_icons.grip
	handle.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	handle.custom_minimum_size.x = 25
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	handle.tooltip_text = "Drag to reorder layer"
	content.add_child(handle)
	for surface in [row, select, handle]:
		layer_scroll.watch_reorder_surface(surface, layer_id, row)
	layer_list.add_child(row)
	return row

func layer_icon_button(action: Callable, width: float) -> Button:
	var control := button("", action)
	control.custom_minimum_size = Vector2(width, 46)
	control.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 5, Color.TRANSPARENT, 0))
	control.add_theme_stylebox_override("hover", style(Color("#353535"), 5, Color.TRANSPARENT, 0))
	control.add_theme_stylebox_override("pressed", style(Color("#414141"), 5, Color.TRANSPARENT, 0))
	control.add_theme_stylebox_override("focus", style(Color.TRANSPARENT, 5, ACCENT, 0))
	return control

func update_layer_row(row: PanelContainer, layer: Dictionary, active: bool, refresh_preview: bool) -> void:
	row.set_meta("locked", layer.locked)
	var row_style := layer_row_styles[int(active)]
	if row.get_theme_stylebox("panel") != row_style:
		row.add_theme_stylebox_override("panel", row_style)
	var select: Button = row.get_node("Content/SelectLayer")
	var title: Label = select.get_node("Identity/Labels/Title")
	var detail: Label = select.get_node("Identity/Labels/Detail")
	var thumb = select.get_node("Identity/Thumbnail")
	var count: int = layer.objects.size()
	var detail_text := "Empty" if count == 0 else "%d %s" % [count, "object" if count == 1 else "objects"]
	if layer.get("type", "vector") == "paint": detail_text = "Paint layer"
	elif layer.get("type", "vector") == "composite": detail_text = "Mixed artwork"
	if layer.get("alpha_locked", false): detail_text = "Alpha lock"
	if canvas.solo_layer_id == layer.id: detail_text = "Solo · " + detail_text
	var opacity := roundi(float(layer.get("opacity", 1.0)) * 100.0)
	if opacity < 100: detail_text = "%d%% · %s" % [opacity, detail_text]
	title.text = layer.name
	detail.text = detail_text
	var shown: bool = canvas.layer_is_visible(layer)
	title.modulate.a = 1.0 if shown else 0.58
	detail.modulate.a = title.modulate.a
	select.tooltip_text = "%s · %s" % [layer.name, detail_text]
	thumb.modulate.a = 1.0 if shown else 0.45
	if refresh_preview: thumb.update_content(layer, Vector2(document.width, document.height))
	var eye: Button = row.get_node("Content/Visibility")
	eye.icon = layer_icons.eye if layer.visible else layer_icons.hidden
	eye.tooltip_text = ("Hide " if layer.visible else "Show ") + layer.name
	var lock: Button = row.get_node("Content/Lock")
	lock.icon = layer_icons.locked if layer.locked else layer_icons.unlocked
	lock.tooltip_text = ("Unlock " if layer.locked else "Lock ") + layer.name
	var handle: Control = row.get_node("Content/DragHandle")
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE if layer.locked else Control.MOUSE_FILTER_STOP
	handle.modulate.a = 0.35 if layer.locked else 1.0

func queue_layer_preview_refresh() -> void:
	if layer_preview_refresh_queued: return
	layer_preview_refresh_queued = true
	refresh_layer_previews.call_deferred()

func refresh_layer_previews() -> void:
	layer_preview_refresh_queued = false
	var view: Rect2 = layer_scroll.get_global_rect()
	var open: bool = layer_scroll.is_visible_in_tree() and (not is_instance_valid(project_home) or not project_home.visible)
	for row in layer_rows.values():
		row.get_node("Content/SelectLayer/Identity/Thumbnail").set_artwork_visible(open and view.intersects(row.get_global_rect()))

func find_layer_index(layer_id: String) -> int:
	return document.layer_index(layer_id)

func select_layer(layer_id: String) -> void:
	canvas.finish()
	var index := find_layer_index(layer_id)
	if index < 0: return
	document.active = index
	document.selection = ""
	canvas.selected_area.clear()
	layer_scroll.cancel_drag()
	refresh_layer_selection()
	canvas.refresh_selection()

func toggle_layer_flag(layer_id: String, key: String) -> void:
	canvas.finish()
	var index := find_layer_index(layer_id)
	document.toggle_layer_flag(index, key)

func toggle_merge_touching() -> void:
	canvas.finish()
	var enabled: bool = not document.layers[document.active].get("merge_touching", false)
	if document.set_merge_touching(document.active, enabled):
		notify("New matching shapes and solid ink will merge when they touch." if enabled else "Merge touching is off.")
	else:
		notify("Merge touching needs an unlocked vector layer.")

func open_layer_actions() -> void:
	var layer: Dictionary = document.layers[document.active]
	var locked: bool = layer.locked
	var merge_index := layer_actions.get_item_index(12)
	layer_actions.set_item_disabled(merge_index, locked or layer.get("type", "vector") != "vector")
	layer_actions.set_item_checked(merge_index, layer.get("merge_touching", false))
	for id in [0, 3, 10]: layer_actions.set_item_disabled(layer_actions.get_item_index(id), locked)
	layer_actions.set_item_checked(layer_actions.get_item_index(10), document.layers[document.active].get("alpha_locked", false))
	layer_actions.set_item_disabled(layer_actions.get_item_index(4), locked or document.layers.size() <= 1)
	layer_actions.set_item_disabled(layer_actions.get_item_index(6), locked or document.active >= document.layers.size() - 1)
	layer_actions.set_item_disabled(layer_actions.get_item_index(7), locked or document.active <= 0)
	var neighbors: Array[int] = [document.active - 1, document.active]
	layer_actions.set_item_disabled(layer_actions.get_item_index(8), not document.can_merge_layers(neighbors))
	layer_actions.set_item_disabled(layer_actions.get_item_index(9), not document.can_merge_layers(document.visible_layers()))
	layer_actions.reset_size()
	layer_actions.position = Vector2i(layer_actions_button.get_screen_position() +
		Vector2(layer_actions_button.size.x - layer_actions.size.x, layer_actions_button.size.y + 4))
	layer_actions.popup()

func edit_layer_opacity() -> void:
	var layer: Dictionary = document.layers[document.active]
	if layer.locked: return
	var dialog := ConfirmationDialog.new()
	dialog.name = "LayerOpacity"
	dialog.title = "Layer opacity"
	dialog.ok_button_text = "Apply"
	var box := margin(dialog, 16)
	box.custom_minimum_size.x = 320
	box.add_child(label(layer.name, 16))
	var opacity_value := SpinBox.new()
	opacity_value.get_line_edit().accessibility_name = "Layer opacity"
	opacity_value.name = "OpacityPercent"
	opacity_value.min_value = 0
	opacity_value.max_value = 100
	opacity_value.suffix = "%"
	opacity_value.value = float(layer.get("opacity", 1.0)) * 100.0
	box.add_child(opacity_value)
	dialog.confirmed.connect(func():
		canvas.finish()
		for index in document.layers.size():
			if document.layers[index].id == layer.id:
				document.set_layer_opacity(index, opacity_value.value / 100.0)
				break
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func reorder_layer(direction: int) -> void:
	document.move_layer(document.active, document.active + direction)

func drop_layer(id: String, slot: int) -> void:
	var count: int = document.layers.size()
	if slot < 0 or slot > count: return
	for source in count:
		if document.layers[source].id != id: continue
		# The panel runs top to bottom while rendering runs bottom to top.
		var destination := count - slot
		if destination > source: destination -= 1
		document.move_layer(source, destination)
		return

func prompt_text(title_text: String, initial: String, callback: Callable) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = title_text
	var entry = LineEdit.new()
	entry.accessibility_name = title_text
	entry.text = initial
	entry.custom_minimum_size = Vector2(330, 46)
	entry.max_length = 120
	dialog.add_child(entry)
	add_child(dialog)
	dialog.confirmed.connect(func(): callback.call(entry.text.strip_edges()); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(390, 150))
	if OS.has_feature("android"):
		text_entry.request_tablet_entry.call_deferred(entry)
	else:
		entry.grab_focus()
		entry.select_all()

func rename_layer() -> void:
	var layer = document.layers[document.active]
	if layer.locked: return
	prompt_text("Rename layer", layer.name, func(value):
		document.rename_layer(document.layer_index(layer.id), value))

func delete_layer() -> void:
	if document.layers.size() <= 1: notify("Keep at least one layer in the document."); return
	var layer: Dictionary = document.layers[document.active]
	if layer.locked: return
	var dialog = ConfirmationDialog.new()
	dialog.title = "Delete layer?"
	dialog.dialog_text = "Delete “%s” and its artwork? You can undo this." % layer.name
	add_child(dialog)
	dialog.confirmed.connect(func():
		canvas.finish()
		document.remove_layer(document.layer_index(layer.id))
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func build_file_dialogs() -> void:
	import_image_dialog = FileDialog.new()
	import_image_dialog.title = "Import image as layer"
	import_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_image_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Images"])
	import_image_dialog.use_native_dialog = true
	import_image_dialog.file_selected.connect(import_image)
	add_child(import_image_dialog)
	save_dialog = FileDialog.new()
	save_dialog.title = "Save Havu project"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.havu ; Havu illustration"])
	save_dialog.use_native_dialog = true
	save_dialog.file_selected.connect(write_project)
	add_child(save_dialog)
	open_dialog = FileDialog.new()
	open_dialog.title = "Open illustration"
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.filters = PackedStringArray(["*.havu ; Havu illustration"])
	open_dialog.use_native_dialog = true
	open_dialog.file_selected.connect(open_project)
	add_child(open_dialog)
	export_dialog = FileDialog.new()
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.use_native_dialog = true
	export_dialog.file_selected.connect(write_export)
	add_child(export_dialog)

func safe_name() -> String:
	return document.title.validate_filename().replace(" ", "-").to_lower()

func save_project() -> void:
	canvas.finish()
	rename_document()
	if file_path.is_empty(): save_as()
	else: write_project(file_path)

func save_as() -> void:
	canvas.finish()
	rename_document()
	save_dialog.current_file = safe_name() + ".havu"
	save_dialog.popup_centered_ratio(0.75)

func write_project(path: String) -> void:
	if project_loading_overlay.visible: return
	await run_indicated_operation("save", "Saving project…", document_work_units(), 18000, save_project_file.bind(path))

func save_project_file(path: String) -> void:
	if not path.begins_with("content://") and not path.ends_with(".havu"): path += ".havu"
	var encoded: PackedByteArray = document.encode_for_save()
	var result = document.save_encoded_to(path, encoded)
	if result != OK: notify("Save failed: %s. Your artwork remains open; try Save as." % error_string(result)); return
	file_path = path
	remember_project(path)
	save_label.text = "Project saved"
	preserve_recovery(encoded)
	notify("Saved “%s”" % path.get_file())

func preserve_recovery(encoded := PackedByteArray()) -> bool:
	if not session_active: return true
	var revision: int = document.revision
	canvas.finish()
	rename_document()
	var was_dirty = document.dirty
	var result: Error = document.save_encoded_to(RECOVERY_PATH, encoded) \
		if not encoded.is_empty() and revision == document.revision else document.save_to(RECOVERY_PATH)
	document.dirty = was_dirty
	if result != OK:
		notify("Recovery could not be saved: %s" % error_string(result))
		return false
	recovered_revision = document.revision
	settings.set_value("session", "title", document.title)
	settings.set_value("session", "file_path", file_path)
	settings.set_value("session", "dirty", was_dirty)
	if settings.save("user://preferences.cfg") == OK: history_preferences_dirty = false
	return true

func autosave() -> void:
	if not session_active or project_home.visible or project_loading_overlay.visible: return
	if canvas.drawing or canvas.moving or canvas.resizing or canvas.node_index >= 0: return
	if Time.get_ticks_msec() - canvas.last_brush_activity < 1000: return
	if recovered_revision == document.revision:
		if history_preferences_dirty and settings.save("user://preferences.cfg") == OK: history_preferences_dirty = false
		return
	if not preserve_recovery(): return
	if document.dirty: save_label.text = "Recovery saved · save project to keep a file"

func open_project(path: String) -> void:
	await load_project(path, false)

func load_project(path: String, resuming: bool) -> void:
	if project_loading_overlay.visible: return
	canvas.finish()
	canvas.reset_touch()
	undo_button.stop_hold()
	show_work_indicator("Restoring project…" if resuming else "Opening project…")
	await presented_project_frame()

	# Keep Android file access and project validation on the engine's main thread.
	var result := Document.read_project(path)
	if result.has("error"):
		finish_project_load(false, result.error)
		return
	if not resuming and not preserve_before_switch():
		finish_project_load(false)
		return

	document.restore(result.project, false)
	document.history.clear()
	document.future.clear()
	if resuming:
		file_path = str(settings.get_value("session", "file_path", ""))
		document.dirty = bool(settings.get_value("session", "dirty", true))
	else:
		var archived := path.begins_with("user://recovered-")
		document.dirty = archived
		file_path = "" if archived else path
		if not archived: remember_project(path)
	canvas.sync_artwork()
	on_document_changed()
	enter_project()
	await presented_project_frame()
	finish_project_load(true, "" if resuming else "Opened “%s”" % document.title)

func object_work_units(object: Dictionary) -> int:
	var units := 4
	units += object.get("points", []).size() + object.get("vertices", []).size()
	if object.kind == "image": units += ceili(object.image_data.length() / 96.0)
	return units

func document_work_units() -> int:
	var units := 0
	for layer in document.layers:
		for object in layer.objects: units += object_work_units(object)
	return units

func show_work_indicator(caption: String) -> void:
	project_loading_label.text = caption
	project_loading_overlay.show()
	project_loading_overlay.grab_focus()

func run_indicated_operation(action: String, caption: String, units: int,
		estimate_threshold: int, operation: Callable) -> Variant:
	# A synchronous operation cannot show a frame after a timer has already
	# expired. Estimate from document size and refine it with measured runtime.
	var rate: float = operation_time_per_unit.get(action, BUSY_FEEDBACK_MS / estimate_threshold)
	var show := units * rate >= BUSY_FEEDBACK_MS or units >= estimate_threshold * 2
	if show:
		undo_button.stop_hold()
		show_work_indicator(caption)
		await presented_project_frame()
	var started := Time.get_ticks_usec()
	var result = operation.call()
	var duration := (Time.get_ticks_usec() - started) / 1000.0
	if show:
		await presented_project_frame()
		if action == "cached_stroke_undo": duration = (Time.get_ticks_usec() - started) / 1000.0
		project_loading_overlay.hide()
	operation_time_per_unit[action] = maxf(duration, 0.1) / maxi(1, units)
	return result

func apply_history_step(forward: bool) -> void:
	if project_loading_overlay.visible: return
	canvas.cancel()
	var stack: Array = document.future if forward else document.history
	if stack.is_empty(): return
	var entry: Dictionary = stack.back()
	var units := maxi(1, ceili(int(entry.get("_cost", 512)) / 128.0))
	var operation := Callable(document, "redo" if forward else "undo")
	if not forward and entry.has("append") and canvas.paint_cache:
		var layer_id: String = document.layers[int(entry.layer)].id
		var mark: Node2D = canvas.retained_marks.get(entry.append.id, {}).get("mark")
		if canvas.layer_renderers.get(layer_id) == canvas.paint_cache and not canvas.paint_cache.is_recent_mark(mark):
			units += int(canvas.layer_cache_costs.get(layer_id, 0))
			await run_indicated_operation("cached_stroke_undo", "Undoing stroke…", units, 18000, operation)
			return
	await run_indicated_operation("history", "Redoing…" if forward else "Undoing…", units, 45000, operation)

func apply_canvas_fill(point: Vector2) -> void:
	if project_loading_overlay.visible: return
	var layer: Dictionary = document.layers[document.active]
	if document.paints_pixels():
		var canvas_pixels := ceili(document.width * document.height / 128.0)
		await run_indicated_operation("paint_fill", "Filling area…", canvas_pixels, 12000, canvas.apply_fill.bind(point))
	else:
		await run_indicated_operation("vector_fill", "Calculating fill…", layer.objects.size(), 1400, canvas.apply_fill.bind(point))

func presented_project_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func finish_project_load(success: bool, message := "") -> void:
	project_loading_overlay.hide()
	if not message.is_empty(): notify(message)
	project_load_finished.emit(success)

func preserve_before_switch() -> bool:
	if not session_active:
		var saved_path = str(settings.get_value("session", "file_path", ""))
		var needs_recovery = saved_path.is_empty() or bool(settings.get_value("session", "dirty", true))
		if needs_recovery and FileAccess.file_exists(RECOVERY_PATH): return archive_recovery()
		return true
	canvas.finish()
	rename_document()
	if document.dirty:
		if not preserve_recovery(): return false
		return archive_recovery()
	return true

func archive_recovery() -> bool:
	var signature := FileAccess.get_sha256(RECOVERY_PATH)
	if not signature.is_empty():
		for entry in recovered_projects:
			if entry.get("signature", "") == signature and FileAccess.file_exists(entry.path): return true
	var destination = "user://recovered-%s-%s.havu" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var error = DirAccess.copy_absolute(RECOVERY_PATH, destination)
	if error != OK:
		notify("Could not keep your last session. Resume it and save your work first.")
		return false
	recovered_projects.push_front({"path": destination, "title": str(settings.get_value("session", "title", "Previous session")),
		"signature": signature})
	return save_project_lists()

func show_image_import() -> void:
	canvas.finish()
	import_image_dialog.popup_centered_ratio(0.75)

func import_image(path: String) -> void:
	canvas.finish()
	var asset := Raster.read(path)
	if asset.has("error"):
		notify(asset.error)
		return
	var layer_name := "Imported image" if path.begins_with("content://") else path.get_file().get_basename().left(120)
	if not document.import_image(asset, layer_name):
		notify("The project has reached its layer or embedded image limit.")
		return
	set_tool("select")
	notify("Image added on its own layer.")

func toggle_canvas_background() -> void:
	canvas.finish()
	document.set_paper_visible(not document.paper_visible)

func choose_layer_export() -> void:
	choose_export("png", document.layers[document.active].id)

func choose_export(kind: String, layer_id := "") -> void:
	canvas.finish()
	export_type = kind
	export_layer_id = layer_id
	export_dialog.title = "Export " + kind.to_upper() if layer_id.is_empty() else "Export layer as PNG"
	export_dialog.filters = PackedStringArray(["*.%s ; %s image" % [kind, kind.to_upper()]])
	var filename := safe_name()
	if not layer_id.is_empty():
		filename += "-" + document.layers[document.active].name.validate_filename().to_lower()
	export_dialog.current_file = filename + "." + kind
	export_dialog.popup_centered_ratio(0.75)

func export_document(layer_id: String):
	var copy := Document.new()
	copy.restore(document.snapshot(false))
	if layer_id.is_empty(): return copy
	for layer in copy.layers:
		if layer.id != layer_id: continue
		layer.visible = true
		copy.layers = [layer]
		copy.active = 0
		copy.paper_visible = false
		return copy
	return null

func write_export(path: String) -> void:
	if project_loading_overlay.visible: return
	if not path.begins_with("content://") and not path.ends_with("." + export_type): path += "." + export_type
	if export_type == "svg":
		await run_indicated_operation("svg", "Exporting SVG…", document_work_units(), 12000, export_svg_file.bind(path))
	else:
		await export_png(path)

func export_svg_file(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: notify("Export failed: " + error_string(FileAccess.get_open_error())); return
	file.store_string(Art.svg(document))
	file.flush()
	var result = file.get_error()
	file.close()
	if result != OK: notify("SVG export failed: " + error_string(result)); return
	notify("SVG exported.")

func export_png(path: String) -> void:
	if exporting_png or project_loading_overlay.visible: return
	if DisplayServer.get_name() == "headless":
		notify("PNG export needs a graphics-enabled session.")
		return
	exporting_png = true
	show_work_indicator("Rendering PNG…")
	await presented_project_frame()
	var render_document = export_document(export_layer_id)
	if not render_document:
		exporting_png = false
		project_loading_overlay.hide()
		notify("The layer selected for export is no longer available.")
		return
	var viewport = SubViewport.new()
	var scale_factor = minf(2.0, 4096.0 / maxf(render_document.width, render_document.height))
	viewport.size = Vector2i(Vector2(render_document.width, render_document.height) * scale_factor)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var drawing_canvas = Canvas.new()
	drawing_canvas.exporting = true
	drawing_canvas.document = render_document
	drawing_canvas.zoom = scale_factor
	drawing_canvas.origin = Vector2.ZERO
	drawing_canvas.size = Vector2(viewport.size)
	viewport.add_child(drawing_canvas)
	add_child(viewport)
	drawing_canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	var result = ERR_CANT_CREATE
	if image != null and not image.is_empty():
		if not render_document.paper_visible or Color(render_document.paper).a < 1.0:
			PngExport.straighten_alpha(image)
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(image.save_png_to_buffer())
			file.flush()
			result = file.get_error()
			file.close()
		else: result = FileAccess.get_open_error()
	viewport.queue_free()
	exporting_png = false
	project_loading_overlay.hide()
	notify("PNG exported." if result == OK else "PNG export failed: " + error_string(result))

func build_new_dialog() -> void:
	new_dialog = ConfirmationDialog.new()
	new_dialog.name = "NewIllustration"
	new_dialog.title = "New illustration"
	new_dialog.ok_button_text = "Create canvas"
	new_dialog.dialog_hide_on_ok = false
	new_dialog.unresizable = true
	var box := margin(new_dialog, 10)
	box.custom_minimum_size.x = 304
	box.add_theme_constant_override("separation", 6)

	var preset_row := HBoxContainer.new()
	box.add_child(preset_row)
	new_preset = OptionButton.new()
	new_preset.accessibility_name = "Canvas preset"
	new_preset.custom_minimum_size.y = 44
	new_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in CANVAS_PRESETS:
		new_preset.add_item("%s  ·  %d × %d" % [preset[0], preset[1].x, preset[1].y])
	new_preset.add_item("Custom size")
	new_preset.item_selected.connect(apply_canvas_preset)
	preset_row.add_child(new_preset)
	new_preview = Control.new()
	new_preview.custom_minimum_size = Vector2(48, 44)
	new_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	new_preview.draw.connect(draw_new_canvas_preview)
	new_preview.resized.connect(new_preview.queue_redraw)
	preset_row.add_child(new_preview)

	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 6)
	box.add_child(fields)
	new_width = canvas_dimension_field(fields, "Width")
	new_swap = icon_button("M5 9H21M17 5L21 9L17 13M21 17H5M9 13L5 17L9 21",
		swap_canvas_dimensions, "Swap width and height")
	new_swap.accessibility_name = "Swap width and height"
	new_swap.custom_minimum_size.y = 44
	new_swap.size_flags_vertical = Control.SIZE_SHRINK_END
	fields.add_child(new_swap)
	new_height = canvas_dimension_field(fields, "Height")

	new_dimensions_note = label("", 13, MUTED)
	new_dimensions_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Give the hidden label its wrapping width before the first popup measures it.
	new_dimensions_note.custom_minimum_size.x = box.custom_minimum_size.x
	new_dimensions_note.size.x = box.custom_minimum_size.x
	box.add_child(new_dimensions_note)
	new_transparent = CheckBox.new()
	new_transparent.text = "Transparent background"
	new_transparent.custom_minimum_size.y = 40
	new_transparent.toggled.connect(func(_value): new_preview.queue_redraw())
	box.add_child(new_transparent)
	canvas_artwork_mode = OptionButton.new()
	canvas_artwork_mode.name = "CanvasArtworkMode"
	canvas_artwork_mode.accessibility_name = "Artwork on resize"
	canvas_artwork_mode.custom_minimum_size.y = 44
	canvas_artwork_mode.add_item("Keep artwork in place", Document.ResizeArtwork.KEEP)
	canvas_artwork_mode.add_item("Scale artwork to fit", Document.ResizeArtwork.FIT)
	canvas_artwork_mode.add_item("Adapt vector layout", Document.ResizeArtwork.ADAPT)
	canvas_artwork_mode.add_item("Preserve composition", Document.ResizeArtwork.COMPOSITION)
	canvas_artwork_mode.hide()
	canvas_artwork_mode.item_selected.connect(func(_value): refresh_canvas_dimensions())
	box.add_child(canvas_artwork_mode)
	new_dialog.confirmed.connect(func():
		if resizing_canvas: resize_current_canvas()
		else: create_document(false))
	add_child(new_dialog)
	primary(new_dialog.get_ok_button())
	new_dialog.get_ok_button().custom_minimum_size.y = 44
	new_dialog.get_cancel_button().custom_minimum_size.y = 44

	canvas_number_pad = CanvasNumberPad.new()
	canvas_number_pad.name = "CanvasNumberPad"
	canvas_number_pad.minimum = Document.MIN_CANVAS_SIZE
	canvas_number_pad.maximum = Document.MAX_CANVAS_SIZE
	canvas_number_pad.transient = true
	canvas_number_pad.exclusive = true
	new_dialog.add_child(canvas_number_pad)
	primary(canvas_number_pad.get_ok_button())
	canvas_number_pad.value_entered.connect(func(value):
		if not new_dialog.visible or not is_instance_valid(dimension_target): return
		dimension_target.text = value
		refresh_canvas_dimensions())
	apply_canvas_preset(0)

func show_new_canvas() -> void:
	var from_resize := resizing_canvas
	resizing_canvas = false
	new_dialog.title = "New illustration"
	new_dialog.ok_button_text = "Create canvas"
	new_transparent.show()
	canvas_artwork_mode.hide()
	if from_resize: apply_canvas_preset(0)
	else: refresh_canvas_dimensions()
	popup_canvas_dialog()

func show_resize_canvas() -> void:
	if not session_active: return
	canvas.finish()
	resizing_canvas = true
	new_dialog.title = "Resize canvas"
	new_dialog.ok_button_text = "Resize"
	new_transparent.hide()
	canvas_artwork_mode.show()
	canvas_artwork_mode.select(canvas_artwork_mode.get_item_index(Document.ResizeArtwork.KEEP))
	canvas_artwork_mode.set_item_disabled(canvas_artwork_mode.get_item_index(Document.ResizeArtwork.FIT), document.has_pixel_paint())
	new_width.text = str(roundi(document.width))
	new_height.text = str(roundi(document.height))
	refresh_canvas_dimensions()
	popup_canvas_dialog()

func popup_canvas_dialog() -> void:
	# BaseButton handles native touch and keyboard activation independently
	# of its mouse-button mask, which also applies to stylus clicks.
	var mouse_buttons := 0 if text_entry.use_tablet_keyboard else MOUSE_BUTTON_MASK_LEFT
	new_width.button_mask = mouse_buttons
	new_height.button_mask = mouse_buttons
	# Fit the currently visible controls on each open, including when
	# switching back from Resize canvas and its longer explanatory text.
	new_dialog.popup_centered(Vector2i.ONE)

func resize_current_canvas() -> void:
	if project_loading_overlay.visible: return
	var dimensions := new_canvas_dimensions()
	if dimensions.x == 0 or dimensions.y == 0:
		refresh_canvas_dimensions()
		return
	var mode := canvas_artwork_mode.get_selected_id()
	new_dialog.hide()
	var result: Error = await run_indicated_operation("resize", "Resizing artwork…", document_work_units(), 23000,
		document.resize_canvas.bind(dimensions, mode))
	if result != OK:
		popup_canvas_dialog()
		notify("Canvas could not be resized. " + error_string(result))
		return
	canvas.cancel()
	canvas.clear_paint_limit()
	clip_check.set_pressed_no_signal(false)
	canvas.fit()
	notify("Canvas resized to %d × %d" % [dimensions.x, dimensions.y])

func canvas_dimension_field(parent: HBoxContainer, field_name: String) -> Button:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	column.add_child(label(field_name + " (px)", 13, MUTED))
	var field := Button.new()
	field.name = field_name
	field.accessibility_name = field_name
	field.custom_minimum_size = Vector2(94, 44)
	field.add_theme_font_size_override("font_size", 18)
	field.icon = make_icon("M5 3H21V23H5ZM9 8H17M9 12h.2M13 12h.2M17 12h.2M9 16h.2M13 16h.2M17 16h.2M9 20h.2M13 20h.2M17 20h.2", "#a8b5ad", 16)
	field.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	field.tooltip_text = "Enter " + field_name.to_lower()
	field.pressed.connect(open_canvas_number_pad.bind(field))
	column.add_child(field)
	return field

func open_canvas_number_pad(field: Button) -> void:
	if not new_dialog.visible or canvas_number_pad.visible: return
	var fallback := func():
		if new_dialog.visible and is_instance_valid(field):
			dimension_target = field
			canvas_number_pad.choose(str(field.name), field.text)
	var apply := func(value: String):
		if not new_dialog.visible or not is_instance_valid(field): return
		field.text = str(value.strip_edges().to_int())
		refresh_canvas_dimensions()
	var options := {"title": str(field.name), "text": field.text, "type": DisplayServer.KEYBOARD_TYPE_NUMBER,
		"integer_range": Vector2i(Document.MIN_CANVAS_SIZE, Document.MAX_CANVAS_SIZE)}
	if not text_entry.request_native(options, apply, fallback): fallback.call()

func apply_canvas_preset(index: int) -> void:
	if index >= CANVAS_PRESETS.size():
		if not text_entry.use_tablet_keyboard: open_canvas_number_pad(new_width)
		return
	var dimensions: Vector2i = CANVAS_PRESETS[index][1]
	new_width.text = str(dimensions.x)
	new_height.text = str(dimensions.y)
	refresh_canvas_dimensions()

func swap_canvas_dimensions() -> void:
	var width_text := new_width.text
	new_width.text = new_height.text
	new_height.text = width_text
	refresh_canvas_dimensions()

func read_canvas_dimension(field: Button) -> int:
	var text := field.text.strip_edges()
	if not text.is_valid_int() or text.length() > 6: return 0
	var value := text.to_int()
	return value if value >= Document.MIN_CANVAS_SIZE and value <= Document.MAX_CANVAS_SIZE else 0

func new_canvas_dimensions() -> Vector2i:
	return Vector2i(read_canvas_dimension(new_width), read_canvas_dimension(new_height))

func refresh_canvas_dimensions() -> void:
	var dimensions := new_canvas_dimensions()
	var valid := dimensions.x > 0 and dimensions.y > 0
	new_dialog.get_ok_button().disabled = not valid
	new_swap.disabled = not valid or dimensions.x == dimensions.y
	var index := CANVAS_PRESETS.size()
	for candidate in CANVAS_PRESETS.size():
		if dimensions == CANVAS_PRESETS[candidate][1]:
			index = candidate
			break
	new_preset.select(index)
	var hint := ""
	if resizing_canvas:
		match canvas_artwork_mode.get_selected_id():
			Document.ResizeArtwork.FIT:
				hint = "Artwork scales proportionally and is centered."
			Document.ResizeArtwork.ADAPT:
				hint = "Vectors follow the new edges and keep their proportions."
			Document.ResizeArtwork.COMPOSITION:
				hint = "Move the illustration together and shrink only if it needs to fit."
			_:
				hint = "New bounds start at the top-left."
		if document.has_pixel_paint():
			hint += " Paint resamples if it shrinks." if canvas_artwork_mode.get_selected_id() == Document.ResizeArtwork.COMPOSITION \
				else " Paint keeps its pixel scale and is cropped at the edges."
	new_dimensions_note.text = hint if valid else (
		"Enter a whole number from %d to %d in both fields." % [Document.MIN_CANVAS_SIZE, Document.MAX_CANVAS_SIZE])
	new_dimensions_note.visible = not new_dimensions_note.text.is_empty()
	new_dimensions_note.add_theme_color_override("font_color", MUTED if valid else Color("#ffb5a6"))
	new_preview.queue_redraw()

func draw_new_canvas_preview() -> void:
	var dimensions := Vector2(new_width.text.to_int(), new_height.text.to_int())
	new_preview.draw_rect(Rect2(Vector2.ZERO, new_preview.size), Color("#161616"))
	if new_dialog.get_ok_button().disabled or minf(new_preview.size.x, new_preview.size.y) <= 10.0: return
	var page_size := dimensions * minf((new_preview.size.x - 10.0) / dimensions.x, (new_preview.size.y - 10.0) / dimensions.y)
	var page := Rect2((new_preview.size - page_size) * 0.5, page_size)
	new_preview.draw_rect(page, Color(document.paper) if resizing_canvas else Color("#faf8f1"))
	if (resizing_canvas and not document.paper_visible) or (not resizing_canvas and new_transparent.button_pressed):
		for y in ceili(page.size.y / 7):
			for x in ceili(page.size.x / 7):
				if (x + y) % 2 == 0:
					new_preview.draw_rect(page.intersection(Rect2(page.position + Vector2(x, y) * 7, Vector2(7, 7))), Color("#d4d1cb"))

func create_document(sample_doc: bool) -> void:
	if project_loading_overlay.visible: return
	var dimensions := Vector2i.ZERO
	if not sample_doc:
		dimensions = new_canvas_dimensions()
		if dimensions.x == 0 or dimensions.y == 0:
			refresh_canvas_dimensions()
			return
	if not preserve_before_switch(): return
	if sample_doc: Sample.populate(document)
	else:
		new_dialog.hide()
		document.blank(float(dimensions.x), float(dimensions.y), not new_transparent.button_pressed)
	file_path = ""
	enter_project()
	if not sample_doc and not settings.get_value("onboarding", "tour_shown", false):
		show_get_started_tour()

func enter_project() -> void:
	session_active = true
	canvas.set_add_node_mode(false)
	canvas.set_solo_layer("")
	project_home.hide()
	canvas.cancel()
	clip_check.set_pressed_no_signal(false)
	canvas.clear_paint_limit()
	update_selection_actions()
	canvas.fit()
	preserve_recovery()

func build_project_home() -> void:
	load_project_lists()
	project_home = ProjectHome.new()
	project_home.new_requested.connect(show_new_canvas)
	project_home.open_requested.connect(func(): open_dialog.popup_centered_ratio(0.75))
	project_home.sample_requested.connect(func(): create_document(true))
	project_home.resume_requested.connect(resume_project)
	project_home.project_requested.connect(open_project)
	project_home.visibility_changed.connect(func():
		queue_layer_preview_refresh()
		update_panel_reveal_visibility()
		if project_home.visible:
			for grip in group_grips.values(): grip.hide()
		else:
			queue_dock_reflow())
	add_child(project_home)
	update_panel_reveal_visibility()

func build_project_loading() -> void:
	var foreground := CanvasLayer.new()
	foreground.layer = 12
	add_child(foreground)
	project_loading_overlay = ColorRect.new()
	project_loading_overlay.name = "ProjectLoading"
	project_loading_overlay.color = Color("#111614c7")
	project_loading_overlay.focus_mode = Control.FOCUS_ALL
	project_loading_overlay.hide()
	foreground.add_child(project_loading_overlay)
	project_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	project_loading_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.theme = theme
	card.add_theme_stylebox_override("panel", style(Color("#1b1b1b"), 12, Color("#3b4b42"), 18))
	center.add_child(card)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 208
	card.add_child(content)
	project_loading_label = label("Opening project…", 17)
	project_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(project_loading_label)
	var progress := ProgressBar.new()
	progress.accessibility_name = "Operation in progress"
	progress.indeterminate = true
	progress.show_percentage = false
	progress.custom_minimum_size.y = 5
	progress.add_theme_stylebox_override("background", style(Color("#303a35"), 3, Color.TRANSPARENT, 0))
	progress.add_theme_stylebox_override("fill", style(ACCENT, 3, Color.TRANSPARENT, 0))
	content.add_child(progress)

func update_panel_reveal_visibility() -> void:
	panel_reveal_tabs.visible = workspace_options.panel_reveal_tabs and (
		not is_instance_valid(project_home) or not project_home.visible)

func show_project_home() -> void:
	undo_button.stop_hold()
	layer_scroll.cancel_drag()
	if session_active and not preserve_recovery(): return
	var focus = get_viewport().gui_get_focus_owner()
	if focus: focus.release_focus()
	project_home.update_projects(
		recent_projects, recovered_projects,
		document.title if session_active else str(settings.get_value("session", "title", "")),
		session_active or FileAccess.file_exists(RECOVERY_PATH))
	project_home.show()
	project_home.move_to_front()

func resume_project() -> void:
	if project_loading_overlay.visible: return
	if session_active:
		project_home.hide()
		return
	await load_project(RECOVERY_PATH, true)

func project_path_key(path: String) -> String:
	if not path.begins_with("content://"): return ProjectSettings.globalize_path(path).simplify_path()
	# Android document pickers can return the same document under a tree URI.
	var parts := path.trim_prefix("content://").split("/")
	var id_index := -1
	if parts.size() >= 3 and parts[1] == "document": id_index = 2
	elif parts.size() >= 5 and parts[1] == "tree" and parts[3] == "document": id_index = 4
	if id_index >= 0:
		var id := parts[id_index].get_slice("?", 0).get_slice("#", 0)
		# Godot's URI decoder expects uppercase percent escapes.
		var escapes := RegEx.create_from_string("%[0-9A-Fa-f]{2}")
		for escape in escapes.search_all(id):
			var begin := escape.get_start()
			var end := escape.get_end()
			id = id.substr(0, begin) + id.substr(begin, end - begin).to_upper() + id.substr(end)
		return "content://%s/document/%s" % [parts[0], id.uri_decode()]
	return path

func load_project_lists() -> void:
	recent_projects.clear()
	recovered_projects.clear()
	var stored_recent = settings.get_value("projects", "recent", [])
	var stored_recovered = settings.get_value("projects", "recovered", [])
	var seen := {}
	var recovered_signatures := {}
	var entries: Array = stored_recovered.duplicate() if stored_recovered is Array else []
	if stored_recent is Array: entries.append_array(stored_recent)
	for entry in entries:
		if not entry is Dictionary or not entry.get("path") is String or not entry.get("title") is String: continue
		if entry.path.is_empty(): continue
		var key := project_path_key(entry.path)
		if seen.has(key): continue
		seen[key] = true
		if entry.path.begins_with("user://recovered-"):
			var recovery: Dictionary = entry.duplicate()
			recovery.title = recovery.title.trim_prefix("Recovery · ")
			if not recovery.has("signature") and FileAccess.file_exists(recovery.path):
				recovery.signature = FileAccess.get_sha256(recovery.path)
			var signature: String = str(recovery.get("signature", ""))
			if not signature.is_empty():
				if recovered_signatures.has(signature): continue
				recovered_signatures[signature] = true
			recovered_projects.append(recovery)
		else:
			recent_projects.append(entry)
	if recent_projects.size() > 6: recent_projects.resize(6)
	if stored_recent != recent_projects or stored_recovered != recovered_projects: save_project_lists()

func save_project_lists() -> bool:
	settings.set_value("projects", "recent", recent_projects.duplicate())
	settings.set_value("projects", "recovered", recovered_projects.duplicate())
	if settings.save("user://preferences.cfg") == OK: return true
	notify("Could not save the project list.")
	return false

func remember_project(path: String) -> void:
	if path.begins_with("content://") and Engine.has_singleton("AndroidRuntime"):
		Engine.get_singleton("AndroidRuntime").updatePersistableUriPermission(path, true)
	var key := project_path_key(path)
	for index in range(recent_projects.size() - 1, -1, -1):
		if project_path_key(recent_projects[index].path) == key: recent_projects.remove_at(index)
	recent_projects.push_front({"path": path, "title": document.title})
	if recent_projects.size() > 6: recent_projects.resize(6)
	save_project_lists()

func saved_brush_index(preset: Dictionary) -> int:
	for index in presets.size():
		if is_same(presets[index], preset): return index
	return -1

func validated_brush_id(previous: Variant = "") -> String:
	if previous is String and previous.length() == 24 and previous.is_valid_hex_number(false):
		if not presets.any(func(preset): return preset.local_id == previous): return previous
	return Crypto.new().generate_random_bytes(12).hex_encode()

func brush_key(preset: Dictionary) -> String:
	if preset.has("local_id"): return "personal:" + preset.local_id
	return "bundled:" + preset.name

func read_brush_shelf(key: String, limit: int) -> Array[String]:
	var shelf: Array[String] = []
	var known := {}
	for preset in builtin_brushes + presets: known[brush_key(preset)] = true
	var stored = settings.get_value("brushes", key, [])
	if stored is Array:
		for id in stored:
			if id is String and known.has(id) and id not in shelf: shelf.append(id)
			if shelf.size() >= limit: break
	return shelf

func toggle_favorite_brush() -> void:
	var key := brush_key(active_brush)
	var next := favorite_brushes.duplicate()
	if key in next: next.erase(key)
	elif next.size() < MAX_FAVORITES: next.append(key)
	else:
		notify("Favorites is full. Remove a favorite to add another.")
		update_brush_selection()
		return
	settings.set_value("brushes", "favorites", next)
	settings.set_value("brushes", "presets", presets)
	if settings.save("user://preferences.cfg") == OK:
		favorite_brushes = next
	else:
		settings.set_value("brushes", "favorites", favorite_brushes)
		notify("Could not save brush favorites.")
	if brush_category.selected == brush_category.item_count - 3: rebuild_brush_rows()
	else: update_brush_selection()

func record_recent_brush(preset: Dictionary) -> void:
	var key := brush_key(preset)
	if not recent_brushes.is_empty() and recent_brushes[0] == key: return
	recent_brushes.erase(key)
	recent_brushes.push_front(key)
	if recent_brushes.size() > RECENT_BRUSH_LIMIT: recent_brushes.resize(RECENT_BRUSH_LIMIT)
	settings.set_value("brushes", "recent", recent_brushes)
	history_preferences_dirty = true

func persist_brushes(next_presets: Array) -> bool:
	settings.set_value("brushes", "presets", next_presets)
	if settings.save("user://preferences.cfg") != OK:
		settings.set_value("brushes", "presets", presets)
		notify("Could not save brushes for the next launch.")
		return false
	presets = next_presets
	return true

func store_brush(preset: Dictionary, replace_index := -1) -> bool:
	var next_presets := presets.duplicate()
	preset.local_id = validated_brush_id() if replace_index < 0 else presets[replace_index].local_id
	if replace_index < 0: next_presets.append(preset)
	else: next_presets[replace_index] = preset
	return persist_brushes(next_presets)

func save_brush_preset() -> void:
	var preset := draft_brush("")
	prompt_text("Save as new brush", active_brush.name + " copy", func(value):
		if value.is_empty(): return
		preset.name = value
		if store_brush(preset):
			show_custom_brush(preset, false)
			notify("Brush saved in My brushes."))

func update_saved_brush() -> void:
	var index := saved_brush_index(active_brush)
	if index < 0: return
	var preset := draft_brush(active_brush.name)
	if store_brush(preset, index):
		show_custom_brush(preset, false)
		notify("Brush updated.")

func open_brush_menu() -> void:
	if saved_brush_index(active_brush) < 0: return
	brush_menu.reset_size()
	brush_menu.position = Vector2i(brush_manage.get_screen_position() + Vector2(brush_manage.size.x - brush_menu.size.x, brush_manage.size.y + 4))
	brush_menu.popup()

func rename_saved_brush() -> void:
	var original := active_brush
	if saved_brush_index(original) < 0: return
	prompt_text("Rename brush", original.name, func(value):
		var index := saved_brush_index(original)
		if index < 0 or value.is_empty() or value == original.name: return
		var renamed := original.duplicate(true)
		renamed.name = value
		if store_brush(renamed, index):
			if is_same(active_brush, original):
				active_brush = renamed
				refresh_brush_editor()
			rebuild_brush_rows())

func delete_saved_brush() -> void:
	var original := active_brush
	if saved_brush_index(original) < 0: return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete brush?"
	dialog.dialog_text = "Remove “%s” from My brushes?" % original.name
	dialog.ok_button_text = "Delete"
	dialog.confirmed.connect(func():
		var index := saved_brush_index(original)
		if index >= 0:
			var next_presets := presets.duplicate()
			next_presets.remove_at(index)
			if persist_brushes(next_presets):
				var key := brush_key(original)
				favorite_brushes.erase(key)
				recent_brushes.erase(key)
				brush_drafts.erase(key)
				settings.set_value("brushes", "favorites", favorite_brushes)
				settings.set_value("brushes", "recent", recent_brushes)
				history_preferences_dirty = true
				if is_same(active_brush, original):
					active_brush = builtin_brushes[0]
					load_brush_editor(brush_drafts.get(brush_key(active_brush), active_brush))
					set_tool("brush")
				rebuild_brush_rows()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func show_custom_brush(preset: Dictionary, keep_draft := true) -> void:
	brush_category.select(brush_category.item_count - 1)
	brush_search.text = ""
	apply_brush(preset, keep_draft)
	rebuild_brush_rows(true)
	for row in brush_row_buttons:
		if not is_same(row.get_meta("preset"), preset): continue
		var reveal := func():
			if is_instance_valid(row) and row.is_inside_tree(): brush_scroll.ensure_control_visible(row)
		reveal.call_deferred()
		break

func import_brush() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Import brushes"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dialog.filters = PackedStringArray(["*.havubrush,*.myb ; Brush presets", "* ; All files"])
	dialog.use_native_dialog = true
	add_child(dialog)
	dialog.files_selected.connect(func(paths: PackedStringArray):
		import_brush_files(paths)
		dialog.queue_free())
	dialog.file_selected.connect(func(path: String):
		import_brush_files(PackedStringArray([path]))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.75)

func import_brush_files(paths: PackedStringArray) -> void:
	var candidates: Array[Dictionary] = []
	var first_error := ""
	for index in mini(paths.size(), 32):
		var result := read_brush_file(paths[index])
		if result.has("error"):
			if first_error.is_empty(): first_error = result.error
			continue
		candidates.append(result)
	if candidates.is_empty():
		if not first_error.is_empty(): notify(first_error)
		return
	var external := candidates.filter(func(candidate): return candidate.get("adapted", false))
	var skipped := paths.size() - candidates.size()
	if external.is_empty():
		finish_brush_import(candidates, skipped)
		return
	review_brush_import(candidates, external, skipped)

func review_brush_import(candidates: Array[Dictionary], external: Array, skipped: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Review brush import"
	dialog.ok_button_text = "Import approximation" if candidates.size() == 1 else "Import brushes"
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = minf(390.0, maxf(230.0, size.x - 92.0))
	dialog.add_child(content)
	var summary := PackedStringArray()
	var ratings := {"high": "High compatibility", "partial": "Partial compatibility", "limited": "Limited compatibility"}
	for index in mini(external.size(), 3):
		var preset: Dictionary = external[index].preset
		var source: Dictionary = preset.import_source
		summary.append(preset.name + " · " + ratings[source.compatibility])
		if not source.limits.is_empty():
			summary.append("Changes: " + ", ".join(source.limits.slice(0, 4)).to_lower() + ".")
	if external.size() > 3: summary.append("%d more MyPaint approximations." % (external.size() - 3))
	summary.append("Havu adapts the brush for editable vectors or paint layers. Both use Havu’s brush engine.")
	if skipped > 0: summary.append("%d files could not be imported or exceed the 32-file limit." % skipped)
	var description := label("\n".join(summary), 14, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	var preview := BrushPreview.new()
	preview.preset = external[0].preset
	preview.detailed = true
	preview.custom_minimum_size.y = 64
	preview.clip_contents = true
	content.add_child(preview)
	add_child(dialog)
	dialog.confirmed.connect(func():
		finish_brush_import(candidates, skipped)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func finish_brush_import(candidates: Array[Dictionary], skipped: int) -> void:
	var next_presets := presets.duplicate()
	for candidate in candidates:
		var preset: Dictionary = candidate.preset
		preset.local_id = validated_brush_id()
		next_presets.append(preset)
	if not persist_brushes(next_presets): return
	show_custom_brush(candidates[0].preset)
	var added := candidates.size()
	var message := "Brush imported." if added == 1 else "%d brushes imported." % added
	if skipped > 0: message += " %d skipped." % skipped
	notify(message)

func read_brush_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "Could not open the brush file."}
	var bytes := file.get_buffer(MAX_BRUSH_FILE_BYTES + 1)
	file.close()
	if bytes.size() > MAX_BRUSH_FILE_BYTES: return {"error": "Brush file is too large."}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8().trim_prefix("\uFEFF")) != OK:
		return {"error": "Choose a Havu .havubrush or a MyPaint .myb brush."}
	var parsed = parser.data
	if valid_preset(parsed):
		var source = parsed.get("import_source")
		if not source is Dictionary or source.get("format") != "MyPaint" or source.get("version") != 3 \
				or source.get("compatibility") not in ["high", "partial", "limited"]:
			parsed.erase("import_source")
		return {"preset": parsed}
	if parsed is Dictionary and (parsed.has("settings") or path.uri_decode().get_extension().to_lower() == "myb"):
		var result := MyPaintBrush.convert(parsed, path)
		if result.has("error") or valid_preset(result.preset): return result
	return {"error": "Choose a Havu .havubrush or a MyPaint .myb brush."}

func valid_preset(value) -> bool:
	if not value is Dictionary or value.get("format") != "havu-brush" or value.get("version") != 1 or not value.get("name") is String: return false
	if value.get("brush") not in BrushLibrary.ENGINES: return false
	for key in ["size", "opacity", "blend", "smoothing"]:
		if not Document.numeric(value.get(key)): return false
	return BrushLibrary.valid_profile(value) and value.size >= 1 and value.size <= 150 and value.opacity >= 0.01 and value.opacity <= 1 and value.blend >= 0 and value.blend <= 1 and value.smoothing >= 0 and value.smoothing <= 0.9

func export_brush() -> void:
	if saved_brush_index(active_brush) < 0:
		notify("Choose a preset from My brushes to share.")
		return
	var preset := draft_brush(active_brush.name)
	var dialog = FileDialog.new()
	dialog.title = "Share brush"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.havubrush ; Havu brush preset"])
	dialog.current_file = preset.name.validate_filename() + ".havubrush"
	dialog.use_native_dialog = true
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file == null: notify("Brush export failed.")
		else: file.store_string(JSON.stringify(preset)); file.close(); notify("Brush exported.")
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered_ratio(0.75)

func build_toast() -> void:
	toast = PanelContainer.new()
	toast.add_theme_stylebox_override("panel", style(Color("#efefef"), 9, Color.TRANSPARENT, 14))
	toast_label = label("", 14, Color("#161616"))
	toast.add_child(toast_label)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	toast.hide()
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 4
	toast_timer.timeout.connect(func(): toast.hide())
	add_child(toast_timer)

func notify(message: String) -> void:
	if not toast: return
	toast_label.text = message
	toast.reset_size()
	toast.position = Vector2((size.x - toast.size.x) / 2, size.y - 120)
	toast.show()
	toast.move_to_front()
	toast_timer.start()

func build_input_settings() -> void:
	canvas.pressure_enabled = bool(settings.get_value("input", "pen_pressure", true))
	canvas.touch_paints = bool(settings.get_value("input", "draw_with_finger", false))
	input_settings_dialog = AcceptDialog.new()
	input_settings_dialog.title = "Input settings"
	input_settings_dialog.ok_button_text = "Done"
	add_child(input_settings_dialog)
	var content = margin(input_settings_dialog, 16)
	content.custom_minimum_size.x = 400

	var pressure_toggle = CheckBox.new()
	pressure_toggle.name = "PenPressure"
	pressure_toggle.text = "Use pen pressure"
	pressure_toggle.custom_minimum_size.y = 44
	pressure_toggle.button_pressed = canvas.pressure_enabled
	pressure_toggle.toggled.connect(func(enabled):
		canvas.pressure_enabled = enabled
		save_input_preference("pen_pressure", enabled))
	content.add_child(pressure_toggle)
	content.add_child(label("Use stylus pressure to vary brush width and color.", 14, MUTED))

	var finger_toggle = CheckBox.new()
	finger_toggle.name = "FingerDrawing"
	finger_toggle.text = "Draw with finger"
	finger_toggle.custom_minimum_size.y = 44
	finger_toggle.button_pressed = canvas.touch_paints
	finger_toggle.toggled.connect(func(enabled):
		canvas.touch_paints = enabled
		save_input_preference("draw_with_finger", enabled))
	content.add_child(finger_toggle)
	content.add_child(label("When off, one finger pans. Two fingers pan and zoom in either mode.", 14, MUTED))

	content.add_child(HSeparator.new())
	var pen_row := HBoxContainer.new()
	content.add_child(pen_row)
	pen_row.add_child(button("Detect pen button", start_pen_detection))
	pen_button_selector = OptionButton.new()
	pen_button_selector.name = "PenButtonSelector"
	pen_button_selector.accessibility_name = "Pen button"
	pen_button_selector.add_item("Button 1", 1)
	pen_button_selector.item_selected.connect(func(_index): refresh_pen_button_action())
	pen_row.add_child(pen_button_selector)
	pen_action_selector = OptionButton.new()
	pen_action_selector.name = "PenSideButton"
	pen_action_selector.accessibility_name = "Pen button action"
	pen_action_selector.custom_minimum_size.y = 44
	for caption in ["Off", "Color picker", "Eraser", "Pan canvas"]: pen_action_selector.add_item(caption)
	pen_action_selector.item_selected.connect(assign_pen_button_action)
	pen_row.add_child(pen_action_selector)
	var hint := label("Hold the assigned pen button while you tap or drag on the canvas.", 14, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

	build_pen_detection_dialog()
	input_settings_dialog.visibility_changed.connect(func():
		if not input_settings_dialog.visible: pen_detection_dialog.hide())

	var legacy = settings.get_value("input", "pen_button_tool", "")
	var stored = settings.get_value("input", "pen_button_actions", {1: legacy})
	if stored is Dictionary:
		for id in [1, 2]:
			var assignment = stored.get(id, "")
			if assignment in PEN_BUTTON_TOOLS and assignment != "": canvas.pen_button_tools[id] = assignment
	if canvas.pen_button_tools.has(2): pen_button_selector.add_item("Button 2", 2)
	if configure_pen_bridge() and pen_bridge.isSamsungDevice():
		var samsung_hint := label(
			"If the pen button opens Air Command, turn off Open Air command with Pen button in Samsung Settings › Advanced features › S Pen › Air command. This applies across the tablet.",
			14, MUTED)
		samsung_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(samsung_hint)
	refresh_pen_button_action()

func refresh_pen_button_action() -> void:
	var action = canvas.pen_button_tools.get(pen_button_selector.get_selected_id(), "")
	pen_action_selector.select(PEN_BUTTON_TOOLS.find(action))

func assign_pen_button_action(index: int) -> void:
	var id := pen_button_selector.get_selected_id()
	var action: String = PEN_BUTTON_TOOLS[index]
	if action.is_empty(): canvas.pen_button_tools.erase(id)
	else: canvas.pen_button_tools[id] = action
	if pen_bridge != null or not canvas.pen_button_tools.is_empty(): configure_pen_bridge()
	save_input_preference("pen_button_actions", canvas.pen_button_tools.duplicate())

func configure_pen_bridge(detecting := false) -> bool:
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"): return false
	var runtime = Engine.get_singleton("AndroidRuntime")
	var activity = runtime.getActivity()
	if activity == null: return false
	if pen_bridge == null:
		var java = Engine.get_singleton("JavaClassWrapper")
		pen_bridge = java.wrap("studio.havu.android.HavuStylus")
		if pen_bridge == null: return false
		canvas.pen_shortcut_contact = func(): return pen_bridge.takeShortcutContact()
		pen_detection_contact = func(): return pen_bridge.takeDetectionContact()
	pen_bridge.configure(activity, detecting or not canvas.pen_button_tools.is_empty())
	return true

func build_pen_detection_dialog() -> void:
	pen_detection_dialog = ConfirmationDialog.new()
	pen_detection_dialog.name = "PenButtonDetection"
	pen_detection_dialog.title = "Detect pen button"
	pen_detection_dialog.ok_button_text = "Choose shortcut"
	pen_detection_dialog.dialog_hide_on_ok = false
	# Keep the native contact and the Godot tap in the same Android window.
	input_settings_dialog.add_child(pen_detection_dialog)
	var content := margin(pen_detection_dialog, 16)
	content.custom_minimum_size.x = 320
	pen_test_target = PanelContainer.new()
	pen_test_target.name = "PenTestTarget"
	pen_test_target.accessibility_name = "Tap here with the pen tip while holding its button"
	pen_test_target.custom_minimum_size.y = 112
	pen_test_target.add_theme_stylebox_override("panel", style(Color("#1c2924"), 10, ACCENT, 12))
	pen_test_target.gui_input.connect(test_pen_button_contact)
	content.add_child(pen_test_target)
	var instructions := label("Hold the button you want to map.\nTap here with the pen tip.", 16)
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pen_test_target.add_child(instructions)
	pen_test_feedback = label("", 14, MUTED)
	pen_test_feedback.custom_minimum_size.y = 44
	pen_test_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(pen_test_feedback)
	pen_detection_dialog.confirmed.connect(confirm_pen_detection)
	pen_detection_dialog.visibility_changed.connect(func():
		if not pen_detection_dialog.visible and pen_bridge != null:
			pen_bridge.setDetection(false)
			configure_pen_bridge())

func start_pen_detection() -> void:
	if not configure_pen_bridge(true):
		notify("Pen button detection is available on Android.")
		return
	show_pen_detection_target()
	pen_bridge.setDetection(true)

func show_pen_detection_target() -> void:
	detected_pen_slot = 0
	pen_test_feedback.text = "If two presses report the same number, they share one shortcut."
	pen_detection_dialog.get_ok_button().disabled = true
	pen_detection_dialog.popup_centered(Vector2i.ONE)

func test_pen_button_contact(event: InputEvent) -> void:
	if not pen_detection_dialog.visible or not pen_detection_contact.is_valid(): return
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled: return
	elif event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	else:
		return
	pen_test_target.accept_event()
	var code: int = pen_detection_contact.call()
	detected_pen_slot = code if code in [1, 2] else 0
	pen_detection_dialog.get_ok_button().disabled = detected_pen_slot == 0
	match code:
		1, 2: pen_test_feedback.text = "Android reported Button %d." % code
		-1: pen_test_feedback.text = "Pen tip detected. Hold the side button and tap again."
		_: pen_test_feedback.text = "Use the pen tip on this area while holding its button."

func confirm_pen_detection() -> void:
	if detected_pen_slot == 0: return
	pen_detection_dialog.hide()
	select_detected_pen_button.call_deferred(detected_pen_slot)

func select_detected_pen_button(id: int) -> void:
	if pen_button_selector.get_item_index(id) == -1:
		pen_button_selector.add_item("Button %d" % id, id)
	pen_button_selector.select(pen_button_selector.get_item_index(id))
	refresh_pen_button_action()
	pen_action_selector.grab_focus()
	pen_action_selector.show_popup()

func build_workspace_settings() -> void:
	workspace_settings_dialog = AcceptDialog.new()
	workspace_settings_dialog.title = "Workspace settings"
	workspace_settings_dialog.ok_button_text = "Done"
	add_child(workspace_settings_dialog)
	var content = margin(workspace_settings_dialog, 16)
	content.custom_minimum_size.x = 400

	var scale_heading := HBoxContainer.new()
	content.add_child(scale_heading)
	var heading := label("UI scale", 15)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_heading.add_child(heading)
	ui_scale_label = label("%d%%" % ui_scale_percent, 15, ACCENT)
	scale_heading.add_child(ui_scale_label)
	var scale_row := HBoxContainer.new()
	content.add_child(scale_row)
	ui_scale_slider = UIScaleSlider.new()
	ui_scale_slider.name = "UIScaleSlider"
	ui_scale_slider.value = ui_scale_percent
	ui_scale_slider.tooltip_text = "Resize the interface"
	ui_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_scale_slider.scale_changed.connect(preview_ui_scale)
	ui_scale_slider.scale_committed.connect(save_ui_scale)
	scale_row.add_child(ui_scale_slider)
	reset_ui_scale_button = button("Reset", func():
		ui_scale_slider.choose_percent(100)
		save_ui_scale(), "Restore UI scale to 100%")
	reset_ui_scale_button.disabled = ui_scale_percent == 100
	scale_row.add_child(reset_ui_scale_button)
	content.add_child(HSeparator.new())

	var options_scroll := SwipeScroll.new()
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_scroll.custom_minimum_size.y = 100
	options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(options_scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_scroll.add_child(options)
	horizontal_toolbar_check = workspace_checkbox(options, "Horizontal toolbar", tools_horizontal, "Set the toolbar direction manually.")
	horizontal_toolbar_check.toggled.connect(set_manual_tool_orientation)
	for key in WORKSPACE_OPTIONS:
		var spec: Array = WORKSPACE_OPTIONS[key]
		var control := workspace_checkbox(options, spec[0], workspace_options[key], spec[1])
		control.name = key
		control.toggled.connect(func(enabled): set_workspace_option(key, enabled))

func workspace_settings_size() -> Vector2i:
	return Vector2i(480, clampi(roundi(size.y) - 84, 300, 620))

func show_workspace_settings() -> void:
	workspace_settings_dialog.popup_centered(workspace_settings_size())

func fit_workspace_settings() -> void:
	if not workspace_settings_dialog.visible: return
	workspace_settings_dialog.size = workspace_settings_size()
	var dimensions := Vector2(workspace_settings_dialog.size)
	workspace_settings_dialog.position = Vector2i(((size - dimensions) * 0.5).max(Vector2.ZERO))

func preview_ui_scale(percent: int) -> void:
	ui_scale_percent = percent
	ui_scale_label.text = "%d%%" % percent
	reset_ui_scale_button.disabled = percent == 100
	var factor := percent / 100.0
	canvas.set_ui_scale(factor)
	get_window().content_scale_factor = factor

func save_ui_scale() -> void:
	if settings.get_value("workspace", "ui_scale_percent", 100) == ui_scale_percent: return
	settings.set_value("workspace", "ui_scale_percent", ui_scale_percent)
	if settings.save("user://preferences.cfg") != OK:
		notify("Could not save UI scale for the next launch.")

func workspace_checkbox(content: VBoxContainer, title_text: String, checked: bool, hint: String) -> CheckBox:
	var control := CheckBox.new()
	control.text = title_text
	control.tooltip_text = hint
	control.custom_minimum_size.y = 44
	control.button_pressed = checked
	content.add_child(control)
	return control

func set_workspace_option(key: String, enabled: bool) -> void:
	workspace_options[key] = enabled
	settings.set_value("workspace", key, enabled)
	match key:
		"edge_docking":
			for panel in panels.values(): panel.edge_docking_enabled = enabled
		"drag_to_hide":
			for panel in panels.values(): panel.drag_to_hide_enabled = enabled
		"contextual_actions":
			sync_selection_menu()
			update_selection_actions()
		"panel_groups":
			if not enabled:
				for panel_key in panels: detach_group_member(panel_key)
				reflow_panel_groups()
		"panel_reveal_tabs":
			update_panel_reveal_visibility()
		"footer_metrics":
			update_workspace_chrome()
			if footer_metrics.visible: update_pointer_readouts()
	if settings.save("user://preferences.cfg") != OK:
		notify("Could not save workspace settings for the next launch.")

func sync_selection_menu() -> void:
	for id in [8, 9, 11, 12, 14, 15, 16]:
		var index := workspace_menu.get_item_index(id)
		if index >= 0: workspace_menu.remove_item(index)
	if not workspace_options.contextual_actions:
		workspace_menu.add_item("Duplicate selection", 8)
		workspace_menu.add_item("Delete selection", 9)
		workspace_menu.add_item("Move to layer…", 16)
		workspace_menu.add_item("Group selection", 11)
		workspace_menu.add_item("Ungroup selection", 12)
		workspace_menu.add_item("Transform selection…", 14)
		workspace_menu.add_item("Merge vectors", 15)

func save_input_preference(key: String, value: Variant) -> void:
	settings.set_value("input", key, value)
	if settings.save("user://preferences.cfg") != OK:
		notify("Could not save input settings for the next launch.")

func show_get_started_tour() -> void:
	if not session_active or project_home.visible: return
	if not get_started_tour:
		var tour_layer := CanvasLayer.new()
		tour_layer.layer = 8
		add_child(tour_layer)
		get_started_tour = GetStartedTour.new()
		get_started_tour.theme = theme
		tour_layer.add_child(get_started_tour)
	if get_started_tour.visible: return
	if not settings.get_value("onboarding", "tour_shown", false):
		settings.set_value("onboarding", "tour_shown", true)
		if settings.save("user://preferences.cfg") != OK:
			notify("Could not save your tour preference.")
	var navigation := "One finger pans by default. Pinch with two fingers to zoom. Tap the zoom percentage and choose Fit page to see the whole illustration."
	if show_shortcut_hints:
		navigation = "Pinch to zoom on a touchscreen. With a mouse, scroll to zoom or hold Space and drag to pan. Choose Fit page from the zoom menu to see the whole illustration."
	var steps: Array[Dictionary] = [
		{"target": zoom_button, "title": "Move around the canvas", "text": navigation},
		{"target": brush_library_button, "title": "Find your brush", "text":
			"Tap the stroke preview to browse brushes. Switch to Settings to tune a brush, or tap the color swatch to choose a color."},
		{"target": header_layers_button, "title": "Work in layers", "text":
			"Open Layers to organize your drawing. Vectors stay sharp when you resize them. Add a paint layer when you want to work with pixels."},
		{"target": header_panels_button, "title": "Edit and arrange", "text":
			"Use Select to move or resize objects, and Nodes to reshape their points. Open Panels to bring back a hidden tool rail. Drag a panel’s heading to move it."},
		{"target": header_tools.get_node("QuickSave"), "title": "Save your work", "text":
			"Tap the save icon to keep an editable Havu project. Open File to export SVG or PNG. You can replay this tour from the three-dot menu."},
	]
	get_started_tour.start(steps)

func show_help() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Welcome to Havu"
	dialog.dialog_text = help_text()
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func help_text() -> String:
	var gestures := ("One finger pans the canvas by default. Pinch to zoom.\n"
		+ "Swipe within a panel to scroll, or drag its heading to move it.\n"
		+ "Drag a layer by its name or thumbnail to reorder it.\n"
		+ "Hold Undo to step back through several changes.")
	if not show_shortcut_hints: return gestures
	return ("Brush B · Select V · Nodes A · Eraser E · Fill G\n"
		+ "Picker I · Rectangle R · Ellipse O · Line L · Pen path P\nText T · Hand H\n\n"
		+ "Pen path: Enter finishes, Shift+Enter closes.\n"
		+ "Space + drag: pan     Wheel: zoom\n"
		+ "Ctrl+Z: undo     Ctrl+Shift+Z: redo\nCtrl+S: save     Ctrl+Shift+S: save as\n"
		+ "Ctrl+O: open     Ctrl+N: new     Ctrl+0: fit\nCtrl+D: duplicate     Delete: delete selection\n"
		+ "Escape: cancel gesture     F12: developer monitor\n\n" + gestures)

func build_developer_panel() -> void:
	developer_panel = PanelContainer.new()
	developer_panel.position = Vector2(270, 110)
	developer_panel.custom_minimum_size = Vector2(330, 160)
	developer_panel.add_theme_stylebox_override("panel", style(Color("#161616"), 8, ACCENT, 18))
	developer_label = label("", 14, ACCENT)
	developer_panel.add_child(developer_label)
	add_child(developer_panel)
	developer_panel.hide()

func _process(delta: float) -> void:
	# Keep label updates off the high-frequency stylus event path.
	if project_home and not project_home.visible and footer_metrics.visible:
		metrics_elapsed += delta
		if metrics_elapsed >= 0.05:
			metrics_elapsed = fmod(metrics_elapsed, 0.05)
			update_pointer_readouts()
	if not developer_panel or not developer_panel.visible: return
	var object_count = 0
	var point_count = 0
	for layer in document.layers:
		object_count += layer.objects.size()
		for object in layer.objects:
			if object.kind == "stroke": point_count += object.points.size()
	developer_label.text = "HAVU · DEVELOPMENT MONITOR\nFPS: %d    Memory: %.1f MB\nObjects: %d    Stroke samples: %d\nPressure: %.3f    Zoom: %.2f\nTool: %s    Drawing: %s\nRecovery: %s" % [Engine.get_frames_per_second(), OS.get_static_memory_usage() / 1048576.0, object_count, point_count, canvas.last_pressure, canvas.zoom, canvas.tool, canvas.drawing, ProjectSettings.globalize_path("user://recovery.havu")]
	if show_shortcut_hints: developer_label.text += "\nF12 to close"

func _unhandled_key_input(event: InputEvent) -> void:
	if project_loading_overlay.visible:
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if is_instance_valid(get_started_tour) and get_started_tour.visible: return
	if project_home.visible:
		if event.ctrl_pressed or event.meta_pressed:
			if event.keycode == KEY_N: show_new_canvas()
			elif event.keycode == KEY_O: open_dialog.popup_centered_ratio(0.75)
		return
	if event.keycode == KEY_F12:
		developer_panel.visible = not developer_panel.visible
		developer_panel.move_to_front()
		get_viewport().set_input_as_handled()
		return
	var focus = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var ctrl = event.ctrl_pressed or event.meta_pressed
	if ctrl:
		match event.keycode:
			KEY_Z: apply_history_step(event.shift_pressed)
			KEY_Y: apply_history_step(true)
			KEY_S:
				if event.shift_pressed: save_as()
				else: save_project()
			KEY_O: open_dialog.popup_centered_ratio(0.75)
			KEY_N: show_new_canvas()
			KEY_0: canvas.fit()
			KEY_D: document.duplicate_selected()
			KEY_G: change_artwork_group(event.shift_pressed)
	else:
		match event.keycode:
			KEY_B: set_tool("brush")
			KEY_V: set_tool("select")
			KEY_A: set_tool("nodes")
			KEY_E: set_tool("erase")
			KEY_G: set_tool("fill")
			KEY_I: set_tool("picker")
			KEY_R: set_tool("rect")
			KEY_O: set_tool("ellipse")
			KEY_L: set_tool("line")
			KEY_P: set_tool("path")
			KEY_ENTER, KEY_KP_ENTER:
				if canvas.tool == "path": canvas.commit_path(event.shift_pressed)
			KEY_T: set_tool("text")
			KEY_H: set_tool("hand")
			KEY_DELETE, KEY_BACKSPACE: document.delete_selected()
			KEY_ESCAPE:
				canvas.set_add_node_mode(false)
				canvas.cancel()
			KEY_BRACKETLEFT: size_slider.value -= 2
			KEY_BRACKETRIGHT: size_slider.value += 2

func show_splash() -> void:
	var overlay = ColorRect.new()
	overlay.color = Color("#101813")
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var image = TextureRect.new()
	image.texture = BRAND_LOGO
	image.custom_minimum_size = Vector2(240, 84)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(image)
	var tagline = label("A LITTLE ROOM TO CREATE", 12, MUTED)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)
	var dedication = label("Made with ♥ for Sini by Björn", 18, ACCENT)
	dedication.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(dedication)
	var tween = create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.45)
	tween.tween_callback(overlay.queue_free)

func _notification(what: int) -> void:
	if not is_instance_valid(canvas) or not autosave_timer: return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if preserve_recovery():
			save_layout()
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		preserve_recovery()
		save_layout()

func icon_button(path: String, callback: Callable, hint: String) -> Button:
	var b = button("", callback, hint)
	b.icon = make_icon(path)
	b.custom_minimum_size = Vector2(44, 42)
	b.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 7, Color.TRANSPARENT, 8))
	return b

func build_header() -> void:
	var header = PanelContainer.new()
	header.name = "TopBar"
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 76
	header.add_theme_stylebox_override("panel", style(Color("#151515"), 0, Color("#303030"), 15))
	add_child(header)
	var row = HBoxContainer.new()
	header_tools = row
	header.add_child(row)
	brand_button = button("", show_project_home, "Back to Projects")
	brand_button.name = "HavuHome"
	brand_button.accessibility_name = "Havu, back to Projects"
	brand_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand_button.expand_icon = true
	brand_button.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 7, Color.TRANSPARENT, 6))
	row.add_child(brand_button)
	file_menu = PopupMenu.new()
	for entry in [["Projects", 6], ["New illustration", 0], ["Open…", 1], ["Save", 2], ["Save as…", 3], ["Resize canvas…", 10], ["Import image as layer…", 7], ["Export SVG…", 4], ["Export PNG…", 5], ["Export active layer as PNG…", 8]]:
		file_menu.add_item(entry[0], entry[1])
	file_menu.add_separator()
	file_menu.add_check_item("Show canvas background", 9)
	file_menu.about_to_popup.connect(func():
		file_menu.set_item_checked(file_menu.get_item_index(9), document.paper_visible))
	file_menu.id_pressed.connect(func(id):
		match id:
			0: show_new_canvas()
			1: open_dialog.popup_centered_ratio(0.75)
			2: save_project()
			3: save_as()
			4: choose_export("svg")
			5: choose_export("png")
			6: show_project_home()
			7: show_image_import()
			8: choose_layer_export()
			9: toggle_canvas_background()
			10: show_resize_canvas()
	)
	add_child(file_menu)
	var file_button = icon_button("M4 6H22M4 13H22M4 20H22", func(): pass, "File · new, open, save and export")
	file_button.pressed.disconnect(file_button.pressed.get_connections()[0].callable)
	file_button.pressed.connect(func(): file_menu.position = Vector2i(file_button.global_position + Vector2(0, 46)); file_menu.popup())
	file_button.name = "FileMenuButton"
	PopupTouch.watch_launcher(file_button, file_menu)
	row.add_child(file_button)
	var save_button := icon_button("M5 3H18L23 8V23H3V3ZM8 3V10H17V3M7 23V15H19V23", save_project, shortcut_hint("Save illustration", "Ctrl+S"))
	save_button.name = "QuickSave"
	row.add_child(save_button)
	row.add_child(VSeparator.new())
	title_edit = LineEdit.new()
	title_edit.custom_minimum_size.x = 240
	title_edit.max_length = 200
	title_edit.placeholder_text = "Untitled illustration"
	title_edit.tooltip_text = "Tap to rename the illustration"
	title_edit.accessibility_name = "Illustration name"
	title_edit.select_all_on_focus = true
	title_edit.right_icon = make_icon("M5 20L15 10L19 14L9 24H5ZM17 8L19 6L23 10L21 12Z", "#a8a8a8", 16)
	title_edit.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 5, Color.TRANSPARENT, 8))
	title_edit.text_submitted.connect(func(_value): title_edit.release_focus())
	title_edit.focus_exited.connect(rename_document)
	row.add_child(title_edit)
	save_label = label("Saved locally", 11, MUTED)
	save_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(save_label)
	var brush_button = button("", func(): toggle_brush_panel(BRUSH_LIBRARY_PANEL), "Brush library")
	brush_library_button = brush_button
	brush_button.custom_minimum_size = Vector2(112, 42)
	brush_button.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 7, Color.TRANSPARENT, 8))
	current_brush_preview = BrushPreview.new()
	current_brush_preview.preset = active_brush
	current_brush_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current_brush_preview.offset_left = 8
	current_brush_preview.offset_right = -8
	brush_button.add_child(current_brush_preview)
	row.add_child(brush_button)
	top_color = button("", toggle_color_panel, "Open Color panel")
	top_color.name = "ColorPanelButton"
	top_color.custom_minimum_size = Vector2(40, 40)
	row.add_child(top_color)
	header_layers_button = icon_button("M3 8L13 3L23 8L13 13ZM3 13L13 18L23 13M3 18L13 23L23 18",
		func(): panels.Layers.visible = not panels.Layers.visible, "Layers")
	row.add_child(header_layers_button)
	header_brush_settings = icon_button("M5 6H21M5 13H21M5 20H21M10 3V9M17 10V16M9 17V23", func(): toggle_brush_panel(BRUSH_SETTINGS_PANEL), "Brush settings")
	row.add_child(header_brush_settings)
	workspace_menu = PopupMenu.new()
	workspace_menu.add_item("Color panel", 0)
	workspace_menu.add_item("Typography", 1)
	workspace_menu.add_item("Reset workspace", 2)
	workspace_menu.add_item("Getting started…", 13)
	workspace_menu.add_item("Help & shortcuts" if show_shortcut_hints else "Help", 3)
	workspace_menu.add_item("Developer monitor", 4)
	workspace_menu.add_item("Free brush resources", 5)
	workspace_menu.add_item("Workspace settings…", 6)
	workspace_menu.add_item("Input settings…", 7)
	workspace_menu.add_item("Shape style…", 10)
	sync_selection_menu()
	workspace_menu.id_pressed.connect(func(id):
		match id:
			0: toggle_color_panel()
			1: panels.Typography.visible = not panels.Typography.visible
			2: reset_layout()
			3: show_help()
			4: developer_panel.visible = not developer_panel.visible; developer_panel.move_to_front()
			5: show_brush_resources()
			6: show_workspace_settings()
			7: input_settings_dialog.popup_centered()
			8:
				document.duplicate_selected()
			9:
				document.delete_selected()
			10: open_shape_style()
			11: change_artwork_group(false)
			12: change_artwork_group(true)
			13: show_get_started_tour()
			14: show_transform_menu.call_deferred()
			15: union_artwork()
			16: show_selection_move.call_deferred()
	)
	add_child(workspace_menu)
	var more = icon_button("M5 13h1M12 13h1M19 13h1", func(): pass, "Workspace options")
	more.pressed.disconnect(more.pressed.get_connections()[0].callable)
	more.pressed.connect(func(): workspace_menu.position = Vector2i(more.global_position + Vector2(-170, 46)); workspace_menu.popup())
	more.name = "WorkspaceMenuButton"
	more.accessibility_name = "Workspace options"
	PopupTouch.watch_launcher(more, workspace_menu)
	row.add_child(more)
	panels_menu = PopupMenu.new()
	for panel_title in PANEL_NAMES: panels_menu.add_check_item(panel_title)
	panels_menu.id_pressed.connect(func(id):
		var key: String = PANEL_NAMES[id]
		var panel = panels[key]
		panel.visible = not panel.visible
		if panel.visible: panel.move_to_front())
	add_child(panels_menu)
	var panels_button = button("Panels", func(): pass, "Show or hide workspace panels")
	header_panels_button = panels_button
	header_panels_icon = make_icon("M4 5H22V21H4ZM10 5V21")
	panels_button.pressed.disconnect(panels_button.pressed.get_connections()[0].callable)
	panels_button.pressed.connect(func():
		for index in PANEL_NAMES.size():
			panels_menu.set_item_checked(index, panels[PANEL_NAMES[index]].visible)
		panels_menu.position = Vector2i(panels_button.global_position + Vector2(-120, 46))
		panels_menu.popup())
	PopupTouch.watch_launcher(panels_button, panels_menu)
	row.add_child(panels_button)

func build_panel_close_target() -> void:
	var target = PanelContainer.new()
	target.name = "HidePanelDropTarget"
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	target.offset_left = -56
	target.offset_right = 56
	target.offset_top = -FOOTER_HEIGHT - 99.0
	target.offset_bottom = -FOOTER_HEIGHT - 27.0
	target.add_theme_stylebox_override("panel", style(Color("#242424"), 14, ACCENT, 8))
	var stack = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(stack)
	var bin = TextureRect.new()
	bin.texture = make_icon("M4 7H22M9 7V4H17V7M6 7L7 22H19L20 7M11 10V18M15 10V18")
	bin.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	bin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(bin)
	var caption = label("Hide panel", 12, Color("#eeeeee"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption)
	add_child(target)
	target.hide()
	var bin_idle = style(Color("#242424"), 14, ACCENT, 8)
	var bin_active = style(Color("#412526"), 14, Color("#f3a5a5"), 8)

	dock_preview = PanelContainer.new()
	dock_preview.name = "DockPlacementPreview"
	dock_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview_style := style(Color(0.19, 0.38, 0.31, 0.24), 0, ACCENT, 8)
	preview_style.set_border_width_all(2)
	dock_preview.add_theme_stylebox_override("panel", preview_style)
	dock_preview_label = label("", 13, ACCENT)
	dock_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dock_preview_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dock_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock_preview.add_child(dock_preview_label)
	add_child(dock_preview)
	dock_preview.hide()

	for key in panels:
		var panel = panels[key]
		panel.close_target = target
		panel.drop_preview_changed.connect(func():
			var bin_hot: bool = panel.over_close_target
			var bin_text := "Release to hide" if bin_hot else "Hide panel"
			if caption.text != bin_text:
				caption.text = bin_text
				target.add_theme_stylebox_override("panel", bin_active if bin_hot else bin_idle)
			update_dock_preview(key, panel))

func update_dock_preview(key: String, panel: Control) -> void:
	var edge: String = panel.pending_dock
	dock_preview.visible = not edge.is_empty()
	if edge.is_empty(): return
	var dimensions := panel.size
	var direction := ""
	if key == "Tools" and workspace_options.auto_orientation:
		var aligning: bool = panel.pending_dock_alignment
		var horizontal: bool = edge in ["top", "bottom"] if aligning else tools_horizontal
		if aligning:
			direction = "\nHorizontal" if horizontal else "\nVertical"
		else:
			direction = "\nKeep horizontal" if horizontal else "\nKeep vertical"
		if horizontal != tools_horizontal:
			var tool_count := tool_grid.get_child_count()
			var gap := tool_grid.get_theme_constant("h_separation" if horizontal else "v_separation")
			var span := tool_count * 44.0 + (tool_count - 1) * gap
			dimensions = Vector2(span + 12, 125) if horizontal else Vector2(68, span + 81)
	var corner: String = panel.pending_dock_corner
	var desired: Rect2 = panel.dock_preview_rect(edge, dimensions, corner)
	var obstacles := docked_group_rects(key)
	for other in panels.values():
		if other != panel and other.visible and not other.dock.is_empty():
			obstacles.append(other.get_rect())
	var destination := find_dock_slot(edge, desired, obstacles)
	panel.pending_dock_slot = destination
	if destination.has_area():
		if destination.position != desired.position: panel.pending_dock_corner = ""
		var dock_label := dock_location_label(edge, panel.pending_dock_corner)
		show_dock_placement(destination, "Dock %s%s" % [dock_label, direction])
	else:
		show_dock_placement(panel.dock_preview_rect(edge, Vector2(200, 40)), "No room · panel will float", false)

func dock_location_label(edge: String, corner: String) -> String:
	if corner.is_empty(): return edge
	return "%s %s" % ([edge, corner] if edge in ["top", "bottom"] else [corner, edge])

func show_dock_placement(destination: Rect2, caption: String, available := true) -> void:
	dock_preview_label.text = caption
	dock_preview.self_modulate = Color.WHITE if available else Color("#e6b1af")
	dock_preview.position = destination.position
	dock_preview.size = destination.size
	dock_preview.show()
	dock_preview.move_to_front()

func find_dock_slot(edge: String, desired: Rect2, obstacles: Array[Rect2]) -> Rect2:
	var work := FloatingPanel.work_area(self, true)
	if desired.size.x > work.size.x or desired.size.y > work.size.y: return Rect2()
	var axis := 0 if edge in ["top", "bottom"] else 1
	var minimum := work.position[axis]
	var maximum := work.end[axis] - desired.size[axis]
	var locations: Array[float] = [clampf(desired.position[axis], minimum, maximum), minimum, maximum]
	# Along a dock edge, the nearest feasible slot is either at the pointer's
	# projection or immediately next to the edge of a panel occupying it.
	for obstacle in obstacles:
		locations.append(obstacle.position[axis] - DOCK_GAP - desired.size[axis])
		locations.append(obstacle.end[axis] + DOCK_GAP)
	var best := Rect2()
	var best_distance := INF
	for location in locations:
		if location < minimum or location > maximum: continue
		var candidate := desired
		candidate.position[axis] = location
		var distance := absf(location - desired.position[axis])
		if distance >= best_distance: continue
		var occupied := false
		for obstacle in obstacles:
			if candidate.intersects(obstacle.grow(DOCK_GAP)):
				occupied = true
				break
		if not occupied:
			best = candidate
			best_distance = distance
	return best

func queue_dock_reflow(last: Control = null) -> void:
	if last: dock_reflow_last = last
	if dock_reflow_queued: return
	dock_reflow_queued = true
	reflow_docked_panels.call_deferred()

func reflow_docked_panels() -> void:
	dock_reflow_queued = false
	var ordered := panels.values()
	if is_instance_valid(dock_reflow_last):
		ordered.erase(dock_reflow_last)
		ordered.append(dock_reflow_last)
	dock_reflow_last = null
	reflow_panel_groups()
	var occupied := docked_group_rects()
	var changed := false
	for panel in ordered:
		if not panel.visible or panel.dock.is_empty() or panel.gesture == "move": continue
		var desired: Rect2 = panel.dock_preview_rect(panel.dock, panel.size, panel.dock_corner)
		var slot := find_dock_slot(panel.dock, desired, occupied)
		if not slot.has_area():
			panel.dock = ""
			panel.constrain()
			changed = true
			continue
		if panel.position != slot.position:
			panel.position = slot.position
			changed = true
		occupied.append(slot)
	if changed: save_layout()

func rebuild_brush_rows(reset_scroll := false) -> void:
	brush_row_buttons.clear()
	for child in brush_rows.get_children():
		brush_rows.remove_child(child)
		child.queue_free()
	if reset_scroll: brush_scroll.scroll_vertical = 0

	var category := brush_category.selected
	var custom_index := brush_category.item_count - 1
	var query := brush_search.text.strip_edges().to_lower()
	var favorites_index := custom_index - 2
	var is_quick_shelf := category == favorites_index or category == favorites_index + 1
	if is_quick_shelf:
		var catalog := {}
		for preset in builtin_brushes + presets: catalog[brush_key(preset)] = preset
		var shelf := favorite_brushes if category == favorites_index else recent_brushes
		for key in shelf:
			var preset: Dictionary = catalog.get(key, {})
			if not preset.is_empty() and brush_matches_query(preset, query): add_brush_row(preset)
	elif category != custom_index:
		var previous_category := ""
		for preset in builtin_brushes:
			if category > 0 and preset.category != BrushLibrary.CATEGORIES[category - 1]: continue
			if not brush_matches_query(preset, query): continue
			if category == 0 and preset.category != previous_category:
				brush_rows.add_child(label(preset.category, 13, MUTED))
				previous_category = preset.category
			add_brush_row(preset)
	if category == 0 or category == custom_index:
		var heading_added := false
		for preset in presets:
			if not brush_matches_query(preset, query): continue
			if category == 0 and not heading_added:
				brush_rows.add_child(label("My brushes", 13, MUTED))
				heading_added = true
			add_brush_row(preset)

	if brush_row_buttons.is_empty():
		var message := "No brushes match your search."
		if query.is_empty():
			if category == favorites_index: message = "Select a brush and tap the star to favorite it."
			elif is_quick_shelf: message = "Brushes you pick appear here."
			else: message = "Save or import a brush to see it here."
		var empty_state = label(message, 14, MUTED)
		empty_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brush_rows.add_child(empty_state)
	update_brush_selection()
	queue_brush_preview_refresh()

func brush_matches_query(preset: Dictionary, query: String) -> bool:
	if query.is_empty(): return true
	var searchable: String = preset.name + " " + preset.get("collection", "")
	return query in searchable.to_lower()

func queue_brush_preview_refresh() -> void:
	if brush_preview_refresh_queued: return
	brush_preview_refresh_queued = true
	refresh_brush_previews.call_deferred()

func refresh_brush_previews() -> void:
	brush_preview_refresh_queued = false
	var view := brush_scroll.get_global_rect()
	var open := brush_scroll.is_visible_in_tree()
	for row in brush_row_buttons:
		row.get_node("StrokePreview").visible = open and view.intersects(row.get_global_rect())

func add_brush_row(preset: Dictionary) -> void:
	var hint: String = preset.name
	if preset.has("collection"): hint += " · Adapted from " + preset.collection
	var row = button("", func(): apply_brush(preset), hint)
	row.custom_minimum_size = Vector2(180, 64)
	row.toggle_mode = true
	row.set_meta("preset", preset)
	row.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 7, Color.TRANSPARENT, 4))
	var selected_style = style(Color("#2c302e"), 7, ACCENT, 4)
	row.add_theme_stylebox_override("pressed", selected_style)
	row.add_theme_stylebox_override("hover_pressed", selected_style)

	var title = label(preset.name, 14)
	title.name = "BrushName"
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 10
	title.offset_right = -10
	title.offset_top = 4
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)
	var star := label("★", 13, ACCENT)
	star.name = "FavoriteMark"
	row.add_child(star)
	star.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	star.offset_left = -26
	star.offset_top = 4

	var preview = BrushPreview.new()
	preview.name = "StrokePreview"
	preview.hide()
	preview.preset = preset
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 10
	preview.offset_right = -10
	preview.offset_top = 24
	preview.offset_bottom = -4
	row.add_child(preview)
	brush_rows.add_child(row)
	brush_row_buttons.append(row)

func update_brush_selection() -> void:
	var active_favorite := brush_key(active_brush) in favorite_brushes
	brush_favorite_button.set_pressed_no_signal(active_favorite)
	brush_favorite_button.tooltip_text = "Remove from Favorites" if active_favorite else "Add the active brush to Favorites"
	for row in brush_row_buttons:
		var preset: Dictionary = row.get_meta("preset")
		var favorite := brush_key(preset) in favorite_brushes
		row.set_pressed_no_signal(is_same(preset, active_brush))
		row.get_node("FavoriteMark").visible = favorite
		row.get_node("BrushName").offset_right = -29 if favorite else -10

func apply_brush(preset: Dictionary, keep_draft := true) -> void:
	canvas.finish()
	if not preset.has("local_id") and saved_brush_index(preset) >= 0: preset.local_id = validated_brush_id()
	var previous := brush_key(active_brush)
	var draft := draft_brush(active_brush.name)
	if keep_draft and brush_draft_changed(draft): brush_drafts[previous] = draft
	else: brush_drafts.erase(previous)
	active_brush = preset
	load_brush_editor(brush_drafts.get(brush_key(preset), preset))
	set_tool("brush")
	brush_library_button.tooltip_text = "%s · Brush library" % preset.name
	record_recent_brush(preset)
	if brush_category.selected == brush_category.item_count - 2: rebuild_brush_rows()
	else: update_brush_selection()

func show_brush_resources() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Free brushes"
	var box = VBoxContainer.new()
	box.custom_minimum_size.x = 430
	var detail := label("All %d Havu brushes are included. Download individual .myb files from the collections below, then import them in Brushes. Imported settings use Havu’s brush engine." % builtin_brushes.size(), 15)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 360
	box.add_child(detail)
	box.add_child(button("Import brushes…", func():
		dialog.hide()
		dialog.queue_free()
		import_brush()))
	for collection in BrushLibrary.AdaptedBrushes.SOURCES:
		var url: String = BrushLibrary.AdaptedBrushes.SOURCES[collection]
		box.add_child(button(collection + " · CC0 brush settings", func(): OS.shell_open(url)))
	dialog.add_child(box)
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.popup_centered()
