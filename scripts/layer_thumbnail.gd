extends Control
## A small, bounded preview of the layer on the page.
const Art = preload("res://scripts/artwork.gd")
const Raster = preload("res://scripts/raster_asset.gd")
const MAX_OBJECTS := 24
const STROKE_SAMPLES := 24

var objects: Array
var has_artwork := false
var page_size := Vector2.ONE
var layer_opacity := 1.0
var artwork := Node2D.new()

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	artwork.draw.connect(draw_artwork)
	add_child(artwork)
	resized.connect(func():
		queue_redraw()
		artwork.queue_redraw())
	artwork.hide()
	artwork.visibility_changed.connect(artwork.queue_redraw)

func update_content(layer: Dictionary, dimensions: Vector2) -> void:
	objects = layer.objects
	page_size = dimensions
	layer_opacity = layer.get("opacity", 1.0)
	var next_has_artwork := not objects.is_empty()
	if next_has_artwork != has_artwork:
		has_artwork = next_has_artwork
		queue_redraw()
	if artwork.is_visible_in_tree(): artwork.queue_redraw()

func set_artwork_visible(value: bool) -> void:
	artwork.visible = value

func _draw() -> void:
	var base := Color("#595959") if has_artwork else Color("#252525")
	var tile := Color("#666666") if has_artwork else Color("#303030")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for y in range(0, int(size.y), 6):
		for x in range(0, int(size.x), 6):
			if (x / 6 + y / 6) % 2 == 0:
				draw_rect(Rect2(x, y, 6, 6), tile)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("#4a4a4a"), false, 1)

func draw_artwork() -> void:
	if objects.is_empty() or layer_opacity <= 0: return
	var zoom := minf((size.x - 4) / page_size.x, (size.y - 4) / page_size.y)
	var origin := (size - page_size * zoom) * 0.5
	var first := maxi(0, objects.size() - MAX_OBJECTS)
	for index in range(first, objects.size()):
		var object: Dictionary = objects[index]
		var start := origin + Art.v(object.pos) * zoom
		var scale := float(object.scale) * zoom
		var color := Color(object.color)
		color.a *= float(object.opacity) * layer_opacity
		match object.kind:
			"rect", "ellipse", "polygon", "path":
				var miniature := object.duplicate()
				miniature.opacity = float(object.opacity) * layer_opacity
				miniature.erase("clip")
				if object.has("vertices") and object.vertices.size() > 64 and not object.get("compound", false):
					miniature.vertices = []
					var step := ceili(object.vertices.size() / 64.0)
					for vertex in range(0, object.vertices.size() - 1, step):
						miniature.vertices.append(object.vertices[vertex])
					miniature.vertices.append(object.vertices[-1])
				artwork.draw_set_transform(start, 0, Vector2.ONE * scale)
				Art.draw_shape(artwork, miniature)
				artwork.draw_set_transform(Vector2.ZERO)
			"stroke":
				draw_stroke(object, start, scale, color)
			"text":
				var font := Art.Fonts.font_for(object.font)
				var font_size := clampi(roundi(float(object.font_size) * scale), 2, 32)
				var lines: PackedStringArray = object.text.split("\n", true, 6)
				for line in lines.size():
					artwork.draw_string(font, start + Vector2(0, line * font_size * 1.35), lines[line].left(45),
						HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			"image":
				var texture := Raster.texture(object)
				if texture: artwork.draw_texture_rect(texture, Rect2(start, Art.v(object.extent) * scale), false, color)

func draw_stroke(object: Dictionary, origin: Vector2, scale: float, color: Color) -> void:
	var points := PackedVector2Array()
	var count: int = object.points.size()
	var step := maxi(1, ceili(float(count) / STROKE_SAMPLES))
	for index in range(0, count, step): points.append(origin + Art.v(object.points[index]) * scale)
	var end := origin + Art.v(object.points[-1]) * scale
	if points[-1] != end: points.append(end)
	var width := maxf(0.65, float(object.size) * scale * 0.55)
	if points.size() == 1: artwork.draw_circle(end, width * 0.5, color)
	else: artwork.draw_polyline(points, color, width, true)
