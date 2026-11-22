extends SceneTree
## Run with godot --headless --path . --script res://tests/benchmark_edits.gd
## Omit --headless and set HAVU_BENCH_FRAMES=1 to sample rendered frames.
## Set HAVU_BENCH_CACHE=1 to exercise the tablet layer-cache code on desktop.
const Document = preload("res://scripts/document.gd")
const Canvas = preload("res://scripts/canvas.gd")

func _initialize() -> void:
	run.call_deferred()

func percentile(samples: Array[float], fraction: float) -> float:
	samples.sort()
	return samples[ceili(samples.size() * fraction) - 1]

func run() -> void:
	var frames := OS.has_environment("HAVU_BENCH_FRAMES")
	var cached := OS.has_environment("HAVU_BENCH_CACHE")
	if frames:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for count in [120, 600, 2400]:
		var doc := Document.new()
		doc.blank(1600, 1200)
		var ids: Array[String] = []
		for index in count:
			if index > 0 and index % (count / 3) == 0:
				doc.layers.append(doc.new_layer())
				doc.active += 1
				doc.layers[doc.active].opacity = 0.75
			var mark := {"kind": "ellipse", "color": "#237259", "opacity": 1.0, "extent": [26, 26]}
			if index % 5 == 0:
				var points := []
				for sample in 48:
					points.append([sample * 0.6, sin(sample * 0.25) * 5, 0.5, "#237259"])
				mark = {"kind": "stroke", "brush": "ink", "color": "#237259", "size": 8.0, "opacity": 0.85, "points": points}
			mark.pos = [40 + (index % 40) * 34, 60 + (index / 40) * 16]
			doc.add(mark)
			if ids.size() < 120: ids.append(mark.id)
		var canvas := Canvas.new()
		canvas.cache_completed_paint = cached
		canvas.size = Vector2(1000, 760)
		canvas.document = doc
		root.add_child(canvas)
		if frames:
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
		# Repeated misses near the far corner measure broad-phase selection
		# without being dominated by the narrow phase of a single large path.
		doc.active = doc.layers.size() - 1
		var pick_times: Array[float] = []
		for i in 25:
			var tick := Time.get_ticks_usec()
			canvas.hit(Vector2(1400 + i, 1150), true)
			if i > 0: pick_times.append((Time.get_ticks_usec() - tick) / 1000.0)
		print("%4d objects | pick miss p95 %6.3f ms" % [count, percentile(pick_times, 0.95)])
		for selected in [30, 120]:
			doc.select_objects(ids.slice(0, selected))
			var start := Vector2(80, 70)
			canvas.start = start
			if not canvas.begin_selection_move(start):
				printerr("Benchmark selection could not start")
				quit(1)
				return
			var first_update := 0.0
			var updates: Array[float] = []
			var frame_times: Array[float] = []
			for index in 41:
				var tick := Time.get_ticks_usec()
				canvas.update_selection_move(start + Vector2(4 + index, 5))
				var duration := (Time.get_ticks_usec() - tick) / 1000.0
				if index == 0: first_update = duration
				else: updates.append(duration)
				if frames:
					await RenderingServer.frame_post_draw
					if index > 0: frame_times.append((Time.get_ticks_usec() - tick) / 1000.0)
			var tick := Time.get_ticks_usec()
			canvas.finish()
			var finish_ms := (Time.get_ticks_usec() - tick) / 1000.0
			tick = Time.get_ticks_usec()
			doc.undo()
			var undo_ms := (Time.get_ticks_usec() - tick) / 1000.0
			tick = Time.get_ticks_usec()
			doc.redo()
			var redo_ms := (Time.get_ticks_usec() - tick) / 1000.0
			doc.undo()
			print("%4d objects, %3d selected | move p95 %6.3f ms | first %7.3f | release %7.3f | undo %7.3f | redo %7.3f | frame p95 %7.3f | static %7.2f MiB" % [
				count, selected, percentile(updates, 0.95), first_update, finish_ms, undo_ms, redo_ms,
				percentile(frame_times, 0.95) if frames else -1.0, OS.get_static_memory_usage() / 1048576.0])
		canvas.queue_free()
		await process_frame
		await process_frame
	await benchmark_paint(frames)
	quit()

func benchmark_paint(frames: bool) -> void:
	var doc := Document.new()
	doc.blank(1600, 1200, false)
	for index in 1200:
		doc.add({"kind": "rect", "color": "#237259", "opacity": 1.0, "extent": [15, 15],
			"pos": [30 + (index % 40) * 37, 30 + (index / 40) * 37]})
	doc.layers.append(doc.new_layer("Paint", "paint"))
	doc.active = 1
	var canvas := Canvas.new()
	canvas.size = Vector2(1000, 760)
	canvas.document = doc
	root.add_child(canvas)
	var releases: Array[float] = []
	var undos: Array[float] = []
	for index in 8:
		var samples := []
		for sample in 32:
			samples.append([100 + sample * 3.0, 100.0 + sin(sample * 0.35) * 9.0, 0.72, "#ad5338"])
		var stroke := {"kind": "stroke", "brush": "soft", "size": 26.0,
			"color": "#ad5338", "opacity": 0.75, "pos": [index * 36, index * 27], "scale": 1.0, "points": samples}
		var tick := Time.get_ticks_usec()
		var result := doc.commit_paint(stroke, false)
		if result != OK: printerr("Paint benchmark commit failed: ", result)
		releases.append((Time.get_ticks_usec() - tick) / 1000.0)
		if frames: await RenderingServer.frame_post_draw
	for index in 8:
		var tick := Time.get_ticks_usec()
		doc.undo()
		undos.append((Time.get_ticks_usec() - tick) / 1000.0)
		if frames: await RenderingServer.frame_post_draw
	print("1200 background objects | raster Soft commit p95 %6.3f ms | paint undo p95 %6.3f" % [
		percentile(releases, 0.95), percentile(undos, 0.95)])
	canvas.queue_free()
