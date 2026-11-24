extends Node
## Run with graphics enabled, or set benchmark_tablet_stress.tscn as the
## main scene of a separate Android diagnostic package.
const PaintTiles = preload("res://scripts/paint_tiles.gd")
const Document = preload("res://scripts/document.gd")
const Art = preload("res://scripts/artwork.gd")
const STRESS_FILE := "user://stress-output.havu"
const TIERS := [600, 2400, 6000, 9600]

var app
var canvas
var doc: Document
var samples := {}
var valid := true

func _ready() -> void:
	run.call_deferred()

func now() -> int:
	return Time.get_ticks_usec()

func elapsed(tick: int) -> float:
	return (now() - tick) / 1000.0

func draw_frame() -> void:
	await RenderingServer.frame_post_draw

func assert_result(condition: bool, message: String) -> void:
	if condition: return
	valid = false
	printerr("HAVU_STRESS_FAIL ", message)

func record(label: String, cpu: float, total: float) -> void:
	if not samples.has(label):
		samples[label] = [[], []]
		print("HAVU_STRESS_STAGE ", label)
	samples[label][0].append(cpu)
	samples[label][1].append(total)

func measure(label: String, command: Callable, draw := true) -> Variant:
	var tick := now()
	var result = command.call()
	var cpu := elapsed(tick)
	if draw: await draw_frame()
	record(label, cpu, elapsed(tick))
	return result

func quantile(values: Array, fraction: float) -> float:
	return values[ceili(values.size() * fraction) - 1]

func report(count: int) -> void:
	for label in samples:
		var cpu: Array = samples[label][0]
		var frames: Array = samples[label][1]
		cpu.sort()
		frames.sort()
		print("HAVU_STRESS %4d %-23s n=%3d CPU p95=%8.2f ms frame p50=%8.2f p95=%8.2f max=%8.2f" %
			[count, label, cpu.size(), quantile(cpu, 0.95), quantile(frames, 0.50), quantile(frames, 0.95), frames.back()])
	print("HAVU_STRESS_MEMORY %d static_mib=%.1f peak_mib=%.1f history=%d" %
		[count, OS.get_static_memory_usage() / 1048576.0, OS.get_static_memory_peak_usage() / 1048576.0, doc.history.size()])
	samples.clear()

func build_fixture(count: int) -> void:
	var fixture := Document.new()
	fixture.blank(2400, 1800)
	fixture.title = "Tablet stress · %d objects" % count
	for index in 5:
		if index > 0: fixture.layers.append(fixture.new_layer("Vector %d" % (index + 1)))
		fixture.active = index
		fixture.layers[index].opacity = 0.72 if index % 2 == 1 else 1.0
		for slot in count / 5:
			var x := 50.0 + (slot % 48) * 47.0
			var y := 55.0 + (slot / 48) * 38.0 + index * 10.0
			var mark := {"kind": "ellipse", "color": "#316951", "opacity": 0.87, "extent": [24, 21]}
			if slot % 7 == 0:
				var points := []
				for sample in 32:
					points.append([sample * 1.15, sin(sample * 0.18) * 8.0, 0.60, "#814d3a"])
				mark = {"kind": "stroke", "brush": "ink", "color": "#814d3a", "size": 7.0, "opacity": 0.85, "points": points}
			mark.pos = [x, y]
			fixture.add(mark)
	fixture.layers.append(fixture.new_layer("Paint", "paint"))
	fixture.active = 4
	doc.restore(fixture.snapshot(false), false)
	doc.history.clear()
	doc.future.clear()
	doc.changed.emit()
	app.enter_project()

func draw_strokes(engine: String, size_pixels: float, passes: int) -> void:
	var preset_id: String = {"ink": "Studio ink", "soft": "Soft shadow", "paint": "Studio paint", "grain": "Graphite shading"}[engine]
	for preset in app.builtin_brushes:
		if preset.name == preset_id:
			app.apply_brush(preset)
			break
	canvas.brush_size = size_pixels
	var layer: Dictionary = doc.layers[doc.active]
	var paint: bool = layer.type == "paint"
	var name: String = engine + (" tiles" if paint else " vector")
	var count_before: int = layer.objects.size()
	for stroke in passes:
		var first := Vector2(180.0, 930.0 + stroke * 46.0)
		var tick := now()
		canvas.begin(canvas.origin + first * canvas.zoom, 0.28)
		for event in 8:
			var point := first + Vector2((event + 1) * 111.0, sin(event * 0.72) * 49.0)
			await measure(name + " move", canvas.update_stroke.bind(canvas.origin + point * canvas.zoom, 0.30 + event * 0.08))
		await measure(name + " lift", canvas.finish)
		record(name + " stroke", 0.0, elapsed(tick))
	assert_result(layer.objects.size() > count_before, name + " stroke did not commit")
	var after: int = layer.objects.size()
	for stroke in passes:
		await measure(name + " undo", doc.undo)
	assert_result(layer.objects.size() == count_before, name + " undo did not restore object count")
	for stroke in passes:
		await measure(name + " redo", doc.redo)
	assert_result(layer.objects.size() == after, name + " redo did not restore object count")

func move_selection(count: int) -> void:
	var ids: Array[String] = []
	for mark in doc.layers[doc.active].objects.slice(0, mini(count, doc.layers[doc.active].objects.size())):
		ids.append(mark.id)
	doc.select_objects(ids)
	app.set_tool("select")
	var first: Dictionary = doc.find_object(ids.front())
	var original := Art.v(first.pos)
	canvas.start = canvas.items_bounds(canvas.transformable_items()).get_center()
	assert_result(canvas.begin_selection_move(canvas.start), "could not start group transform")
	for step in 20:
		await measure("Move %d objects" % ids.size(), canvas.update_selection_move.bind(canvas.start + Vector2(12.0 + step * 3.0, 24.0)))
	await measure("Transform commit", canvas.finish)
	var moved := Art.v(first.pos)
	assert_result(moved.distance_to(original) > 1.0, "transform did not move the selection")
	await measure("Transform undo", doc.undo)
	assert_result(Art.v(doc.find_object(ids.front()).pos).is_equal_approx(original), "transform undo changed the pose")
	await measure("Transform redo", doc.redo)
	assert_result(Art.v(doc.find_object(ids.front()).pos).is_equal_approx(moved), "transform redo changed the pose")

func compare_staged_pixels() -> void:
	if not OS.has_feature("android"): return
	var layer := {"objects": []}
	var page := Vector2i(811, 307)
	var mark := {"kind": "stroke", "brush": "soft", "size": 185.0, "color": "#316951",
		"opacity": 0.47, "pos": [0.0, 0.0], "scale": 1.0, "points": []}
	var complete := []
	for index in 50:
		complete.append([12.0 + index * 15.0, 188.0 + sin(index * 0.22) * 56.0,
			0.25 + index * 0.014, "#318457" if index % 3 == 0 else "#946251"])
	for brush in ["soft", "soft", "paint", "mix"]:
		mark.brush = brush
		mark.continuous_edges = brush != "soft"
		var staged := PaintTiles.new()
		staged.prepare_layer(layer, page)
		staged.begin_android_stage()
		assert_result(staged.native_stroke > 0, "Android raster did not launch")
		for count in range(3, complete.size(), 3):
			mark.points = complete.slice(0, count)
			staged.stage_stroke(mark, 1000)
		mark.points = complete
		staged.stage_stroke(mark, -1)
		var reference := PaintTiles.new()
		reference.prepare_layer(layer, page)
		for dab in Art.paint_footprints(mark): reference.paint_polygon(dab.polygon, dab.color)
		var mismatched := 0
		for origin in reference.changed:
			var got: Image = staged.changed.get(origin)
			if not got or got.get_data() != reference.changed[origin].get_data(): mismatched += 1
		for origin in staged.changed:
			if not reference.changed.has(origin) and not staged.changed[origin].is_invisible(): mismatched += 1
		assert_result(mismatched == 0, "Android staged raster differs from the serial painter")
		print("HAVU_STRESS_STAGED_PARITY brush=%s mismatched_tiles=%d" % [brush, mismatched])
		layer = reference.encode_result(layer)
		for index in layer.objects.size():
			if not layer.objects[index].has("id"): layer.objects[index].id = "tile-%d" % index

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	app = load("res://main.tscn").instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	app.autosave_timer.stop()
	canvas = app.canvas
	doc = app.document
	for count in TIERS:
		print("HAVU_STRESS_START ", count)
		await measure("Construct and open", build_fixture.bind(count))
		app.autosave_timer.stop()
		await draw_frame()
		var view: Vector2 = canvas.size * 0.5
		var dense_id: String = doc.layers[3].id
		var work_id: String = doc.layers[4].id
		for index in 10:
			await measure("Pan", canvas.pan_by.bind(Vector2(20, 9) * (1 if index < 5 else -1)))
			await measure("Zoom", canvas.zoom_at.bind(1.08 if index < 5 else 1.0 / 1.08, view))
		canvas.finish_cache_navigation()
		canvas.fit()
		await draw_frame()
		for index in 3:
			await measure("Layer visibility", app.toggle_layer_flag.bind(dense_id, "visible"))
			await measure("Layer visibility", app.toggle_layer_flag.bind(dense_id, "visible"))
			await measure("Layer choose", app.select_layer.bind(dense_id))
			await measure("Layer choose", app.select_layer.bind(work_id))
		await move_selection(120 if count < 2400 else 360)
		for engine in ["ink", "soft", "grain"]:
			await draw_strokes(engine, 100.0 if engine == "soft" else 17.0, 4)
		await measure("Select paint layer", app.select_layer.bind(doc.layers[5].id))
		await draw_strokes("paint", 155.0, 4)
		await draw_strokes("soft", 185.0, 4)
		var saved = await measure("Save", doc.save_to.bind(STRESS_FILE), false)
		assert_result(saved == OK, "save failed")
		var decoded: Dictionary = await measure("Read and validate", Document.read_project.bind(STRESS_FILE), false)
		assert_result(decoded.has("project") and decoded.project.layers.size() == doc.layers.size(), "saved stress document failed validation")
		await measure("Serialize SVG", Art.svg.bind(doc, false), false)
		report(count)
		if not valid: break
	if valid: compare_staged_pixels()
	print("HAVU_STRESS_DONE ", "pass" if valid else "fail")
	get_tree().quit(0 if valid else 1)
