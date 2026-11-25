extends "res://tests/benchmark_tablet_stress.gd"
## Uses the same touch-driven canvas entry points and rendered-frame timing as the tablet stress suite.

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	app = load("res://main.tscn").instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	app.autosave_timer.stop()
	canvas = app.canvas
	doc = app.document
	build_fixture(2400)
	await draw_frame()
	for engine in ["ink", "pencil", "soft"]:
		await symmetric_brush(engine, false)
	app.select_layer(doc.layers[5].id)
	await symmetric_brush("soft", true)
	await symmetric_brush("pencil", true)
	app.select_layer(doc.layers[4].id)
	canvas.configure_symmetry(CanvasMode.OFF, 6, false)
	await cut_workloads()
	report(2400)
	build_fixture(7200)
	await draw_frame()
	await symmetric_brush("pencil", false)
	canvas.configure_symmetry(CanvasMode.OFF, 6, false)
	await radial_repeat_workloads()
	await cut_workloads()
	report(7200)
	compare_symmetric_raster()
	print("HAVU_SYMMETRY_DONE ", "pass" if valid else "fail")
	get_tree().quit(0 if valid else 1)

const CanvasMode = preload("res://scripts/drawing_symmetry.gd").Mode

func radial_repeat_workloads() -> void:
	var stroke := {"kind": "stroke", "brush": "ink", "size": 12.0, "opacity": 1.0,
		"pos": [1200, 900], "scale": 1.5, "angle": 0.57, "mirrored": true, "color": "#45726d", "points": []}
	for index in 256: stroke.points.append([12.0 + index * 0.79, sin(index * 0.04) * 18.0, 0.72, "#45726d"])
	doc.append_with_history(stroke)
	var layer: Dictionary = doc.layers[doc.active]
	var original_count: int = layer.objects.size()
	var pivot := Art.object_transform(stroke) * Art.v(stroke.points[0])
	app.show_transform_menu()
	var menu: PopupMenu = app.transform_menu
	assert_result(not menu.is_item_disabled(menu.get_item_index(13)), "Transform did not offer radial repeat for a selected stroke")
	menu.hide()
	app.transform_action(13)
	await get_tree().process_frame
	var dialog := app.get_node_or_null("RadialRepeat") as ConfirmationDialog
	assert_result(dialog != null, "radial repeat options did not open")
	if dialog:
		dialog.confirmed.emit()
		assert_result(layer.objects.size() == original_count + 5, "radial repeat dialog did not default to six arms")
		doc.undo()
		await draw_frame()
	for attempt in 7:
		var result: String = await measure("Repeat 12 ink arms", doc.repeat_radially.bind({"layer": layer, "object": stroke}, 12))
		assert_result(result.is_empty() and layer.objects.size() == original_count + 11, "radial repeat failed to create arms")
		if not result.is_empty(): return
		for index in 11:
			var copy: Dictionary = layer.objects[original_count + index]
			var pose := Art.object_transform(copy)
			var tip := Art.object_transform(stroke) * Art.v(stroke.points[-1])
			var expected := pivot + (tip - pivot).rotated(TAU * (index + 1) / 12)
			assert_result((pose * Art.v(copy.points[0])).distance_to(pivot) < 0.01 and
				(pose * Art.v(copy.points[-1])).distance_to(expected) < 0.01, "repeat missed the original pivot or angle")
		await measure("Repeat undo", doc.undo)
		assert_result(layer.objects.size() == original_count and doc.selection == stroke.id, "repeat undo changed the original")
		await measure("Repeat redo", doc.redo)
		assert_result(layer.objects.size() == original_count + 11, "repeat redo did not restore the complete pattern")
		doc.undo()
		await draw_frame()

func symmetric_brush(engine: String, pixel_layer: bool) -> void:
	app.set_tool("brush")
	canvas.brush = engine
	canvas.brush_profile = {"spacing": 0.11}
	canvas.brush_size = 155.0 if engine == "soft" else 33.0
	canvas.opacity = 0.7 if engine == "soft" else 1.0
	var arm_count := 6 if engine == "ink" else 12
	canvas.configure_symmetry(CanvasMode.RADIAL, arm_count, true)
	var label := "%d %s %s" % [arm_count, engine, "paint" if pixel_layer else "vector"]
	var initial: Array = doc.layers[doc.active].objects.duplicate()
	for attempt in 4:
		var first := Vector2(1280, 910 + 19 * attempt)
		canvas.begin(canvas.origin + first * canvas.zoom, 0.65)
		for event in 16:
			var next := first + Vector2((event + 1) * 27.0, sin(event * 0.58) * 27.0)
			await measure(label + " move", canvas.update_stroke.bind(canvas.origin + next * canvas.zoom, 0.67))
		await measure(label + " lift", canvas.finish)
		var changed: Array = doc.layers[doc.active].objects.duplicate()
		assert_result(changed != initial and (pixel_layer or changed.size() == initial.size() + arm_count),
			label + " failed to commit all its arms")
		await measure(label + " undo", doc.undo)
		assert_result(doc.layers[doc.active].objects == initial, label + " did not undo cleanly")
		await measure(label + " redo", doc.redo)
		assert_result(doc.layers[doc.active].objects == changed, label + " did not redo exactly")
		doc.undo()
		await draw_frame()

func cut_workloads() -> void:
	var layer: Dictionary = doc.layers[doc.active]
	var shape := {"kind": "rect", "pos": [270, 250], "extent": [1550, 1130], "color": "#356850", "opacity": 0.82}
	doc.append_with_history(shape)
	var id: String = shape.id
	var holes := [0, 6]
	for prior in holes:
		if prior > 0:
			for offset in prior:
				var result := doc.cut_vector_shape({"layer": layer, "object": doc.find_object(id)},
					cut_loop(Vector2(420 + offset * 205, 1040), 48, 52))
				assert_result(result.is_empty(), "setup cut failed")
		for density in [48, 512]:
			for attempt in 7:
				var loop := cut_loop(Vector2(845, 670), 223, density)
				var item := {"layer": layer, "object": doc.find_object(id)}
				var result: String = await measure("Cut %d pts / %d holes" % [density, prior], doc.cut_vector_shape.bind(item, loop))
				assert_result(result.is_empty() and not Art.contains(doc.find_object(id), Vector2(845, 670)),
					"cut failed to produce a hole")
				await measure("Cut undo / %d holes" % prior, doc.undo)
				assert_result(Art.contains(doc.find_object(id), Vector2(845, 670)), "cut undo failed")

func cut_loop(center: Vector2, radius: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in count:
		var angle := TAU * index / count
		points.append(center + Vector2.from_angle(angle) * radius * (1.0 + 0.035 * sin(8.0 * angle)))
	return points

func compare_symmetric_raster() -> void:
	var fixture := Document.new()
	fixture.blank(640, 640, false, "paint")
	var layer: Dictionary = fixture.layers[0]
	var stroke := {"kind": "stroke", "brush": "soft", "size": 105.0, "opacity": 0.6,
		"pos": [0, 0], "scale": 1.0, "color": "#45726d", "points": []}
	for index in 20:
		stroke.points.append([345.0 + index * 7, 322.0 + sin(index * 0.2) * 10.0, 0.72, "#45726d"])
	var symmetry := preload("res://scripts/drawing_symmetry.gd")
	var strokes: Array[Dictionary] = [stroke]
	for pose in symmetry.poses(CanvasMode.RADIAL, 12, Vector2(320, 320)):
		strokes.append(symmetry.stroke_instance(stroke, pose))
	var footprints := Art.paint_footprints(stroke)
	var reference := PaintTiles.new()
	reference.prepare_layer(layer, Vector2i(640, 640))
	for arm in strokes:
		var pose := Art.object_transform(arm)
		for footprint in footprints: reference.paint_polygon(pose * footprint.polygon, footprint.color)
	var expected := reference.encode_result(layer)
	var actual := PaintTiles.new().apply_instances(layer, Vector2i(640, 640), strokes, false)
	var by_origin := {}
	for tile in expected.objects: by_origin[Vector2i(Art.v(tile.pos))] = tile
	var missing := false
	var error_sum := 0
	var channels := 0
	var worst := 0
	for tile in actual.objects:
		var key := Vector2i(Art.v(tile.pos))
		if not by_origin.has(key):
			missing = true
			continue
		var a: PackedByteArray = Art.Raster.get_asset(tile).image.get_data()
		var b: PackedByteArray = Art.Raster.get_asset(by_origin[key]).image.get_data()
		for index in a.size():
			var delta := absi(a[index] - b[index])
			error_sum += delta
			worst = maxi(worst, delta)
		channels += a.size()
	var mean := float(error_sum) / maxi(channels, 1)
	print("HAVU_SYMMETRY_RASTER tiles=%d channels=%d mean_delta=%.4f max_delta=%d" %
		[actual.objects.size(), channels, mean, worst])
	assert_result(not missing and actual.objects.size() == expected.objects.size() and mean < 0.5 and worst <= 16,
		"symmetric raster diverges from the reference")
