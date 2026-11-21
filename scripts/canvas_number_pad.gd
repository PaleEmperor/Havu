extends ConfirmationDialog
## Editable dimensions with a touch keypad and hardware keyboard support.

signal value_entered(value: String)

var minimum := 64
var maximum := 10000
var entry: LineEdit
var keys: GridContainer
var range_hint: Label
var replace_on_digit := true

func _ready() -> void:
	dialog_hide_on_ok = false
	ok_button_text = "Apply"
	get_ok_button().custom_minimum_size.y = 44
	get_cancel_button().custom_minimum_size.y = 44

	var layout := VBoxContainer.new()
	layout.custom_minimum_size.x = 244
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	entry = LineEdit.new()
	entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.custom_minimum_size.y = 48
	entry.max_length = str(maximum).length()
	entry.virtual_keyboard_enabled = false
	entry.select_all_on_focus = true
	entry.add_theme_font_size_override("font_size", 24)
	entry.text_changed.connect(func(_value):
		replace_on_digit = false
		refresh_validity())
	layout.add_child(entry)
	register_text_enter(entry)

	keys = GridContainer.new()
	keys.columns = 3
	layout.add_child(keys)
	for digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "Clear", "0", "⌫"]:
		var key := Button.new()
		key.text = digit
		key.name = "Backspace" if digit == "⌫" else ("Clear" if digit == "Clear" else "Digit" + digit)
		key.accessibility_name = "Backspace" if digit == "⌫" else digit
		key.custom_minimum_size = Vector2(0, 48)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.focus_mode = Control.FOCUS_NONE
		key.pressed.connect(press_key.bind(digit))
		keys.add_child(key)

	range_hint = Label.new()
	range_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	range_hint.text = "%d–%d px" % [minimum, maximum]
	layout.add_child(range_hint)
	confirmed.connect(apply_number)

func choose(dimension: String, value: String) -> void:
	title = dimension
	entry.accessibility_name = dimension
	entry.text = value
	replace_on_digit = true
	refresh_validity()
	popup_centered()
	entry.edit()
	entry.select_all()

func press_key(key: String) -> void:
	match key:
		"Clear": entry.text = ""
		"⌫": entry.text = entry.text.left(-1)
		_: entry.text = key if replace_on_digit else (entry.text + key).left(entry.max_length)
	replace_on_digit = false
	entry.deselect()
	entry.caret_column = entry.text.length()
	refresh_validity()

func refresh_validity() -> void:
	var value := entry.text.strip_edges()
	var valid := value.is_valid_int() and value.to_int() >= minimum and value.to_int() <= maximum
	get_ok_button().disabled = not valid
	range_hint.modulate = Color.WHITE if valid else Color("#ffc5b9")

func apply_number() -> void:
	entry.apply_ime()
	refresh_validity()
	if get_ok_button().disabled: return
	var value := str(entry.text.to_int())
	hide()
	value_entered.emit(value)
