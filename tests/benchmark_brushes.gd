extends SceneTree
## Run with HAVU_BENCH_FRAMES=1 godot --path . --audio-driver Dummy --script res://tests/benchmark_brushes.gd -- --test
## Or use --headless without HAVU_BENCH_FRAMES for main-thread timings.
const Document = preload("res://scripts/document.gd")
const Canvas = preload("res://scripts/canvas.gd")

func _initialize() -> void:
	run.call_deferred()

func p95(values: Array[float]) -> float:
	values.sort()
	return values[ceili(values.size() * 0.95) - 1]

func frame(graphics: bool) -> void:
	if graphics: await RenderingServer.frame_post_draw
	else: await process_frame

func run() -> void:
	var graphics := OS.has_environment("HAVU_BENCH_FRAMES")
	if graphics: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for scenario in [["soft", "vector"], ["pencil", "vector"], ["ink", "vector"], ["soft", "paint"]]:
		var brush: String = scenario[0]
		var mode: String = scenario[1]
		var doc := Document.new()
		doc.blank(1200, 900)
		for layer_index in 9:
			if layer_index > 0: doc.layers.append(doc.new_layer())
			doc.active = layer_index
			for index in (96 if layer_index == 0 else 70):
				var pos := Vector2(40 + (index % 15) * 74, 35 + (index / 15) * 84 + layer_index * 7)
				if layer_index == 0 or index % 10 == 0:
					var points := []
					for sample in 42:
						points.append([sample * 1.5, 9.0 * sin(sample * 0.22), 0.63, "#2e744f"])
					doc.add({"kind":"stroke", "brush":brush, "color":"#2e744f", "opacity":0.62, "size":16.0,
						"points": points, "pos": [pos.x,pos.y]})
				else:
					doc.add({"kind":"rect", "color":"#bcaf96", "opacity":0.4, "extent":[27.0,24.0], "pos":[pos.x,pos.y]})
		if mode == "paint": doc.layers.append(doc.new_layer("Paint test", "paint"))
		var canvas := Canvas.new()
		canvas.document = doc
		canvas.cache_completed_paint = true
		canvas.size = Vector2(1100,820)
		canvas.zoom = 1.0
		canvas.brush = brush
		canvas.brush_size = 24.0
		root.add_child(canvas)
		await frame(graphics)
		await frame(graphics)
		for layer_index in ([0, 8] if mode == "vector" else [9]):
			doc.active = layer_index
			var motion: Array[float] = []
			var commit: Array[float] = []
			var commit_frame: Array[float] = []
			var undo_frame: Array[float] = []
			var redo_frame: Array[float] = []
			for pass_index in 8:
				var start := Vector2(100, 520 + pass_index * 22)
				canvas.begin(canvas.origin + start * canvas.zoom, 0.64)
				for sample in 64:
					var tick := Time.get_ticks_usec()
					var point := start + Vector2(9.0 * (1 + sample), 35.0 * sin(sample * 0.12))
					canvas.update_stroke(canvas.origin + point * canvas.zoom, 0.4 + 0.4 * absf(sin(sample * 0.13)))
					motion.append((Time.get_ticks_usec() - tick) / 1000.0)
					if sample % 8 == 7: await frame(graphics)
				var tick := Time.get_ticks_usec()
				canvas.finish()
				commit.append((Time.get_ticks_usec() - tick) / 1000.0)
				await frame(graphics)
				commit_frame.append((Time.get_ticks_usec() - tick) / 1000.0)
			for pass_index in 5:
				var tick := Time.get_ticks_usec()
				doc.undo()
				await frame(graphics)
				undo_frame.append((Time.get_ticks_usec() - tick) / 1000.0)
			for pass_index in 5:
				var tick := Time.get_ticks_usec()
				doc.redo()
				await frame(graphics)
				redo_frame.append((Time.get_ticks_usec() - tick) / 1000.0)
			print("%s %s layer %d | motion CPU %.3f ms | commit CPU %.3f ms | commit frame %.3f ms | undo frame %.3f ms | redo frame %.3f ms" % [
				brush, mode, layer_index, p95(motion), p95(commit), p95(commit_frame), p95(undo_frame), p95(redo_frame)])
		canvas.queue_free()
		await process_frame
	quit()
