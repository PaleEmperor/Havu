extends SceneTree
## Run on a graphics-enabled viewport. The same workload is used in the Android diagnostic export.
const Canvas = preload("res://scripts/canvas.gd")
const Document = preload("res://scripts/document.gd")
const Art = preload("res://scripts/artwork.gd")
const TABLET_FIXTURE := "user://ink-benchmark.havu"

func _initialize() -> void:
	run.call_deferred()

func p95(samples: Array[float]) -> float:
	samples.sort()
	return samples[ceili(samples.size() * 0.95) - 1]

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var fixture := OS.get_environment("HAVU_BENCH_PROJECT")
	if fixture.is_empty() and FileAccess.file_exists(TABLET_FIXTURE): fixture = TABLET_FIXTURE
	for alpha in [1.0, 0.65]:
		var doc := Document.new()
		doc.blank(1200, 900)
		for layer in 4:
			if layer > 0: doc.layers.append(doc.new_layer())
			doc.active = layer
			for index in 120:
				var points := []
				for sample in 26: points.append([sample * 2.0, sin(sample * 0.18) * 9.0, 0.55, "#435e4d"])
				doc.add({"kind": "stroke", "brush": "ink", "color": "#435e4d", "opacity": 1.0, "size": 11.0,
					"points": points, "pos": [35 + (index % 15) * 72, 35 + (index / 15) * 70 + layer * 9]})
		if not fixture.is_empty():
			var error := doc.load_from(fixture)
			if not error.is_empty():
				printerr("HAVU_FLICK_ERROR ", error)
				quit(1)
				return
		var canvas := Canvas.new()
		canvas.document = doc
		canvas.cache_completed_paint = true
		canvas.size = get_root().get_visible_rect().size
		canvas.brush = "ink"
		canvas.brush_size = 5.0
		canvas.opacity = alpha
		canvas.smoothing = 0.5
		get_root().add_child(canvas)
		canvas.fit()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		for layer_index in ([0, 3] if fixture.is_empty() else [doc.active]):
			doc.active = layer_index
			var moves: Array[float] = []
			var frames: Array[float] = []
			var commits: Array[float] = []
			var tip_error := 0.0
			var release_error := 0.0
			for pass_index in 12:
				var first := Vector2(70, 70 + pass_index * 57)
				var width_scale := minf(1.0, (doc.width - 120.0) / 1035.0)
				canvas.begin(canvas.origin + first * canvas.zoom, 0.65)
				for sample in 10:
					var point := first + Vector2(94.0 * width_scale * (sample + 1), 31.0 * sin(sample * 0.71))
					var started := Time.get_ticks_usec()
					canvas.update_stroke(canvas.origin + point * canvas.zoom, 0.64 + 0.21 * sin(sample * 0.25))
					moves.append((Time.get_ticks_usec() - started) / 1000.0)
					await RenderingServer.frame_post_draw
					frames.append((Time.get_ticks_usec() - started) / 1000.0)
					tip_error = maxf(tip_error, Art.v(canvas.current.points[-1]).distance_to(point) * canvas.zoom)
				var endpoint := first + Vector2(1035 * width_scale, 18)
				var release := InputEventMouseButton.new()
				release.button_index = MOUSE_BUTTON_LEFT
				release.position = canvas.origin + endpoint * canvas.zoom
				var started := Time.get_ticks_usec()
				canvas._gui_input(release)
				await RenderingServer.frame_post_draw
				commits.append((Time.get_ticks_usec() - started) / 1000.0)
				var committed: Dictionary = doc.layers[layer_index].objects.back()
				release_error = maxf(release_error, Art.v(committed.points[-1]).distance_to(endpoint) * canvas.zoom)
			print("HAVU_FLICK alpha=%.2f layer=%d move_p95=%.2f ms frame_p95=%.2f ms release_p95=%.2f ms tip=%.2f px release_error=%.2f px" %
				[alpha, layer_index, p95(moves), p95(frames), p95(commits), tip_error, release_error])
		canvas.queue_free()
		await process_frame
	print("HAVU_FLICK_DONE")
	quit()
