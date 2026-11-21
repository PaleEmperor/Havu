extends VBoxContainer

signal adjusted(value: Color, hue: float, commit: bool)

const TouchSlider = preload("res://scripts/touch_slider.gd")

const RGB_NAMES := ["Red", "Green", "Blue"]
const HSV_NAMES := ["Hue", "Saturation", "Value"]
const RGB_MAX := [255.0, 255.0, 255.0]
const HSV_MAX := [359.0, 100.0, 100.0]

var model: OptionButton
var labels: Array[Label] = []
var sliders: Array[HSlider] = []
var fields: Array[SpinBox] = []
var ramps: Array[Gradient] = []
var color := Color.WHITE
var hue := 0.0
var dragging := false
var syncing := false
var start_color := Color.WHITE
var start_hue := 0.0

func _ready() -> void:
	add_theme_constant_override("separation", 7)
	model = OptionButton.new()
	model.add_item("RGB")
	model.add_item("HSV")
	model.custom_minimum_size.y = 40
	model.item_selected.connect(func(_index): sync())
	add_child(model)
	for index in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		add_child(row)
		var caption := Label.new()
		caption.custom_minimum_size.x = 14
		caption.add_theme_font_size_override("font_size", 12)
		row.add_child(caption)
		labels.append(caption)
		var slider := TouchSlider.new()
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		slider.size_flags_vertical = SIZE_SHRINK_CENTER
		slider.custom_minimum_size = Vector2(52, 36)
		slider.step = 1.0
		var ramp := Gradient.new()
		var texture := GradientTexture1D.new()
		texture.gradient = ramp
		var track := StyleBoxTexture.new()
		track.texture = texture
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		slider.add_theme_stylebox_override("slider", track)
		slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
		slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
		slider.drag_started.connect(begin_adjustment)
		slider.drag_ended.connect(end_adjustment)
		slider.value_changed.connect(func(value): change_channel(index, value, not dragging))
		row.add_child(slider)
		sliders.append(slider)
		ramps.append(ramp)
		var field := SpinBox.new()
		field.custom_minimum_size = Vector2(64, 38)
		field.step = 1.0
		field.get_line_edit().add_theme_font_size_override("font_size", 13)
		field.value_changed.connect(func(value): change_channel(index, value, true))
		row.add_child(field)
		fields.append(field)
	sync()

func begin_adjustment() -> void:
	start_color = color
	start_hue = hue
	dragging = true

func end_adjustment(changed: bool) -> void:
	dragging = false
	if changed:
		adjusted.emit(color, hue, true)
	elif start_color != color or not is_equal_approx(start_hue, hue):
		set_color(start_color, start_hue)
		adjusted.emit(color, hue, false)

func set_color(value: Color, next_hue: float) -> void:
	if value == color and is_equal_approx(next_hue, hue): return
	color = value
	hue = next_hue
	if is_node_ready(): sync()

func channel_values() -> Array:
	if model.selected == 0: return [color.r * 255, color.g * 255, color.b * 255]
	return [hue * 360, color.s * 100, color.v * 100]

func change_channel(index: int, value: float, commit: bool) -> void:
	if syncing: return
	var values := channel_values()
	values[index] = value
	if model.selected == 0:
		color = Color(values[0] / 255, values[1] / 255, values[2] / 255, color.a)
		if color.s > 0.0001: hue = color.h
	else:
		hue = fposmod(values[0] / 360, 1.0)
		color = Color.from_hsv(hue, values[1] / 100, values[2] / 100, color.a)
	sync()
	adjusted.emit(color, hue, commit)

func sync() -> void:
	syncing = true
	var rgb := model.selected == 0
	var values := channel_values()
	var ranges := RGB_MAX if rgb else HSV_MAX
	var names := RGB_NAMES if rgb else HSV_NAMES
	for index in sliders.size():
		labels[index].text = names[index].left(1)
		sliders[index].tooltip_text = names[index]
		sliders[index].max_value = ranges[index]
		fields[index].max_value = ranges[index]
		sliders[index].set_value_no_signal(values[index])
		fields[index].set_value_no_signal(values[index])
		update_ramp(index, rgb)
	syncing = false

func update_ramp(index: int, rgb: bool) -> void:
	var ramp := ramps[index]
	if rgb:
		var low := Color(color.r, color.g, color.b)
		var high := low
		low[index] = 0
		high[index] = 1
		ramp.offsets = PackedFloat32Array([0, 1])
		ramp.colors = PackedColorArray([low, high])
	elif index == 0:
		ramp.offsets = PackedFloat32Array([0, 1.0 / 6, 2.0 / 6, 0.5, 4.0 / 6, 5.0 / 6, 1])
		ramp.colors = PackedColorArray([Color.RED, Color.YELLOW, Color.LIME, Color.CYAN, Color.BLUE, Color.MAGENTA, Color.RED])
	else:
		ramp.offsets = PackedFloat32Array([0, 1])
		ramp.colors = PackedColorArray([Color.from_hsv(hue, 0.0, color.v), Color.from_hsv(hue, 1.0, color.v)]) if index == 1 \
			else PackedColorArray([Color.BLACK, Color.from_hsv(hue, color.s, 1.0)])
