extends "res://tests/benchmark_tablet_stress.gd"
## Run the same in-memory geometry and end-to-end workload on either build.

const VectorFill = preload("res://scripts/vector_fill.gd")
const SEED := Vector2(540, 500)

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	app = load("res://main.tscn").instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	app.autosave_timer.stop()
	canvas = app.canvas
	doc = app.document
	for count in [600, 2400, 7200]:
		await fill_fixture(count, false)
		await fill_fixture(count, true)
		report(count)
	print("HAVU_FILL_DONE ", "pass" if valid else "fail")
	get_tree().quit(0 if valid else 1)

func fill_fixture(count: int, dense: bool) -> void:
	var fixture := Document.new()
	fixture.blank(2400, 1800, false)
	var layer: Dictionary = fixture.layers[0]
	fixture.add({"kind": "polygon", "pos": [420, 420], "opacity": 1.0, "color": "#226451",
		"vertices": [[0, 0], [250, 0], [250, 12], [12, 12], [12, 180], [250, 180], [250, 192], [0, 192]]})
	fixture.add({"kind": "rect", "pos": [663, 422], "extent": [13, 188], "opacity": 1.0, "color": "#226451"})
	for index in count - 2:
		var p := Vector2(890 + index % 110 * 12, 90 + (index / 110) * 19)
		if dense and index < 150:
			p = Vector2(364 + index % 25 * 14, 345 + (index / 25) * 10)
		fixture.add({"kind": "ellipse", "pos": [p.x, p.y], "extent": [10, 8],
			"opacity": 0.85, "color": "#273f30"})
	doc.restore(fixture.snapshot(false), false)
	doc.history.clear()
	doc.future.clear()
	doc.changed.emit()
	app.enter_project()
	app.set_tool("fill")
	canvas.color = Color("#dd6f47")
	await draw_frame()
	var label := "Dense" if dense else "Sparse"
	var live_layer: Dictionary = doc.layers[0]
	var nearby := func(radius: float) -> Array: return canvas.pick_candidate_indices(live_layer, SEED, radius)
	for attempt in 6:
		var query := VectorFill.find_region.bind(live_layer.objects, SEED, canvas.page_bounds(), canvas.pick_bounds)
		if canvas.has_method("update_fill_pick_grid"):
			query = VectorFill.find_region.bind(live_layer.objects, SEED, canvas.page_bounds(), canvas.pick_bounds, nearby)
		var geometry: Dictionary = await measure(label + " region", query, false)
		assert_result(not geometry.is_empty(), label + " region was not detected")
		await measure(label + " Fill tap", canvas.fill_at.bind(SEED))
		var fill := doc.find_object(doc.selection)
		assert_result(doc.layers[0].objects.size() == count + 1 and not fill.is_empty() and Art.contains(fill, SEED),
			label + " fill tap failed")
		await measure(label + " Fill undo", doc.undo)
		assert_result(doc.layers[0].objects.size() == count, label + " undo failed")
		await measure(label + " Fill redo", doc.redo)
		assert_result(doc.layers[0].objects.size() == count + 1, label + " redo failed")
		doc.undo()
		await draw_frame()
