extends Node
## Graphics benchmark for a real project. Set HAVU_BENCH_PROJECT to a .havu file
## on desktop, or place a copy at user://project-benchmark.havu in a diagnostic APK.
const Art = preload("res://scripts/artwork.gd")
const Document = preload("res://scripts/document.gd")
const Canvas = preload("res://scripts/canvas.gd")
const FIXTURE := "user://project-benchmark.havu"
const SAVE := "user://benchmark-output.havu"
var stats := {}
var app
var canvas: Canvas
var doc: Document

func _ready() -> void:
	run.call_deferred()

func frame() -> void:
	await RenderingServer.frame_post_draw

func start() -> int:
	return Time.get_ticks_usec()

func ms(tick: int) -> float:
	return (Time.get_ticks_usec() - tick) / 1000.0

func record(label: String, cpu: float, total: float) -> void:
	if not stats.has(label):
		stats[label] = [[], []]
		print("HAVU_PROJECT_STAGE ", label)
	stats[label][0].append(cpu)
	stats[label][1].append(total)

func measure(label: String, action: Callable, render := true) -> void:
	var tick := start()
	action.call()
	var cpu := ms(tick)
	if render: await frame()
	record(label, cpu, ms(tick))

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var source := OS.get_environment("HAVU_BENCH_PROJECT")
	if source.is_empty(): source = FIXTURE
	app = load("res://main.tscn").instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	app.autosave_timer.stop()
	canvas = app.canvas
	doc = app.document
	canvas.cache_completed_paint = true
	canvas.cache_extra_layers = true
	if not FileAccess.file_exists(source):
		printerr("HAVU_PROJECT_ERROR missing benchmark fixture")
		get_tree().quit(1)
		return
	var tick := start()
	await app.load_project(source, false)
	if app.project_home.visible:
		printerr("HAVU_PROJECT_ERROR project did not open")
		get_tree().quit(1)
		return
	record("Open in studio", 0.0, ms(tick))
	var initial_index: int = doc.active
	var initial_id: String = doc.layers[initial_index].id
	var dense := 0
	for index in doc.layers.size():
		if doc.layers[index].objects.size() > doc.layers[dense].objects.size(): dense = index
	var dense_id: String = doc.layers[dense].id
	var center := canvas.size * 0.5
	await frame()
	for index in 16:
		await measure("Pan", canvas.pan_by.bind(Vector2(12, 7) * (1 if index < 8 else -1)))
	canvas.finish_cache_navigation()
	canvas.fit()
	await frame()
	for index in 14:
		await measure("Zoom", canvas.zoom_at.bind(1.04 if index < 7 else 1.0 / 1.04, center))
	canvas.finish_cache_navigation()
	canvas.fit()
	await frame()
	for index in 8:
		await measure("Show / hide dense layer", app.toggle_layer_flag.bind(dense_id, "visible"))
		await measure("Pick displayed color", canvas.sample_visible_color.bind(center, canvas.to_document(center)), false)
	for index in 4:
		await measure("Select dense layer", app.select_layer.bind(dense_id))
		await measure("Select drawing layer", app.select_layer.bind(initial_id))
	app.set_tool("brush")
	for engine in ["ink", "mix"]:
		canvas.brush = engine
		canvas.brush_size = 12.0
		for index in 4:
			var point := Vector2(doc.width * 0.22, doc.height * (0.22 + index * 0.05))
			await measure(engine + " down", canvas.begin.bind(canvas.origin + point * canvas.zoom, 0.62))
			if not canvas.drawing or canvas.current.get("brush") != engine:
				printerr("HAVU_PROJECT_ERROR expected %s stroke on the active layer" % engine)
				get_tree().quit(1)
				return
			for sample in 12:
				var next := point + Vector2(doc.width * (sample + 1) * 0.042, sin(sample * 0.52) * 22)
				await measure(engine + " move", canvas.update_stroke.bind(canvas.origin + next * canvas.zoom, 0.7))
			await measure(engine + " release", canvas.finish)
			await measure(engine + " undo", doc.undo)
	app.select_layer(dense_id)
	var ids: Array[String] = []
	for object in doc.layers[dense].objects:
		if object.kind != "image" and ids.size() < 30: ids.append(object.id)
	for index in 6:
		await measure("Object miss", canvas.hit.bind(Vector2(-50 - index, 20), true), false)
	doc.select_objects(ids)
	if not ids.is_empty():
		await measure_transform(ids.slice(0, 1), 4)
		if ids.size() > 1: await measure_transform(ids, 2)
		app.set_tool("brush")
	app.select_layer(initial_id)
	for index in 3:
		await measure("Serialize and save", doc.save_to.bind(SAVE), false)
		await measure("Read and validate", Document.read_project.bind(SAVE), false)
		await measure("Serialize SVG", Art.svg.bind(doc, false), false)
	tick = start()
	await app.export_png("user://benchmark-output.png")
	record("Export PNG", 0.0, ms(tick))
	for label in stats:
		var values: Array = stats[label]
		var n: int = values[0].size()
		values[0].sort()
		values[1].sort()
		print("HAVU_PROJECT %-24s n=%2d CPU p95=%8.2f ms total p50=%8.2f ms p95=%8.2f ms max=%8.2f ms" %
			[label, n, values[0][ceili(n * 0.95) - 1], values[1][ceili(n * 0.50) - 1],
			values[1][ceili(n * 0.95) - 1], values[1][-1]])
	print("HAVU_PROJECT_DONE")
	get_tree().quit()

func measure_transform(ids: Array[String], repeats: int) -> void:
	app.set_tool("select")
	for repeat in repeats:
		doc.select_objects(ids)
		var grouped := ids.size() > 1 and doc.group_selected()
		await frame()
		canvas.start = canvas.items_bounds(canvas.transformable_items()).get_center()
		if canvas.begin_selection_move(canvas.start):
			for index in 12:
				await measure("Move %d selected" % ids.size(),
					canvas.update_selection_move.bind(canvas.start + Vector2(10 + index * 4, 12)))
			await measure("Commit move %d" % ids.size(), canvas.finish)
			await measure("Undo move %d" % ids.size(), doc.undo)
		if grouped: doc.undo()
