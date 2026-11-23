extends SceneTree
## Desktop graphics benchmark. Run with godot --path . --audio-driver Dummy
## --script res://tests/benchmark_workflows.gd -- --test
const Art = preload("res://scripts/artwork.gd")
const Document = preload("res://scripts/document.gd")
const Canvas = preload("res://scripts/canvas.gd")
const SAVE_PATH := "user://benchmark-workflows.havu"
const REPEATS := 12

var elapsed := {}
var app
var doc: Document

func _initialize() -> void:
	run.call_deferred()

func percentile(samples: Array, fraction: float) -> float:
	samples.sort()
	return samples[ceili(samples.size() * fraction) - 1]

func measure(label: String, action: Callable, render := true) -> Variant:
	var started := Time.get_ticks_usec()
	var result = action.call()
	var cpu := (Time.get_ticks_usec() - started) / 1000.0
	if render: await RenderingServer.frame_post_draw
	if not elapsed.has(label): elapsed[label] = [[], []]
	elapsed[label][0].append(cpu)
	elapsed[label][1].append((Time.get_ticks_usec() - started) / 1000.0)
	return result

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.autosave_timer.stop()
	doc = app.document
	doc.blank(1600, 1200, false)
	var ids: Array[String] = []
	for layer in 30:
		if layer > 0: doc.layers.append(doc.new_layer("Artwork %d" % layer))
		doc.active = layer
		for index in 80:
			var pos := [20 + (index % 15) * 76, 35 + (index / 15) * 55 + layer * 12]
			var object := {"kind": "rect", "pos": pos, "extent": [33, 26], "opacity": 1.0, "color": "#237259"}
			if index % 4 == 0:
				var points := []
				for step in 48: points.append([step * 1.5, sin(step * 0.23) * 5, 0.7, "#237259"])
				object = {"kind": "stroke", "pos": pos, "opacity": 0.8, "color": "#237259",
					"brush": "ink", "size": 11.0, "points": points}
			doc.add(object)
			if ids.size() < 120: ids.append(object.id)
	doc.active = 0
	doc.selection = ""
	doc.commit()
	var root_id: String = doc.layers[0].id
	var destination: String = doc.layers[2].id
	for index in 2:
		doc.active = index
		var mark := {"kind": "rect", "pos": [1300 + index * 28, 605], "extent": [32, 30],
			"opacity": 1.0, "color": "#237259"}
		doc.add(mark)
	for x in [1300, 1328]:
		var mark := {"kind": "rect", "pos": [x, 680], "extent": [32, 30],
			"opacity": 1.0, "color": "#237259"}
		doc.add(mark)
	var union_ids: Array[String] = [doc.layers[1].objects[-2].id, doc.layers[1].objects[-1].id]
	doc.select_objects([])
	doc.commit()
	app.enter_project()
	app.canvas.fit()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for index in REPEATS:
		doc.select_objects(ids)
		await measure("Group 120 stroke/shape objects", doc.group_selected)
		await measure("Mirror the group", app.canvas.turn_selection.bind(0.0, 1))
		doc.undo()
		doc.undo()
		doc.select_objects(ids)
		await measure("Duplicate 120", doc.duplicate_selected)
		await measure("Undo duplication", doc.undo)
		doc.select_objects(ids)
		await measure("Move 120 to another layer", doc.move_selection_to_layer.bind(destination))
		doc.undo()
		doc.select_objects(ids)
		await measure("Delete 120", doc.delete_selected)
		doc.undo()
		doc.select_objects(union_ids)
		await measure("Union two shapes", doc.union_selected)
		doc.undo()
		doc.active = doc.layer_index(root_id)
		var fill_object: Dictionary = doc.layers[0].objects[1]
		await measure("Fill an existing shape", doc.recolor_shape.bind(0, fill_object, "#bb4455"))
		doc.undo()
		await measure("Resize and fit artwork", doc.resize_canvas.bind(Vector2i(1400, 1000), Document.ResizeArtwork.FIT))
		doc.undo()
		await measure("Reorder a layer", doc.move_layer.bind(2, 4))
		doc.undo()
		await measure("Save Havu", doc.save_to.bind(SAVE_PATH), false)
		var loaded: Dictionary = await measure("Read and validate Havu", Document.read_project.bind(SAVE_PATH), false)
		if loaded.has("error"):
			printerr(loaded.error)
			quit(1)
			return
		await measure("SVG serialization", Art.svg.bind(doc), false)
	for label in elapsed:
		var values: Array = elapsed[label]
		print("%-36s | CPU p50 %7.2f ms | CPU p95 %7.2f ms | complete p95 %7.2f ms" % [
			label, percentile(values[0], 0.5), percentile(values[0], 0.95), percentile(values[1], 0.95)])
	print("Engine allocations at end: %.2f MiB" % (OS.get_static_memory_usage() / 1048576.0))
	DirAccess.remove_absolute(SAVE_PATH)
	quit()
