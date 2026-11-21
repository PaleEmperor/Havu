extends ConfirmationDialog

signal value_entered(value: String)

const TEXT_ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l"],
	["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"],
]
const SYMBOL_ROWS := [
	["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"],
	["-", "_", "+", "=", "/", ":", ";", "?", "'", "\""],
	["ä", "ö", "å", "ü", "ß", "é", "è", "ç", "ñ", "€"],
	["⇧", ".", ",", "[", "]", "{", "}", "<", ">", "⌫"],
]

var keyboard_type := DisplayServer.KEYBOARD_TYPE_DEFAULT
var signed_numbers := false
var max_length := 0
var multiline := false
var numeric := false
var upper := false
var symbols := false
var editor: Control
var rows: VBoxContainer
var key_buttons := {}

func _ready() -> void:
	dialog_hide_on_ok = false
	ok_button_text = "Apply"
	get_ok_button().custom_minimum_size.y = 44
	get_cancel_button().custom_minimum_size.y = 44
	multiline = keyboard_type == DisplayServer.KEYBOARD_TYPE_MULTILINE
	numeric = keyboard_type in [DisplayServer.KEYBOARD_TYPE_NUMBER, DisplayServer.KEYBOARD_TYPE_NUMBER_DECIMAL]
	var layout := VBoxContainer.new()
	layout.custom_minimum_size.x = 248 if numeric else 448
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	if multiline:
		var area := TextEdit.new()
		area.custom_minimum_size.y = 76
		area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		editor = area
	else:
		var line := LineEdit.new()
		line.custom_minimum_size.y = 44
		line.max_length = max_length
		line.select_all_on_focus = true
		editor = line
		register_text_enter(line)
	editor.virtual_keyboard_enabled = false
	editor.set_meta("in_app_text_entry", true)
	editor.accessibility_name = title
	layout.add_child(editor)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	layout.add_child(rows)
	rebuild_keys()

	confirmed.connect(func():
		if editor is LineEdit: editor.apply_ime()
		var value: String = editor.text
		hide()
		value_entered.emit(value))

func choose(value: String) -> void:
	editor.text = value
	popup_centered()
	if editor is LineEdit:
		editor.edit()
		editor.select_all()
	else:
		editor.grab_focus()
		editor.set_caret_line(editor.get_line_count() - 1)
		editor.set_caret_column(editor.get_line(editor.get_caret_line()).length())

func rebuild_keys() -> void:
	for row in rows.get_children():
		rows.remove_child(row)
		row.queue_free()
	key_buttons.clear()
	if numeric:
		var decimal := "." if keyboard_type == DisplayServer.KEYBOARD_TYPE_NUMBER_DECIMAL else "Clear"
		for keys in [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [decimal, "0", "⌫"]]:
			add_key_row(keys)
	else:
		for keys in (SYMBOL_ROWS if symbols else TEXT_ROWS): add_key_row(keys)

	var actions: Array = []
	if numeric:
		if signed_numbers: actions.append("-")
		if keyboard_type == DisplayServer.KEYBOARD_TYPE_NUMBER_DECIMAL: actions.append("Clear")
	else:
		actions.append("ABC" if symbols else "#+=")
		actions.append("Space")
		if multiline: actions.append("New line")
	actions.append("Paste")
	add_key_row(actions)

func add_key_row(keys: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	rows.add_child(row)
	for key: String in keys:
		var button := Button.new()
		button.text = key.to_upper() if upper else key
		if key.length() > 1: button.text = key
		button.accessibility_name = "Backspace" if key == "⌫" else ("Shift" if key == "⇧" else button.text)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.y = 40
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if key == "Space": button.size_flags_stretch_ratio = 4.0
		button.pressed.connect(press_key.bind(key))
		row.add_child(button)
		key_buttons[key] = button

func press_key(key: String) -> void:
	match key:
		"⇧":
			upper = not upper
			rebuild_keys()
		"#+=", "ABC":
			symbols = not symbols
			rebuild_keys()
		"⌫": erase_character()
		"Clear": editor.text = ""
		"Space": insert_text(" ")
		"New line": insert_text("\n")
		"Paste": insert_text(DisplayServer.clipboard_get())
		_: insert_text(key.to_upper() if upper else key)

func insert_text(value: String) -> void:
	if value.is_empty(): return
	if editor is LineEdit: delete_line_selection(editor)
	editor.insert_text_at_caret(value)

func erase_character() -> void:
	if editor is TextEdit:
		editor.backspace()
	elif not delete_line_selection(editor) and editor.caret_column > 0:
		editor.delete_text(editor.get_previous_composite_character_column(editor.caret_column), editor.caret_column)

func delete_line_selection(line: LineEdit) -> bool:
	if not line.has_selection(): return false
	var first := line.get_selection_from_column()
	var last := line.get_selection_to_column()
	line.deselect()
	line.delete_text(first, last)
	line.caret_column = first
	return true
