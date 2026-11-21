extends SceneTree
const PngExport = preload("res://scripts/png_export.gd")
const Raster = preload("res://scripts/raster_asset.gd")
const Document = preload("res://scripts/document.gd")
const Art = preload("res://scripts/artwork.gd")
const BrushLibrary = preload("res://scripts/brush_library.gd")
const PigmentIndex = preload("res://scripts/pigment_index.gd")
const Sample = preload("res://scripts/sample.gd")
var checks = 0
var failures = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	else: print("PASS: " + description)

func _initialize() -> void:
	run.call_deferred()

func stroke(color = "#226451") -> Dictionary:
	return {"kind": "stroke", "brush": "ink", "size": 20.0, "color": color, "opacity": 1.0, "points": [[10.0, 10.0, 0.1, color], [100.0, 20.0, 1.0, color], [150.0, 100.0, 0.5, color]]}

func run() -> void:
	var doc = Document.new()
	doc.blank()
	doc.checkpoint()
	doc.add(stroke())
	doc.commit()
	check(doc.layers[0].objects.size() == 1, "stroke is added to real document")
	var id = doc.selection
	var object = doc.find_object(id)
	check(Art.contains(object, Vector2(80, 18)), "stroke geometry can be selected")
	check(not Art.contains(object, Vector2(800, 900)), "selection rejects empty canvas")
	check(not Art.stroke_polygon(object).is_empty(), "pressure stroke produces vector outline")
	check(not Geometry2D.triangulate_polygon(Art.stroke_polygon(object)).is_empty(), "stroke outline triangulates")
	doc.undo()
	check(doc.layers[0].objects.is_empty(), "undo removes entire stroke")
	doc.redo()
	check(doc.layers[0].objects.size() == 1, "redo restores stroke")
	doc.selection = id
	doc.duplicate_selected()
	check(doc.layers[0].objects.size() == 2 and doc.selection != id, "duplicate creates independent object")
	doc.delete_selected()
	check(doc.layers[0].objects.size() == 1, "delete removes selected vector")
	var path = "user://roundtrip.havu"
	check(doc.save_to(path) == OK, "atomic project save succeeds")
	var reopened = Document.new()
	check(reopened.load_from(path).is_empty(), "project reopens")
	check(reopened.snapshot() == doc.snapshot(), "save/reopen preserves every document field")
	var prior = reopened.snapshot()
	var file = FileAccess.open("user://broken.havu", FileAccess.WRITE)
	file.store_string('{"format":"havu","version":1,"width":"bad"}')
	file.close()
	check(not reopened.load_from("user://broken.havu").is_empty(), "malformed project rejected")
	check(reopened.snapshot() == prior, "failed open preserves current artwork")
	var invalid = doc.snapshot()
	invalid.layers[0].objects[0].points[0][2] = -2
	check(not Document.validate(invalid).is_empty(), "invalid pressure rejected before loading")
	invalid = doc.snapshot()
	invalid.layers[0].objects[0].pos = [NAN, 0]
	check(not Document.validate(invalid).is_empty(), "non-finite coordinates rejected")
	Sample.populate(doc)
	check(Document.validate(doc.snapshot()).is_empty(), "complete café sample is a valid editable document")
	var svg = Art.svg(doc)
	check(svg.contains("<text") and svg.contains("<polygon") and svg.contains("data:font/ttf;base64,"), "SVG exports vectors and embedded typography")
	file = FileAccess.open("res://docs/cafe-example.svg", FileAccess.WRITE)
	file.store_string(svg)
	file.close()
	var catalog := BrushLibrary.builtins()
	var categories := {}
	var collections := {}
	for preset in catalog:
		categories[preset.category] = int(categories.get(preset.category, 0)) + 1
		if preset.has("collection"):
			collections[preset.collection] = int(collections.get(preset.collection, 0)) + 1
	check(catalog.size() == 124 and categories.size() == 9 and categories.values().all(func(value): return value >= 6),
		"124 bundled brushes cover nine categories")
	check(collections == {"MyPaint": 54, "SenlinOS": 19}, "both CC0 packs are bundled with source credits")
	for preset in catalog:
		var sample_stroke = stroke()
		sample_stroke.merge({"pos": [0, 0], "scale": 1.0, "brush": preset.brush, "size": preset.size, "opacity": preset.opacity}, true)
		sample_stroke.merge(BrushLibrary.profile_from(preset))
		var valid_segments := BrushLibrary.valid_profile(preset)
		if preset.brush != "ink":
			var segments = Art.segments(sample_stroke)
			for part in segments:
				if Geometry2D.triangulate_polygon(part.polygon).is_empty(): valid_segments = false
			valid_segments = valid_segments and not segments.is_empty()
		else:
			valid_segments = valid_segments and not Geometry2D.triangulate_polygon(Art.stroke_polygon(sample_stroke)).is_empty()
		check(valid_segments, "%s produces drawable vector brush geometry" % preset.name)
	var dab := {"kind": "stroke", "brush": "marker", "size": 40.0, "opacity": 1.0,
		"color": "#226451", "points": [[0, 0, 0.35, "#226451"]], "tip_ratio": 0.25,
		"tip_angle": 0, "pressure_curve": 0.55}
	var broad_tip: PackedVector2Array = Art.segments(dab)[0].polygon
	dab.tip_angle = 90
	var rotated_tip: PackedVector2Array = Art.segments(dab)[0].polygon
	check(absf(broad_tip[0].x) > absf(rotated_tip[0].x) * 3, "changing nib angle rotates the vector dab")
	dab.pressure_curve = 2.3
	var light_tip: PackedVector2Array = Art.segments(dab)[0].polygon
	check(light_tip[0].length() < rotated_tip[0].length() * 0.6, "pressure curves change stroke width at the same input pressure")
	dab.brush = "chalk"
	dab.grain = 0.35
	var scattered: int = Art.segments(dab).size()
	dab.grain = 1.45
	check(Art.segments(dab).size() > scattered * 3, "grain profiles change the density of vector marks")
	dab.grain_size = 0.85
	dab.grain_spread = 0.67
	dab.opacity_pressure = 0.6
	dab.taper_end = 2.0
	dab.points.append([4.0, 0.0, 0.7, "#b3385a"])
	var baked_grain := Art.segments(dab, 1, 2)
	var grain_instances := Art.grain_buffer(dab, 1, 2)
	var same_grain := grain_instances.size() == baked_grain.size() * Art.GRAIN_STRIDE
	for index in baked_grain.size():
		var offset := index * Art.GRAIN_STRIDE
		var center := Vector2(grain_instances[offset + 3], grain_instances[offset + 7])
		var radius := grain_instances[offset]
		var phase := grain_instances[offset + 12]
		var pigment := Color(grain_instances[offset + 8], grain_instances[offset + 9],
			grain_instances[offset + 10], grain_instances[offset + 11])
		same_grain = same_grain and pigment.is_equal_approx(baked_grain[index].color)
		for corner in Art.GRAIN_SIDES:
			var point := center + Vector2.from_angle(TAU * corner / Art.GRAIN_SIDES) * radius * (0.7 + absf(sin(phase + corner)) * 0.3)
			same_grain = same_grain and point.distance_to(baked_grain[index].polygon[corner]) < 0.001
	check(same_grain, "instanced grain retains the vector speck geometry and pressure-dependent color")
	dab.clip = [[0.0, 0.0], [2.0, 0.0], [2.0, 2.0], [0.0, 2.0]]
	check(not Art.uses_grain_instances(dab), "clipped grain uses the selection-aware vector renderer")
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.project_home.visible and not app.session_active, "Havu starts on Projects")
	check(app.undo_button.tooltip_text.ends_with("Ctrl+Z") and app.help_text().contains("F12"),
		"desktop help and tooltips show keyboard hints")
	app.show_shortcut_hints = false
	check(app.shortcut_hint("Undo · Hold to repeat", "Ctrl+Z") == "Undo · Hold to repeat"
		and app.help_text().contains("Pinch to zoom") and not app.help_text().contains("Ctrl+"),
		"tablet help and tooltips describe touch actions")
	app.show_shortcut_hints = true
	check(Art.Fonts.FACES.size() == 58 and Art.Fonts.FACES.keys().all(
		func(id): return Art.Fonts.font_for(id).resource_path == Art.Fonts.bundled_path(id)), "all 58 bundled faces load")
	check(Art.Fonts.font_for("fraunces").has_char("ä".unicode_at(0))
		and Art.Fonts.font_for("caveat").has_char("ö".unicode_at(0)), "new families support accented menu text")
	app.show_fonts()
	app.font_search.text = "stix"
	app.font_search.text_changed.emit("stix")
	check(app.font_results.get_child_count() == 4 and app.font_preview.text != "",
		"the font browser filters by family and previews the result")
	var styled_names := true
	for row in app.font_results.get_children():
		var matching: Array[Dictionary] = Art.Fonts.entries().filter(func(face): return face.name == row.text)
		styled_names = styled_names and matching.size() == 1 and row.get_theme_font("font") == Art.Fonts.font_for(matching[0].id)
	check(styled_names, "the font picker shows each listed name in its own face")
	app.fonts_dialog.hide()
	app.fonts_dialog.confirmed.emit()
	check(app.canvas.text_font.begins_with("stix_"), "using a preview selects the bundled face")
	app.font_import_dialog.files_selected.emit(PackedStringArray(["res://assets/fonts/OpenSans-Regular.ttf"]))
	var imported_face: String = app.canvas.text_font
	check(imported_face.begins_with("custom_") and app.font_choice.text == "Open Sans",
		"font selection can import and immediately use a TrueType face")
	Art.Fonts.imported.clear()
	Art.Fonts.loaded.erase(imported_face)
	Art.Fonts.scanned = false
	check(Art.Fonts.entry(imported_face).name == "Open Sans"
		and Art.Fonts.font_for(imported_face).get_font_name() == "Open Sans",
		"the imported font is available from the on-disk library")
	app.show_fonts()
	app.font_category.select(Art.Fonts.CATEGORIES.find("Imported") + 1)
	app.rebuild_font_results()
	check(app.font_results.get_child_count() == 1
		and app.font_results.get_child(0).get_theme_font("font") == Art.Fonts.font_for(imported_face),
		"imported font names use their own typefaces in the picker too")
	app.fonts_dialog.hide()
	var font_doc := Document.new()
	font_doc.blank()
	var font_text := {"kind": "text", "text": "Lunch · 12 €", "font_size": 42.0, "color": "#002218", "opacity": 1.0}
	Art.Fonts.apply_to_text(font_text, imported_face)
	font_doc.add(font_text)
	var bundled_text := {"kind": "text", "text": "Specials", "font_size": 42.0, "color": "#002218", "opacity": 1.0}
	Art.Fonts.apply_to_text(bundled_text, "stix_bold")
	font_doc.add(bundled_text)
	var text_svg := Art.svg(font_doc)
	check(text_svg.contains('font-family="Open Sans"') and text_svg.contains("data:font/otf")
		and text_svg.count("@font-face") == 1, "SVG identifies imported fonts and embeds only bundled faces in use")
	check(font_doc.save_to("user://font-roundtrip.havu") == OK
		and font_doc.load_from("user://font-roundtrip.havu").is_empty()
		and font_doc.layers[0].objects[0].font == imported_face, "font choices survive saving and reopening")
	app.choose_typography_font("serif")
	app.autosave()
	check(not FileAccess.file_exists("user://recovery.havu"), "home leaves recovery untouched")
	app.project_home.new_requested.emit()
	check(app.new_dialog.visible, "New illustration opens the canvas size dialog")
	app.apply_canvas_preset(2)
	check(app.new_canvas_dimensions() == Vector2i(2480, 3508), "A4 fills both dimension fields")
	app.swap_canvas_dimensions()
	check(app.new_canvas_dimensions() == Vector2i(3508, 2480), "swapping the dimensions turns the page landscape")
	await process_frame
	check(app.new_dialog.size.x <= 356 and app.new_dialog.size.y <= 270
		and app.new_width.size.y >= 44 and app.new_height.size.y >= 44,
		"Create Canvas fits its compact layout and keeps full-height number controls")
	tap_window_control(app.new_dialog, app.new_width)
	var number_pad = app.canvas_number_pad
	check(number_pad.visible and number_pad.title == "Width" and not number_pad.entry.virtual_keyboard_enabled,
		"tapping Width opens an in-app keypad independently of Android text input")
	await process_frame
	tap_window_control(number_pad, number_pad.keys.get_node("Digit1"))
	tap_window_control(number_pad, number_pad.keys.get_node("Digit2"))
	check(number_pad.entry.text == "12" and number_pad.get_ok_button().disabled and app.new_width.text == "3508",
		"the keypad rejects an out-of-range dimension while keeping the original value")
	tap_window_control(number_pad, number_pad.get_cancel_button())
	await process_frame
	check(not number_pad.visible and app.new_width.text == "3508", "Cancel keeps the old width")
	tap_window_control(app.new_dialog, app.new_width)
	await process_frame
	for digit in ["7", "2", "0"]: tap_window_control(number_pad, number_pad.keys.get_node("Digit" + digit))
	tap_window_control(number_pad, number_pad.get_ok_button())
	tap_window_control(app.new_dialog, app.new_height)
	await process_frame
	for digit in ["9", "6", "0"]: tap_window_control(number_pad, number_pad.keys.get_node("Digit" + digit))
	tap_window_control(number_pad, number_pad.get_ok_button())
	check(app.new_canvas_dimensions() == Vector2i(720, 960), "touch keypad applies both dimensions to the canvas dialog")
	app.new_transparent.button_pressed = true
	app.new_dialog.confirmed.emit()
	check(not app.project_home.visible and app.document.width == 720 and app.document.height == 960
		and not app.document.paper_visible, "creating a project uses the typed dimensions and transparency")
	var tour: Control = app.get_started_tour
	await process_frame
	check(tour.visible and tour.step_index == 0 and tour.target == app.zoom_button
		and tour.spotlight.has_area(), "the first blank illustration opens the workspace tour on the zoom control")
	tap_window_control(root, tour.skip_button)
	var saved_onboarding := ConfigFile.new()
	check(not tour.visible and saved_onboarding.load("user://preferences.cfg") == OK
		and saved_onboarding.get_value("onboarding", "tour_shown", false),
		"skipping the tour closes it and saves the one-time preference")
	app.workspace_menu.id_pressed.emit(13)
	check(tour.visible and tour.step_index == 0, "the three-dot menu reopens the tour at the beginning")
	tour.next_button.pressed.emit()
	check(tour.step_index == 1 and tour.target == app.brush_library_button, "Next takes the tour to the actual Brush library")
	tour.back_button.pressed.emit()
	check(tour.step_index == 0, "Back returns to the previous tour step")
	for _index in tour.steps.size(): tour.next_button.pressed.emit()
	check(not tour.visible, "Done closes the tour from the final step")
	check(app.document.layers[0].type == "vector", "new illustrations open with an editable vector layer")
	check(app.tool_buttons.fill.self_modulate.a < 0.5 and app.tool_buttons.nodes.self_modulate.a == 1.0,
		"an empty vector layer dims Fill and leaves Nodes available")
	app.tool_buttons.fill.pressed.emit()
	check(app.canvas.tool != "fill" and app.toast_label.text.begins_with("Vector Fill needs")
		and not app.tool_buttons.fill.button_pressed, "a dimmed Fill button explains its restriction without selecting the tool")
	app.file_menu.id_pressed.emit(10)
	check(app.new_dialog.visible and app.new_dialog.title == "Resize canvas"
		and app.new_canvas_dimensions() == Vector2i(720, 960) and not app.new_transparent.visible,
		"File opens the resize dialog with the current canvas dimensions")
	var adapt_option: int = app.canvas_artwork_mode.get_item_index(Document.ResizeArtwork.ADAPT)
	check(app.canvas_artwork_mode.visible and app.canvas_artwork_mode.get_selected_id() == Document.ResizeArtwork.KEEP,
		"Resize asks how artwork should follow the new bounds")
	app.canvas_artwork_mode.select(adapt_option)
	app.canvas_artwork_mode.item_selected.emit(adapt_option)
	check(app.new_dimensions_note.text.contains("follow the new edges"), "Adapt vector layout explains the resize behavior")
	await process_frame
	click_window_control(app.new_dialog, app.new_width)
	await process_frame
	for digit in ["9", "0", "0"]: click_window_control(number_pad, number_pad.keys.get_node("Digit" + digit))
	click_window_control(number_pad, number_pad.get_ok_button())
	app.new_dialog.confirmed.emit()
	check(app.document.width == 900.0 and app.document.height == 960.0 and not app.document.paper_visible
		and not app.new_dialog.visible, "resizing an existing canvas keeps its background and changes the page dimensions")
	app.document.undo()
	check(app.document.width == 720.0 and app.document.height == 960.0, "one undo restores the previous canvas dimensions")
	app.show_new_canvas()
	app.new_dialog.hide()
	app.new_transparent.button_pressed = false
	await process_frame
	var quick_save: Button = app.get_node("TopBar").find_child("QuickSave", true, false)
	var save_tap := InputEventScreenTouch.new()
	save_tap.position = quick_save.get_global_rect().get_center()
	save_tap.pressed = true
	root.push_input(save_tap, true)
	save_tap.pressed = false
	root.push_input(save_tap, true)
	check(app.save_dialog.visible and app.save_dialog.current_file.ends_with(".havu"),
		"tapping Quick Save on a new project opens Save As")
	app.save_dialog.hide()
	var title_touch := InputEventScreenTouch.new()
	title_touch.pressed = true
	title_touch.position = app.title_edit.get_global_rect().get_center()
	root.push_input(title_touch, true)
	check(app.title_edit.is_editing() and app.title_edit.get_selected_text() == "Untitled illustration",
		"touching the project name enters text editing and selects its title")
	app.title_edit.release_focus()
	var title_release := InputEventScreenTouch.new()
	title_release.position = title_touch.position
	root.push_input(title_release, true)
	doc = app.document
	app.set_tool("nodes")
	app.layer_actions.id_pressed.emit(11)
	var paint_index: int = doc.active
	var paint_history: int = doc.history.size()
	check(app.layer_actions.get_item_text(app.layer_actions.get_item_index(11)) == "New paint layer"
		and paint_index == 1 and doc.paints_pixels(), "the Layers menu can add a separate paint layer")
	check(app.canvas.tool == "brush" and app.tool_buttons.nodes.self_modulate.a < 0.5
		and app.tool_buttons.fill.self_modulate.a == 1.0, "switching to paint leaves the incompatible Nodes mode")
	await process_frame
	var nodes_touch := InputEventScreenTouch.new()
	nodes_touch.position = app.tool_buttons.nodes.get_global_rect().get_center()
	nodes_touch.index = 6
	nodes_touch.pressed = true
	root.push_input(nodes_touch.duplicate(), true)
	nodes_touch.pressed = false
	root.push_input(nodes_touch.duplicate(), true)
	check(app.canvas.tool == "brush" and app.toast.visible and app.toast_label.text == "Nodes are unavailable on paint layers.",
		"touching dimmed Nodes on a paint layer shows a short status")
	app.canvas.fit()
	for index in 4:
		var base := Vector2(70, 68 + index * 8)
		app.canvas.color = Color("#a34939")
		app.canvas.begin(app.canvas.origin + base * app.canvas.zoom, 0.92)
		app.canvas.update_stroke(app.canvas.origin + (base + Vector2(40, 0)) * app.canvas.zoom, 0.92)
		app.canvas.finish()
	check(doc.history.size() - paint_history == 4 and doc.layers[paint_index].objects.size() == 1 and doc.layers[paint_index].objects[0].paint_tile,
		"four brush gestures share one pixel tile with one undo step each")
	var held_undo := InputEventScreenTouch.new()
	held_undo.index = 4
	held_undo.pressed = true
	held_undo.position = app.undo_button.get_global_rect().get_center()
	root.push_input(held_undo, true)
	check(doc.history.size() - paint_history == 3, "touch-down undoes immediately")
	await create_timer(0.42).timeout
	check(doc.history.size() - paint_history == 2, "holding Undo repeats one step after the initial pause")
	var released_undo := InputEventScreenTouch.new()
	released_undo.index = held_undo.index
	released_undo.position = held_undo.position
	root.push_input(released_undo, true)
	await create_timer(0.23).timeout
	check(doc.history.size() - paint_history == 2 and not app.undo_button.held, "releasing Undo stops the repeats")
	doc.redo()
	check(doc.history.size() - paint_history == 3, "paint layer undo retains redo")
	var tile: Dictionary = doc.layers[paint_index].objects[0]
	check(Raster.pixel_at(tile, Vector2(85, 68)).a > 0.9 and Document.validate(doc.snapshot()).is_empty()
		and Art.svg(doc, false).contains("data:image/png;base64,"), "paint pixels survive project validation and SVG embedding")
	app.set_tool("erase")
	app.canvas.begin(app.canvas.origin + Vector2(85, 68) * app.canvas.zoom, 1.0)
	app.canvas.finish()
	check(Raster.pixel_at(doc.layers[paint_index].objects[0], Vector2(85, 68)).a < 0.1, "the eraser cuts pixels without deleting the whole paint layer")
	app.set_tool("rect")
	app.canvas.begin(app.canvas.origin + Vector2(200, 200) * app.canvas.zoom, 0.55)
	app.canvas.update_stroke(app.canvas.origin + Vector2(300, 300) * app.canvas.zoom, 0.55)
	app.canvas.finish()
	check(doc.layers.size() == 3 and doc.layers[paint_index].type == "paint" and doc.layers[paint_index + 1].objects[0].kind == "rect",
		"shape tools create editable vector objects above a paint layer")
	var vector_resize := Document.new()
	vector_resize.blank(100.0, 200.0)
	vector_resize.add({"kind": "ellipse", "pos": [10.0, 20.0], "extent": [40.0, 30.0], "color": "#79d7b4", "opacity": 1.0})
	check(vector_resize.resize_canvas(Vector2i(400, 400), Document.ResizeArtwork.FIT) == OK
		and Art.v(vector_resize.layers[0].objects[0].pos) == Vector2(120.0, 40.0)
		and vector_resize.layers[0].objects[0].scale == 2.0
		and vector_resize.layers[0].objects[0].extent == [40.0, 30.0]
		and Document.validate(vector_resize.snapshot()).is_empty(), "fit scales and centers native vector geometry without resampling")
	vector_resize.undo()
	check(vector_resize.width == 100.0 and vector_resize.layers[0].objects[0].scale == 1.0,
		"undo restores canvas dimensions and vector placement together")
	var corners_doc := Document.new()
	corners_doc.blank(400.0, 300.0)
	var corner_ids: Array[String] = []
	for place in [[20, 15], [340, 15], [20, 255], [340, 255]]:
		corners_doc.add({"kind": "rect", "pos": place, "extent": [40, 30], "color": "#336653", "opacity": 1.0})
		corner_ids.append(corners_doc.selection)
	check(corners_doc.resize_canvas(Vector2i(900, 450), Document.ResizeArtwork.ADAPT) == OK
		and Document.validate(corners_doc.snapshot()).is_empty(), "the proportional layout adapts to a wider aspect ratio")
	var corner_margin := Vector2(20.0 / 360.0 * 840.0, 22.5)
	var expected_corners := [
		corner_margin, Vector2(840.0 - corner_margin.x, corner_margin.y),
		Vector2(corner_margin.x, 405.0 - corner_margin.y), Vector2(840.0, 405.0) - corner_margin,
	]
	var corners_match := true
	for index in corner_ids.size():
		var corner_object := corners_doc.find_object(corner_ids[index])
		corners_match = corners_match and Art.v(corner_object.pos).is_equal_approx(expected_corners[index])
		corners_match = corners_match and corner_object.scale == 1.5 and corner_object.extent == [40, 30]
	check(corners_match, "each corner keeps its relative margins and the same vector proportions")
	corners_doc.undo()
	check(corners_doc.width == 400.0 and Art.v(corners_doc.find_object(corner_ids[3]).pos) == Vector2(340, 255),
		"undo restores the original corner positions")

	var group_layer := corners_doc.new_layer()
	corners_doc.layers.append(group_layer)
	corners_doc.active = 1
	corners_doc.add({"kind": "rect", "pos": [345, 230], "extent": [20, 20], "color": "#79d7b4", "opacity": 1.0})
	var nearby_id: String = corners_doc.selection
	corners_doc.select_objects([corner_ids[3], nearby_id])
	corners_doc.group_selected()
	check(corners_doc.resize_canvas(Vector2i(900, 450), Document.ResizeArtwork.ADAPT) == OK
		and (Art.v(corners_doc.find_object(nearby_id).pos) - Art.v(corners_doc.find_object(corner_ids[3]).pos))
			.is_equal_approx(Vector2(7.5, -37.5)),
		"adapting the layout keeps the spacing of a group across layers")
	var paint_resize := Document.new()
	paint_resize.blank(130.0, 130.0, false, "paint")
	var edge_pixels := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	edge_pixels.fill(Color("#79d7b4"))
	var edge_tile := Raster.encode_png(edge_pixels)
	edge_tile.merge({"kind": "image", "color": "#ffffff", "opacity": 1.0, "paint_tile": true, "pos": [128.0, 128.0]})
	paint_resize.add(edge_tile)
	check(paint_resize.resize_canvas(Vector2i(140, 140)) == OK
		and paint_resize.layers[0].objects[0].extent == [12, 12]
		and Raster.pixel_at(paint_resize.layers[0].objects[0], Vector2(1, 1)) == Color("#79d7b4")
		and Raster.pixel_at(paint_resize.layers[0].objects[0], Vector2(5, 5)).a == 0.0
		and Document.validate(paint_resize.snapshot()).is_empty(), "growing a paint canvas pads the edge tile without scaling its pixels")
	check(paint_resize.resize_canvas(Vector2i(129, 129)) == OK
		and paint_resize.layers[0].objects[0].extent == [1, 1] and Document.validate(paint_resize.snapshot()).is_empty(),
		"shrinking crops paint tiles at the new bounds")
	paint_resize.undo()
	check(paint_resize.layers[0].objects[0].extent == [12, 12]
		and Raster.pixel_at(paint_resize.layers[0].objects[0], Vector2(1, 1)) == Color("#79d7b4"),
		"undo restores cropped paint pixels")
	var edge_points := PackedVector2Array([Vector2.ZERO, Vector2(40, 0), Vector2(40, 40), Vector2(0, 40)])
	var edge_mesh := Art.screen_edge_geometry(edge_points, Geometry2D.triangulate_polygon(edge_points), Color("#79d7b4"))
	var outer_uv: Vector2 = edge_mesh.uv[4] - Art.EDGE_UV_ORIGIN
	check(edge_mesh.vertices.size() == 8 and edge_mesh.indices.size() == 30
		and edge_mesh.colors[0].a == 1.0 and edge_mesh.colors[4].a == 0.0
		and outer_uv.is_equal_approx(Vector2(-1, -1)), "filled vector edges carry an outward transparent rim")
	var reverse_points := edge_points.duplicate()
	reverse_points.reverse()
	var reverse_mesh := Art.screen_edge_geometry(reverse_points, Geometry2D.triangulate_polygon(reverse_points), Color.WHITE)
	check((reverse_mesh.uv[7] - Art.EDGE_UV_ORIGIN).is_equal_approx(outer_uv),
		"reversing the polygon winding leaves the edge rim pointing outside")
	paint_resize.layers.append(paint_resize.new_layer("Vectors"))
	paint_resize.active = 1
	paint_resize.add({"kind": "ellipse", "pos": [92.0, 10.0], "extent": [36.0, 30.0], "color": "#202020", "opacity": 1.0})
	var mixed_vector_id: String = paint_resize.selection
	check(paint_resize.resize_canvas(Vector2i(260, 140), Document.ResizeArtwork.ADAPT) == OK
		and paint_resize.find_object(mixed_vector_id).pos[0] > 170.0
		and paint_resize.layers[0].objects[0].pos == [128.0, 128.0]
		and Raster.pixel_at(paint_resize.layers[0].objects[0], Vector2(1, 1)) == Color("#79d7b4")
		and Document.validate(paint_resize.snapshot()).is_empty(),
		"mixed projects adapt vectors and keep editable paint at its original pixel coordinates")
	var fill_scene := Document.new()
	fill_scene.blank(256, 256, false, "paint")
	var enclosed := stroke("#236044")
	enclosed.merge({"pos": [0, 0], "scale": 1.0})
	enclosed.points = [[30, 30, 1.0, "#236044"], [110, 30, 1.0, "#236044"], [110, 90, 1.0, "#236044"],
		[30, 90, 1.0, "#236044"], [30, 30, 1.0, "#236044"]]
	fill_scene.commit_paint(enclosed, false)
	check(fill_scene.fill_paint(Vector2i(66, 58), Color("#ffad64")) == OK, "the bucket fills an enclosed raster brush outline")
	var filled_tile: Dictionary = fill_scene.layers[0].objects[0]
	check(Raster.pixel_at(filled_tile, Vector2(66, 58)).is_equal_approx(Color("#ffad64"))
		and Raster.pixel_at(filled_tile, Vector2(8, 8)).a == 0, "raster fill stops at the outline and leaves the outside transparent")
	var restored_paint := Document.new()
	check(fill_scene.save_to("user://paint-roundtrip.havu") == OK
		and restored_paint.load_from("user://paint-roundtrip.havu").is_empty() and restored_paint.paints_pixels()
		and Raster.pixel_at(restored_paint.layers[0].objects[0], Vector2(66, 58)).is_equal_approx(Color("#ffad64")),
		"saved paint layers reopen as editable pixels")
	restored_paint.layers.append(restored_paint.new_layer("Accent", "paint"))
	restored_paint.active = 1
	var accent := stroke("#204a9e")
	accent.merge({"pos": [0, 0], "scale": 1.0, "points": [[66.0, 58.0, 1.0, "#204a9e"]]}, true)
	restored_paint.commit_paint(accent, false)
	restored_paint.set_layer_opacity(1, 0.5)
	var paint_layers: Array[int] = [0, 1]
	check(restored_paint.merge_layers(paint_layers) and restored_paint.layers.size() == 1 and restored_paint.paints_pixels(),
		"merging two paint layers leaves one editable paint layer")
	var merged_color := Raster.pixel_at(restored_paint.layers[0].objects[0], Vector2(66, 58))
	check(merged_color.r > 0.5 and merged_color.r < 0.65 and merged_color.a == 1.0,
		"paint-layer merge composites pixels with the source opacity")
	app.canvas.fit()
	var canvas = app.canvas
	doc.blank()
	app.set_tool("brush")
	canvas.fit()
	var p0 = canvas.origin + Vector2(100, 100) * canvas.zoom
	var p1 = canvas.origin + Vector2(350, 150) * canvas.zoom
	canvas.begin(p0, 0.1)
	canvas.update_stroke(p1, 0.9)
	canvas.finish()
	check(doc.layers[0].objects.size() == 1, "canvas gesture commits a stroke")
	object = doc.layers[0].objects[0]
	check(object.points[0][2] < object.points[-1][2], "pen pressure is preserved across stroke")
	doc.undo()
	check(doc.layers[0].objects.is_empty(), "canvas gesture is one undo step")
	canvas.tool = "rect"
	canvas.begin(p0, 0.5)
	canvas.update_stroke(p1, 0.5)
	canvas.finish()
	object = doc.layers[0].objects[0]
	check(object.kind == "rect" and object.extent[0] > 100, "shape tool draws editable geometry")
	canvas.tool = "fill"
	canvas.color = Color("#ff0000")
	canvas.begin(canvas.origin + Vector2(120, 110) * canvas.zoom, 0.5)
	check(object.color == "#ff0000", "Fill changes a shape's actual color")
	canvas.tool = "select"
	canvas.begin(canvas.origin + Vector2(120, 110) * canvas.zoom, 0.5)
	canvas.update_stroke(canvas.origin + Vector2(150, 140) * canvas.zoom, 0.5)
	canvas.finish()
	check(absf(object.pos[0] - 130) < 0.1, "selection moves artwork in document coordinates")
	check(canvas.set_clip_from_selection(), "selected shape becomes a paint clipping region")
	canvas.tool = "brush"
	canvas.brush = "mix"
	canvas.color = Color("#0000ff")
	canvas.smoothing = 0
	canvas.begin(canvas.origin + Vector2(150, 150) * canvas.zoom, 0.05)
	canvas.update_stroke(canvas.origin + Vector2(300, 150) * canvas.zoom, 1.0)
	canvas.finish()
	var paint = doc.layers[0].objects[-1]
	check(paint.has("clip") and paint.clip.size() == 4, "paint stroke retains clipping geometry")
	var light = Color(paint.points[0][3])
	var firm = Color(paint.points[-1][3])
	check(firm.b > light.b, "firm pressure deposits more selected blue pigment")
	var segment = Art.segments(paint)[0]
	check(not Art.clipped_polygon(paint, segment.polygon).is_empty(), "paint segments can be clipped for rendering")
	canvas.clip_enabled = false
	canvas.tool = "select"
	var before_click_history = doc.history.size()
	canvas.begin(canvas.origin + Vector2(160, 160) * canvas.zoom, 0.5)
	canvas.finish()
	check(doc.history.size() == before_click_history, "selecting without moving does not consume an undo step")
	var prior_snapshot = doc.snapshot()
	canvas.begin(canvas.origin + Vector2(160, 160) * canvas.zoom, 0.5)
	canvas.update_stroke(canvas.origin + Vector2(185, 190) * canvas.zoom, 0.5)
	canvas.cancel()
	check(doc.snapshot() == prior_snapshot, "Escape cancels movement without changing artwork")
	canvas.tool = "text"
	canvas.text_content = "Sini & Björn <3"
	canvas.begin(canvas.origin + Vector2(100, 400) * canvas.zoom, 0.5)
	check(doc.layers[0].objects[-1].text == "Sini & Björn <3", "typed Unicode text is stored without conversion")
	check(Art.svg(doc, false).contains("Sini &amp; Björn &lt;3"), "SVG escapes text safely")
	var count = doc.layers[0].objects.size()
	doc.layers[0].locked = true
	canvas.tool = "brush"
	canvas.begin(p0, 0.5)
	canvas.finish()
	check(doc.layers[0].objects.size() == count, "locked layers reject drawing")
	canvas.zoom_at(2, Vector2(300, 300))
	var anchor = canvas.to_document(Vector2(300, 300))
	canvas.zoom_at(2, Vector2(300, 300))
	check(anchor.distance_to(canvas.to_document(Vector2(300, 300))) < 0.01, "zoom preserves point under pointer")
	check(app.brush_row_buttons.size() == categories.Inking, "the brush library starts with a browsable Inking category")
	app.brush_category.select(5)
	app.brush_category.item_selected.emit(5)
	check(app.brush_row_buttons.size() == categories.Blending and app.brush_row_buttons[0].tooltip_text == "Color mixer", "selecting Blending shows its stroke previews")
	app.brush_row_buttons[0].pressed.emit()
	check(app.canvas.brush == "mix" and app.canvas.blending > 0.8, "brush row applies genuine mixing settings")
	app.brush_category.select(0)
	app.brush_category.item_selected.emit(0)
	check(app.brush_row_buttons.size() == catalog.size(), "All brushes browses every built-in preset")
	app.toggle_brush_panel("Brushes")
	await process_frame
	await process_frame
	var first_preview: Control = app.brush_row_buttons[0].get_node("StrokePreview")
	var last_preview: Control = app.brush_row_buttons[-1].get_node("StrokePreview")
	check(first_preview.is_visible_in_tree() and not last_preview.is_visible_in_tree(), "only visible brush rows render stroke previews")
	var brush_row: Button = app.brush_row_buttons[0]
	var row_point := brush_row.get_global_rect().get_center()
	var brush_presses: Array[bool] = []
	brush_row.pressed.connect(func(): brush_presses.append(true))
	var swipe_press := InputEventScreenTouch.new()
	swipe_press.pressed = true
	swipe_press.position = row_point
	root.push_input(swipe_press, true)
	var swipe_motion := InputEventScreenDrag.new()
	swipe_motion.position = row_point - Vector2(0, 16)
	swipe_motion.relative = Vector2(0, -16)
	root.push_input(swipe_motion, true)
	await process_frame
	var swipe_release := InputEventScreenTouch.new()
	swipe_release.position = swipe_motion.position
	root.push_input(swipe_release, true)
	check(app.brush_scroll.scroll_vertical > 0 and brush_presses.is_empty(), "a swipe over a brush row scrolls without picking it")
	swipe_press.position = brush_row.get_global_rect().get_center()
	swipe_release.position = swipe_press.position
	root.push_input(swipe_press.duplicate(), true)
	root.push_input(swipe_release.duplicate(), true)
	check(brush_presses.size() == 1, "a short touch still picks a brush row")
	# The Android backend delivers S Pen contact and motion through mouse events.
	app.brush_scroll.swipe_with_mouse = true
	var pen_hover := InputEventMouseMotion.new()
	pen_hover.position = brush_row.get_global_rect().get_center()
	root.push_input(pen_hover, true)
	var pen_press := InputEventMouseButton.new()
	pen_press.button_index = MOUSE_BUTTON_LEFT
	pen_press.pressed = true
	pen_press.position = pen_hover.position
	root.push_input(pen_press, true)
	var before_pen_swipe: int = app.brush_scroll.scroll_vertical
	var pen_motion := InputEventMouseMotion.new()
	pen_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	pen_motion.position = pen_press.position + Vector2(25, -20)
	pen_motion.relative = pen_motion.position - pen_press.position
	root.push_input(pen_motion, true)
	var pen_release := InputEventMouseButton.new()
	pen_release.button_index = MOUSE_BUTTON_LEFT
	pen_release.position = pen_motion.position
	root.push_input(pen_release, true)
	check(app.brush_scroll.scroll_vertical > before_pen_swipe and brush_presses.size() == 1,
		"a diagonal S Pen swipe over the brush preview scrolls vertically without picking the brush")
	app.brush_scroll.watch_press(pen_press, brush_row)
	check(app.brush_scroll.mouse_swipe, "the scroll panel has an active pen capture")
	var handoff := InputEventScreenTouch.new()
	handoff.index = 21
	handoff.pressed = true
	app.brush_scroll.watch_press(handoff, brush_row)
	check(not app.brush_scroll.mouse_swipe and app.brush_scroll.swipe_index == 21,
		"a finger can take over scrolling if a pen release was lost")
	app.brush_scroll.clear_swipe()
	await process_frame
	pen_hover.position = brush_row.get_global_rect().get_center()
	root.push_input(pen_hover.duplicate(), true)
	pen_press.position = pen_hover.position
	pen_release.position = pen_hover.position
	root.push_input(pen_press.duplicate(), true)
	root.push_input(pen_release.duplicate(), true)
	check(brush_presses.size() == 2, "a short S Pen tap still picks a brush row")
	app.brush_scroll.scroll_vertical = int(app.brush_scroll.get_v_scroll_bar().max_value)
	await process_frame
	await process_frame
	check(last_preview.is_visible_in_tree() and not first_preview.is_visible_in_tree(), "scrolling renders the newly visible previews")
	app.toggle_brush_panel("Brushes")
	app.brush_search.text = "AIRBRUSH"
	app.brush_search.text_changed.emit("AIRBRUSH")
	check(app.brush_row_buttons.size() == 4, "brush search is case insensitive")
	app.brush_search.text = "senlinos"
	app.brush_search.text_changed.emit("senlinos")
	check(app.brush_row_buttons.size() == collections.SenlinOS, "brush search finds presets by source collection")
	app.brush_search.text = "No matching brush"
	app.brush_search.text_changed.emit(app.brush_search.text)
	check(app.brush_row_buttons.is_empty() and app.brush_rows.get_child(0) is Label, "empty brush search has a clear empty state")
	var custom = BrushLibrary.preset("Sini blend", "mix", 35, 0.8, 0.9, 0.21)
	app.presets.append(custom)
	app.show_custom_brush(custom)
	check(app.brush_category.get_item_text(app.brush_category.selected) == "My brushes" and app.brush_row_buttons[0].button_pressed, "custom presets have a separate shelf with the chosen brush highlighted")
	app.brush_category.select(1)
	app.brush_category.item_selected.emit(1)
	check(not app.panels.Brushes.visible and not app.panels.Color.visible, "minimal workspace keeps detail drawers closed")
	app.toggle_brush_panel("Brush settings")
	await process_frame
	await process_frame
	check(app.panels.Brushes.visible and app.brush_pages.current_tab == 1 and app.brush_editor_preview.is_visible_in_tree()
		and not app.brush_scroll.is_visible_in_tree(), "the settings shortcut opens the Settings tab of the Brush panel")
	app.toggle_brush_panel("Brush settings")
	check(app.valid_preset({"format": "havu-brush", "version": 1, "name": "Sini", "brush": "mix", "size": 40, "opacity": 1, "blend": 0.8, "smoothing": 0.2}), "shareable brush preset validates")
	check(not app.valid_preset({"format": "havu-brush", "version": 1}), "incomplete brush preset rejected")
	await process_frame
	for key in app.panels:
		var panel = app.panels[key]
		check(panel.size.x >= panel.custom_minimum_size.x, "%s panel lays out at usable width" % key)
		print("LAYOUT: %s %s %s" % [key, panel.position, panel.size])
	check(app.panels.Tools.get_rect().end.x < app.panels.Brushes.position.x, "brush drawer sits beside icon rail")
	check(not app.panels.Color.get_rect().intersects(app.panels.Layers.get_rect()), "default right panels do not overlap")
	app.save_dialog.file_selected.emit("user://home-recent.havu")
	app.title_edit.text = "Saved through Quick Save"
	quick_save.pressed.emit()
	var quick_saved := Document.new()
	check(quick_saved.load_from("user://home-recent.havu").is_empty()
		and quick_saved.title == "Saved through Quick Save" and not app.save_dialog.visible,
		"Quick Save writes the existing project directly")
	app.title_edit.text = "Unsaved artwork"
	app.show_project_home()
	check(app.project_home.visible and app.project_home.resume_button.visible, "return to Projects offers Resume")
	check(app.project_home.recent_rows.get_child_count() == 1, "saved project appears in Recent projects")
	app.project_home.project_requested.emit("user://missing.havu")
	check(app.project_home.visible and app.document.title == "Unsaved artwork", "failed recent open preserves the session")
	var legacy_recents: Array = app.recent_projects.duplicate()
	legacy_recents.append({"path": ProjectSettings.globalize_path("user://home-recent.havu"), "title": "Duplicate bookmark"})
	app.settings.set_value("projects", "recent", legacy_recents)
	app.settings.save("user://preferences.cfg")
	app.autosave_timer.stop()
	app.queue_free()
	await process_frame

	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.project_home.visible and app.project_home.recent_rows.get_child_count() == 1, "startup collapses legacy recent entries for the same file")
	app.project_home.resume_requested.emit()
	check(app.document.title == "Unsaved artwork" and app.document.dirty and app.file_path == "user://home-recent.havu", "Resume restores edits and the original save destination")
	app.show_project_home()
	app.project_home.project_requested.emit("user://home-recent.havu")
	check(not app.project_home.visible and app.document.title != "Unsaved artwork", "recent project opens the explicitly saved version")
	app.show_project_home()
	var recovery_entry: Dictionary = app.recovered_projects[0]
	check(recovery_entry.title == "Unsaved artwork" and FileAccess.file_exists(recovery_entry.path)
		and app.project_home.recovery_button.visible and app.project_home.recent_rows.get_child_count() == 1,
		"switching keeps unsaved edits accessible separately from Recent projects")
	for repeat_index in 3:
		app.project_home.project_requested.emit(ProjectSettings.globalize_path("user://home-recent.havu"))
		app.show_project_home()
	check(app.project_home.recent_rows.get_child_count() == 1 and app.recovered_projects.size() == 1,
		"reopening the same project never adds another recent or recovery entry")
	check(app.project_path_key("content://provider/tree/primary%3APictures/document/primary%3APictures%2FMenu.havu")
		== app.project_path_key("content://provider/document/primary%3aPictures%2fMenu.havu"),
		"Android tree and document URIs for the same project use one recent key")
	app.project_home.recovery_menu.id_pressed.emit(0)
	check(app.document.title == "Unsaved artwork" and app.file_path.is_empty(), "opening an archived recovery uses Save As")
	app.show_project_home()
	app.project_home.sample_requested.emit()
	check(not app.project_home.visible and app.document.title == "The little green café", "editable café sample opens from Projects")

	await process_frame
	var stack_before: Array = app.document.snapshot().layers
	var active_layer_id: String = app.document.layers[app.document.active].id
	var bottom_row: Control = app.layer_list.get_child(-1)
	var top_row: Control = app.layer_list.get_child(0)
	var bottom_thumb = bottom_row.get_node("Content/SelectLayer/Identity/Thumbnail")
	check(bottom_thumb.objects.size() == stack_before[0].objects.size()
		and bottom_thumb.artwork.is_visible_in_tree(), "visible layer thumbnails show the layer's own artwork")
	check(app.layer_rows[active_layer_id].get_theme_stylebox("panel") == app.layer_row_styles[1],
		"the active layer uses the accent row style")
	var drag_handle: Control = bottom_row.get_node("Content/DragHandle")
	var start := drag_handle.get_global_rect().get_center()
	var target := top_row.get_global_rect().position + Vector2(20, 4)
	var press := InputEventScreenTouch.new()
	press.index = 1
	press.pressed = true
	press.position = bottom_thumb.get_global_rect().get_center()
	root.push_input(press, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = target
	root.push_input(drag, true)
	check(app.layer_scroll.drop_slot == 0, "touch dragging the layer thumbnail locates insertion above the first layer")
	check(bottom_row.modulate.a < 1.0, "layer reorder highlights the row being dragged")
	var release := InputEventScreenTouch.new()
	release.index = 1
	release.position = target
	root.push_input(release, true)
	check(bottom_row.modulate.a == 1.0, "releasing a reorder restores the layer row")
	check(app.document.layers[-1].id == stack_before[0].id and app.document.layers[app.document.active].id == active_layer_id, "drag changes stacking order and preserves the active layer")
	check(app.document.history.size() == 1, "layer drag is one undo step")
	app.document.undo()
	check(app.document.layers == stack_before, "undo restores the entire layer stack")
	app.document.redo()
	check(app.document.layers[-1].id == stack_before[0].id, "redo restores the new stacking order")
	app.drop_layer(stack_before[0].id, 1)
	check(app.document.history.size() == 1, "dropping in the same place adds no history")
	await process_frame
	drag_handle = app.layer_list.get_child(0).get_node("Content/DragHandle")
	var mouse_press := InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	mouse_press.position = drag_handle.size * 0.5
	drag_handle.gui_input.emit(mouse_press)
	var motion := InputEventMouseMotion.new()
	motion.position = start
	app.layer_scroll._input(motion)
	var mouse_release := InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.position = Vector2.ZERO
	app.layer_scroll._input(mouse_release)
	check(app.document.layers[-1].id == stack_before[0].id and app.document.history.size() == 1, "releasing outside the layers cancels a mouse drag")

	var moved_row: Control = app.layer_list.get_child(0)
	var moved_id: String = app.document.layers[-1].id
	var title_hit: Control = moved_row.get_node("Content/SelectLayer/Identity/Labels/Title")
	app.select_layer(app.document.layers[0].id)
	press.position = title_hit.get_global_rect().get_center()
	release.position = press.position
	root.push_input(press.duplicate(), true)
	root.push_input(release.duplicate(), true)
	check(app.document.layers[app.document.active].id == moved_id, "tapping the layer name still selects its layer")
	var lock_hit: Control = moved_row.get_node("Content/Lock")
	press.position = lock_hit.get_global_rect().get_center()
	release.position = press.position
	root.push_input(press.duplicate(), true)
	check(app.layer_scroll.layer_id.is_empty(), "the lock button does not grab the layer for reordering")
	root.push_input(release.duplicate(), true)
	check(app.document.layers[-1].locked, "the lock button still works on touch")
	press.position = title_hit.get_global_rect().get_center()
	release.position = press.position
	root.push_input(press.duplicate(), true)
	check(app.layer_scroll.layer_id.is_empty(), "a locked layer name cannot start a reorder")
	root.push_input(release.duplicate(), true)
	app.toggle_layer_flag(moved_id, "locked")
	await process_frame
	mouse_press.position = Vector2(moved_row.get_global_rect().position.x + 2.0, moved_row.get_global_rect().get_center().y)
	root.push_input(mouse_press.duplicate(), true)
	motion.position = mouse_press.position + Vector2(0, 12)
	root.push_input(motion.duplicate(), true)
	check(app.layer_scroll.dragging and moved_row.modulate.a < 1.0, "the layer row margin is a mouse drag target")
	root.push_input(mouse_release.duplicate(), true)

	app.create_document(false)
	check(not app.get_started_tour or not app.get_started_tour.visible,
		"creating another illustration after a restart keeps the tour closed")
	var context_doc = app.document
	var context_canvas = app.canvas
	context_doc.add({"kind": "rect", "pos": [100, 100], "extent": [100, 100], "color": "#226451", "opacity": 1.0})
	context_doc.commit()
	context_doc.selection = ""
	app.set_tool("select")
	check(app.selection_actions.is_visible_in_tree() and app.selection_actions.get_child(0).disabled, "Select opens its tray with actions disabled until artwork is selected")
	context_canvas.begin(context_canvas.origin + Vector2(150, 150) * context_canvas.zoom, 0.5)
	context_canvas.finish()
	check(not app.selection_actions.get_child(0).disabled, "selecting artwork enables contextual actions")
	app.selection_actions.get_child(0).pressed.emit()
	check(context_doc.layers[0].objects.size() == 2, "contextual Duplicate adds an object")
	app.set_tool("brush")
	check(not app.selection_actions.is_visible_in_tree(), "switching tools hides the selection actions")
	app.set_tool("select")
	app.selection_actions.get_child(1).pressed.emit()
	check(context_doc.layers[0].objects.size() == 1 and app.selection_actions.get_child(1).disabled, "contextual Delete removes the selection and disables the actions")

	await process_frame
	var rail: Control = app.panels.Tools
	var duplicate_action: Button = app.selection_actions.get_child(0)
	var delete_action: Button = app.selection_actions.get_child(1)
	check(app.selection_actions.vertical and delete_action.position.y > duplicate_action.position.y
		and delete_action.position.x == duplicate_action.position.x, "Select actions stack on a vertical toolbar")
	check(app.selection_tray.position.x >= rail.position.x + rail.size.x, "left toolbar opens Select actions to the right")
	rail.position.x = app.size.x - rail.size.x - 20
	check(app.selection_tray.position.x + app.selection_tray.size.x <= rail.position.x, "right toolbar opens Select actions to the left")
	rail.position = Vector2(16, 103)
	app.horizontal_toolbar_check.button_pressed = not app.horizontal_toolbar_check.button_pressed
	await process_frame
	await process_frame
	check(app.tool_grid.columns == app.tool_grid.get_child_count(), "workspace setting switches the toolbar to a horizontal row")
	check(not app.selection_actions.vertical and delete_action.position.x > duplicate_action.position.x
		and delete_action.position.y == duplicate_action.position.y, "Select actions form a row on a horizontal toolbar")
	check(app.selection_tray.position.y >= rail.position.y + rail.size.y, "horizontal toolbar opens Select actions below")
	rail.position.y = app.size.y - 65 - rail.size.y
	check(app.selection_tray.position.y + app.selection_tray.size.y <= rail.position.y, "toolbar near the bottom opens Select actions above")
	app.horizontal_toolbar_check.button_pressed = not app.horizontal_toolbar_check.button_pressed
	await process_frame
	await process_frame
	check(app.tool_grid.columns == 1 and rail.size.x < 100, "switching back restores a narrow toolbar")

	var header_edge: float = app.get_node("TopBar").get_rect().end.y
	mouse_press.position = Vector2(20, 20)
	rail._gui_input(mouse_press)
	motion.position = Vector2(400, header_edge + 22)
	rail._input(motion)
	check(app.dock_preview.visible and app.dock_preview_label.text == "Dock top\nKeep vertical"
		and app.dock_preview.size.y > app.dock_preview.size.x, "first edge contact previews docking in the current orientation")
	mouse_release.position = motion.position
	rail._input(mouse_release)
	check(rail.dock == "top" and not app.tools_horizontal, "releasing at first contact keeps the toolbar vertical")

	rail._gui_input(mouse_press)
	motion.position = Vector2(425, header_edge + 2)
	rail._input(motion)
	check(app.dock_preview_label.text == "Dock top\nHorizontal", "dragging deeper previews rotation")
	motion.position.y = header_edge + 22
	rail._input(motion)
	check(app.dock_preview_label.text == "Dock top\nKeep vertical", "backing away from the inner zone restores the first preview")
	motion.position.y = header_edge + 2
	rail._input(motion)
	check(rail.close_target.visible, "dragging a panel reveals the bin")
	check(app.dock_preview.visible and app.dock_preview_label.text == "Dock top\nHorizontal"
		and app.dock_preview.position.y == header_edge, "dragging to an edge previews the placement and toolbar direction")
	mouse_release.position = motion.position
	rail._input(mouse_release)
	await process_frame
	check(rail.dock == "top" and app.tools_horizontal and is_equal_approx(rail.position.y, header_edge), "top drop docks the toolbar horizontally")
	check(not app.selection_actions.vertical, "top docking rotates the Select actions with the toolbar")
	check(not app.dock_preview.visible, "docking clears the placement preview")

	rail._gui_input(mouse_press)
	motion.position = Vector2(app.size.x - 2, 300)
	rail._input(motion)
	mouse_release.position = motion.position
	rail._input(mouse_release)
	await process_frame
	await process_frame
	check(rail.dock == "right" and not app.tools_horizontal and is_equal_approx(rail.position.x + rail.size.x, app.size.x), "right drop docks the toolbar vertically")

	check(app.selection_actions.vertical, "side docking restores the vertical Select actions")

	rail._gui_input(mouse_press)
	motion.position = Vector2(app.size.x - 2, header_edge + 8)
	rail._input(motion)
	var top_right_slot: Rect2 = rail.pending_dock_slot
	check(top_right_slot.position.y == header_edge and top_right_slot.end.x == app.size.x
		and app.dock_preview_label.text.begins_with("Dock top right"), "the preview shows a flush top-right corner")
	mouse_release.position = motion.position
	rail._input(mouse_release)
	await process_frame
	check(rail.get_rect() == top_right_slot and app.settings.get_value("panel_dock_corner", "Tools") == "top",
		"the panel lands in the previewed corner and saves its corner anchor")

	var initial_width: float = rail.size.x
	var grip: Control = rail.resize_grip
	mouse_press.position = grip.size * 0.5
	grip.gui_input.emit(mouse_press)
	motion.position = grip.get_global_rect().get_center() - Vector2(42, 0)
	rail._input(motion)
	mouse_release.position = motion.position
	rail._input(mouse_release)
	await process_frame
	check(rail.size.x > initial_width and is_equal_approx(rail.position.x + rail.size.x, app.size.x), "resizing keeps a docked panel anchored")
	check(rail.position.y == header_edge, "resizing keeps the top-right corner flush")

	mouse_press.position = Vector2(30, 20)
	rail._gui_input(mouse_press)
	motion.position = rail.close_target.get_global_rect().get_center()
	rail._input(motion)
	check(rail.over_close_target and not app.dock_preview.visible, "the bin takes precedence over docking")
	mouse_release.position = motion.position
	rail._input(mouse_release)
	check(not rail.visible and not rail.close_target.visible and not app.selection_tray.visible, "dropping on the bin hides the toolbar and its tray")
	check(not app.settings.get_value("panel_visible", "Tools"), "hidden panels stay hidden across sessions")
	app.panels_menu.id_pressed.emit(0)
	check(rail.visible and rail.dock == "right" and rail.size.x > initial_width, "Panels reopens the toolbar with its dock and size")

	context_doc.blank(1250.0, 1200.0)
	app.set_tool("brush")
	context_canvas.brush = "ink"
	context_canvas.smoothing = 0.9
	context_canvas.fit()
	var stroke_origin: Vector2 = context_canvas.origin
	var stroke_zoom: float = context_canvas.zoom
	var input_accumulation := Input.use_accumulated_input
	context_canvas.begin(stroke_origin + Vector2(100, 300) * stroke_zoom, 0.25)
	check(not Input.use_accumulated_input, "freehand stroke receives unmerged input")
	var endpoint := Vector2(950, 300)
	context_canvas.update_stroke(stroke_origin + endpoint * stroke_zoom, 0.95)
	var live_point: Vector2 = Art.v(context_canvas.current.points[-1])
	var physical_per_unit: float = stroke_zoom * context_canvas.get_screen_transform().get_scale().x
	check(live_point.distance_to(endpoint) * physical_per_unit <= 2.01, "stabilization keeps the stroke tail within two physical pixels")
	check(context_canvas.live_first >= 64 and context_canvas.preview_root.get_child_count() > 1, "long live stroke retains completed batches")
	var live_edges: Material = context_canvas.preview_root.get_child(0).material
	context_canvas.finish()
	var completed_stroke: Dictionary = context_doc.layers[0].objects[0]
	check(Art.v(completed_stroke.points[-1]).distance_to(endpoint) < 0.01, "lifting the pen finishes at the last received sample")
	check(Input.use_accumulated_input == input_accumulation, "finishing restores normal input buffering")
	var committed_mark: Node2D = context_canvas.retained_marks[completed_stroke.id].mark
	check(live_edges != null and committed_mark.material == live_edges,
		"inking uses the same pixel-edge shader while drawing and after commit")
	context_canvas.brush = "soft"
	context_canvas.begin(stroke_origin + Vector2(200, 500) * stroke_zoom, 0.4)
	context_canvas.update_stroke(stroke_origin + Vector2(260, 500) * stroke_zoom, 0.6)
	check(context_canvas.live_first > 0 and context_canvas.current.points.size() - context_canvas.live_first < 12,
		"soft brush only redraws its latest dabs during a stroke")
	context_canvas.finish()
	check(is_same(committed_mark, context_canvas.retained_marks[completed_stroke.id].mark), "inking another stroke reuses completed artwork")
	var cache_doc := Document.new()
	cache_doc.blank()
	for index in 80:
		var mark := stroke()
		mark.brush = "soft"
		mark.pos = [100.0 + index, 100.0]
		cache_doc.add(mark)
	var test_canvas = load("res://scripts/canvas.gd").new()
	test_canvas.cache_completed_paint = true
	test_canvas.size = Vector2(480, 420)
	test_canvas.document = cache_doc
	root.add_child(test_canvas)
	check(test_canvas.paint_cache != null and test_canvas.retained_marks.size() == 80,
		"a busy tablet layer caches the display while retaining every editable mark")
	var cache_surface = test_canvas.paint_cache
	var quality_material: ShaderMaterial = cache_surface.display.material
	cache_surface.update_view(Vector2(640, 480), Vector2(12, 17), 0.25, 1.0)
	check(cache_surface.surface.size == Vector2i(1280, 960) and quality_material.get_shader_parameter("filter_overview")
		and cache_surface.display.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
		"zoomed-out vector cache uses a supersampled, filtered texture")
	cache_surface.update_view(Vector2(640, 480), Vector2(12, 17), 2.0, 1.0)
	check(cache_surface.surface.size == Vector2i(640, 480) and not quality_material.get_shader_parameter("filter_overview"),
		"normal zoom returns the cache to native pixel density")
	cache_surface.update_view(Vector2(2160, 1440), Vector2.ZERO, 0.2, 1.0)
	var cache_size: Vector2i = cache_surface.surface.size
	check(cache_size.x > 2160 and cache_size.x <= 3072 and cache_size.x * cache_size.y < 5510000,
		"larger display caches stay within their pixel budget")
	test_canvas.redraw_view()
	var cached_object: Dictionary = cache_doc.layers[0].objects[0]
	var cached_mark: Node2D = test_canvas.retained_marks[cached_object.id].mark
	# Drive the render completion in the headless test without a GPU.
	cache_surface.finish_cache_frame()
	check(not cached_mark.visible and cache_surface.surface.render_target_clear_mode == SubViewport.CLEAR_MODE_NEVER,
		"finished cache marks leave the render pass after their pixels are stored")
	test_canvas.begin(test_canvas.origin + Vector2(240, 270) * test_canvas.zoom, 0.75)
	check(test_canvas.preview_root.get_parent() == test_canvas.paint_cache,
		"live ink draws above the cache without rebaking old strokes")
	test_canvas.paint_cache.surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	test_canvas.finish()
	check(cache_doc.layers[0].objects.size() == 81 and
		test_canvas.paint_cache.surface.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"committing a stroke queues one finished-layer refresh")
	var appended: Dictionary = cache_doc.layers[0].objects[-1]
	var appended_mark: Node2D = test_canvas.retained_marks[appended.id].mark
	check(not cached_mark.visible and appended_mark.visible and cache_surface.pending_marks == [appended_mark]
		and cache_surface.surface.render_target_clear_mode == SubViewport.CLEAR_MODE_NEVER,
		"an appended stroke draws over the saved cache without replaying older marks")
	for index in 3:
		test_canvas.begin(test_canvas.origin + Vector2(245 + index * 4, 280) * test_canvas.zoom, 0.65)
		test_canvas.finish()
	check(cache_doc.layers[0].objects.size() == 84 and cache_surface.pending_marks.size() == 4
		and not cached_mark.visible, "rapid commits queue all new marks in one render frame")
	cache_surface.finish_cache_frame()
	check(not appended_mark.visible and cache_surface.pending_marks.is_empty(),
		"the finished draw clears the pending mark queue")
	cache_doc.undo()
	check(cache_doc.layers[0].objects.size() == 83 and cached_mark.visible and cache_surface.rebuild_pending
		and cache_surface.surface.render_target_clear_mode == SubViewport.CLEAR_MODE_ONCE,
		"undo clears and rebuilds the cached layer from its retained vectors")
	cache_doc.redo()
	check(cache_doc.layers[0].objects.size() == 84, "redo preserves the individually editable cached strokes")
	var glaze: Dictionary = stroke()
	glaze.brush = "soft"
	glaze.opacity = 0.25
	var glaze_batch := Art.wet_batch_geometry(glaze, 0, glaze.points.size())
	check(glaze_batch.vertices.size() == glaze_batch.uv.size() and glaze_batch.vertices.size() == glaze_batch.colors.size()
		and not glaze_batch.indices.is_empty() and glaze_batch.indices[-1] < glaze_batch.vertices.size(),
		"the watercolor batch carries its feather geometry, pigment and edge data")
	cache_doc.blank()
	test_canvas.zoom = 0.2
	test_canvas.redraw_view()
	cache_doc.append_vector_object({"kind": "rect", "pos": [90, 140], "extent": [90, 80], "color": "#226451", "opacity": 1.0})
	check(test_canvas.paint_cache != null and test_canvas.retained_marks.size() == 1,
		"the first vector shape uses the quality cache when committed at overview zoom")
	test_canvas.zoom = 2.0
	test_canvas.redraw_view()
	check(test_canvas.paint_cache == null and test_canvas.retained_marks.size() == 1,
		"zooming into a light illustration switches back to retained vector rendering")
	test_canvas.free()
	context_doc.undo()
	check(context_doc.layers[0].objects.size() == 1, "fast append undo removes only the new stroke")
	context_doc.redo()
	check(context_doc.layers[0].objects.size() == 2, "fast append redo restores the new stroke")

	context_canvas.brush = "pencil"
	context_canvas.begin(stroke_origin + Vector2(100, 620) * stroke_zoom, 0.25)
	context_canvas.update_stroke(stroke_origin + Vector2(900, 620) * stroke_zoom, 0.8)
	await process_frame
	await process_frame
	var sealed_grain: Node2D = context_canvas.preview_root.get_child(0)
	var live_mesh: MultiMesh = sealed_grain.get_meta(Art.GRAIN_BATCHES, [null])[0]
	check(live_mesh != null and live_mesh.instance_count == 24 * int(Art.grain_profile(context_canvas.current).x),
		"the live pencil retains one instanced mesh per sealed batch")
	context_canvas.finish()
	await process_frame
	await process_frame
	var grain_object: Dictionary = context_doc.layers[0].objects[-1]
	var grain_mark: Node2D = context_canvas.retained_marks[grain_object.id].mark
	var committed_batches: Array = grain_mark.get_meta(Art.GRAIN_BATCHES, [])
	check(not committed_batches.is_empty() and live_mesh != null and committed_batches[0].mesh == live_mesh.mesh,
		"the pencil commits as a vector stroke and reuses the live grain tip")

	var pigment_index := PigmentIndex.new()
	Sample.populate(context_doc)
	pigment_index.rebuild(context_doc)
	var same_colors := true
	for sample_index in 96:
		var point := Vector2((sample_index * 101) % 900, (sample_index * 73) % 1100)
		if not pigment_index.sample(point).is_equal_approx(Art.sample(context_doc, point)):
			same_colors = false
			break
	check(same_colors, "indexed paint sampling preserves colors and layer order")

	var wet_doc := Document.new()
	wet_doc.blank()
	for brush_index in 4:
		var wet := stroke()
		wet.brush = "soft" if brush_index % 2 == 0 else "paint"
		wet.opacity = 0.5
		wet.opacity_pressure = 0.5
		wet.taper_start = 1.8
		wet.taper_end = 0.9
		wet.pos = [0.0, brush_index * 7.0]
		wet.scale = 1.1
		wet.points = []
		for sample_index in 84:
			wet.points.append([80 + sample_index * 2.0, 180 + sin(sample_index * 0.14) * 15.0,
				0.2 if sample_index % 2 == 0 else 0.85, "#116759" if sample_index % 3 == 0 else "#29bb95"])
		wet_doc.add(wet)
	wet_doc.layers[0].opacity = 0.73
	pigment_index.rebuild(wet_doc)
	same_colors = true
	for index in 210:
		var query := Vector2(85 + index * 0.92, 202 + sin(index * 0.45) * 38.0)
		if not pigment_index.sample(query).is_equal_approx(Art.sample(wet_doc, query)):
			same_colors = false
			break
	check(same_colors, "cached stroke sampling matches the reference for overlapping, scaled, tapered and translucent strokes")
	var cached_stroke = pigment_index.entries[wet_doc.layers[0].objects[0].id].stroke
	wet_doc.layers[0].objects[0].pos = [100.0, 30.0]
	pigment_index.rebuild(wet_doc)
	check(is_same(cached_stroke, pigment_index.entries[wet_doc.layers[0].objects[0].id].stroke)
		and pigment_index.sample(Vector2(260, 210)).is_equal_approx(Art.sample(wet_doc, Vector2(260, 210))),
		"moving artwork reuses local stroke geometry while updating world bounds")

	app.workspace_menu.id_pressed.emit(7)
	check(app.input_settings_dialog.visible, "workspace menu opens Input settings")
	var pressure_toggle: CheckBox = app.input_settings_dialog.find_child("PenPressure", true, false)
	var finger_toggle: CheckBox = app.input_settings_dialog.find_child("FingerDrawing", true, false)
	check(pressure_toggle.button_pressed and not finger_toggle.button_pressed, "input settings retain pen and touch defaults")
	pressure_toggle.button_pressed = false
	finger_toggle.button_pressed = true
	check(not app.canvas.pressure_enabled and app.canvas.touch_paints, "input settings update the canvas")
	var pen_button_choice: OptionButton = app.input_settings_dialog.find_child("PenSideButton", true, false)
	check(pen_button_choice.selected == 0, "the pen shortcut is off by default")
	pen_button_choice.item_selected.emit(1)
	app.select_detected_pen_button(2)
	pen_button_choice.get_popup().hide()
	check(app.pen_button_selector.get_selected_id() == 2 and pen_button_choice.selected == 0,
		"detecting the other rocker end opens its independent assignment")
	pen_button_choice.item_selected.emit(2)
	check(app.canvas.pen_button_tools == {1: "picker", 2: "erase"}, "the two rocker ends can have different shortcuts")
	app.input_settings_dialog.hide()
	app.autosave_timer.stop()
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(not app.canvas.pressure_enabled and app.canvas.touch_paints, "input settings persist across restart")
	check(app.canvas.pen_button_tools == {1: "picker", 2: "erase"}, "both pen assignments survive restart")

	var pen_doc := Document.new()
	pen_doc.blank(240, 200, false)
	pen_doc.add({"kind": "rect", "pos": [40, 40], "extent": [100, 80], "color": "#226451", "opacity": 1.0})
	pen_doc.commit()
	var pen_canvas = load("res://scripts/canvas.gd").new()
	pen_canvas.document = pen_doc
	pen_canvas.size = Vector2(480, 420)
	root.add_child(pen_canvas)
	pen_canvas.fit()
	var pen_down := InputEventMouseButton.new()
	pen_down.button_index = MOUSE_BUTTON_LEFT
	pen_down.pressed = true
	pen_down.position = pen_canvas.origin + Vector2(80, 70) * pen_canvas.zoom
	var rocker := [1]
	pen_canvas.pen_shortcut_contact = func(): return rocker[0]
	pen_canvas.pen_button_tools = {1: "picker", 2: "erase"}
	pen_canvas._gui_input(pen_down)
	check(pen_canvas.color.is_equal_approx(Color("#226451")) and pen_canvas.tool == "brush" and not pen_canvas.drawing,
		"a modified pen tap picks the canvas color and keeps the chosen brush")
	rocker[0] = 2
	pen_canvas._gui_input(pen_down)
	check(pen_doc.layers[0].objects.is_empty() and pen_canvas.tool == "brush",
		"the pen eraser temporarily removes a vector object")
	pen_doc.undo()
	check(pen_doc.layers[0].objects.size() == 1, "pen erasing uses ordinary undo")

	pen_doc.blank(240, 200, false, "paint")
	pen_doc.commit_paint(stroke(), false)
	pen_down.position = pen_canvas.origin + Vector2(100, 20) * pen_canvas.zoom
	check(Art.sample(pen_doc, Vector2(100, 20)) == Color("#226451"), "the paint-layer sample starts with pigment")
	pen_canvas._gui_input(pen_down)
	check(pen_canvas.drawing and pen_canvas.current.get("erasing", false) and pen_canvas.tool == "brush",
		"the held pen button starts a paint-layer eraser stroke")
	pen_down.pressed = false
	pen_canvas._gui_input(pen_down)
	check(Art.sample(pen_doc, Vector2(100, 20)) == Color(pen_doc.paper), "lifting the pen commits pixel erasing")
	pen_canvas.pen_button_tools[2] = "hand"
	pen_down.pressed = true
	pen_canvas._gui_input(pen_down)
	check(pen_canvas.dragging and not pen_canvas.drawing and pen_canvas.tool == "brush",
		"the configured other rocker end can temporarily pan the canvas")
	pen_down.pressed = false
	pen_canvas._gui_input(pen_down)
	pen_canvas.free()

	app.create_document(false)
	app.set_tool("brush")
	var original_pen_contact: Callable = app.canvas.pen_shortcut_contact
	app.canvas.pen_shortcut_contact = func(): return rocker[0]
	app.document.add({"kind": "rect", "pos": [40, 40], "extent": [100, 80], "color": "#226451", "opacity": 1.0})
	app.document.commit()
	app.canvas.fit()
	pen_down.pressed = true
	pen_down.position = app.canvas.origin + Vector2(80, 70) * app.canvas.zoom
	app.canvas._gui_input(pen_down)
	rocker[0] = 0
	pen_down.pressed = false
	app.canvas._gui_input(pen_down)
	check(app.document.layers[0].objects.is_empty() and app.canvas.tool == "brush"
		and app.tool_buttons.brush.button_pressed and not app.tool_buttons.erase.button_pressed,
		"the pen eraser removes a vector without leaving its toolbar button highlighted after release")
	pen_down.pressed = true
	app.canvas._gui_input(pen_down)
	check(app.canvas.drawing and not app.canvas.current.get("erasing", false),
		"the next unmodified pen contact draws with the chosen brush")
	pen_down.pressed = false
	app.canvas._gui_input(pen_down)
	app.set_tool("erase")
	check(app.tool_buttons.erase.button_pressed and not app.tool_buttons.brush.button_pressed,
		"the eraser stays highlighted when it was explicitly selected")
	app.set_tool("brush")
	app.canvas.pen_shortcut_contact = original_pen_contact

	app.create_document(false)
	context_canvas = app.canvas
	context_doc = app.document
	context_canvas.touch_paints = false
	var pan_origin: Vector2 = context_canvas.origin
	touch_press(context_canvas, 2, Vector2(300, 250))
	touch_move(context_canvas, 2, Vector2(324, 280))
	check(context_canvas.origin.is_equal_approx(pan_origin + Vector2(24, 30)) and not context_canvas.drawing, "one finger pans without drawing")
	touch_press(context_canvas, 7, Vector2(424, 280))
	var pinch_anchor: Vector2 = context_canvas.to_document(Vector2(374, 280))
	var pinch_zoom: float = context_canvas.zoom
	touch_move(context_canvas, 7, Vector2(474, 300))
	check(context_canvas.zoom > pinch_zoom and context_canvas.to_document(Vector2(399, 290)).is_equal_approx(pinch_anchor), "a two-finger pinch zooms around the moving midpoint")
	var after_pinch: Vector2 = context_canvas.origin
	touch_release(context_canvas, 7, Vector2(474, 300))
	check(context_canvas.origin.is_equal_approx(after_pinch), "lifting one finger does not jump the canvas")
	touch_move(context_canvas, 2, Vector2(284, 272))
	check(context_canvas.origin.is_equal_approx(after_pinch + Vector2(-40, -8)), "remaining finger keeps panning")
	touch_release(context_canvas, 2, Vector2(-30, 272))
	check(context_canvas.touch_points.is_empty() and not context_canvas.is_processing_input(), "release outside the canvas ends the captured gesture")

	context_canvas.touch_paints = true
	context_canvas.fit()
	var touch_ink: Vector2 = context_canvas.origin + Vector2(200, 250) * context_canvas.zoom
	touch_press(context_canvas, 4, touch_ink)
	check(context_canvas.drawing, "finger drawing can still start a stroke")
	touch_move(context_canvas, 4, touch_ink + Vector2(15, 10))
	touch_press(context_canvas, 5, touch_ink + Vector2(100, 10))
	check(not context_canvas.drawing and context_doc.layers[0].objects.is_empty(), "adding a second finger cancels the provisional stroke")
	touch_move(context_canvas, 5, touch_ink + Vector2(125, 10))
	touch_release(context_canvas, 5, touch_ink + Vector2(125, 10))
	touch_release(context_canvas, 4, touch_ink)
	touch_press(context_canvas, 4, touch_ink)
	touch_move(context_canvas, 4, touch_ink + Vector2(20, 10))
	touch_release(context_canvas, 4, touch_ink + Vector2(20, 10))
	check(context_doc.layers[0].objects.size() == 1, "a single finger stroke still commits")
	app.set_tool("erase")
	touch_press(context_canvas, 4, touch_ink)
	touch_press(context_canvas, 5, touch_ink + Vector2(60, 0))
	touch_release(context_canvas, 5, touch_ink + Vector2(60, 0))
	touch_release(context_canvas, 4, touch_ink)
	check(context_doc.layers[0].objects.size() == 1, "beginning a pinch with Eraser active leaves artwork intact")
	app.set_tool("hand")
	pan_origin = context_canvas.origin
	touch_press(context_canvas, 5, touch_ink)
	touch_move(context_canvas, 5, touch_ink + Vector2(12, 6))
	touch_release(context_canvas, 5, touch_ink + Vector2(12, 6))
	check(context_canvas.origin.is_equal_approx(pan_origin + Vector2(12, 6)), "Hand pans with finger drawing enabled")

	context_doc.blank(720.0, 960.0)
	context_canvas.fit()
	app.set_tool("brush")
	var pointer_event := InputEventMouseMotion.new()
	pointer_event.position = context_canvas.origin + Vector2(128, 240) * context_canvas.zoom
	context_canvas._gui_input(pointer_event)
	app.update_pointer_readouts()
	check(app.pointer_x.text == "X 128" and app.pointer_y.text == "Y 240", "footer reports page coordinates at the current zoom")
	check(app.page_dimensions.text == "720 × 960", "footer shows the new page dimensions")
	var compact_footer: PanelContainer = app.get_node("BottomBar")
	check(is_equal_approx(compact_footer.size.y, 40.0)
		and compact_footer.get_global_rect().encloses(app.zoom_button.get_global_rect())
		and is_equal_approx(context_canvas.get_rect().end.y, compact_footer.position.y - 10.0),
		"the 40-pixel footer fits its zoom control and gives the recovered space to the canvas")
	context_canvas.begin(pointer_event.position, 0.35)
	pointer_event.pressure = 0.63
	pointer_event.position += Vector2(10, 5)
	context_canvas._gui_input(pointer_event)
	app.update_pointer_readouts()
	check(app.pointer_pressure.text == "Pressure 63%", "footer shows reported pressure during drawing")
	context_canvas.finish()
	context_canvas.mouse_exited.emit()
	app.update_pointer_readouts()
	check(app.pointer_x.text == "X —" and app.pointer_y.text == "Y —" and app.pointer_pressure.text == "Pressure —", "footer clears metrics when the pointer leaves")
	var zoom_popup: PopupMenu = app.get_node("ZoomPresets")
	app.zoom_button.pressed.emit()
	check(zoom_popup.visible, "zoom readout opens the zoom presets")
	zoom_popup.id_pressed.emit(200)
	check(is_equal_approx(context_canvas.zoom, 2.0) and app.zoom_button.text.begins_with("200%"), "zoom preset updates the canvas and footer together")
	zoom_popup.hide()

	app.workspace_menu.id_pressed.emit(6)
	check(app.workspace_settings_dialog.visible, "workspace menu opens Workspace settings")
	var rotate_check: CheckBox = app.workspace_settings_dialog.find_child("auto_orientation", true, false)
	var edge_check: CheckBox = app.workspace_settings_dialog.find_child("edge_docking", true, false)
	var bin_check: CheckBox = app.workspace_settings_dialog.find_child("drag_to_hide", true, false)
	var selection_check: CheckBox = app.workspace_settings_dialog.find_child("contextual_actions", true, false)
	var metrics_check: CheckBox = app.workspace_settings_dialog.find_child("footer_metrics", true, false)
	rotate_check.button_pressed = false
	bin_check.button_pressed = false
	selection_check.button_pressed = false
	metrics_check.button_pressed = false
	app.workspace_settings_dialog.hide()
	app.set_tool("select")
	check(not app.selection_tray.visible and app.workspace_menu.get_item_index(8) >= 0, "Select actions remain available in the menu when the tray is off")
	check(not app.footer_metrics.visible and app.zoom_button.visible, "canvas metrics can be hidden while keeping zoom controls")

	rail = app.panels.Tools
	mouse_press.position = Vector2(20, 20)
	rail._gui_input(mouse_press)
	motion.position = Vector2(500, 84)
	rail._input(motion)
	check(not rail.close_target.visible, "turning off the drag bin suppresses it")
	mouse_release.position = motion.position
	rail._input(mouse_release)
	check(rail.dock == "top" and not app.tools_horizontal, "toolbar can dock without rotating")
	edge_check.button_pressed = false
	rail._gui_input(mouse_press)
	motion.position = Vector2(app.size.x - 4, 330)
	rail._input(motion)
	mouse_release.position = motion.position
	rail._input(mouse_release)
	check(rail.dock.is_empty(), "turning off snapping allows the toolbar to float near edges")
	app.autosave_timer.stop()
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(not app.workspace_options.auto_orientation and not app.panels.Tools.edge_docking_enabled
		and not app.panels.Tools.drag_to_hide_enabled and not app.workspace_options.contextual_actions
		and not app.footer_metrics.visible, "workspace options persist across restart")

	app.create_document(false)
	app.set_workspace_option("edge_docking", true)
	var library = app.panels.Brushes
	app.show_brush_tab("Brushes")
	library.position = Vector2(110, 135)
	await process_frame
	await process_frame
	var library_rect: Rect2 = library.get_rect()
	app.brush_tab_buttons[1].pressed.emit()
	await process_frame
	check(app.panels.Brushes == library and not app.panels.has("Brush settings")
		and library.get_rect() == library_rect and app.brush_tuning_scroll.is_visible_in_tree(),
		"Library and Settings share one panel, position, and size")
	app.brush_tab_buttons[0].pressed.emit()
	await process_frame
	check(app.brush_scroll.is_visible_in_tree() and not app.brush_tuning_scroll.is_visible_in_tree()
		and library.get_rect() == library_rect, "returning to Library keeps the shared panel in place")

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	# Simulate opening a workspace saved before the two panels were combined.
	app.settings.set_value("workspace", "unified_brush_panel", false)
	app.settings.set_value("panel_visible", "Brushes", false)
	app.settings.set_value("panel_visible", "Brush settings", true)
	app.settings.set_value("layout_minimal_v2", "Brush settings", library_rect.position / app.size)
	app.settings.save("user://preferences.cfg")
	app.autosave_timer.stop()
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	library = app.panels.Brushes
	check(library.visible and app.brush_pages.current_tab == 1
		and library.position.is_equal_approx(library_rect.position), "legacy Brush settings placement migrates to the shared panel")

	app.create_document(false)
	var color_panel = app.panels.Color
	var layers_panel = app.panels.Layers
	color_panel.show()
	layers_panel.show()
	color_panel.dock = "right"
	color_panel.position.y = 84
	color_panel.constrain()
	layers_panel.dock = ""
	layers_panel.position = Vector2(620, 210)
	await process_frame
	var color_position: Vector2 = color_panel.position
	mouse_press.position = Vector2(24, 20)
	layers_panel._gui_input(mouse_press)
	motion.position = Vector2(app.size.x - 5, 125)
	layers_panel._input(motion)
	var free_slot: Rect2 = layers_panel.pending_dock_slot
	check(free_slot.has_area() and free_slot.position.y >= color_panel.get_rect().end.y + 10
		and app.dock_preview.position == free_slot.position, "dock preview shifts below an occupied spot")
	mouse_release.position = motion.position
	layers_panel._input(mouse_release)
	await process_frame
	check(layers_panel.dock == "right" and layers_panel.position == free_slot.position
		and color_panel.position == color_position, "drop uses the previewed slot and keeps the existing dock in place")
	library._gui_input(mouse_press)
	motion.position = Vector2(app.size.x - 5, 160)
	library._input(motion)
	check(not library.pending_dock_slot.has_area() and app.dock_preview_label.text.begins_with("No room"), "a full dock shows why the panel will stay floating")
	mouse_release.position = motion.position
	library._input(mouse_release)
	check(library.dock.is_empty(), "dropping at a full edge leaves the panel floating")
	layers_panel.hide()
	await process_frame
	library._gui_input(mouse_press)
	motion.position = Vector2(app.size.x - 5, 160)
	library._input(motion)
	check(library.pending_dock_slot.has_area(), "hiding a docked panel frees its space")
	library._input(escape)

	var footer_edge: float = app.get_node("BottomBar").position.y
	color_panel._gui_input(mouse_press)
	motion.position = Vector2(9, footer_edge - 2)
	color_panel._input(motion)
	var bottom_left_slot: Rect2 = color_panel.pending_dock_slot
	mouse_release.position = motion.position
	color_panel._input(mouse_release)
	await process_frame
	check(color_panel.get_rect() == bottom_left_slot and bottom_left_slot.position.x == 0.0
		and bottom_left_slot.end.y == footer_edge, "the opposite corner meets the left edge and bottom bar")

	# Build a nested layout entirely through the drop previews.
	app.set_workspace_option("panel_groups", true)
	for panel in app.panels.values(): panel.hide()
	color_panel.show()
	layers_panel.show()
	library.show()
	for panel in [color_panel, layers_panel, library]: panel.dock = ""
	color_panel.position = Vector2(430, 124)
	layers_panel.position = Vector2(110, 180)
	library.position = Vector2(1030, 155)
	await process_frame
	mouse_press.position = Vector2(24, 20)
	layers_panel._gui_input(mouse_press)
	motion.position = color_panel.get_rect().get_center()
	motion.position.y = color_panel.get_rect().end.y - 4
	layers_panel._input(motion)
	check(app.group_preview.visible and app.group_preview_text.text == "Join below"
		and app.group_preview_outlines.visible, "any panel can preview a split group with another panel")
	mouse_release.position = motion.position
	layers_panel._input(mouse_release)
	await process_frame
	check(app.panel_groups.size() == 1 and color_panel.get_rect().end.y < layers_panel.position.y, "joining below creates a column")
	library._gui_input(mouse_press)
	motion.position = layers_panel.get_rect().get_center()
	motion.position.x = layers_panel.get_rect().end.x - 4
	library._input(motion)
	check(app.group_preview_text.text == "Join right" and app.group_preview_cells.size() == 2, "a nested split previews the whole arrangement")
	mouse_release.position = motion.position
	library._input(mouse_release)
	await process_frame
	check(app.panel_groups.size() == 1 and color_panel.position.x == layers_panel.position.x
		and library.position.y == layers_panel.position.y
		and color_panel.get_rect().end.x == library.get_rect().end.x,
		"one wide top panel spans the two panels below")
	var original_layers: Rect2 = layers_panel.get_rect()
	var original_settings: Rect2 = library.get_rect()
	var original_color: Rect2 = color_panel.get_rect()
	var original_layers_body_height: float = layers_panel.body_scroll.size.y
	var group_resize_handle: Control = layers_panel.resize_grip
	var group_resize_origin := group_resize_handle.get_global_rect().get_center()
	mouse_press.position = group_resize_origin
	root.push_input(mouse_press, true)
	motion.position = group_resize_origin + Vector2(-24, 21)
	root.push_input(motion, true)
	await process_frame
	check(layers_panel.size.is_equal_approx(original_layers.size + Vector2(-24, 21))
		and is_equal_approx(library.position.x, original_settings.position.x - 24)
		and color_panel.get_rect() == original_color, "dragging a grouped handle resizes its tile and neighbor live")
	check(is_equal_approx(layers_panel.body_scroll.size.y, original_layers_body_height + 21),
		"the grouped panel content gets extra room before release")
	root.push_input(escape, true)
	await process_frame
	check(layers_panel.get_rect() == original_layers and library.get_rect() == original_settings,
		"cancel restores both grouped panels")
	mouse_release.position = motion.position
	root.push_input(mouse_release, true)
	var resize_touch := InputEventScreenTouch.new()
	resize_touch.index = 8
	resize_touch.pressed = true
	resize_touch.position = group_resize_origin
	root.push_input(resize_touch, true)
	var resize_drag := InputEventScreenDrag.new()
	resize_drag.index = resize_touch.index
	resize_drag.position = group_resize_origin + Vector2(-18, 14)
	root.push_input(resize_drag, true)
	await process_frame
	var resized_layers: Rect2 = layers_panel.get_rect()
	var resized_settings: Rect2 = library.get_rect()
	resize_touch.position = resize_drag.position
	resize_touch.pressed = false
	root.push_input(resize_touch, true)
	await process_frame
	check(resized_layers != original_layers and layers_panel.get_rect() == resized_layers
		and library.get_rect() == resized_settings, "touch release keeps the live grouped layout")
	var group: Dictionary = app.panel_groups[0]
	var grip_panel: Control = app.group_grips[group.id]
	var prior_color: Vector2 = color_panel.position
	var prior_settings: Vector2 = library.position
	mouse_press.position = grip_panel.get_global_rect().get_center()
	root.push_input(mouse_press.duplicate(), true)
	motion.position = mouse_press.position + Vector2(30, 0)
	root.push_input(motion.duplicate(), true)
	mouse_release.position = motion.position
	root.push_input(mouse_release.duplicate(), true)
	check(color_panel.position == prior_color + Vector2(30, 0) and library.position == prior_settings + Vector2(30, 0), "the group grip moves all members together")

	var floating_group_position: Vector2 = group.position
	var group_header_edge: float = app.get_node("TopBar").get_rect().end.y
	var obstruction: Control = app.panels.Typography
	obstruction.dock = "top"
	obstruction.show()
	obstruction.position.x = app.size.x
	obstruction.constrain()
	await process_frame
	mouse_press.position = grip_panel.get_global_rect().get_center()
	root.push_input(mouse_press.duplicate(), true)
	motion.position = Vector2(app.size.x - 6, group_header_edge + 2)
	root.push_input(motion.duplicate(), true)
	check(app.dock_preview.visible and app.dock_preview_label.text == "Dock group top"
		and app.dock_preview.get_rect().end.x <= obstruction.position.x,
		"the group dock preview finds room beside an occupied corner")
	root.push_input(escape.duplicate(), true)
	await process_frame
	mouse_release.position = motion.position
	root.push_input(mouse_release.duplicate(), true)
	check(group.position == floating_group_position and group.dock.is_empty() and not app.dock_preview.visible,
		"canceling a dock drag restores the floating group")
	obstruction.hide()
	obstruction.dock = ""

	resize_touch.pressed = true
	resize_touch.position = grip_panel.get_global_rect().get_center()
	root.push_input(resize_touch.duplicate(), true)
	resize_drag.position = Vector2(2, group_header_edge + 6)
	root.push_input(resize_drag.duplicate(), true)
	var group_place: Rect2 = app.dock_preview.get_rect()
	check(app.dock_preview.visible and app.dock_preview_label.text == "Dock group top left"
		and group_place.position == Vector2(0, group_header_edge), "touching the group grip previews a flush corner")
	resize_touch.pressed = false
	resize_touch.position = resize_drag.position
	root.push_input(resize_touch.duplicate(), true)
	check(group.bounds == group_place and group.dock == "left" and group.corner == "top"
		and color_panel.group_docked and layers_panel.group_docked and not app.dock_preview.visible,
		"releasing the group grip docks all panels as one unit")

	app.show_project_home()
	check(app.project_home.visible and not grip_panel.is_visible_in_tree(), "opening Projects immediately hides Move group")
	await process_frame
	check(not grip_panel.is_visible_in_tree(), "a queued layout refresh keeps Move group hidden on Projects")
	app.project_home.resume_requested.emit()
	await process_frame
	check(not app.project_home.visible and grip_panel.is_visible_in_tree(), "resuming the workspace restores Move group")

	app.autosave_timer.stop()
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	color_panel = app.panels.Color
	layers_panel = app.panels.Layers
	library = app.panels.Brushes
	check(app.panel_groups.size() == 1 and color_panel.group_cell.has_area()
		and layers_panel.position.y == library.position.y, "nested groups survive restart")
	check(layers_panel.size == resized_layers.size and library.size == resized_settings.size,
		"grouped resize dimensions survive restart")
	var restored_grip: Control = app.group_grips[app.panel_groups[0].id]
	check(app.project_home.visible and not restored_grip.is_visible_in_tree(), "restored groups stay hidden on the startup Projects screen")
	app.project_home.resume_requested.emit()
	await process_frame
	check(restored_grip.is_visible_in_tree(), "Move group appears when resuming after restart")
	var restored_group: Dictionary = app.panel_groups[0]
	check(restored_group.dock == "left" and restored_group.corner == "top"
		and restored_group.bounds.position == Vector2(0, group_header_edge), "the group corner dock survives restart")
	var grip_offset: Vector2 = restored_grip.size * 0.5
	mouse_press.position = restored_grip.get_global_rect().position + grip_offset
	root.push_input(mouse_press.duplicate(), true)
	motion.position = floating_group_position + grip_offset
	root.push_input(motion.duplicate(), true)
	mouse_release.position = motion.position
	root.push_input(mouse_release.duplicate(), true)
	await process_frame
	check(restored_group.dock.is_empty() and restored_group.position == floating_group_position,
		"dragging the grip away undocks the group together")
	mouse_press.position = Vector2(24, 20)
	library._gui_input(mouse_press)
	motion.position = Vector2(1140, 250)
	library._input(motion)
	mouse_release.position = motion.position
	library._input(mouse_release)
	await process_frame
	check(app.find_panel_group("Brushes").is_empty() and app.panel_groups.size() == 1,
		"dragging a panel clear of the group leaves the other members joined")

	library.position = Vector2(995, 135)
	library.dock = ""
	app.show_brush_tab("Brush settings")
	await process_frame
	library._gui_input(mouse_press)
	motion.position = color_panel.get_rect().get_center()
	motion.position.x = color_panel.get_rect().end.x - 4
	library._input(motion)
	mouse_release.position = motion.position
	library._input(mouse_release)
	await process_frame
	var brush_group: Dictionary = app.find_panel_group("Brushes")
	check(not brush_group.is_empty(), "the Brush panel can join a split group from Settings")
	var grouped_brush: Rect2 = library.get_rect()
	app.brush_tab_buttons[0].pressed.emit()
	await process_frame
	check(is_same(app.find_panel_group("Brushes"), brush_group) and library.get_rect() == grouped_brush
		and app.brush_pages.current_tab == 0, "switching tabs keeps the same group tile and dimensions")

	app.create_document(false)
	context_doc = app.document
	context_canvas = app.canvas
	context_doc.blank(900.0, 1100.0)
	context_canvas.fit()
	context_canvas.zoom_at(2.25, context_canvas.size * 0.5)
	context_canvas.pan_by(Vector2(35, -20))
	var intended_center: Vector2 = context_canvas.to_document(context_canvas.size * 0.5)
	var zoom_before_resize: float = context_canvas.zoom
	var desktop_size: Vector2 = app.size
	app.size = Vector2(800, 1280)
	await process_frame
	await process_frame
	check(app.compact_workspace() and context_canvas.size.x > 650 and app.title_edit.custom_minimum_size.x < 150,
		"portrait gives the canvas the right-side space and uses a compact header")
	check(app.get_node("TopBar").size.x <= app.size.x and app.get_node("BottomBar").size.x <= app.size.x, "portrait fits both bars without clipping")
	var portrait_save: Button = app.get_node("TopBar").find_child("QuickSave", true, false)
	check(portrait_save.is_visible_in_tree() and portrait_save.get_global_rect().end.x <= app.size.x,
		"Quick Save fits in the portrait header")
	check(is_equal_approx(context_canvas.zoom, zoom_before_resize)
		and context_canvas.to_document(context_canvas.size * 0.5).is_equal_approx(intended_center),
		"rotation keeps the same zoom and centered document point")
	check(context_doc.width == 900 and context_doc.height == 1100, "workspace orientation leaves artwork dimensions untouched")
	check(app.panel_groups.size() == 1, "portrait keeps the panel grouping")
	context_canvas.fit()
	app.size = desktop_size
	await process_frame
	await process_frame
	check(context_canvas.view_fitted and context_canvas.to_document(context_canvas.size * 0.5).is_equal_approx(Vector2(450, 550)),
		"Fit keeps the page centered after returning to landscape")
	check(ProjectSettings.get_setting("display/window/handheld/orientation") == DisplayServer.SCREEN_SENSOR
		and app.android_content_base(Vector2i(1600, 2560)) == Vector2i(800, 1050)
		and app.android_content_base(Vector2i(2560, 1600)) == Vector2i(1050, 720),
		"Android is configured for sensor rotation and orientation-specific UI scaling")

	app.panels.Color.hide()
	app.top_color.pressed.emit()
	check(app.panels.Color.visible and app.panels.Color.is_ancestor_of(app.color_picker), "top swatch opens the movable Color panel")
	await process_frame
	var color_wheel: Control = app.color_picker
	var shade: Rect2 = color_wheel.shade_rect()
	var start_color: Color = app.canvas.color
	touch_press(color_wheel, 3, shade.get_center())
	touch_move(color_wheel, 3, shade.position + Vector2(10, 5))
	check(app.canvas.color == start_color and app.color_preview_style.bg_color != start_color,
		"the panel shows a live wheel preview without recording intermediate colors")
	touch_release(color_wheel, 3, shade.position + Vector2(10, 5))
	check(app.canvas.color != start_color and app.recent_colors[0] == "#" + app.canvas.color.to_html(false),
		"touch release selects a wheel color and adds it to recents")
	app.color_hex.text = "#12A4BA"
	app.apply_color_hex()
	check(app.canvas.color == Color("#12a4ba") and app.top_color.tooltip_text.ends_with("#12A4BA"),
		"hex input keeps the canvas color, wheel and top swatch in sync")
	var most_recent: String = app.recent_colors[0]
	app.color_hex.text = "#oops"
	app.apply_color_hex()
	check(app.color_hex.text == "#12A4BA" and app.recent_colors[0] == most_recent, "invalid hex input leaves the active color unchanged")
	touch_press(color_wheel, 3, shade.get_center())
	color_wheel.finish_picker(true)
	check(app.color_preview_style.bg_color == Color("#12a4ba") and app.canvas.color == Color("#12a4ba")
		and app.recent_colors[0] == most_recent, "canceling the wheel restores the committed swatch")
	app.color_panel_tabs[1].pressed.emit()
	await process_frame
	var channels = app.color_channels
	check(channels.is_visible_in_tree() and not color_wheel.visible
		and channels.fields[0].value == 18 and channels.fields[1].value == 164,
		"RGB fields show the same color as the wheel and hex field")
	channels.fields[0].value = 96
	check(app.color_hex.text == "#60A4BA" and app.canvas.color.is_equal_approx(Color("#60a4ba")),
		"typing an RGB value updates the color and hex field")
	var prior_drag_color: String = app.recent_colors[0]
	channels.sliders[2].drag_started.emit()
	channels.sliders[2].value = 125
	channels.sliders[2].value = 130
	check(app.color_hex.text == "#60A482" and app.recent_colors[0] == prior_drag_color,
		"dragging a channel previews the color and leaves recents unchanged")
	channels.sliders[2].drag_ended.emit(true)
	check(app.recent_colors[0] == "#60a482", "the channel commits once on release")
	var before_switch: Color = app.canvas.color
	channels.model.select(1)
	channels.model.item_selected.emit(1)
	check(app.canvas.color == before_switch and channels.fields[0].max_value == 359,
		"switching to HSV changes the scale without changing the color")
	app.set_color(Color("#808080"))
	channels.fields[0].value = 180
	channels.fields[1].value = 100
	check(app.canvas.color.h > 0.49 and app.canvas.color.h < 0.51 and app.canvas.color.s > 0.99,
		"HSV keeps the chosen hue while adjusting saturation of a neutral color")

	app.color_panel_tabs[2].pressed.emit()
	app.set_color(Color("#395f4b"))
	app.edit_saved_swatch(true)
	app.edit_saved_swatch(true)
	check(app.palette_page.is_visible_in_tree() and app.saved_swatches_hex == ["#395f4b"],
		"the docked palette saves a single copy of the current color")
	app.set_color(Color("#384550"))
	app.edit_saved_swatch(true)
	app.remove_swatch.pressed.emit()
	check(app.saved_swatches_hex == ["#395f4b"], "a saved swatch can be removed from the panel")
	app.color_panel_tabs[0].pressed.emit()
	for swatch in ["#100200", "#100300", "#100400", "#100500", "#100600", "#100700"]:
		app.set_color(Color(swatch), true)
	app.set_color(Color("#100300"), true)
	check(app.recent_colors.size() == 6 and app.recent_colors.count("#100300") == 1
		and app.recent_colors[0] == "#100300", "recents keep six unique colors in most-recent order")
	app.recent_swatches.get_child(1).pressed.emit()
	check(app.canvas.color == Color("#100700"), "a recent swatch can be recalled")
	app.set_color(Color("#fc72a5"))
	context_canvas = app.canvas
	app.set_tool("brush")
	context_canvas.begin(context_canvas.origin + Vector2(150, 150) * context_canvas.zoom, 0.50)
	context_canvas.finish()
	check(app.recent_colors[0] == "#fc72a5", "a committed brush stroke records the color used")
	app.save_layout()
	app.autosave_timer.stop()
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.recent_colors.size() == 6 and app.recent_colors[0] == "#fc72a5", "recent color swatches survive restart")
	check(app.saved_swatches_hex == ["#395f4b"], "saved palette colors survive restart")

	app.create_document(false)
	app.reset_layout()
	app.toggle_brush_panel("Brushes")
	library = app.panels.Brushes
	await process_frame
	var brush_height: float = app.brush_scroll.size.y
	var library_grip: Control = library.resize_grip
	mouse_press.position = library_grip.size * 0.5
	library_grip.gui_input.emit(mouse_press)
	motion.position = library_grip.get_global_rect().get_center() + Vector2(90, 150)
	library._input(motion)
	mouse_release.position = motion.position
	library._input(mouse_release)
	await process_frame
	await process_frame
	check(app.brush_scroll.size.y > brush_height + 100 and app.brush_scroll.size.x > 290,
		"enlarging the brush panel gives the brush list more space")
	library.preferred_size = Vector2(240, 400)
	library.apply_preferred_size()
	await process_frame
	await process_frame
	check(library.size.x == 240.0 and not library.body_scroll.get_h_scroll_bar().visible
		and not library.body_scroll.get_v_scroll_bar().visible,
		"brush controls still fit when the panel is smaller than its previous scroll threshold")
	library.preferred_size = Vector2(160, 175)
	library.apply_preferred_size()
	await process_frame
	await process_frame
	check(library.size.x <= 161 and library.body_scroll.get_h_scroll_bar().visible
		and library.body_scroll.get_v_scroll_bar().visible,
		"a small panel keeps its size and scrolls to reveal controls")
	library.preferred_size = Vector2.ONE
	library.apply_preferred_size()
	await process_frame
	await process_frame
	check(library.size.x <= 152.0 * 0.95 and library.size.y <= 136.0 * 0.95
		and library.body_scroll.get_v_scroll_bar().visible,
		"panel width and height can shrink at least five percent further")
	var dimensions_before: Vector2 = app.layer_scroll.size
	app.panels.Layers.preferred_size = Vector2(350, 620)
	app.panels.Layers.apply_preferred_size()
	await process_frame
	await process_frame
	check(app.layer_scroll.size.y > dimensions_before.y + 90 and app.layer_scroll.size.x > dimensions_before.x,
		"the layers list fills the resized panel")
	app.set_tool("text")
	var text_area_before: Vector2 = app.text_edit.size
	app.panels.Typography.preferred_size = Vector2(400, 520)
	app.panels.Typography.apply_preferred_size()
	await process_frame
	await process_frame
	check(app.text_edit.size.y > text_area_before.y + 100 and app.text_edit.size.x > text_area_before.x,
		"the text editor grows with Typography")
	app.toggle_color_panel()
	await process_frame
	var wheel_radius: float = app.color_picker.outer_radius()
	app.panels.Color.preferred_size = Vector2(420, 480)
	app.panels.Color.apply_preferred_size()
	await process_frame
	await process_frame
	check(app.color_picker.outer_radius() > wheel_radius + 45, "a larger Color panel shows a larger wheel")

	app.create_document(false)
	context_doc = app.document
	context_canvas = app.canvas
	# Start with a legacy project snapshot to exercise its new defaults.
	var legacy = context_doc.snapshot()
	legacy.erase("paper_visible")
	legacy.layers[0].erase("opacity")
	check(Document.validate(legacy).is_empty(), "older projects keep an opaque background and layers by default")
	context_doc.add({"kind": "rect", "extent": [80, 80], "color": "#d24845", "opacity": 1.0})
	context_doc.commit()
	var fixture := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	fixture.fill(Color(0, 0.6, 0.8, 0.5))
	check(fixture.save_png("user://menu-logo.png") == OK, "test image with alpha can be written")
	check(Raster.decode(fixture.save_jpg_to_buffer(), "jpeg") != null
		and Raster.decode(fixture.save_webp_to_buffer(), "webp") != null, "JPEG and WebP use bounded image decoders")
	app.file_menu.id_pressed.emit(7)
	check(app.import_image_dialog.visible, "File menu opens the image picker")
	app.import_image_dialog.hide()
	app.import_image_dialog.file_selected.emit("user://menu-logo.png")
	var image_layer: Dictionary = context_doc.layers[-1]
	var imported: Dictionary = image_layer.objects[0]
	check(context_doc.layers.size() == 2 and context_doc.active == 1 and image_layer.name == "menu-logo"
		and imported.kind == "image" and context_doc.selection == imported.id, "image imports onto a selected layer above the current artwork")
	check(Art.bounds(imported).get_center().is_equal_approx(Vector2(context_doc.width, context_doc.height) * 0.5)
		and absf(Art.color_at(imported, Art.bounds(imported).get_center()).a - 0.5) < 0.01,
		"the imported image is centered and preserves its alpha")
	app.layer_actions.id_pressed.emit(0)
	var opacity_dialog: ConfirmationDialog = app.get_node("LayerOpacity")
	var opacity_value: SpinBox = opacity_dialog.find_child("OpacityPercent", true, false)
	opacity_value.value = 45
	opacity_dialog.hide()
	opacity_dialog.confirmed.emit()
	check(is_equal_approx(image_layer.opacity, 0.45) and context_canvas.layer_renderers[image_layer.id] is CanvasGroup,
		"Layer opacity applies once to the entire layer")
	context_doc.undo()
	check(is_equal_approx(context_doc.layers[-1].opacity, 1), "opacity is one undo step")
	context_doc.redo()
	var image_layer_id: String = context_doc.layers[-1].id
	app.file_menu.id_pressed.emit(9)
	var export_svg := Art.svg(context_doc, false)
	check(export_svg.contains("data:image/png;base64,") and export_svg.contains('opacity="0.45"')
		and not export_svg.contains('width="100%"') and export_svg.contains("<polygon"),
		"transparent SVG embeds the picture, keeps the vector shape and writes layer opacity")
	app.layer_actions.id_pressed.emit(2)
	check(app.export_dialog.visible and app.export_layer_id == image_layer_id, "active layer offers a PNG export")
	app.export_dialog.hide()
	var isolated = app.export_document(app.export_layer_id)
	check(isolated.layers.size() == 1 and isolated.layers[0].id == image_layer_id
		and not isolated.paper_visible and isolated.width == context_doc.width,
		"the PNG export document keeps only that layer on a transparent, full-size canvas")
	app.layer_actions.id_pressed.emit(5)
	check(context_doc.layers.size() == 3 and context_doc.layers[-1].objects[0].id != imported.id
		and context_doc.layers[-1].objects[0].image_key == imported.image_key,
		"duplicating a layer gives the image an independent object")
	app.write_project("user://menu-picture.havu")
	DirAccess.remove_absolute("user://menu-logo.png")
	var reopened_image := Document.new()
	check(reopened_image.load_from("user://menu-picture.havu").is_empty() and not reopened_image.paper_visible
		and is_equal_approx(reopened_image.layers[-1].opacity, 0.45),
		"the project reopens with embedded pictures and transparency after deleting the source file")
	var lookup := PigmentIndex.new()
	lookup.rebuild(reopened_image)
	var sampled_point := Art.bounds(reopened_image.layers[-1].objects[0]).get_center()
	check(lookup.sample(sampled_point).is_equal_approx(Art.sample(reopened_image, sampled_point)),
		"eyedropper and mixer respect picture alpha and layer opacity")

	var source_texture := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	source_texture.set_pixel(4, 4, Color("#79d7b4"))
	var original_pixels := source_texture.get_data()
	var displayed := Raster.display_image(source_texture)
	check(displayed.has_mipmaps() and displayed.get_size() == source_texture.get_size()
		and displayed.get_pixel(4, 4) == source_texture.get_pixel(4, 4)
		and not source_texture.has_mipmaps() and source_texture.get_data() == original_pixels,
		"display mipmaps preserve the editable raster source")
	var premultiplied := Image.create_from_data(2, 1, false, Image.FORMAT_RGBA8,
		PackedByteArray([64, 16, 0, 128, 120, 90, 30, 255]))
	PngExport.straighten_alpha(premultiplied)
	check(premultiplied.get_data() == PackedByteArray([128, 32, 0, 128, 120, 90, 30, 255]),
		"transparent PNG conversion keeps the original color through partial alpha")

	app.reset_layout()
	for panel in app.panels.values(): panel.hide()
	var covering_panel: Control = app.panels.Brushes
	var covered_layers = app.panels.Layers
	var covered_color = app.panels.Color
	covering_panel.show()
	covering_panel.position = Vector2(180, 170)
	var fixed_position := covering_panel.position
	covered_color.position = fixed_position
	covered_color.show()
	check(not covered_color.get_rect().intersects(covering_panel.get_rect())
		and covering_panel.position == fixed_position, "opening a panel finds a clear slot without moving the open panel")
	covered_color.hide()
	app.set_workspace_option("avoid_panel_overlap", false)
	covered_color.position = fixed_position
	covered_color.show()
	check(covered_color.position == fixed_position, "workspace settings can keep the exact saved position on reopening")
	covered_color.hide()
	covering_panel.hide()
	app.set_workspace_option("avoid_panel_overlap", true)
	for panel in [covered_layers, covered_color, covering_panel]:
		panel.preferred_size = Vector2(390, 360) if panel == covering_panel else Vector2(180, 190)
		panel.apply_preferred_size()
		panel.show()
		panel.move_to_front()
	await process_frame
	covering_panel.position = Vector2(320, 210)
	covered_layers.position = Vector2(350, 234)
	covered_color.position = Vector2(412, 269)
	await process_frame
	var tabs: Dictionary = app.panel_reveal_tabs.tabs
	var layers_tab: Control = tabs.Layers
	var color_tab: Control = tabs.Color
	check(layers_tab.is_visible_in_tree() and color_tab.is_visible_in_tree()
		and not layers_tab.get_rect().intersects(covering_panel.get_rect())
		and not color_tab.get_rect().intersects(covering_panel.get_rect())
		and not layers_tab.get_rect().intersects(color_tab.get_rect()),
		"fully covered panels get separate grab tabs outside the covering panel")
	covered_color.position.x = covering_panel.get_rect().end.x - 60
	await process_frame
	check(not color_tab.is_visible_in_tree(), "partially visible panels need no grab tab")
	covered_color.position.x = 412
	await process_frame

	var panel_action: Button = app.layer_actions_button
	var original_layers_position: Vector2 = covered_layers.position
	var original_layers_size: Vector2 = covered_layers.preferred_size
	covered_layers.preferred_size = Vector2(290, 300)
	covered_layers.apply_preferred_size()
	await process_frame
	covered_layers.position.x += covering_panel.get_rect().end.x + 16 - panel_action.get_global_rect().get_center().x
	var exposed_layers_position: Vector2 = covered_layers.position
	await process_frame
	tap_window_control(root, panel_action)
	check(covered_layers.get_index() > covering_panel.get_index() and covered_layers.position == exposed_layers_position
		and app.layer_actions.visible,
		"touching a control on a partially covered panel raises it and activates the control")
	app.layer_actions.hide()
	covering_panel.move_to_front()
	click_window_control(root, panel_action)
	check(covered_layers.get_index() > covering_panel.get_index() and covered_layers.position == exposed_layers_position
		and app.layer_actions.visible,
		"pressing the exposed panel control with a pen also raises it without moving it")
	app.layer_actions.hide()
	covered_layers.preferred_size = original_layers_size
	covered_layers.apply_preferred_size()
	covered_layers.position = original_layers_position
	covering_panel.move_to_front()
	await process_frame

	var cover_position := covering_panel.position
	var layer_position: Vector2 = covered_layers.position
	var tab_tap := InputEventScreenTouch.new()
	tab_tap.index = 10
	tab_tap.pressed = true
	tab_tap.position = layers_tab.get_global_rect().get_center()
	root.push_input(tab_tap, true)
	var tab_drag := InputEventScreenDrag.new()
	tab_drag.index = tab_tap.index
	var drag_offset := Vector2(415, 280)
	tab_drag.position = tab_tap.position + drag_offset
	root.push_input(tab_drag, true)
	await process_frame
	check(covered_layers.position.is_equal_approx(layer_position + drag_offset)
		and covering_panel.position == cover_position and not layers_tab.is_visible_in_tree(),
		"touch dragging a grab tab moves only the covered panel live")
	tab_tap.pressed = false
	tab_tap.position = tab_drag.position
	root.push_input(tab_tap, true)
	mouse_press.position = color_tab.get_global_rect().get_center()
	mouse_release.position = mouse_press.position
	root.push_input(mouse_press, true)
	root.push_input(mouse_release, true)
	await process_frame
	check(covered_color.get_index() > covering_panel.get_index() and not color_tab.is_visible_in_tree(),
		"clicking a grab tab brings the covered panel forward")

	covering_panel.move_to_front()
	await process_frame
	app.show_project_home()
	await process_frame
	check(not color_tab.is_visible_in_tree(), "covered-panel grab tabs stay out of Projects")
	app.project_home.resume_requested.emit()
	await process_frame
	check(color_tab.is_visible_in_tree(), "grab tabs return on the canvas")
	app.set_workspace_option("panel_reveal_tabs", false)
	check(not color_tab.is_visible_in_tree(), "grab tabs can be disabled in Workspace settings")

	var flat_nib: Dictionary = catalog.filter(func(preset): return preset.name == "Senlin calligraphy")[0]
	app.apply_brush(flat_nib)
	app.canvas.fit()
	var draw_start: Vector2 = app.canvas.origin + Vector2(120, 120) * app.canvas.zoom
	app.canvas.begin(draw_start, 0.55)
	app.canvas.finish()
	var new_stroke: Dictionary = app.document.layers[app.document.active].objects[-1]
	var nib_profile := BrushLibrary.profile_from(flat_nib)
	check(new_stroke.kind == "stroke" and BrushLibrary.profile_from(new_stroke) == nib_profile
		and BrushLibrary.profile_from(app.current_brush_preview.cached) == nib_profile,
		"selecting an adapted brush applies the same profile to the preview and canvas")
	app.write_project("user://brush-profile.havu")
	var reopened_profile := Document.new()
	check(reopened_profile.load_from("user://brush-profile.havu").is_empty()
		and BrushLibrary.profile_from(reopened_profile.find_object(new_stroke.id)) == nib_profile,
		"adapted brush profiles survive project save and reopen")
	check(Art.svg(reopened_profile, false).contains(Art.points_string(Art.segments(new_stroke)[0].polygon)),
		"adapted nib geometry exports as vectors")
	var invalid_preset := flat_nib.duplicate()
	invalid_preset.tip_ratio = 0
	check(not app.valid_preset(invalid_preset), "out-of-range brush profiles are rejected on import")

	app.reset_layout()
	app.create_document(false)
	await process_frame
	var original_layer: Dictionary = app.document.layers[0]
	var layers_before: Control = app.layer_rows[original_layer.id]
	var new_layer_button: Button = app.panels.Layers.find_child("NewLayerButton", true, false)
	new_layer_button.pressed.emit()
	check(app.document.layers.size() == 2 and app.document.active == 1
		and app.document.layers[1].type == "vector" and app.layer_rows[original_layer.id] == layers_before,
		"the new layer button creates and selects a vector layer while retaining existing rows")
	var layer_select: Button = layers_before.get_node("Content/SelectLayer")
	layer_select.pressed.emit()
	check(app.document.active == 0 and layers_before.get_theme_stylebox("panel") == app.layer_row_styles[1],
		"selecting the name or thumbnail moves the active accent")
	var eye: Button = layers_before.get_node("Content/Visibility")
	var lock: Button = layers_before.get_node("Content/Lock")
	await process_frame
	for control in [eye, lock]:
		var layer_tap := InputEventScreenTouch.new()
		layer_tap.index = 11
		layer_tap.position = control.get_global_rect().get_center()
		layer_tap.pressed = true
		root.push_input(layer_tap, true)
		layer_tap.pressed = false
		root.push_input(layer_tap, true)
	check(not original_layer.visible and original_layer.locked
		and eye.icon == app.layer_icons.hidden and lock.icon == app.layer_icons.locked,
		"touching visibility and lock buttons updates the row state")
	lock.pressed.emit()
	app.document.set_layer_opacity(0, 0.48)
	var layer_detail: Label = layer_select.get_node("Identity/Labels/Detail")
	check(layer_detail.text.begins_with("48%"), "layer opacity is visible in the row")

	app.create_document(false)
	var vector_doc = app.document
	var vector_canvas = app.canvas
	app.set_workspace_option("contextual_actions", true)
	vector_canvas.fit()
	app.tool_buttons.shapes.pressed.emit()
	check(app.shape_menu.visible and app.shape_menu.get_item_text(8) == "Line"
		and app.shape_menu.get_item_text(10) == "Pen path", "the Shapes tool opens a menu with lines and custom paths")
	app.shape_menu.hide()
	app.shape_menu.id_pressed.emit(2)
	check(vector_canvas.tool == "rounded_rect" and app.shape_actions.is_visible_in_tree(), "choosing a shape shows its contextual Style control")
	app.shape_actions.get_child(0).pressed.emit()
	app.shape_fill_switch.button_pressed = false
	app.shape_outline_switch.button_pressed = true
	app.shape_outline_picker.color = Color("#b4483180")
	app.shape_line_width.value = 12
	app.shape_style_opacity.value = 60
	app.shape_style_dialog.hide()
	app.shape_style_dialog.confirmed.emit()
	var shape_start: Vector2 = vector_canvas.origin + Vector2(150, 150) * vector_canvas.zoom
	var shape_end: Vector2 = vector_canvas.origin + Vector2(410, 360) * vector_canvas.zoom
	vector_canvas.begin(shape_start, 0.55)
	vector_canvas.update_stroke(shape_end, 0.55)
	vector_canvas.finish()
	var hollow: Dictionary = vector_doc.layers[0].objects[-1]
	check(hollow.kind == "rect" and hollow.corner_radius > 0 and not Art.has_fill(hollow)
		and not Art.contains(hollow, Vector2(260, 240)) and Art.contains(hollow, Vector2(260, 150)),
		"an outline-only rounded rectangle is hollow and selectable at its edge")
	check(is_equal_approx(Art.color_at(hollow, Vector2(260, 150)).a, Color("#b4483180").a * 0.6),
		"outline transparency and shape opacity are applied together")
	var vector_svg := Art.svg(vector_doc, false)
	check(vector_svg.contains('fill="none" stroke="#b44831"') and vector_svg.contains('stroke-width="12.0"')
		and vector_svg.contains(' rx="'), "outline-only rounded rectangles export as editable SVG geometry")

	app.set_tool("select")
	check(app.selected_shape_style.is_visible_in_tree(), "a selected vector shape exposes Style")
	app.selected_shape_style.pressed.emit()
	app.shape_fill_switch.button_pressed = true
	app.shape_fill_picker.color = Color("#79d7b440")
	app.shape_style_dialog.hide()
	app.shape_style_dialog.confirmed.emit()
	check(Art.has_fill(hollow) and hollow.color == "#79d7b440" and hollow.outline_width == 12,
		"Style edits an existing vector shape without replacing its geometry")
	vector_doc.undo()
	check(not vector_doc.find_object(hollow.id).fill_enabled, "undo restores the previous shape style")
	check(app.tool_buttons.fill.self_modulate.a == 1.0, "vector artwork re-enables the Fill button")
	app.set_tool("fill")
	vector_canvas.color = Color("#226451")
	vector_canvas.touch_paints = false
	var shape_tap: Vector2 = vector_canvas.origin + Vector2(260, 240) * vector_canvas.zoom
	vector_canvas.begin_contact(0, shape_tap)
	vector_canvas.end_contact(0, shape_tap, false)
	check(vector_doc.find_object(hollow.id).fill_enabled, "a finger tap fills a hollow vector shape with finger painting off")

	var fill_doc := Document.new()
	fill_doc.blank()
	var loop := stroke()
	loop.points = [[100.0, 100.0, 1.0, "#226451"], [350.0, 100.0, 1.0, "#226451"],
		[350.0, 350.0, 1.0, "#226451"], [100.0, 350.0, 1.0, "#226451"], [100.0, 100.0, 1.0, "#226451"]]
	fill_doc.add(loop)
	var fill_canvas = load("res://scripts/canvas.gd").new()
	fill_canvas.document = fill_doc
	fill_canvas.size = Vector2(620, 520)
	root.add_child(fill_canvas)
	fill_canvas.fit()
	fill_canvas.tool = "fill"
	fill_canvas.color = Color("#b44440")
	var loop_center: Vector2 = fill_canvas.origin + Vector2(225, 225) * fill_canvas.zoom
	fill_canvas.begin(loop_center, 0.55)
	var filled: Dictionary = fill_doc.layers[0].objects[0]
	check(filled.kind == "polygon" and filled.color == "#b44440" and fill_doc.layers[0].objects[-1].id == loop.id
		and Document.validate(fill_doc.snapshot()).is_empty(), "Fill finds a closed brush outline from its center and preserves the stroke")
	fill_canvas.color = Color("#e1b45b")
	fill_canvas.begin(fill_canvas.origin + Vector2(100, 225) * fill_canvas.zoom, 0.55)
	check(fill_doc.layers[0].objects.size() == 2 and filled.color == "#e1b45b", "refilling from the outline recolors the existing region")
	fill_doc.undo()
	check(fill_doc.layers[0].objects[0].color == "#b44440", "one undo restores the previous fill")
	fill_doc.layers[0].locked = true
	fill_canvas.begin(loop_center, 0.55)
	check(fill_doc.layers[0].objects[0].color == "#b44440", "Fill respects a locked visible layer")
	fill_doc.layers[0].locked = false
	var old_fill_origin: Vector2 = fill_canvas.origin
	fill_canvas.begin_contact(1, loop_center)
	fill_canvas.move_contact(1, loop_center + Vector2(24, 0), 0.55)
	fill_canvas.end_contact(1, loop_center + Vector2(24, 0), false)
	check(fill_canvas.origin == old_fill_origin + Vector2(24, 0) and fill_doc.layers[0].objects[0].color == "#b44440",
		"dragging with Fill selected pans without applying color")
	fill_doc.blank()
	for line in [[Vector2(100, 100), Vector2(340, 100)], [Vector2(340, 100), Vector2(340, 340)],
			[Vector2(340, 340), Vector2(100, 340)], [Vector2(100, 340), Vector2(100, 100)],
			[Vector2(220, 100), Vector2(220, 340)]]:
		var vertices := []
		for point in line: vertices.append([point.x, point.y])
		fill_doc.add({"kind": "path", "vertices": vertices, "color": "#141414", "opacity": 1.0,
			"outline_width": 7.0, "outline_color": "#141414"})
	fill_canvas.color = Color("#ed7e44")
	var compartment_tap: Vector2 = fill_canvas.origin + Vector2(160, 220) * fill_canvas.zoom
	fill_canvas.begin_contact(1, compartment_tap)
	fill_canvas.end_contact(1, compartment_tap, false)
	var compartment: Dictionary = fill_doc.find_object(fill_doc.selection)
	check(compartment.get("kind") == "polygon" and Art.contains(compartment, Vector2(160, 220))
		and not Art.contains(compartment, Vector2(280, 220)) and fill_doc.layers[0].objects.size() == 6,
		"vector bucket fills one compartment enclosed by several touching lines")
	if compartment.get("kind") == "polygon":
		check(Document.validate(fill_doc.snapshot()).is_empty() and Art.svg(fill_doc, false).contains("#ed7e44"),
			"the traced compartment remains an editable polygon in the document and SVG")
		fill_canvas.color = Color("#65d8a9")
		fill_canvas.fill_at(Vector2(160, 220))
		check(compartment.color == "#65d8a9" and fill_doc.layers[0].objects.size() == 6,
			"refilling a traced compartment changes its color in place")
	fill_doc.layers[0].objects.pop_back()
	fill_doc.layers[0].objects.pop_back()
	fill_doc.layers[0].objects.pop_front()
	fill_canvas.fill_at(Vector2(160, 220))
	check(fill_doc.layers[0].objects.size() == 3, "vector bucket leaves an open outline alone")

	fill_doc.blank()
	var overshot := stroke()
	overshot.points = [[80, 100, 0.8, "#226451"], [340, 100, 0.8, "#226451"], [340, 340, 0.8, "#226451"],
		[100, 340, 0.8, "#226451"], [100, 80, 0.8, "#226451"]]
	overshot.size = 12.0
	fill_doc.add(overshot)
	fill_canvas.fill_at(Vector2(200, 200))
	var crossing_fill: Dictionary = fill_doc.find_object(fill_doc.selection)
	check(crossing_fill.get("kind") == "polygon" and fill_doc.layers[0].objects.size() == 2
		and Art.contains(crossing_fill, Vector2(200, 200)), "a hand-drawn outline fills when its ends cross")

	var unfilled_color: String = crossing_fill.get("color", "")
	fill_doc.layers.append(fill_doc.new_layer("Empty"))
	fill_doc.active = 1
	fill_canvas.color = Color("#881155")
	fill_canvas.fill_at(Vector2(200, 200))
	check(crossing_fill.get("color") == unfilled_color and fill_doc.layers[1].objects.is_empty(),
		"Fill leaves artwork on other layers alone")

	fill_canvas.free()

	for tool in ["line", "arrow", "triangle", "diamond", "star", "circle", "square"]:
		app.set_tool(tool)
		vector_canvas.begin(shape_start, 0.55)
		vector_canvas.update_stroke(shape_end, 0.55)
		vector_canvas.finish()
		var next_shape: Dictionary = vector_doc.layers[0].objects[-1]
		check(next_shape.kind == vector_canvas.SHAPE_TOOLS[tool] and Art.polygon(next_shape).size() >= 2,
			"%s creates editable vector geometry" % tool)
	var square: Dictionary = vector_doc.layers[0].objects[-1]
	check(is_equal_approx(square.extent[0], square.extent[1]), "the Square tool constrains both dimensions on tablets")
	vector_svg = Art.svg(vector_doc, false)
	check(vector_svg.contains("<polyline") and vector_svg.contains("<ellipse"), "lines, arrows and ellipses export without rasterization")

	app.set_tool("path")
	for point in [Vector2(530, 160), Vector2(680, 180), Vector2(630, 310)]:
		vector_canvas.begin(vector_canvas.origin + point * vector_canvas.zoom, 0.55)
		vector_canvas.finish()
	check(not app.finish_path_button.disabled and not app.close_path_button.disabled, "three pen points can finish open or closed")
	app.close_path_button.pressed.emit()
	var custom_shape: Dictionary = vector_doc.layers[0].objects[-1]
	check(custom_shape.kind == "polygon" and custom_shape.vertices.size() == 3 and vector_canvas.path_points.is_empty(),
		"Close commits a custom path as a fillable vector shape")
	app.set_tool("nodes")
	check(app.node_spread_slider.editable and app.node_spread_slider.value == 0.0,
		"paths start in single-node mode")
	app.node_spread_slider.value = 75
	check(vector_canvas.path_node_spread == 0.75 and vector_canvas.stroke_node_spread == 0.25
		and app.settings.get_value("workspace", "path_node_spread") == 0.75,
		"the contextual Spread slider saves a separate preference for paths")
	app.node_spread_slider.value = 0
	var neighboring_vertex: Array = custom_shape.vertices[1].duplicate()
	var first_point: Vector2 = vector_canvas.origin + Art.v(custom_shape.pos) * vector_canvas.zoom
	vector_canvas.begin(first_point, 0.55)
	vector_canvas.update_stroke(first_point + Vector2(20, 10) * vector_canvas.zoom, 0.55)
	vector_canvas.finish()
	check(Art.v(custom_shape.vertices[0]).is_equal_approx(Vector2(20, 10)) and custom_shape.vertices[1] == neighboring_vertex,
		"dragging a path node leaves its neighbors fixed at zero Spread")
	check(app.node_actions.is_visible_in_tree(), "the Nodes tool shows its Add node action beside the toolbar")
	app.add_node_button.pressed.emit()
	check(vector_canvas.adding_node and app.add_node_button.button_pressed, "the contextual action arms node insertion")
	var closing_midpoint := Art.v(custom_shape.vertices[0]).lerp(Art.v(custom_shape.vertices[-1]), 0.5)
	var insert_touch: Vector2 = vector_canvas.origin + (Art.v(custom_shape.pos) + closing_midpoint) * vector_canvas.zoom
	vector_canvas.begin_contact(7, insert_touch)
	check(custom_shape.vertices.size() == 3, "a finger touch waits for release before adding a node")
	vector_canvas.end_contact(7, insert_touch, false)
	check(custom_shape.vertices.size() == 4 and Art.v(custom_shape.vertices[-1]).is_equal_approx(closing_midpoint)
		and custom_shape.get("node_anchors") == [3] and not vector_canvas.adding_node
		and not app.add_node_button.button_pressed, "releasing on a closing edge adds a node and returns to move mode")
	var custom_id: String = custom_shape.id
	vector_doc.undo()
	check(vector_doc.find_object(custom_id).vertices.size() == 3, "one undo removes the inserted node")
	vector_doc.redo()
	check(vector_doc.find_object(custom_id).vertices.size() == 4, "redo restores the inserted node")
	vector_doc.selection = custom_id
	var node_offset := Vector2(14, 6)
	vector_canvas.begin(insert_touch, 0.55)
	vector_canvas.update_stroke(insert_touch + node_offset * vector_canvas.zoom, 0.55)
	vector_canvas.finish()
	check(Art.v(vector_doc.find_object(custom_id).vertices[3]).is_equal_approx(closing_midpoint + node_offset),
		"the newly inserted node is immediately draggable")
	app.set_tool("path")
	vector_canvas.begin(shape_start, 0.55)
	vector_canvas.begin(shape_end, 0.55)
	app.finish_path_button.pressed.emit()
	check(vector_doc.layers[0].objects[-1].kind == "path", "Finish commits a custom path without closing it")
	app.write_project("user://vector-shapes.havu")
	var reopened_shapes := Document.new()
	check(reopened_shapes.load_from("user://vector-shapes.havu").is_empty()
		and Art.svg(reopened_shapes, false) == Art.svg(vector_doc, false), "vector geometry and paint survive project save and reopen")

	var reopened_anchors: Array = reopened_shapes.find_object(custom_id).get("node_anchors", [])
	check(reopened_anchors.size() == 1 and int(reopened_anchors[0]) == 3, "explicit nodes survive project save and reopen")

	app.reset_layout()
	app.toggle_color_panel()
	app.color_panel_tabs[1].pressed.emit()
	app.set_color(Color("#000000"))
	await process_frame
	await process_frame
	var red_slider: HSlider = app.color_channels.sliders[0]
	var rgb_area := red_slider.get_global_rect()
	var red_touch := InputEventScreenTouch.new()
	red_touch.index = 12
	red_touch.position = rgb_area.position + rgb_area.size * Vector2(0.4, 0.5)
	red_touch.pressed = true
	var color_before_slider: String = app.recent_colors[0]
	root.push_input(red_touch, true)
	var red_drag := InputEventScreenDrag.new()
	red_drag.index = red_touch.index
	red_drag.position = rgb_area.position + rgb_area.size * Vector2(0.8, 0.5)
	root.push_input(red_drag, true)
	check(app.canvas.color.r > 0.65 and app.recent_colors[0] == color_before_slider,
		"a finger can drag an RGB slider without committing intermediate colors")
	red_touch.pressed = false
	red_touch.position = red_drag.position
	root.push_input(red_touch, true)
	check(app.recent_colors[0] == "#" + app.canvas.color.to_html(false),
		"touch release keeps the adjusted RGB color")
	var rgb_committed: Color = app.canvas.color
	var rgb_history: String = app.recent_colors[0]
	red_touch.position = rgb_area.position + rgb_area.size * Vector2(0.25, 0.5)
	red_touch.pressed = true
	root.push_input(red_touch, true)
	red_touch.pressed = false
	red_touch.canceled = true
	root.push_input(red_touch, true)
	check(app.canvas.color == rgb_committed and app.recent_colors[0] == rgb_history,
		"canceling a touch adjustment restores the original color")
	mouse_press.position = rgb_area.position + rgb_area.size * Vector2(0.25, 0.5)
	root.push_input(mouse_press, true)
	check(app.canvas.color.r < 0.4 and app.recent_colors[0] == rgb_history,
		"pressing the RGB track with a mouse or pen previews without changing recents")
	mouse_release.position = mouse_press.position
	root.push_input(mouse_release, true)
	check(app.recent_colors[0] == "#" + app.canvas.color.to_html(false), "releasing the track commits the preview")

	app.canvas.zoom_at(1.7, app.canvas.size * 0.5)
	app.canvas.pan_by(Vector2(26, -12))
	var canvas_anchor: Vector2 = app.canvas.to_document(app.canvas.size * 0.5)
	var shown_zoom: float = app.canvas.visible_zoom()
	var unscaled_workspace: Vector2 = app.size
	var art_before_scale: Dictionary = app.document.snapshot()
	app.show_workspace_settings()
	await process_frame
	var settings_window: AcceptDialog = app.workspace_settings_dialog
	var scale_control = app.ui_scale_slider
	var old_track: Transform2D = scale_control.get_screen_transform()
	var track_middle: float = scale_control.size.y * 0.5
	var track_width: float = scale_control.size.x
	var scale_press := InputEventScreenTouch.new()
	scale_press.index = 13
	scale_press.pressed = true
	scale_press.position = scale_control.get_global_transform_with_canvas() * Vector2(track_width * 0.4, track_middle)
	settings_window.push_input(scale_press, true)
	var scale_drag := InputEventScreenDrag.new()
	scale_drag.index = scale_press.index
	var desired_screen := old_track * Vector2(track_width * 0.8, track_middle)
	scale_drag.position = scale_control.get_global_transform_with_canvas() * (scale_control.get_screen_transform().affine_inverse() * desired_screen)
	settings_window.push_input(scale_drag, true)
	await process_frame
	await process_frame
	check(scale_control.dragging and app.ui_scale_label.text == "120%" and is_equal_approx(root.content_scale_factor, 1.2)
		and app.size.x < unscaled_workspace.x, "dragging UI scale changes the workspace before release")
	check(is_equal_approx(app.canvas.visible_zoom(), shown_zoom)
		and app.canvas.to_document(app.canvas.size * 0.5).is_equal_approx(canvas_anchor)
		and app.document.snapshot() == art_before_scale, "UI scale preserves manual canvas zoom, position, and document geometry")
	scale_press.pressed = false
	scale_press.position = scale_control.get_global_transform_with_canvas() * (scale_control.get_screen_transform().affine_inverse() * desired_screen)
	settings_window.push_input(scale_press, true)
	check(not scale_control.dragging and app.settings.get_value("workspace", "ui_scale_percent", 100) == 120,
		"release saves the UI scale even though the slider moved during the drag")
	old_track = scale_control.get_screen_transform()
	scale_press.index = 14
	scale_press.pressed = true
	scale_press.position = scale_control.get_global_transform_with_canvas() * Vector2(scale_control.size.x * 0.2, scale_control.size.y * 0.5)
	settings_window.push_input(scale_press, true)
	check(app.ui_scale_label.text == "90%", "the slider previews smaller interface sizes")
	scale_press.pressed = false
	scale_press.canceled = true
	settings_window.push_input(scale_press, true)
	check(is_equal_approx(root.content_scale_factor, 1.2)
		and app.settings.get_value("workspace", "ui_scale_percent", 100) == 120, "canceling a drag restores the previous scale")
	settings_window.hide()
	app.autosave_timer.stop()
	app.queue_free()
	await process_frame
	root.content_scale_factor = 1.0
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.ui_scale_slider.value == 120 and is_equal_approx(root.content_scale_factor, 1.2),
		"UI scale survives restart")
	root.content_scale_size = app.android_content_base(Vector2i(800, 1050))
	root.size = Vector2i(800, 1050)
	app.project_home.resume_requested.emit()
	app.ui_scale_slider.choose_percent(130)
	app.show_workspace_settings()
	await process_frame
	await process_frame
	check(app.size.x < 690 and app.get_node("TopBar").size.x <= app.size.x
		and app.get_node("BottomBar").size.x <= app.size.x and app.workspace_settings_dialog.size.y < app.size.y,
		"the largest UI scale keeps toolbar controls and settings within a tablet portrait viewport")
	app.workspace_settings_dialog.hide()
	app.reset_ui_scale_button.pressed.emit()
	await process_frame
	check(app.ui_scale_label.text == "100%" and is_equal_approx(root.content_scale_factor, 1.0)
		and app.settings.get_value("workspace", "ui_scale_percent", 0) == 100, "Reset restores and saves the default UI scale")

	var workspace_opener: Button = app.header_tools.get_node("WorkspaceMenuButton")
	var file_opener: Button = app.header_tools.get_node("FileMenuButton")
	tap_window_control(root, workspace_opener)
	check(app.workspace_menu.visible, "a finger opens the workspace three-dot menu through the toolbar")
	tap_window_control(root, workspace_opener)
	await process_frame
	await process_frame
	check(not app.workspace_menu.visible, "tapping the three dots again closes its menu")
	click_window_control(root, file_opener)
	check(app.file_menu.visible, "a pen opens the File menu through the toolbar")
	tap_window_control(root, workspace_opener)
	await process_frame
	await process_frame
	check(not app.file_menu.visible and app.workspace_menu.visible,
		"one finger tap switches from the pen-opened File menu to Workspace options")
	var input_settings_tap := InputEventScreenTouch.new()
	var input_settings_index: int = app.workspace_menu.get_item_index(7)
	var item_height: float = float(app.workspace_menu.size.y) / app.workspace_menu.item_count
	input_settings_tap.position = Vector2(app.workspace_menu.position) + Vector2(30, item_height * (input_settings_index + 0.5))
	input_settings_tap.pressed = true
	root.push_input(input_settings_tap, true)
	input_settings_tap = input_settings_tap.duplicate()
	input_settings_tap.pressed = false
	root.push_input(input_settings_tap, true)
	await process_frame
	await process_frame
	check(app.input_settings_dialog.visible, "a finger selects Input settings from the Workspace menu")
	app.input_settings_dialog.hide()
	await process_frame
	var missed_release := InputEventScreenTouch.new()
	missed_release.index = 23
	missed_release.position = workspace_opener.get_global_rect().get_center()
	missed_release.pressed = true
	root.push_input(missed_release, true)
	tap_window_control(root, workspace_opener)
	check(app.workspace_menu.visible, "a missing finger release cannot block the next tap on the three dots")
	missed_release.pressed = false
	missed_release.canceled = true
	root.push_input(missed_release, true)
	app.workspace_menu.hide()
	await process_frame

	# Exercise real input routing with a tablet-sized embedded viewport.
	zoom_popup = app.get_node("ZoomPresets")
	app.zoom_button.pressed.emit()
	var picked_by_touch: Array[int] = []
	zoom_popup.id_pressed.connect(func(id): picked_by_touch.append(id))
	var menu_tap := InputEventScreenTouch.new()
	menu_tap.index = 22
	menu_tap.pressed = true
	menu_tap.position = Vector2(zoom_popup.position) + Vector2(25, 16)
	root.push_input(menu_tap, true)
	menu_tap = menu_tap.duplicate()
	menu_tap.pressed = false
	root.push_input(menu_tap, true)
	await process_frame
	await process_frame
	check(picked_by_touch == [0] and not zoom_popup.visible and not Input.emulate_mouse_from_touch,
		"a finger chooses from a popup through real viewport input without global mouse emulation")
	app.zoom_button.pressed.emit()
	menu_tap = menu_tap.duplicate()
	menu_tap.pressed = true
	menu_tap.position = Vector2(zoom_popup.position) - Vector2(15, 15)
	root.push_input(menu_tap, true)
	menu_tap = menu_tap.duplicate()
	menu_tap.pressed = false
	root.push_input(menu_tap, true)
	await process_frame
	await process_frame
	check(not zoom_popup.visible and picked_by_touch == [0],
		"a finger tap outside the popup dismisses it without choosing an item")

	app.reset_layout()
	var blender: Dictionary = app.builtin_brushes.filter(func(preset): return preset.name == "Color mixer")[0]
	var blender_original := blender.duplicate(true)
	app.apply_brush(blender)
	app.open_brush_editor()
	await process_frame
	await process_frame
	var pressure_panel: Dictionary = app.brush_editor_sections.Pressure
	pressure_panel.button.pressed.emit()
	check(pressure_panel.content.is_visible_in_tree() and app.brush_pressure_graph.is_visible_in_tree(),
		"expanding Pressure reveals the width graph and brush pressure controls")
	var draft_preview = app.brush_editor_preview
	await process_frame
	var preview_position: Vector2 = draft_preview.global_position
	app.brush_tuning_scroll.scroll_vertical = 170
	await process_frame
	check(app.brush_tuning_scroll.scroll_vertical > 0 and draft_preview.global_position == preview_position,
		"the live preview stays in view while advanced controls scroll")
	var previous_mix_preview: Array = draft_preview.cached.points.duplicate(true)
	app.brush_profile_controls.pressure_curve.slider.value = 180
	app.brush_profile_controls.minimum_width.slider.value = 37
	app.brush_profile_controls.opacity_pressure.slider.value = 80
	check(draft_preview.cached.pressure_curve == 1.8 and draft_preview.cached.minimum_width == 0.37
		and draft_preview.cached.opacity_pressure == 0.8 and not app.brush_revert.disabled,
		"pressure edits immediately update the automatic stroke preview")
	app.brush_editor_sections.Mixing.button.pressed.emit()
	app.brush_profile_controls.pigment_load.slider.value = 135
	app.brush_profile_controls.pigment_carry.slider.value = 72
	app.brush_profile_controls.deposit_curve.slider.value = 72
	check(draft_preview.cached.points[9][3] != previous_mix_preview[9][3],
		"mixing edits change pigment in the automatic preview before saving")
	var before_stabilizing: Array = draft_preview.cached.points.duplicate(true)
	app.smooth_slider.value = 85
	check(draft_preview.cached.points[10][1] != before_stabilizing[10][1],
		"stabilization edits change the preview stroke itself")
	app.brush_profile_controls.spacing.slider.value = 38
	check(draft_preview.cached.points.size() < previous_mix_preview.size(), "spacing edits change the live sample density")

	app.brush_profile_controls.pressure_floor.slider.value = 20
	app.brush_profile_controls.pressure_ceiling.slider.value = 70
	app.brush_profile_controls.opacity_curve.slider.value = 200
	app.brush_profile_controls.pickup_curve.slider.value = 65
	check(draft_preview.cached.points[0][2] < 0.01 and draft_preview.cached.opacity_curve == 2.0
		and is_equal_approx(Art.stroke_alpha(0.5, 0.8, 2.0), 0.4),
		"pressure range and opacity curve update the live stroke and its alpha response independently")
	app.brush_editor_sections.Taper.button.pressed.emit()
	app.brush_profile_controls.taper_start.slider.value = 125
	app.brush_profile_controls.taper_end.slider.value = 150
	app.brush_profile_controls.taper_tip.slider.value = 12
	var drawn_preview: Dictionary = draft_preview.cached
	var preview_taper := Art.stroke_taper(drawn_preview)
	var preview_count: int = drawn_preview.points.size()
	check(app.brush_editor_sections.Taper.content.is_visible_in_tree()
		and is_equal_approx(Art.taper_factor(preview_taper, 0, preview_count), 0.12)
		and is_equal_approx(Art.taper_factor(preview_taper, preview_count - 1, preview_count), 0.12),
		"start and end taper change the live stroke geometry")
	var mix_only := {"pigment_load": 0.0, "pigment_carry": 0.7, "pickup_curve": 0.65}
	check(BrushLibrary.mix_pigment(Color.RED, Color.GREEN, Color.BLUE, 0.5, "mix", 1.0, mix_only).is_equal_approx(
		BrushLibrary.mix_pigment(Color.YELLOW, Color.GREEN, Color.BLUE, 0.5, "mix", 1.0, mix_only)),
		"zero pigment load blends existing colors without depositing the selected pigment")

	app.brush_editor_sections["Test pad"].button.pressed.emit()
	await process_frame
	var scratch = app.brush_test_canvas
	scratch.pressure_enabled = true
	var project_before_pad: Dictionary = app.document.snapshot()
	var pad_start: Vector2 = scratch.origin + Vector2(32, 55) * scratch.zoom
	var pad_end: Vector2 = scratch.origin + Vector2(195, 57) * scratch.zoom
	scratch.begin(pad_start, 0.2)
	scratch.update_stroke(pad_end, 0.8)
	var live_taper := Art.stroke_taper(scratch.current)
	var live_count: int = scratch.current.points.size()
	check(Art.taper_factor(live_taper, live_count - 1, live_count) == 1.0,
		"the pen keeps its untapered width at the live tip")
	scratch.finish()
	var test_mark: Dictionary = scratch.document.layers[1].objects[0]
	check(test_mark.spacing == 0.38 and test_mark.pigment_load == 1.35 and test_mark.points[0][3] != test_mark.points[-1][3]
		and app.document.snapshot() == project_before_pad, "the test pad uses draft settings without modifying the illustration")
	var test_taper := Art.stroke_taper(test_mark)
	var test_count: int = test_mark.points.size()
	check(is_equal_approx(test_mark.points[0][2], 0.01) and is_equal_approx(test_mark.points[-1][2], 1.0)
		and is_equal_approx(Art.taper_factor(test_taper, test_count - 1, test_count), 0.12)
		and not test_mark.has("live_stroke") and Document.validate(scratch.document.snapshot()).is_empty(),
		"the pad stores remapped pressure and applies the end taper when the pen lifts")

	var tapered_segment: Dictionary = Art.segments(test_mark)[-1]
	check(Art.svg(scratch.document, false).contains(Art.points_string(tapered_segment.polygon)),
		"the completed taper survives SVG export as vector geometry")

	app.clear_brush_test_pad()
	check(scratch.document.layers[1].objects.is_empty(), "clearing the test pad leaves the mixer surface ready")
	check(blender == blender_original and not app.brush_update.visible, "draft controls leave the bundled preset untouched")

	var prior_preset_count: int = app.presets.size()
	app.save_brush_preset()
	var save_brush_prompt: ConfirmationDialog = app.get_child(-1)
	var brush_name_input: LineEdit = save_brush_prompt.get_child(0)
	brush_name_input.text = "Sini's test blender"
	save_brush_prompt.hide()
	save_brush_prompt.confirmed.emit()
	var personal: Dictionary = app.active_brush
	check(app.presets.size() == prior_preset_count + 1 and personal.name == "Sini's test blender"
		and personal.minimum_width == 0.37 and personal.pigment_carry == 0.72
		and personal.pressure_ceiling == 0.70 and personal.taper_end == 1.50 and personal.pickup_curve == 0.65
		and app.brush_update.visible and app.brush_update.disabled, "Save as stores a named, editable preset in My brushes")
	app.brush_profile_controls.pigment_load.slider.value = 96
	app.brush_update.pressed.emit()
	check(app.presets.size() == prior_preset_count + 1 and app.active_brush.pigment_load == 0.96,
		"Update edits the personal brush without adding a duplicate")
	app.brush_profile_controls.pigment_load.slider.value = 43
	app.brush_revert.pressed.emit()
	check(app.canvas.brush_profile.pigment_load == 0.96 and app.brush_revert.disabled,
		"Reset restores the stored personal brush settings")
	app.export_brush()
	var brush_export_dialog: FileDialog = app.get_child(-1)
	brush_export_dialog.hide()
	brush_export_dialog.file_selected.emit("user://sini-test.havubrush")
	var brush_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://sini-test.havubrush"))
	check(app.valid_preset(brush_file) and BrushLibrary.profile_from(brush_file) == BrushLibrary.profile_from(app.active_brush),
		"exported Havu brushes retain advanced settings")
	app.import_brush()
	var brush_import_dialog: FileDialog = app.get_child(-1)
	brush_import_dialog.hide()
	brush_import_dialog.file_selected.emit("user://sini-test.havubrush")
	check(app.presets.size() == prior_preset_count + 2 and app.canvas.brush_profile.pigment_load == 0.96,
		"sharing and importing a brush restores the advanced controls")
	app.delete_saved_brush()
	var delete_brush_prompt: ConfirmationDialog = app.get_child(-1)
	delete_brush_prompt.hide()
	delete_brush_prompt.confirmed.emit()
	check(app.presets.size() == prior_preset_count + 1
		and app.presets[-1].name == "Sini's test blender", "deleting an imported copy keeps the original personal preset")
	app.apply_brush(app.presets[-1])
	app.brush_favorite_button.pressed.emit()
	var favorite_personal_key: String = app.brush_key(app.active_brush)
	app.brush_profile_controls.pigment_load.slider.value = 120
	app.rename_saved_brush()
	var rename_brush_prompt: ConfirmationDialog = app.get_child(-1)
	rename_brush_prompt.get_child(0).text = "Sini's blender"
	rename_brush_prompt.hide()
	rename_brush_prompt.confirmed.emit()
	check(app.active_brush.name == "Sini's blender" and app.active_brush.pigment_load == 0.96
		and app.canvas.brush_profile.pigment_load == 1.2, "renaming a personal brush keeps current draft edits unsaved")
	check(app.brush_key(app.active_brush) == favorite_personal_key and favorite_personal_key in app.favorite_brushes,
		"a renamed personal brush keeps its Favorite identity")
	var pressure_doc := Document.new()
	pressure_doc.blank()
	var pressure_ink := stroke()
	pressure_ink.opacity_pressure = 1.0
	pressure_ink.minimum_width = 0.3
	pressure_doc.add(pressure_ink)
	var ink_segments := Art.segments(pressure_ink)
	check(not Art.uses_ink_outline(pressure_ink) and ink_segments[0].color.a < ink_segments[-1].color.a
		and Art.svg(pressure_doc, false).count("<polygon") == ink_segments.size(),
		"pressure opacity is rendered and exported on ink strokes")
	app.autosave_timer.stop()
	app.queue_free()
	await process_frame
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.presets[-1].name == "Sini's blender" and app.presets[-1].pigment_load == 0.96
		and app.presets[-1].opacity_pressure == 0.8, "personal brush controls survive restart")
	check(favorite_personal_key in app.favorite_brushes and app.brush_key(app.presets[-1]) == favorite_personal_key
		and favorite_personal_key in app.recent_brushes, "favorite and recent brushes survive restart")

	app.create_document(false)
	app.reset_layout()
	var layered = app.document
	layered.add({"kind": "rect", "pos": [100, 100], "extent": [280, 200], "color": "#457c65", "opacity": 1.0})
	layered.commit()
	app.add_document_layer()
	layered.add({"kind": "rect", "pos": [130, 120], "extent": [160, 120], "color": "#f9ae88", "opacity": 1.0})
	layered.add({"kind": "rect", "pos": [170, 145], "extent": [160, 120], "color": "#6b396d", "opacity": 1.0})
	layered.commit()
	var selected_layer_id: String = layered.layers[1].id
	var mark_id: String = layered.layers[1].objects[0].id
	var opacity_history: int = layered.history.size()
	var scale_bar: HSlider = app.layer_opacity_slider
	await process_frame
	await process_frame
	var opacity_track := scale_bar.get_global_rect()
	var opacity_touch := InputEventScreenTouch.new()
	opacity_touch.index = 15
	opacity_touch.pressed = true
	opacity_touch.position = opacity_track.position + opacity_track.size * Vector2(0.62, 0.5)
	root.push_input(opacity_touch, true)
	var opacity_motion := InputEventScreenDrag.new()
	opacity_motion.index = opacity_touch.index
	opacity_motion.position = opacity_track.position + opacity_track.size * Vector2(0.40, 0.5)
	root.push_input(opacity_motion, true)
	var opacity_group: CanvasGroup = app.canvas.layer_renderers[selected_layer_id]
	check(is_equal_approx(opacity_group.self_modulate.a, 0.40) and layered.layers[1].opacity == 1.0
		and layered.history.size() == opacity_history, "layer opacity previews live without saving every drag step")
	opacity_touch.position = opacity_motion.position
	opacity_touch.pressed = false
	root.push_input(opacity_touch, true)
	check(is_equal_approx(layered.layers[1].opacity, 0.4) and layered.history.size() == opacity_history + 1,
		"releasing layer opacity commits one undo step")
	scale_bar.drag_started.emit()
	scale_bar.value = 75
	scale_bar.drag_ended.emit(false)
	check(scale_bar.value == 40 and is_equal_approx(layered.layers[1].opacity, 0.4),
		"canceling opacity preview restores the layer")

	var overlap_point := Vector2(195, 174)
	var before_merge: Dictionary = layered.snapshot()
	var expected_composite := Art.sample(layered, overlap_point)
	app.layer_actions.id_pressed.emit(8)
	check(layered.layers.size() == 1 and layered.can_edit(mark_id) and layered.layers[0].objects.size() == 3,
		"Merge Down keeps all marks editable in one layer")
	check(Art.sample(layered, overlap_point).is_equal_approx(expected_composite)
		and app.canvas.sample_pigment(overlap_point).is_equal_approx(expected_composite)
		and Art.svg(layered, false).count('<g opacity="0.4">') == 1
		and app.canvas.merge_renderers.size() == 1, "Merge Down keeps a translucent source composited as a single group")
	layered.undo()
	check(layered.snapshot() == before_merge, "undo restores the original layers and opacity")
	layered.redo()
	check(layered.layers.size() == 1 and layered.can_edit(mark_id), "redo restores the editable merge")
	layered.set_layer_opacity(0, 0.7)
	app.add_document_layer()
	var hidden_layer: Dictionary = layered.layers[-1]
	app.toggle_layer_flag(hidden_layer.id, "visible")
	app.toggle_layer_flag(hidden_layer.id, "locked")
	app.add_document_layer()
	layered.add({"kind": "ellipse", "pos": [140, 130], "extent": [140, 120], "color": "#fcda9a", "opacity": 0.6})
	layered.commit()
	var visible_composite := Art.sample(layered, overlap_point)
	app.layer_actions.id_pressed.emit(9)
	check(layered.layers.size() == 2 and layered.layers[1].id == hidden_layer.id and not layered.layers[1].visible,
		"Merge Visible leaves hidden layers intact")
	check(app.canvas.sample_pigment(overlap_point).is_equal_approx(visible_composite) and app.canvas.merge_renderers.size() == 2,
		"an already-merged translucent layer retains its nested opacity in a new merge")
	check(app.canvas.merge_renderers.values().any(func(node): return node.get_children().any(func(child): return child is SubViewport)),
		"nested opacity uses a separate render surface")
	app.select_layer(hidden_layer.id)
	check(not app.layer_opacity_slider.editable and app.alpha_lock_button.disabled, "full lock disables opacity and transparency controls")
	var locked_state: Dictionary = layered.snapshot()
	layered.rename_layer(layered.active, "Should stay locked")
	layered.move_layer(layered.active, 0)
	layered.remove_layer(layered.active)
	check(layered.snapshot() == locked_state, "full lock prevents renaming, moving, and deleting")
	app.write_project("user://merged-stack.havu")
	var restored_stack := Document.new()
	check(restored_stack.load_from("user://merged-stack.havu").is_empty()
		and Art.sample(restored_stack, overlap_point).is_equal_approx(visible_composite),
		"merged opacity scopes survive save and reopen")

	app.create_document(false)
	layered = app.document
	layered.add({"kind": "rect", "pos": [110, 100], "extent": [100, 120], "color": "#407d68", "opacity": 1.0})
	layered.add({"kind": "rect", "pos": [230, 100], "extent": [100, 120], "color": "#8d6656", "opacity": 0.5})
	layered.commit()
	app.alpha_lock_button.pressed.emit()
	var locked_layer_id: String = layered.layers[0].id
	check(layered.layers[0].alpha_locked and app.alpha_lock_button.button_pressed
		and app.layer_rows[locked_layer_id].get_node("Content/SelectLayer/Identity/Labels/Detail").text == "Alpha lock",
		"the checkerboard toggle shows alpha lock on the active layer")
	app.apply_brush(app.builtin_brushes[0])
	app.set_color(Color("#edb341"))
	var work_canvas = app.canvas
	work_canvas.fit()
	work_canvas.begin(work_canvas.origin + Vector2(35, 150) * work_canvas.zoom, 0.7)
	work_canvas.update_stroke(work_canvas.origin + Vector2(375, 150) * work_canvas.zoom, 0.7)
	work_canvas.finish()
	var protected_mark: Dictionary = layered.layers[0].objects[-1]
	check(protected_mark.has("paint_mask") and Art.contains(protected_mark, Vector2(150, 150))
		and not Art.contains(protected_mark, Vector2(70, 150)) and not Art.contains(protected_mark, Vector2(270, 150)),
		"alpha lock clips new brushwork to solid vector artwork and leaves other areas untouched")
	var previous_marks: int = layered.layers[0].objects.size()
	work_canvas.begin(work_canvas.origin + Vector2(75, 280) * work_canvas.zoom, 0.6)
	work_canvas.update_stroke(work_canvas.origin + Vector2(360, 280) * work_canvas.zoom, 0.6)
	work_canvas.finish()
	check(layered.layers[0].objects.size() == previous_marks, "a fully clipped brush stroke does not add an invisible object")
	app.write_project("user://alpha-lock.havu")
	var restored_mask := Document.new()
	check(restored_mask.load_from("user://alpha-lock.havu").is_empty() and restored_mask.layers[0].alpha_locked
		and Art.svg(restored_mask, false).contains('clip-path="url(#mask'), "alpha lock and clipped strokes survive save and SVG export")

	app.create_document(false)
	var solo_doc = app.document
	solo_doc.add({"kind": "rect", "pos": [105, 105], "extent": [120, 100], "color": "#24584a", "opacity": 1.0})
	solo_doc.commit()
	var first_layer_id: String = solo_doc.layers[0].id
	app.add_document_layer()
	var hidden_between: String = solo_doc.layers[1].id
	app.toggle_layer_flag(hidden_between, "visible")
	app.add_document_layer()
	var upper_layer_id: String = solo_doc.layers[2].id
	solo_doc.add({"kind": "rect", "pos": [160, 150], "extent": [130, 100], "color": "#ca8862", "opacity": 1.0})
	solo_doc.commit()
	var whole_stack: Dictionary = solo_doc.snapshot()
	app.layer_solo_button.pressed.emit()
	check(app.canvas.layer_renderers.size() == 1 and app.canvas.layer_renderers.has(upper_layer_id)
		and app.layer_solo_button.button_pressed and solo_doc.snapshot() == whole_stack,
		"Solo isolates the active layer without changing visibility or document history")
	check(app.canvas.sample_pigment(Vector2(125, 125)).is_equal_approx(Color(solo_doc.paper))
		and app.export_document("").snapshot() == whole_stack, "Solo affects picking while export retains the full stack")
	app.select_layer(first_layer_id)
	check(app.layer_solo_button.button_pressed and app.canvas.layer_renderers.has(first_layer_id)
		and not app.canvas.layer_renderers.has(upper_layer_id), "Solo follows the selected layer")
	app.layer_solo_button.pressed.emit()
	check(app.canvas.solo_layer_id.is_empty() and app.canvas.layer_renderers.has(upper_layer_id)
		and not app.canvas.layer_renderers.has(hidden_between), "leaving Solo restores the original visibility")

	var mixer: Dictionary = app.builtin_brushes.filter(func(preset): return preset.name == "Color mixer")[0]
	app.apply_brush(mixer)
	app.size_slider.value = 74
	app.apply_brush(app.builtin_brushes[0])
	app.apply_brush(mixer)
	check(app.canvas.brush_size == 74 and not app.brush_revert.disabled and mixer.size == 56,
		"switching away and back restores the unsaved draft without editing the preset")
	app.brush_revert.pressed.emit()
	check(app.canvas.brush_size == 56 and app.brush_revert.disabled, "Reset explicitly discards the restored draft")
	app.brush_favorite_button.pressed.emit()
	var favorites_index: int = app.brush_category.item_count - 3
	app.brush_category.select(favorites_index)
	app.brush_category.item_selected.emit(favorites_index)
	app.brush_search.text = "mixer"
	app.brush_search.text_changed.emit("mixer")
	check(app.brush_row_buttons.size() == 1 and app.brush_row_buttons[0].button_pressed
		and app.brush_row_buttons[0].get_node("FavoriteMark").visible, "Favorites filters brush previews and marks the active brush")
	app.brush_search.text = ""
	var recent_index := favorites_index + 1
	app.brush_category.select(recent_index)
	app.brush_category.item_selected.emit(recent_index)
	check(is_same(app.brush_row_buttons[0].get_meta("preset"), mixer)
		and app.recent_brushes.count(app.brush_key(mixer)) == 1, "Recent puts the latest brush first without duplicates")

	app.create_document(false)
	var selection_doc = app.document
	var selection_canvas = app.canvas
	selection_canvas.fit()
	selection_doc.add({"kind": "rect", "pos": [150, 150], "extent": [40, 40], "color": "#276251", "opacity": 1.0})
	var first_mark: String = selection_doc.selection
	app.add_document_layer()
	selection_doc.add({"kind": "ellipse", "pos": [235, 180], "extent": [40, 40], "color": "#f1d094", "opacity": 1.0})
	var second_mark: String = selection_doc.selection
	selection_doc.add({"kind": "rect", "pos": [355, 355], "extent": [30, 30], "color": "#bc8866", "opacity": 1.0})
	var corner_mark: String = selection_doc.selection
	app.add_document_layer()
	selection_doc.add({"kind": "rect", "pos": [180, 215], "extent": [30, 30], "color": "#c78677", "opacity": 1.0})
	selection_doc.layers[2].locked = true
	selection_doc.commit()
	app.tool_buttons.select.pressed.emit()
	check(app.selection_menu.visible and app.selection_menu.get_item_text(3) == "Freehand", "Select opens the object and area mode menu")
	app.selection_menu.hide()
	app.selection_menu.id_pressed.emit(1)
	var local := func(point: Vector2) -> Vector2: return selection_canvas.origin + point * selection_canvas.zoom
	touch_press(selection_canvas, 16, local.call(Vector2(125, 125)))
	touch_move(selection_canvas, 16, local.call(Vector2(315, 260)))
	check(selection_canvas.marquee_active and selection_doc.area_selection.is_empty(),
		"one finger draws a marquee with live feedback before committing")
	touch_release(selection_canvas, 16, local.call(Vector2(315, 260)))
	check(selection_doc.area_selection == [first_mark, second_mark] and not app.selection_actions.get_child(0).disabled,
		"rectangle selects enclosed objects across editable layers")
	var move_history: int = selection_doc.history.size()
	touch_press(selection_canvas, 16, local.call(Vector2(215, 185)))
	touch_move(selection_canvas, 16, local.call(Vector2(235, 209)))
	touch_release(selection_canvas, 16, local.call(Vector2(235, 209)))
	check(Art.v(selection_doc.find_object(first_mark).pos).is_equal_approx(Vector2(170, 174))
		and Art.v(selection_doc.find_object(second_mark).pos).is_equal_approx(Vector2(255, 204))
		and selection_doc.history.size() == move_history + 1, "dragging the empty space inside a marquee box moves both objects in one undo step")
	app.selection_actions.get_child(0).pressed.emit()
	check(selection_doc.layers[0].objects.size() == 2 and selection_doc.layers[1].objects.size() == 3
		and selection_doc.area_selection.size() == 2, "Duplicate keeps each copy on its original layer")
	app.selection_actions.get_child(1).pressed.emit()
	check(selection_doc.layers[0].objects.size() == 1 and selection_doc.layers[1].objects.size() == 2
		and selection_doc.layers[2].objects.size() == 1, "Delete removes only the selected copies")
	app.set_tool("select_ellipse")
	selection_canvas.begin(local.call(Vector2(90, 90)), 0.55)
	selection_canvas.update_stroke(local.call(Vector2(400, 400)), 0.55)
	selection_canvas.finish()
	check(selection_doc.area_selection == [first_mark, second_mark] and corner_mark not in selection_doc.area_selection,
		"ellipse selection excludes objects in the corners of its bounding rectangle")
	app.set_tool("select_lasso")
	selection_canvas.begin(local.call(Vector2(130, 130)), 0.55)
	for point in [Vector2(325, 130), Vector2(325, 292), Vector2(285, 292), Vector2(285, 258),
		Vector2(225, 258), Vector2(225, 320), Vector2(130, 320), Vector2(130, 130)]:
		selection_canvas.update_stroke(local.call(point), 0.55)
	selection_canvas.finish()
	check(selection_doc.area_selection == [first_mark, second_mark], "a freehand loop selects only the enclosed objects")
	app.set_tool("select_square")
	selection_canvas.begin(local.call(Vector2(470, 100)), 0.55)
	selection_canvas.update_stroke(local.call(Vector2(620, 190)), 0.55)
	selection_canvas.finish()
	check(Art.polygon_bounds(selection_canvas.selected_area).size.is_equal_approx(Vector2(90, 90)),
		"the Square marquee constrains both sides with touch controls alone")
	app.set_tool("select_circle")
	selection_canvas.begin(local.call(Vector2(470, 100)), 0.55)
	selection_canvas.update_stroke(local.call(Vector2(620, 190)), 0.55)
	selection_canvas.finish()
	check(Art.polygon_bounds(selection_canvas.selected_area).size.is_equal_approx(Vector2(90, 90)),
		"the Circle marquee constrains both axes")
	app.set_tool("select_rect")
	selection_canvas.begin(local.call(Vector2(480, 300)), 0.55)
	selection_canvas.update_stroke(local.call(Vector2(610, 420)), 0.55)
	selection_canvas.finish()
	check(selection_doc.selected_items().is_empty() and selection_canvas.selected_area.size() == 4,
		"an empty marquee is retained as a paintable region")
	app.clip_check.button_pressed = true
	selection_canvas.begin(local.call(Vector2(440, 350)), 0.55)
	selection_canvas.update_stroke(local.call(Vector2(650, 350)), 0.55)
	selection_canvas.finish()
	var clipped_area_mark: Dictionary = selection_doc.layers[selection_doc.active].objects[-1]
	check(clipped_area_mark.has("clip") and Art.contains(clipped_area_mark, Vector2(550, 350))
		and not Art.contains(clipped_area_mark, Vector2(450, 350)), "Paint inside selection clips new brushwork to the marquee")
	check(app.paint_actions.visible, "the brush offers a way to clear an active paint limit")
	var before_outside: int = selection_doc.layers[selection_doc.active].objects.size()
	selection_canvas.begin(local.call(Vector2(100, 100)), 0.55)
	selection_canvas.finish()
	check(selection_doc.layers[selection_doc.active].objects.size() == before_outside,
		"painting wholly outside a selection creates no invisible mark")
	app.set_paint_limit(false)
	selection_canvas.clear_selection()
	var selected_shapes: Array[String] = [first_mark, second_mark]
	selection_doc.select_objects(selected_shapes)
	app.set_tool("select")
	check(app.paint_inside_button.visible, "Select offers Paint inside beside its other contextual actions")
	app.paint_inside_button.pressed.emit()
	check(selection_canvas.clip_regions.size() == 2 and selection_canvas.tool == "brush",
		"two separated shapes make a combined paint limit with a gap")
	selection_canvas.begin(local.call(Vector2(160, 194)), 0.8)
	selection_canvas.update_stroke(local.call(Vector2(330, 238)), 0.8)
	selection_canvas.finish()
	var combined_mark: Dictionary = selection_doc.layers[selection_doc.active].objects[-1]
	check(combined_mark.has("paint_mask") and Art.contains(combined_mark, Vector2(184, 200))
		and Art.contains(combined_mark, Vector2(275, 224)) and not Art.contains(combined_mark, Vector2(230, 212))
		and Document.validate(selection_doc.snapshot()).is_empty()
		and Art.svg(selection_doc, false).contains('clip-path="url(#mask'), "a combined paint limit clips each region on canvas and in SVG")
	app.set_paint_limit(false)
	app.create_document(false)
	selection_canvas.fit()
	selection_doc.add({"kind": "rect", "pos": [150, 150], "extent": [40, 40], "color": "#276251", "opacity": 1.0})
	first_mark = selection_doc.selection
	app.add_document_layer()
	selection_doc.add({"kind": "ellipse", "pos": [235, 180], "extent": [40, 40], "color": "#f1d094", "opacity": 1.0})
	second_mark = selection_doc.selection
	selection_doc.commit()
	selected_shapes = [first_mark, second_mark]
	selection_doc.select_objects(selected_shapes)
	app.set_tool("select")
	check(app.group_artwork_button.visible, "Group appears for separate vector objects")
	var group_history: int = selection_doc.history.size()
	app.group_artwork_button.pressed.emit()
	var group_id: String = selection_doc.find_object(first_mark).get("artwork_group", "")
	check(not group_id.is_empty() and selection_doc.find_object(second_mark).get("artwork_group") == group_id
		and not app.group_artwork_button.visible and app.ungroup_artwork_button.visible
		and selection_doc.history.size() == group_history + 1, "grouping vectors keeps both on their original layers in one undo step")
	selection_canvas.clear_selection()
	selection_canvas.touch_paints = false
	var grouped_center := Art.v(selection_doc.find_object(first_mark).pos) + Vector2(10, 10)
	touch_press(selection_canvas, 18, local.call(grouped_center))
	touch_release(selection_canvas, 18, local.call(grouped_center))
	check(selection_doc.area_selection == selected_shapes, "a finger tap on one member selects the whole group")
	var first_position := Art.v(selection_doc.find_object(first_mark).pos)
	var second_position := Art.v(selection_doc.find_object(second_mark).pos)
	var move_group_by := Vector2(28, 24)
	var group_gap: Vector2 = selection_canvas.items_bounds(selection_doc.selected_items()).get_center()
	touch_press(selection_canvas, 18, local.call(group_gap))
	touch_move(selection_canvas, 18, local.call(group_gap + move_group_by))
	touch_release(selection_canvas, 18, local.call(group_gap + move_group_by))
	check(Art.v(selection_doc.find_object(first_mark).pos).is_equal_approx(first_position + move_group_by)
		and Art.v(selection_doc.find_object(second_mark).pos).is_equal_approx(second_position + move_group_by),
		"dragging the group moves all its members by the same offset")
	var group_bounds: Rect2 = selection_canvas.items_bounds(selection_doc.selected_items())
	var relative_before := Art.v(selection_doc.find_object(second_mark).pos) - Art.v(selection_doc.find_object(first_mark).pos)
	var resize_history: int = selection_doc.history.size()
	touch_press(selection_canvas, 18, local.call(group_bounds.end))
	touch_move(selection_canvas, 18, local.call(group_bounds.end + group_bounds.size * 0.5))
	touch_release(selection_canvas, 18, local.call(group_bounds.end + group_bounds.size * 0.5))
	var relative_after := Art.v(selection_doc.find_object(second_mark).pos) - Art.v(selection_doc.find_object(first_mark).pos)
	check(is_equal_approx(selection_doc.find_object(first_mark).scale, 1.5)
		and is_equal_approx(selection_doc.find_object(second_mark).scale, 1.5)
		and relative_after.is_equal_approx(relative_before * 1.5)
		and selection_doc.history.size() == resize_history + 1, "dragging the group corner scales both vectors and their spacing uniformly")
	selection_doc.undo()
	check(selection_doc.find_object(first_mark).scale == 1.0 and selection_doc.find_object(second_mark).get("artwork_group") == group_id,
		"undo restores both sizes without breaking the artwork group")
	selection_doc.redo()
	var saved_group := Document.new()
	check(selection_doc.save_to("user://grouped.havu") == OK and saved_group.load_from("user://grouped.havu").is_empty(),
		"an artwork group saves and reopens as a valid project")
	var one_member: Array[String] = [second_mark]
	saved_group.select_artwork(one_member)
	check(saved_group.area_selection == selected_shapes and is_equal_approx(saved_group.find_object(second_mark).scale, 1.5),
		"reopened artwork still selects and transforms as a group")
	saved_group.duplicate_selected()
	var duplicate_items := saved_group.selected_items()
	var duplicate_id: String = duplicate_items[0].object.get("artwork_group", "")
	check(duplicate_items.size() == 2 and not duplicate_id.is_empty() and duplicate_id != group_id
		and duplicate_items[1].object.get("artwork_group") == duplicate_id, "duplicating a group gives the copies independent membership")
	saved_group.layers[1].locked = true
	check(saved_group.select_artwork([first_mark]) and saved_group.selected_items().is_empty(),
		"a protected layer blocks editing the whole group")
	selection_doc.select_artwork(one_member)
	app.set_tool("select")
	app.ungroup_artwork_button.pressed.emit()
	check(not selection_doc.find_object(first_mark).has("artwork_group") and not selection_doc.find_object(second_mark).has("artwork_group"),
		"Ungroup keeps the resized artwork and removes the group membership")
	app.create_document(false)
	var merge_doc = app.document
	var fresh_rect := func(x: float, color: String) -> Dictionary:
		return {"kind": "rect", "pos": [x, 80.0], "extent": [50.0, 40.0], "color": color, "opacity": 1.0}
	var prior_vector: Dictionary = fresh_rect.call(80.0, "#22553f")
	merge_doc.append_vector_object(prior_vector)
	var previous_id: String = prior_vector.id
	app.layer_actions.id_pressed.emit(12)
	app.open_layer_actions()
	check(app.layer_actions.is_item_checked(app.layer_actions.get_item_index(12)), "Layers offers a per-vector-layer Merge touching toggle")
	app.layer_actions.hide()
	merge_doc.append_vector_object(fresh_rect.call(120.0, "#22553f"))
	check(merge_doc.layers[0].objects.size() == 2 and not merge_doc.find_object(previous_id).has("merge_batch"),
		"turning on Merge touching keeps older artwork separate even when a new mark overlaps it")
	var first_new_id: String = merge_doc.selection
	var merge_history: int = merge_doc.history.size()
	merge_doc.append_vector_object(fresh_rect.call(170.0, "#22553f"))
	var union: Dictionary = merge_doc.find_object(merge_doc.selection)
	check(merge_doc.layers[0].objects.size() == 2 and union.kind == "polygon"
		and Art.contains(union, Vector2(130, 95)) and Art.contains(union, Vector2(210, 95))
		and merge_doc.find_object(first_new_id).is_empty() and merge_doc.find_object(previous_id).kind == "rect"
		and merge_doc.history.size() == merge_history + 1, "only matching marks drawn while the toggle is on merge into one editable shape")
	merge_doc.undo()
	check(merge_doc.find_object(first_new_id).kind == "rect" and merge_doc.layers[0].objects.size() == 2,
		"undo removes the last draw and restores the earlier mark before union")
	merge_doc.redo()
	app.layer_actions.id_pressed.emit(12)
	merge_doc.append_vector_object(fresh_rect.call(215.0, "#22553f"))
	app.layer_actions.id_pressed.emit(12)
	merge_doc.append_vector_object(fresh_rect.call(230.0, "#22553f"))
	check(merge_doc.layers[0].objects.size() == 4 and merge_doc.layers[0].objects[-1].kind == "rect",
		"re-enabling Merge touching starts fresh and leaves the previous drawing session alone")
	var merge_roundtrip := Document.new()
	check(merge_doc.save_to("user://merge-touching.havu") == OK
		and merge_roundtrip.load_from("user://merge-touching.havu").is_empty()
		and merge_roundtrip.layers[0].merge_batch == merge_doc.layers[0].merge_batch,
		"the layer toggle and eligible marks survive saving and reopening")

	var ink_union := Document.new()
	ink_union.blank()
	ink_union.set_merge_touching(0, true)
	var first_ink := stroke()
	first_ink.points = [[50, 80, 1.0, "#226451"], [100, 80, 1.0, "#226451"]]
	var next_ink := stroke()
	next_ink.points = [[95, 80, 1.0, "#226451"], [160, 80, 1.0, "#226451"]]
	ink_union.append_vector_object(first_ink)
	ink_union.append_vector_object(next_ink)
	check(ink_union.layers[0].objects.size() == 1 and ink_union.layers[0].objects[0].kind == "polygon"
		and Art.contains(ink_union.layers[0].objects[0], Vector2(150, 80)), "solid ink joins as editable vector geometry")
	var box_doc := Document.new()
	box_doc.blank(700.0, 600.0)
	box_doc.add({"kind": "ellipse", "pos": [120.0, 100.0], "extent": [160.0, 160.0],
		"fill_enabled": false, "outline_color": "#226451", "outline_width": 4.0, "color": "#226451", "opacity": 1.0})
	var box_selected: String = box_doc.selection
	box_doc.add({"kind": "rect", "pos": [190.0, 170.0], "extent": [20.0, 20.0], "color": "#5a7d6d", "opacity": 1.0})
	var artwork_under_box: String = box_doc.selection
	box_doc.add({"kind": "rect", "pos": [470.0, 160.0], "extent": [40.0, 40.0], "color": "#302938", "opacity": 1.0})
	var outside_box: String = box_doc.selection
	var box_canvas = load("res://scripts/canvas.gd").new()
	box_canvas.document = box_doc
	box_canvas.size = Vector2(740, 650)
	box_canvas.tool = "select"
	root.add_child(box_canvas)
	box_canvas.fit()
	var at_box := func(point: Vector2) -> Vector2: return box_canvas.origin + point * box_canvas.zoom
	box_doc.selection = box_selected
	var box_move_start := Vector2(200, 180)
	var box_move_end := Vector2(230, 205)
	touch_press(box_canvas, 19, at_box.call(box_move_start))
	touch_move(box_canvas, 19, at_box.call(box_move_end))
	touch_release(box_canvas, 19, at_box.call(box_move_end))
	check(box_doc.selection == box_selected and Art.v(box_doc.find_object(box_selected).pos).is_equal_approx(Vector2(150, 125))
		and Art.v(box_doc.find_object(artwork_under_box).pos).is_equal_approx(Vector2(190, 170)),
		"a finger drag over artwork inside the selected box moves only the original selection")
	box_canvas.tool = "select_ellipse"
	box_canvas.begin(at_box.call(Vector2(155, 130)), 0.55)
	box_canvas.update_stroke(at_box.call(Vector2(165, 145)), 0.55)
	box_canvas.finish()
	check(Art.v(box_doc.find_object(box_selected).pos).is_equal_approx(Vector2(160, 140)) and not box_canvas.marquee_active,
		"a single selection box takes precedence over starting a new marquee")
	var box_handle := Art.bounds(box_doc.find_object(box_selected)).end
	touch_press(box_canvas, 19, at_box.call(box_handle))
	touch_move(box_canvas, 19, at_box.call(box_handle + Vector2(30, 30)))
	touch_release(box_canvas, 19, at_box.call(box_handle + Vector2(30, 30)))
	check(box_doc.find_object(box_selected).scale > 1.0 and Art.v(box_doc.find_object(box_selected).pos).is_equal_approx(Vector2(160, 140)),
		"the bottom-right corner still resizes the selected object")
	box_canvas.tool = "select"
	touch_press(box_canvas, 19, at_box.call(Vector2(485, 175)))
	touch_release(box_canvas, 19, at_box.call(Vector2(485, 175)))
	check(box_doc.selection == outside_box, "tapping outside the selection box can select new artwork")
	box_canvas.free()

	var heart_ink := func(coordinates: Array) -> Dictionary:
		var mark := stroke()
		mark.size = 10.0
		mark.points.clear()
		for position in coordinates:
			mark.points.append([position[0], position[1], 1.0, mark.color])
		return mark
	var left_heart: Dictionary = heart_ink.call([[100, 60], [85, 45], [65, 44], [48, 57], [45, 78], [52, 100], [70, 126], [100, 160]])
	var right_heart: Dictionary = heart_ink.call([[100, 60], [115, 45], [135, 44], [152, 57], [155, 78], [148, 100], [130, 126], [111, 160]])
	var heart_doc := Document.new()
	heart_doc.blank()
	heart_doc.set_merge_touching(0, true)
	heart_doc.append_vector_object(left_heart)
	heart_doc.append_vector_object(right_heart)
	var heart: Dictionary = heart_doc.layers[0].objects[-1]
	var heart_center := Vector2(100, 90)
	check(heart_doc.layers[0].objects.size() == 1 and heart.get("compound", false)
		and Art.contains(heart, Vector2(105.5, 160)) and not Art.contains(heart, heart_center),
		"heart halves join across a small gap as one editable outline with a clear center")
	var heart_vertices := Art.polygon(heart)
	var heart_triangles := Geometry2D.triangulate_polygon(heart_vertices)
	var render_hole := not heart_triangles.is_empty()
	for index in range(0, heart_triangles.size(), 3):
		var triangle := PackedVector2Array([heart_vertices[heart_triangles[index]],
			heart_vertices[heart_triangles[index + 1]], heart_vertices[heart_triangles[index + 2]]])
		render_hole = render_hole and not Geometry2D.is_point_in_polygon(heart_center, triangle)
	check(render_hole, "the merged heart triangulates without painting its center")
	var fill_region := preload("res://scripts/vector_fill.gd").find_region(heart_doc.layers[0].objects, heart_center)
	check(not fill_region.is_empty() and Geometry2D.is_point_in_polygon(heart_center, fill_region.vertices),
		"Vector Fill can color the center separately after Merge touching")
	var reopened_heart := Document.new()
	check(heart_doc.save_to("user://merged-heart.havu") == OK and reopened_heart.load_from("user://merged-heart.havu").is_empty()
		and Art.polygon(reopened_heart.layers[0].objects[0]) == heart_vertices
		and Art.svg(reopened_heart, false).contains(Art.points_string(heart_vertices)),
		"the joined outline and its hole survive project save and SVG export")
	reopened_heart.append_vector_object(heart_ink.call([[44, 90], [156, 90]]))
	var divided_heart: Dictionary = reopened_heart.layers[0].objects[0]
	check(reopened_heart.layers[0].objects.size() == 1 and Art.contains(divided_heart, heart_center)
		and not Art.contains(divided_heart, Vector2(100, 75)) and not Art.contains(divided_heart, Vector2(100, 110)),
		"a later crossing stroke can merge with an existing outline and retain both enclosed areas")
	var mask: Array = Art.vector_paint_mask(heart_doc.layers[0])
	var broad_dab := PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(200, 200), Vector2(0, 200)])
	var masked := Art.clipped_polygon({}, broad_dab, Art.prepare_paint_mask({"paint_mask": mask}))
	check(masked.size() == 1 and not Geometry2D.is_point_in_polygon(heart_center, masked[0]),
		"the transparent center stays outside alpha-locked paint")
	heart_doc.undo()
	check(not heart_doc.layers[0].objects[0].get("compound", false), "undo restores the original open heart half")
	right_heart.points[-1][0] = 114.0
	heart_doc.append_vector_object(right_heart)
	check(not heart_doc.layers[0].objects[0].get("compound", false),
		"a wider gap stays open even when the other tips overlap")
	var isolated_ink := Document.new()
	isolated_ink.blank()
	isolated_ink.set_merge_touching(0, true)
	isolated_ink.append_vector_object(heart_ink.call([[50, 80], [100, 80]]))
	isolated_ink.append_vector_object(heart_ink.call([[114, 80], [160, 80]]))
	check(isolated_ink.layers[0].objects.size() == 2, "nearby ink remains separate outside the contact tolerance")
	isolated_ink.undo()
	isolated_ink.append_vector_object(heart_ink.call([[111, 80], [160, 80]]))
	check(isolated_ink.layers[0].objects.size() == 1 and Art.contains(isolated_ink.layers[0].objects[0], Vector2(105.5, 80)),
		"two ink tips can merge across a small gap without another point of contact")
	var blocked_union := Document.new()
	blocked_union.blank()
	blocked_union.set_merge_touching(0, true)
	blocked_union.append_vector_object(fresh_rect.call(60.0, "#22553f"))
	blocked_union.append_vector_object(fresh_rect.call(70.0, "#ff4400"))
	blocked_union.append_vector_object(fresh_rect.call(105.0, "#22553f"))
	check(blocked_union.layers[0].objects.size() == 3 and Art.sample(blocked_union, Vector2(78, 95)) == Color("#ff4400"),
		"merging keeps a differently colored intervening object above the art it covers")
	blocked_union.blank(160.0, 160.0, false, "paint")
	check(not blocked_union.set_merge_touching(0, true), "paint layers cannot enable the vector union toggle")
	var open_line := {"kind": "path", "vertices": [[40, 60], [160, 80]], "pos": [25, 25], "scale": 1.5,
		"outline_color": "#000000", "outline_width": 10.0, "color": "#000000", "opacity": 1.0}
	var line_limit := Art.selection_contours(open_line)
	check(line_limit.size() == 1 and Geometry2D.is_point_in_polygon(Vector2(175, 130), line_limit[0]),
		"an open vector line supplies a transformed paintable contour")
	var round_stroke := stroke()
	round_stroke.brush = "mix"
	round_stroke.continuous_edges = true
	var joined := Art.segments(round_stroke)
	check(joined.size() == 2 and joined[0].polygon[1].is_equal_approx(joined[1].polygon[0]),
		"round mixer brush segments meet at a shared edge")
	var tools_panel = app.panels.Tools
	tools_panel.dock = "left"
	check(tools_panel.get_theme_stylebox("panel").get_corner_radius(CORNER_TOP_LEFT) == 0, "docked panels use square corners")
	tools_panel.dock = ""
	check(tools_panel.get_theme_stylebox("panel").get_corner_radius(CORNER_TOP_LEFT) > 0, "undocking restores rounded corners")

	var node_doc := Document.new()
	node_doc.blank(1000.0, 1000.0)
	var node_stroke := stroke()
	node_stroke.points = []
	for i in 121: node_stroke.points.append([100.0 + i * 5.0, 300.0, 0.5, "#226451"])
	node_doc.add(node_stroke)
	node_doc.selection = ""
	var node_canvas = load("res://scripts/canvas.gd").new()
	node_canvas.size = Vector2(1000, 1000)
	node_canvas.document = node_doc
	root.add_child(node_canvas)
	node_canvas.zoom = 1.0
	node_canvas.origin = Vector2.ZERO
	node_canvas.tool = "nodes"
	var grip_point := Vector2(402, 301)
	node_canvas.begin(grip_point, 0.55)
	node_canvas.update_stroke(grip_point + Vector2(0, 24), 0.55)
	check(node_canvas.node_index == 60 and Art.v(node_stroke.points[60]).is_equal_approx(Vector2(400, 324))
		and node_stroke.points[59][1] > 320.0 and node_stroke.points[61][1] > 320.0
		and node_stroke.points[0][1] == 300.0, "a node drags nearby samples without jumping to the finger")
	node_canvas.update_stroke(grip_point + Vector2(0, 375), 0.55)
	check(node_stroke.points[60][1] == 675.0 and node_stroke.points[0][1] == 300.0
		and node_stroke.points[-1][1] == 300.0 and node_stroke.points[72][1] == 300.0,
		"a long drag keeps default brush deformation local")
	node_canvas.update_stroke(grip_point + Vector2(0, 24), 0.55)
	node_canvas.finish()
	check(node_stroke.points[-1][1] == 300.0 and node_stroke.points[60][2] == 0.5
		and node_doc.history.size() == 1, "easing back restores distant samples and preserves pressure")
	node_doc.undo()
	check(node_doc.layers[0].objects[0].points[60][1] == 300.0, "one undo restores the complete node drag")
	var wide_stroke: Dictionary = node_doc.layers[0].objects[0]
	node_canvas.stroke_node_spread = 1.0
	node_canvas.begin(grip_point, 0.55)
	node_canvas.update_stroke(grip_point + Vector2(0, 24), 0.55)
	check(wide_stroke.points[72][1] > 320.0 and wide_stroke.points[0][1] > 300.0
		and wide_stroke.points[0][1] < wide_stroke.points[60][1], "higher Spread bends a wider area with a smooth falloff")
	node_canvas.finish()
	node_doc.undo()
	node_canvas.stroke_node_spread = 0.0
	node_canvas.begin(grip_point, 0.55)
	node_canvas.update_stroke(grip_point + Vector2(0, 24), 0.55)
	var focused_stroke: Dictionary = node_doc.layers[0].objects[0]
	check(focused_stroke.points[60][1] == 324.0 and focused_stroke.points[59][1] == 300.0
		and focused_stroke.points[61][1] == 300.0, "zero Spread moves only the active brush node")
	node_canvas.finish()
	node_doc.undo()
	var closed_stroke := stroke()
	closed_stroke.points = [[100, 100, 0.6, "#226451"], [130, 100, 0.6, "#226451"], [220, 150, 0.6, "#226451"],
		[120, 140, 0.6, "#226451"], [100, 100, 0.6, "#226451"]]
	node_doc.add(closed_stroke)
	node_doc.commit()
	node_canvas.begin_contact(0, Vector2(100, 100))
	node_canvas.move_contact(0, Vector2(100, 120), 0.55)
	node_canvas.end_contact(0, Vector2(100, 120), false)
	check(Art.v(closed_stroke.points[0]).is_equal_approx(Vector2(100, 120))
		and Art.v(closed_stroke.points[-1]).is_equal_approx(Vector2(100, 120)),
		"zero Spread preserves a closed stroke’s joined endpoints during touch drag")
	var dense_stroke: Dictionary = node_doc.layers[0].objects[0]
	node_doc.selection = dense_stroke.id
	node_canvas.set_add_node_mode(true)
	node_canvas.begin(Vector2(405, 300), 0.55)
	check(dense_stroke.points.size() == 121 and 61 in node_canvas.editable_nodes(dense_stroke)
		and dense_stroke.get("node_anchors") == [61], "an existing hidden brush sample can be promoted to a visible node")
	node_canvas.set_add_node_mode(true)
	node_canvas.begin(Vector2(402.5, 300), 0.55)
	check(dense_stroke.points.size() == 122 and Art.v(dense_stroke.points[61]).is_equal_approx(Vector2(402.5, 300))
		and dense_stroke.points[61][2] == 0.5 and dense_stroke.points[61][3] == "#226451"
		and dense_stroke.get("node_anchors") == [61, 62],
		"inserting between brush samples preserves pressure and color and shifts existing anchors")

	node_canvas.free()

	var text_fields: Array[Control] = [app.title_edit, app.brush_search, app.color_hex, app.text_edit, app.font_size.get_line_edit()]
	check(text_fields.all(func(field): return field.gui_input.is_connected(app.text_entry.field_input.bind(field))),
		"project, search, color, typography and spin box inputs share the tablet text entry handler")
	app.text_entry.apply_value(app.title_edit, "Menu for Sini")
	check(app.document.title == "Menu for Sini", "accepted tablet text commits the project title")
	app.text_entry.apply_value(app.color_hex, "#5A7D6D")
	check(app.canvas.color.to_html(false) == "5a7d6d", "accepted tablet text applies the hex color")
	app.text_entry.apply_value(app.font_size.get_line_edit(), "72")
	check(is_equal_approx(app.font_size.value, 72.0), "accepted tablet text applies numeric spin box input")
	app.text_entry.apply_value(app.text_edit, "First line\nSecond line")
	check(app.text_edit.get_line_count() == 2, "tablet text entry preserves multiple lines")

	app.text_entry.use_tablet_keyboard = true
	tap_window_control(root, app.title_edit)
	await process_frame
	await process_frame
	var tablet_keyboard = app.text_entry.dialog
	check(tablet_keyboard != null and tablet_keyboard.visible and tablet_keyboard.title == "Illustration name",
		"a finger tap on the project name opens the built-in tablet keyboard")
	for key in ["⇧", "s", "⇧", "i", "n", "i"]:
		tap_window_control(tablet_keyboard, tablet_keyboard.key_buttons[key])
		await process_frame
	tap_window_control(tablet_keyboard, tablet_keyboard.get_ok_button())
	check(app.document.title == "Sini", "the built-in keyboard changes the project name without the system IME")

	app.panels.Typography.show()
	app.panels.Typography.move_to_front()
	await process_frame
	click_window_control(root, app.text_edit)
	await process_frame
	check(app.text_entry.dialog == null and app.text_edit.has_focus(),
		"an S Pen click focuses Typography without opening the onscreen keyboard")
	tap_window_control(root, app.text_edit)
	await process_frame
	await process_frame
	tablet_keyboard = app.text_entry.dialog
	check(tablet_keyboard != null and tablet_keyboard.visible and tablet_keyboard.multiline,
		"a finger tap opens the multiline tablet keyboard in Typography")
	tablet_keyboard.editor.select_all()
	for key in ["#+=", "ö", "New line", "ABC", "s"]: tablet_keyboard.press_key(key)
	tablet_keyboard.confirmed.emit()
	check(app.text_edit.text == "ö\ns" and app.canvas.text_content == "ö\ns",
		"the keyboard inserts accents and line breaks in typography")

	tap_window_control(root, app.font_size.get_line_edit())
	await process_frame
	await process_frame
	tablet_keyboard = app.text_entry.dialog
	check(tablet_keyboard != null and tablet_keyboard.numeric,
		"editable SpinBox values open the built-in numeric layout")
	tablet_keyboard.press_key("8")
	tablet_keyboard.press_key("4")
	tablet_keyboard.confirmed.emit()
	check(app.font_size.value == 84.0, "the numeric keyboard commits a Typography point size")

	app.show_fonts()
	await process_frame
	tap_window_control(app.fonts_dialog, app.font_search)
	await process_frame
	await process_frame
	tablet_keyboard = app.text_entry.dialog
	check(tablet_keyboard != null and tablet_keyboard.get_parent() == app.fonts_dialog,
		"search fields can use the tablet keyboard inside a popup")
	for key in ["s", "e", "r", "i", "f"]: tablet_keyboard.press_key(key)
	tablet_keyboard.confirmed.emit()
	check(app.font_search.text == "serif", "the keyboard applies a search query to its original dialog")
	app.fonts_dialog.hide()

	# The host cannot start Android's IME. Exercise the same dispatch and
	# completion callbacks that the native dialog uses.
	var native_requests: Array[Dictionary] = []
	var native_prompts: Array[Callable] = []
	app.text_entry.native_prompt = func(options: Dictionary, finish: Callable) -> bool:
		native_requests.append(options)
		native_prompts.append(finish)
		return true
	click_window_control(root, app.title_edit)
	await process_frame
	check(native_requests.is_empty(), "an S Pen click on the project name does not request the native keyboard")
	var ime_touch := InputEventScreenTouch.new()
	ime_touch.position = app.title_edit.get_global_rect().get_center()
	ime_touch.pressed = true
	root.push_input(ime_touch, true)
	await process_frame
	await process_frame
	check(native_requests.size() == 1 and native_requests[0].text == "Sini"
		and app.text_entry.dialog == null, "touch-down requests the platform editor even before touch release")
	ime_touch.pressed = false
	root.push_input(ime_touch.duplicate(), true)
	native_prompts[0].call(true, "Sini’s café", true)
	check(app.document.title == "Sini’s café", "the platform editor commits to the original field")

	app.show_new_canvas()
	await process_frame
	var old_width: String = app.new_width.text
	click_window_control(app.new_dialog, app.new_width)
	app.apply_canvas_preset(app.CANVAS_PRESETS.size())
	await process_frame
	check(native_requests.size() == 1 and not app.canvas_number_pad.visible,
		"pen clicks and choosing Custom size leave the numeric keyboard closed")
	tap_window_control(app.new_dialog, app.new_width)
	await process_frame
	check(native_requests.size() == 2 and native_requests[1].type == DisplayServer.KEYBOARD_TYPE_NUMBER
		and not app.canvas_number_pad.visible, "canvas dimensions request the native numeric keyboard")
	check(native_requests[1].integer_range == Vector2i(Document.MIN_CANVAS_SIZE, Document.MAX_CANVAS_SIZE),
		"the native editor receives the canvas limits")
	native_prompts[1].call(false, "", true)
	check(app.new_width.text == old_width, "canceling the native dimension editor preserves the width")
	app.new_width.pressed.emit()
	native_prompts[2].call(true, "720", true)
	check(app.new_width.text == "720", "applying a native width updates the canvas draft")
	app.new_height.pressed.emit()
	native_prompts[3].call(false, "", false)
	check(app.canvas_number_pad.visible and app.canvas_number_pad.title == "Height",
		"an unavailable native editor leaves the canvas keypad available")
	app.canvas_number_pad.hide()
	app.new_dialog.hide()

	print("RESULT: %d checks, %d failures" % [checks, failures])
	app.autosave_timer.stop()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)

func tap_window_control(window: Window, control: Control) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = control.get_global_rect().get_center()
	touch.pressed = true
	window.push_input(touch, true)
	touch.pressed = false
	window.push_input(touch.duplicate(), true)

func click_window_control(window: Window, control: Control) -> void:
	var hover := InputEventMouseMotion.new()
	hover.position = control.get_global_rect().get_center()
	if window != root:
		hover.position = control.get_screen_position() + control.size * 0.5
	root.push_input(hover, true)
	var click := InputEventMouseButton.new()
	click.position = hover.position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)
	click.pressed = false
	root.push_input(click.duplicate(), true)

func touch_press(canvas: Control, index: int, point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = true
	event.position = point
	canvas._gui_input(event)

func touch_move(canvas: Control, index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = canvas.get_global_transform_with_canvas() * point
	canvas._input(event)

func touch_release(canvas: Control, index: int, point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = canvas.get_global_transform_with_canvas() * point
	canvas._input(event)
