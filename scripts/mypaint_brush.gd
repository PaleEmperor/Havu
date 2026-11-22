extends RefCounted
## Converts the pressure response and static settings of a MyPaint JSON preset
## into an editable Havu brush. It does not run libmypaint's dab engine.

const BrushLibrary = preload("res://scripts/brush_library.gd")
const PRESSURE_SETTINGS := ["radius_logarithmic", "opaque", "opaque_multiply"]
const UNSUPPORTED_EFFECTS := {
	"Dabs while holding still": ["dabs_per_second"],
	"Color shifts and special blend modes": ["change_color_h", "change_color_l", "change_color_hsl_s",
		"change_color_v", "change_color_hsv_s", "colorize", "posterize", "paint_mode"],
	"Per-dab position or size jitter": ["offset_by_speed", "offset_by_speed_slowness", "radius_by_random",
		"offset_y", "offset_x", "offset_angle", "offset_angle_2", "offset_angle_asc", "offset_angle_view", "offset_angle_2_asc", "offset_angle_2_view"],
	"Smudge sampling and transparency": ["smudge_radius_log", "smudge_transparency", "smudge_bucket", "smudge_length_log"],
	"Pixel snapping or built-in alpha lock": ["snap_to_pixel", "lock_alpha"],
}

static func convert(source: Dictionary, path: String) -> Dictionary:
	if source.get("version") != 3 or not source.get("settings") is Dictionary:
		return {"error": "Choose a MyPaint version 3 (.myb) brush."}
	var settings: Dictionary = source.settings
	var radius = settings.get("radius_logarithmic")
	if not radius is Dictionary or not number(radius.get("base_value")):
		return {"error": "This MyPaint brush has no readable radius."}
	if has_nonzero_value(settings, "eraser"):
		return {"error": "This preset is an eraser. Use Havu’s Eraser tool for erasing."}

	var low_width := radius_at(settings, 0.0)
	var mid_width := radius_at(settings, 0.5)
	var full_width := radius_at(settings, 1.0)
	var diameter := clampf(2.0 * maxf(low_width, maxf(mid_width, full_width)), 1.0, 150.0)
	var width_floor := clampf(2.0 * low_width / diameter, 0.02, 1.0)

	var light_opacity := opacity_at(settings, 0.05)
	var mid_opacity := opacity_at(settings, 0.5)
	var firm_opacity := opacity_at(settings, 1.0)
	var opacity := maxf(0.01, maxf(light_opacity, maxf(mid_opacity, firm_opacity)))
	var opacity_floor := clampf(light_opacity / opacity, 0.0, 1.0)

	var hardness := clampf(value_at(settings, "hardness", 0.5, 0.8), 0.0, 1.0)
	var blend := clampf(value_at(settings, "smudge", 0.5, 0.0), 0.0, 1.0)
	var tip_ratio := 1.0 / maxf(1.0, value_at(settings, "elliptical_dab_ratio", 0.5, 1.0))
	var scatter := maxf(0.0, value_at(settings, "offset_by_random", 0.5, 0.0))
	var engine := "ink"
	if blend >= 0.50: engine = "mix"
	elif hardness < 0.55: engine = "soft"
	elif scatter >= 0.35: engine = "chalk"
	elif tip_ratio < 0.92: engine = "marker" if blend < 0.1 else "paint"
	elif blend >= 0.1: engine = "paint"
	else: tip_ratio = 1.0
	var tracking := maxf(0.0, value_at(settings, "slow_tracking", 0.5, 0.0))
	tracking += maxf(0.0, value_at(settings, "slow_tracking_per_dab", 0.5, 0.0))
	var smoothing := minf(0.85, 1.0 - exp(-tracking * 0.14))
	var preset := BrushLibrary.preset(brush_name(source, path), engine, diameter, opacity, blend, smoothing)
	var dabs := value_at(settings, "dabs_per_actual_radius", 0.5, 2.0)
	dabs += value_at(settings, "dabs_per_basic_radius", 0.5, 0.0)
	preset.spacing = clampf(0.5 / maxf(0.001, dabs), 0.06, 0.55)
	preset.minimum_width = width_floor
	preset.pressure_curve = map_curve(width_floor, clampf(2.0 * mid_width / diameter, 0.0, 1.0), 0.15, 3.5)
	preset.opacity_pressure = 1.0 - opacity_floor
	preset.opacity_curve = map_curve(opacity_floor, mid_opacity / opacity, 0.25, 4.0)
	preset.tip_ratio = clampf(tip_ratio, 0.14, 1.0)
	preset.tip_angle = wrapf(value_at(settings, "elliptical_dab_angle", 0.5, 0.0), -180.0, 180.0)
	if engine == "soft": preset.feather = clampf(1.0 - hardness, 0.15, 0.95)
	if engine in BrushLibrary.WET_ENGINES:
		preset.pigment_carry = clampf(value_at(settings, "smudge_length", 0.5, 0.55), 0.0, 0.95)
	if engine == "chalk":
		preset.grain_spread = clampf(0.35 + scatter * 0.5, 0.2, 1.2)
	preset.collection = "MyPaint"
	var limits := compatibility_limits(settings, preset, low_width, full_width, light_opacity, firm_opacity, scatter)
	preset.import_source = {"format": "MyPaint", "version": 3,
		"compatibility": "limited" if limits.size() >= 3 else ("partial" if not limits.is_empty() else "high"),
		"limits": limits}
	return {"preset": preset, "adapted": true}

static func compatibility_limits(settings: Dictionary, preset: Dictionary, low_width: float,
		full_width: float, low_opacity: float, full_opacity: float, scatter: float) -> PackedStringArray:
	var limits := PackedStringArray()
	for label in UNSUPPORTED_EFFECTS:
		for key in UNSUPPORTED_EFFECTS[label]:
			if not has_nonzero_value(settings, key): continue
			limits.append(label)
			break
	var input_labels := {}
	for key in settings:
		var entry = settings[key]
		if not entry is Dictionary or not entry.get("inputs") is Dictionary: continue
		for input in entry.inputs:
			var points = entry.inputs[input]
			if not points is Array or points.is_empty(): continue
			if input == "pressure" and key in PRESSURE_SETTINGS: continue
			var label := "Tilt, direction, rotation or speed dynamics" if input != "pressure" else "Pressure effects beyond size and opacity"
			input_labels[label] = true
	limits.append_array(PackedStringArray(input_labels.keys()))
	for index in range(1, 8):
		var pressure := index / 8.0
		var fitted_width: float = preset.size * lerpf(preset.minimum_width, 1.0, pow(pressure, preset.pressure_curve))
		var fitted_opacity: float = preset.opacity * lerpf(1.0 - preset.opacity_pressure, 1.0, pow(pressure, preset.opacity_curve))
		if absf(radius_at(settings, pressure) * 2.0 - fitted_width) > maxf(1.0, preset.size * 0.12) \
				or absf(opacity_at(settings, pressure) - fitted_opacity) > 0.12:
			limits.append("Abrupt or non-standard pressure response")
			break
	if full_width < low_width or full_opacity < low_opacity:
		if not limits.has("Abrupt or non-standard pressure response"): limits.append("Abrupt or non-standard pressure response")
	if preset.blend >= 0.1: limits.append("Original smudge behavior uses Havu’s color mixing")
	if scatter > 0.0: limits.append("Scatter uses Havu’s grain or changes shape")
	return limits

static func has_nonzero_value(settings: Dictionary, key: String) -> bool:
	var entry = settings.get(key)
	if not entry is Dictionary: return false
	if number(entry.get("base_value")) and not is_zero_approx(float(entry.base_value)): return true
	var inputs = entry.get("inputs")
	if not inputs is Dictionary: return false
	for points in inputs.values():
		if not points is Array: continue
		for point in points:
			if point is Array and point.size() == 2 and number(point[1]) and not is_zero_approx(float(point[1])):
				return true
	return false

static func brush_name(source: Dictionary, path: String) -> String:
	var file_part := path.uri_decode().get_file()
	var file_name := file_part.get_basename()
	var declared = source.get("name", "")
	if declared is String and not declared.strip_edges().is_empty():
		return declared.replace("\n", " ").replace("\r", " ").strip_edges().left(100)
	if not file_name.is_empty() and (not path.begins_with("content://") or not file_part.get_extension().is_empty()):
		return file_name.replace("_", " ").left(100)
	var parent = source.get("parent_brush_name", "")
	if parent is String and not parent.get_file().is_empty(): return parent.get_file().replace("_", " ").left(100)
	return "Imported MyPaint brush"

static func radius_at(settings: Dictionary, pressure: float) -> float:
	return exp(clampf(value_at(settings, "radius_logarithmic", pressure, 2.0), -8.0, 5.0))

static func opacity_at(settings: Dictionary, pressure: float) -> float:
	var base := clampf(value_at(settings, "opaque", pressure, 1.0), 0.0, 1.0)
	return base * clampf(value_at(settings, "opaque_multiply", pressure, 1.0), 0.0, 1.0)

static func map_curve(floor_value: float, mid_value: float, minimum: float, maximum: float) -> float:
	if floor_value >= 0.999: return 1.0
	var normalized := clampf((mid_value - floor_value) / (1.0 - floor_value), 0.001, 0.999)
	return clampf(log(normalized) / log(0.5), minimum, maximum)

static func value_at(settings: Dictionary, key: String, pressure: float, default: float) -> float:
	var entry = settings.get(key)
	if not entry is Dictionary or not number(entry.get("base_value")): return default
	var base := clampf(float(entry.base_value), -10000.0, 10000.0)
	var inputs = entry.get("inputs")
	if not inputs is Dictionary: return base
	var points = inputs.get("pressure")
	if not points is Array or points.is_empty(): return base
	var previous := Vector2(-INF, 0.0)
	for point in points:
		if not point is Array or point.size() != 2 or not number(point[0]) or not number(point[1]): return base
		var sample := Vector2(clampf(float(point[0]), -10000.0, 10000.0), clampf(float(point[1]), -10000.0, 10000.0))
		if sample.x < previous.x: return base
		if pressure < sample.x:
			if not previous.is_finite(): return base + sample.y
			return base + lerpf(previous.y, sample.y, inverse_lerp(previous.x, sample.x, pressure))
		previous = sample
	return base + previous.y

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)
