extends SceneTree
## Run with godot --headless --path . --script res://tests/benchmark_layers.gd.
## Run with a graphics driver and HAVU_BENCH_FRAMES=1 to include presentation time.
const Document = preload("res://scripts/document.gd")

func _initialize() -> void:
	run.call_deferred()

func p95(values: Array[float]) -> float:
	values.sort()
	return values[ceili(values.size() * 0.95) - 1]

func frame() -> void:
	await process_frame
	if OS.has_environment("HAVU_BENCH_FRAMES"):
		await RenderingServer.frame_post_draw

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frame()
	app.project_home.hide()
	app.autosave_timer.stop()
	app.canvas.cache_completed_paint = true
	var doc: Document = app.document
	doc.blank(1200, 1000, false)
	for layer_number in 30:
		if layer_number > 0: doc.layers.append(doc.new_layer("Artwork %d" % layer_number))
		doc.active = layer_number
		for index in 80:
			var mark := {"kind": "ellipse", "color": "#247552", "opacity": 1.0, "extent": [26.0, 18.0]}
			if index % 4 == 0:
				var points := []
				for sample in 32:
					points.append([sample * 0.8, sin(sample * 0.3) * 5.0, 0.75, "#247552"])
				mark = {"kind": "stroke", "brush": "ink", "color": "#247552", "size": 7.0, "opacity": 1.0, "points": points}
			mark.pos = [float(index % 35) * 32.0, float(index / 35) * 23.0 + layer_number * 23.0]
			doc.add(mark)
	doc.commit()
	await frame()
	var selection: Array[float] = []
	var visibility: Array[float] = []
	var visible_frames: Array[float] = []
	var layer_id: String = doc.layers[15].id
	for index in 28:
		var tick := Time.get_ticks_usec()
		app.select_layer(doc.layers[index % 30].id)
		selection.append((Time.get_ticks_usec() - tick) / 1000.0)
		await frame()
		tick = Time.get_ticks_usec()
		app.toggle_layer_flag(layer_id, "visible")
		visibility.append((Time.get_ticks_usec() - tick) / 1000.0)
		await frame()
		if OS.has_environment("HAVU_BENCH_FRAMES"):
			visible_frames.append((Time.get_ticks_usec() - tick) / 1000.0)
	print("2,400 objects / 30 layers | select p95 %.3f ms | hide/show p95 %.3f ms" % [p95(selection), p95(visibility)])
	if not visible_frames.is_empty(): print("hide/show frame p95 %.3f ms" % p95(visible_frames))
	quit()
