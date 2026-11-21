extends RefCounted
## The names describe presets for Havu's vector brush engines.
const AdaptedBrushes = preload("res://scripts/adapted_brushes.gd")
const CATEGORIES = ["Inking", "Sketching", "Markers & lettering", "Painting", "Blending", "Glazes & shading", "Dry textures", "Watercolor", "Effects"]
const ENGINES := ["ink", "paint", "mix", "soft", "pencil", "chalk", "marker"]
const WET_ENGINES := ["paint", "mix", "soft"]
const DRY_ENGINES := ["pencil", "chalk"]
const PROFILE_LIMITS := {"pressure_curve": [0.15, 3.5], "tip_ratio": [0.14, 1.0],
	"tip_angle": [-180, 180], "grain": [0.2, 1.8], "minimum_width": [0.02, 1.0],
	"opacity_pressure": [0.0, 1.0], "spacing": [0.06, 0.55], "grain_size": [0.4, 1.5],
	"grain_spread": [0.2, 1.2], "feather": [0.15, 0.95], "pigment_load": [0.0, 1.8],
	"pigment_carry": [0.0, 0.95], "deposit_curve": [0.35, 3.5], "pickup_curve": [0.35, 3.5],
	"pressure_floor": [0.0, 0.45], "pressure_ceiling": [0.55, 1.0], "opacity_curve": [0.25, 4.0],
	"taper_start": [0.0, 4.0], "taper_end": [0.0, 4.0], "taper_tip": [0.05, 1.0]}

static func profile_default(key: String, engine: String) -> float:
	match key:
		"tip_ratio": return 0.25 if engine == "marker" else 1.0
		"tip_angle": return -45.0 if engine == "marker" else 0.0
		"minimum_width": return 0.12
		"opacity_pressure", "pressure_floor", "taper_start", "taper_end": return 0.0
		"taper_tip": return 0.08
		"spacing": return 0.16
		"feather": return 0.8
		"pigment_carry": return 0.55
		"deposit_curve": return 1.4
	return 1.0

static func map_pressure(pressure: float, profile: Dictionary) -> float:
	var low: float = profile.get("pressure_floor", 0.0)
	var high: float = profile.get("pressure_ceiling", 1.0)
	return clampf((pressure - low) / (high - low), 0.0, 1.0)

static func mix_pigment(picked: Color, underlying: Color, carried: Color, pressure: float,
		engine: String, blending: float, profile: Dictionary) -> Color:
	var pickup_curve: float = profile.get("pickup_curve", 1.0)
	var pickup_response := 1.0 - pressure if pickup_curve == 1.0 else pow(1.0 - pressure, pickup_curve)
	var pickup := blending * pickup_response * (0.8 if engine == "mix" else 0.35)
	var carry_strength: float = profile.get("pigment_carry", 0.55)
	var load_amount: float = profile.get("pigment_load", 1.0)
	var deposit_curve: float = profile.get("deposit_curve", 1.4)
	var deposit := (pow(pressure, deposit_curve) * (0.8 if engine == "mix" else 1.2) + (1.0 - blending) * 0.5) * load_amount
	return carried.lerp(underlying, 1.0 - carry_strength) \
		.lerp(picked, clampf(deposit, 0.02, 1.0) if load_amount > 0.0 else 0.0).lerp(underlying, pickup)

static func stabilize(point: Vector2, previous: Vector2, distance: float, strength: float, limit: float) -> Vector2:
	return point.move_toward(previous, minf(distance * strength * 0.55, limit))

static func profile_from(preset_or_stroke: Dictionary) -> Dictionary:
	var profile := {}
	for key in PROFILE_LIMITS:
		if preset_or_stroke.has(key): profile[key] = float(preset_or_stroke[key])
	return profile

static func valid_profile(preset_or_stroke: Dictionary) -> bool:
	for key in PROFILE_LIMITS:
		if not preset_or_stroke.has(key): continue
		var value = preset_or_stroke[key]
		var limits: Array = PROFILE_LIMITS[key]
		if not (value is float or value is int) or not is_finite(value) or value < limits[0] or value > limits[1]: return false
	return true

static func preset(name: String, brush: String, size: float, opacity: float, blend: float, smoothing: float) -> Dictionary:
	return {"format": "havu-brush", "version": 1, "name": name, "brush": brush, "size": size, "opacity": opacity, "blend": blend, "smoothing": smoothing}

static func builtins() -> Array:
	# Each group defines its palette in display order. Values after the engine
	# are size, opacity, color pickup, and stabilization.
	var groups = [
		[
			["Studio ink", "ink", 18, 1, 0, 0.35],
			["Fine liner", "ink", 4, 1, 0, 0.50],
			["Detail nib", "ink", 2, 1, 0, 0.22],
			["Loose ink", "ink", 12, 1, 0, 0.08],
			["Poster ink", "ink", 48, 1, 0, 0.55],
			["Ink wash line", "ink", 32, 0.42, 0, 0.20],
		],
		[
			["Graphite", "pencil", 12, 0.70, 0, 0.18],
			["Soft pencil", "pencil", 28, 0.48, 0, 0.15],
			["Hard pencil", "pencil", 4, 0.85, 0, 0.10],
			["Loose layout", "pencil", 19, 0.32, 0, 0.04],
			["Graphite shading", "pencil", 62, 0.37, 0, 0.08],
			["Dense graphite", "pencil", 40, 0.92, 0, 0.24],
		],
		[
			["Chisel marker", "marker", 38, 0.80, 0, 0.22],
			["Bold lettering", "marker", 68, 1, 0, 0.60],
			["Small italic nib", "marker", 10, 0.95, 0, 0.48],
			["Broad highlighter", "marker", 72, 0.18, 0, 0.45],
			["Sign painter", "marker", 110, 0.94, 0, 0.36],
			["Brush script", "ink", 34, 1, 0, 0.64],
		],
		[
			["Studio paint", "paint", 42, 1, 0.45, 0.20],
			["Opaque block-in", "paint", 96, 1, 0.08, 0.20],
			["Pigment detail", "paint", 11, 0.95, 0.28, 0.14],
			["Cream paint", "paint", 56, 0.95, 0.64, 0.28],
			["Water wash", "soft", 98, 0.26, 0.66, 0.18],
			["Thin wash", "paint", 29, 0.34, 0.60, 0.12],
		],
		[
			["Color mixer", "mix", 56, 1, 0.85, 0.25],
			["Gentle blender", "mix", 90, 0.50, 1, 0.40],
			["Detail blender", "mix", 14, 0.81, 0.92, 0.20],
			["Pigment mixer", "mix", 39, 1, 0.48, 0.19],
			["Edge softener", "soft", 31, 0.55, 0.96, 0.17],
			["Broad blender", "mix", 142, 0.73, 0.96, 0.32],
			["Silk transition", "mix", 72, 0.68, 1, 0.32, {"pressure_curve": 0.55}],
			["Firm pigment blender", "mix", 46, 0.96, 0.78, 0.23, {"pressure_curve": 1.8}],
			["Small seam blender", "mix", 9, 0.89, 0.98, 0.15, {"pressure_curve": 0.75}],
		],
		[
			["Soft glaze", "soft", 72, 0.40, 0.70, 0.30],
			["Airbrush", "soft", 110, 0.65, 0.15, 0.30],
			["Detail airbrush", "soft", 22, 0.78, 0.17, 0.25],
			["Soft shadow", "soft", 136, 0.43, 0.35, 0.20],
			["Color veil", "soft", 145, 0.14, 0.86, 0.38],
			["Feathered light", "soft", 52, 0.76, 0.08, 0.15],
		],
		[
			["Dry chalk", "chalk", 38, 0.65, 0, 0.12],
			["Charcoal", "chalk", 62, 0.88, 0, 0.09],
			["Chalk detail", "chalk", 10, 0.86, 0, 0.16],
			["Pastel dust", "chalk", 86, 0.31, 0, 0.05],
			["Broad chalk", "chalk", 128, 0.76, 0, 0.21],
			["Fine grain", "pencil", 92, 0.19, 0, 0.12],
		],
		[
			["Tea stain", "soft", 84, 0.22, 0.65, 0.20, {"pressure_curve": 0.65}],
			["Wet lifting brush", "mix", 49, 0.43, 1, 0.17, {"pressure_curve": 0.65}],
			["Color pooling", "paint", 49, 0.30, 0.70, 0.14, {"pressure_curve": 1.45}],
		],
		[
			["Sugar dust", "pencil", 66, 0.62, 0, 0.12, {"pressure_curve": 0.65, "grain": 0.48}],
			["Char specks", "chalk", 64, 0.90, 0, 0.10, {"pressure_curve": 1.35, "grain": 0.38}],
			["Velvet grain", "chalk", 48, 0.36, 0, 0.14, {"pressure_curve": 0.80, "grain": 1.55}],
		],
	]
	var adapted := AdaptedBrushes.presets()
	var result = []
	for group_index in groups.size():
		var category: String = CATEGORIES[group_index]
		for spec in groups[group_index]:
			var brush = preset(spec[0], spec[1], spec[2], spec[3], spec[4], spec[5])
			brush.category = category
			if spec.size() > 6: brush.merge(spec[6])
			result.append(brush)
		for brush in adapted:
			if brush.category == category: result.append(brush)
	return result
