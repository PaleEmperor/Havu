extends Node

signal accepted(field: Control)

const AndroidTextInput = preload("res://scripts/android_text_input.gd")
const TabletTextDialog = preload("res://scripts/tablet_text_dialog.gd")

var scope: Control
var editing: Control
var dialog: TabletTextDialog
var use_tablet_keyboard := OS.has_feature("android")
var native_prompt := AndroidTextInput.request
var native_pending := false

func watch(root: Control) -> void:
	scope = root
	get_tree().node_added.connect(watch_field)

func watch_field(node: Node) -> void:
	if not (node is LineEdit or node is TextEdit) or not scope.is_ancestor_of(node): return
	if node.has_meta("in_app_text_entry") or not node.virtual_keyboard_enabled: return
	# The native dialog owns the IME on Android, including when an S Pen
	# event also brings the underlying Godot control into edit mode.
	if OS.has_feature("android"): node.virtual_keyboard_enabled = false
	var handler := field_input.bind(node)
	if not node.gui_input.is_connected(handler): node.gui_input.connect(handler)

func field_input(event: InputEvent, field: Control) -> void:
	if not field.editable or not event is InputEventScreenTouch: return
	if event.device == InputEvent.DEVICE_ID_EMULATION or not event.pressed or event.canceled: return
	# Godot delivers Android stylus contact as mouse input. A real finger
	# tap explicitly requests the IME while a pen can still focus the field.
	if use_tablet_keyboard: request_tablet_entry.call_deferred(field)
	else: edit_inline(field, event.position)
	field.accept_event()

func edit_inline(field: Control, position: Vector2) -> void:
	if field is LineEdit:
		field.edit()
		if field.select_all_on_focus: field.select_all()
	else:
		var cell: Vector2i = field.get_line_column_at_pos(Vector2i(position))
		field.grab_focus()
		field.deselect()
		field.set_caret_line(cell.y)
		field.set_caret_column(cell.x)

func request_tablet_entry(field: Control) -> void:
	if not is_instance_valid(field) or not field.is_visible_in_tree() or not field.editable or is_instance_valid(editing): return
	var options := field_options(field)
	var apply := func(value: String):
		if not is_instance_valid(field) or not field.is_visible_in_tree(): return
		if field.get_parent() is SpinBox: value = value.replace(",", ".")
		apply_value(field, value)
	var fallback := func(): open_tablet_dialog(field, options)
	if not request_native(options, apply, fallback): fallback.call()

func request_native(options: Dictionary, apply: Callable, fallback: Callable) -> bool:
	if not use_tablet_keyboard: return false
	if native_pending: return true
	native_pending = true
	var launched: bool = native_prompt.call(options, finish_native.bind(apply, fallback))
	if not launched: native_pending = false
	return launched

func finish_native(accepted_value: bool, value: String, shown: bool, apply: Callable, fallback: Callable) -> void:
	native_pending = false
	if not shown: fallback.call()
	elif accepted_value: apply.call(value)

func field_options(field: Control) -> Dictionary:
	var title := field.accessibility_name
	if title.is_empty(): title = field.tooltip_text.split(" · ")[0]
	var options := {"title": title, "text": field.text, "type": DisplayServer.KEYBOARD_TYPE_MULTILINE}
	if title.is_empty(): options.title = "Edit text" if field is TextEdit else "Enter value"
	if field is LineEdit:
		options.type = field.virtual_keyboard_type
		options.max_length = field.max_length
	var spin := field.get_parent() as SpinBox
	if spin:
		options.text = str(spin.value) if not is_equal_approx(spin.value, roundf(spin.value)) else str(roundi(spin.value))
		options.signed = spin.min_value < 0.0 or spin.allow_lesser
		options.type = (DisplayServer.KEYBOARD_TYPE_NUMBER if is_equal_approx(spin.step, roundf(spin.step)) and spin.step > 0.0
			else DisplayServer.KEYBOARD_TYPE_NUMBER_DECIMAL)
	return options

func open_tablet_dialog(field: Control, options: Dictionary) -> void:
	if not is_instance_valid(field) or not field.is_visible_in_tree(): return
	var host := field.get_window()
	if not host: return
	editing = field
	var editor := TabletTextDialog.new()
	dialog = editor
	editor.transient = true
	editor.exclusive = true
	editor.title = options.title
	editor.keyboard_type = options.type
	editor.max_length = options.get("max_length", 0)
	editor.signed_numbers = options.get("signed", false)
	host.add_child(editor)
	editor.value_entered.connect(func(value):
		if is_instance_valid(field) and field.is_visible_in_tree(): apply_value(field, value))
	editor.visibility_changed.connect(func():
		if editor.visible: return
		editing = null
		dialog = null
		editor.queue_free())
	editor.choose(options.text)

func apply_value(field: Control, value: String) -> void:
	if field is LineEdit:
		field.text = value.left(field.max_length) if field.max_length > 0 else value
		field.text_changed.emit(field.text)
		var spin := field.get_parent() as SpinBox
		if spin: spin.apply()
	else:
		field.text = value
		field.text_changed.emit()
	accepted.emit(field)

func _exit_tree() -> void:
	if is_instance_valid(dialog): dialog.queue_free()
