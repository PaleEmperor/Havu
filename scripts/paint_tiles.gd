extends RefCounted
## Paint a stroke into sparse, fixed-size image tiles. Existing tile images
## are copied on first write so history and duplicate layers stay independent.
const Art = preload("res://scripts/artwork.gd")
const Raster = preload("res://scripts/raster_asset.gd")
const TILE_SIZE := 128

var tiles := {}
var changed := {}
var page_size: Vector2i
var erasing: bool
var alpha_locked: bool
var scanline := Image.create_empty(TILE_SIZE, 1, false, Image.FORMAT_RGBA8)

func apply(layer: Dictionary, page: Vector2i, stroke: Dictionary, erase: bool) -> Dictionary:
	prepare_layer(layer, page)
	erasing = erase
	if erasing and alpha_locked: return {}
	for footprint in Art.paint_footprints(stroke):
		paint_polygon(footprint.polygon, footprint.color)
	return encode_result(layer)

func prepare_layer(layer: Dictionary, page: Vector2i) -> void:
	page_size = page
	alpha_locked = layer.get("alpha_locked", false)
	for object in layer.objects:
		if object.get("paint_tile", false): tiles[Vector2i(Art.v(object.pos))] = object

func merge_layers(layers: Array[Dictionary]) -> Array:
	for layer in layers:
		var opacity: float = layer.get("opacity", 1.0)
		if opacity <= 0.0: continue
		for tile in layer.objects:
			var origin := Vector2i(Art.v(tile.pos))
			var asset := Raster.get_asset(tile)
			if asset.is_empty(): continue
			var source: Image = asset.image
			if opacity < 1.0:
				source = source.duplicate()
				source.convert(Image.FORMAT_RGBA8)
				var pixels := source.get_data()
				for index in range(3, pixels.size(), 4): pixels[index] = roundi(pixels[index] * opacity)
				source.set_data(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8, pixels)
			if not changed.has(origin):
				changed[origin] = source.duplicate()
				continue
			var target: Image = changed[origin]
			target.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	return encode_result({"objects": []}).get("objects", [])

static func resize_bounds(layer: Dictionary, page: Vector2i) -> Dictionary:
	var objects := []
	var canvas := Rect2i(Vector2i.ZERO, page)
	for tile in layer.objects:
		var origin := Vector2i(Art.v(tile.pos))
		if not canvas.has_point(origin): continue
		var target_size := Vector2i.ONE * TILE_SIZE
		target_size = target_size.min(page - origin)
		var source_size := Vector2i(Art.v(tile.extent))
		if target_size == source_size:
			objects.append(tile)
			continue
		var asset := Raster.get_asset(tile)
		if asset.is_empty(): return {"error": ERR_INVALID_DATA}
		var image := Image.create_empty(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
		var source: Image = asset.image
		if source.get_format() != Image.FORMAT_RGBA8:
			source = source.duplicate()
			source.convert(Image.FORMAT_RGBA8)
		image.blit_rect(source, Rect2i(Vector2i.ZERO, target_size.min(source_size)), Vector2i.ZERO)
		if image.is_invisible(): continue
		var resized: Dictionary = tile.duplicate()
		resized.merge(Raster.encode_png(image), true)
		objects.append(resized)
	return {"objects": objects}

static func artwork_bounds(layer: Dictionary) -> Dictionary:
	var bounds := Rect2i()
	for tile in layer.objects:
		var asset := Raster.get_asset(tile)
		if asset.is_empty(): return {"error": ERR_INVALID_DATA}
		var used: Rect2i = asset.image.get_used_rect()
		if not used.has_area(): continue
		used.position += Vector2i(Art.v(tile.pos))
		bounds = bounds.merge(used) if bounds.has_area() else used
	return {"bounds": bounds}

func transform_artwork(layer: Dictionary, page: Vector2i, source: Rect2i, factor: float, offset: Vector2) -> Dictionary:
	if not source.has_area(): return {"objects": []}
	page_size = page
	if factor == 1.0:
		# Retile with a pixel-aligned translation, without allocating a full image.
		var shift := Vector2i(offset.round())
		for tile in layer.objects:
			var asset := Raster.get_asset(tile)
			if asset.is_empty(): return {"error": ERR_INVALID_DATA}
			blit_transformed_image(asset.image, Vector2i(Art.v(tile.pos)) + shift)
	else:
		# Resize a single image per layer so interpolation crosses tile edges.
		# Refuse a dense allocation beyond the tablet memory budget.
		var begin := (Vector2(source.position) * factor + offset).round()
		var end := (Vector2(source.end) * factor + offset).round()
		var target := Vector2i((end - begin).max(Vector2.ONE))
		if source.get_area() + target.x * target.y > 8 * 1024 * 1024:
			return {"error": ERR_OUT_OF_MEMORY}
		var image := Image.create_empty(source.size.x, source.size.y, false, Image.FORMAT_RGBA8)
		for tile in layer.objects:
			var asset := Raster.get_asset(tile)
			if asset.is_empty(): return {"error": ERR_INVALID_DATA}
			var pixels: Image = rgba_image(asset.image)
			var tile_rect := Rect2i(Vector2i(Art.v(tile.pos)), pixels.get_size())
			var visible := tile_rect.intersection(source)
			if visible.has_area():
				image.blit_rect(pixels, Rect2i(visible.position - tile_rect.position, visible.size),
					visible.position - source.position)
		image.fix_alpha_edges()
		image.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
		blit_transformed_image(image, Vector2i(begin))
	return {"objects": encode_result({"objects": []}).get("objects", [])}

static func rgba_image(source: Image) -> Image:
	if source.get_format() == Image.FORMAT_RGBA8: return source
	var copy := source.duplicate()
	copy.convert(Image.FORMAT_RGBA8)
	return copy

func blit_transformed_image(source: Image, offset: Vector2i) -> void:
	var pixels := rgba_image(source)
	var used := pixels.get_used_rect()
	used.position += offset
	used = used.intersection(Rect2i(Vector2i.ZERO, page_size))
	if not used.has_area(): return
	var tile_start := tile_origin(used.position)
	for y in range(tile_start.y, used.end.y, TILE_SIZE):
		for x in range(tile_start.x, used.end.x, TILE_SIZE):
			var origin := Vector2i(x, y)
			var tile_size := (page_size - origin).min(Vector2i.ONE * TILE_SIZE)
			var region := Rect2i(origin, tile_size).intersection(used)
			if not changed.has(origin):
				changed[origin] = Image.create_empty(tile_size.x, tile_size.y, false, Image.FORMAT_RGBA8)
			changed[origin].blit_rect(pixels, Rect2i(region.position - offset, region.size), region.position - origin)

func fill_region(layer: Dictionary, page: Vector2i, seed: Vector2i, ink: Color) -> Dictionary:
	prepare_layer(layer, page)
	if not Rect2i(Vector2i.ZERO, page).has_point(seed) or ink.a <= 0.0: return {}
	var bands := {}
	for origin: Vector2i in tiles:
		var asset := Raster.get_asset(tiles[origin])
		if asset.is_empty(): continue
		if not bands.has(origin.y): bands[origin.y] = {}
		bands[origin.y][origin.x] = asset.image
	var seed_origin := tile_origin(seed)
	var seed_image: Image = bands.get(seed_origin.y, {}).get(seed_origin.x)
	var source := seed_image.get_pixelv(seed - seed_origin) if seed_image else Color.TRANSPARENT
	if (source.a == 0.0 and alpha_locked) or (source == ink and ink.a == 1.0): return {}
	for band in bands.values(): band.sort()
	var rows := {}
	rows[seed.y] = matching_spans(seed.y, source, bands)
	var pending: Array[Vector2i] = []
	for index in rows[seed.y].size():
		var span: Vector2i = rows[seed.y][index]
		if seed.x >= span.x and seed.x < span.y:
			pending.append(Vector2i(index, seed.y))
			break
	var visited := {}
	scanline.fill(ink)
	while not pending.is_empty():
		var next: Vector2i = pending.pop_back()
		if visited.has(next): continue
		visited[next] = true
		var span: Vector2i = rows[next.y][next.x]
		paint_span(next.y, span.x, span.y, ink)
		for y in [next.y - 1, next.y + 1]:
			if y < 0 or y >= page_size.y: continue
			if not rows.has(y): rows[y] = matching_spans(y, source, bands)
			for index in rows[y].size():
				var candidate: Vector2i = rows[y][index]
				if candidate.x >= span.y: break
				if candidate.y > span.x and not visited.has(Vector2i(index, y)):
					pending.append(Vector2i(index, y))
	return encode_result(layer)

func matching_spans(y: int, source: Color, bands: Dictionary) -> Array[Vector2i]:
	var band_y := (y / TILE_SIZE) * TILE_SIZE
	var band: Dictionary = bands.get(band_y, {})
	var spans: Array[Vector2i] = []
	var cursor := 0
	var clear := source.a == 0.0
	for origin_x: int in band:
		if clear and cursor < origin_x: append_span(spans, cursor, origin_x)
		var image: Image = band[origin_x]
		var start := -1
		for x in image.get_width():
			var pixel := image.get_pixel(x, y - band_y)
			if (clear and pixel.a == 0.0) or pixel == source:
				if start < 0: start = origin_x + x
			elif start >= 0:
				append_span(spans, start, origin_x + x)
				start = -1
		cursor = origin_x + image.get_width()
		if start >= 0: append_span(spans, start, cursor)
	if clear and cursor < page_size.x: append_span(spans, cursor, page_size.x)
	return spans

func append_span(spans: Array[Vector2i], start: int, stop: int) -> void:
	if not spans.is_empty() and spans[-1].y == start:
		spans[-1].y = stop
	else:
		spans.append(Vector2i(start, stop))

func tile_origin(point: Vector2i) -> Vector2i:
	return (point / TILE_SIZE) * TILE_SIZE

func encode_result(layer: Dictionary) -> Dictionary:
	var replacements := {}
	var additions := []
	for origin in changed:
		var image: Image = changed[origin]
		var old: Dictionary = tiles.get(origin, {})
		if image.is_invisible():
			if not old.is_empty(): replacements[old.id] = {}
			continue
		var encoded := Raster.encode_png(image)
		if not old.is_empty() and old.image_key == encoded.image_key: continue
		encoded.merge({"kind": "image", "paint_tile": true, "pos": [origin.x, origin.y],
			"scale": 1.0, "color": "#ffffff", "opacity": 1.0})
		if old.is_empty():
			additions.append(encoded)
		else:
			encoded.id = old.id
			replacements[old.id] = encoded
	if replacements.is_empty() and additions.is_empty(): return {}
	var objects := []
	for object in layer.objects:
		var replacement: Dictionary = replacements.get(object.id, object)
		if not replacement.is_empty(): objects.append(replacement)
	objects.append_array(additions)
	return {"objects": objects}

func paint_polygon(polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 3 or color.a <= 0.0: return
	var bounds := Art.polygon_bounds(polygon)
	var first_y := maxi(0, floori(bounds.position.y))
	var stop_y := mini(page_size.y, ceili(bounds.end.y))
	var crossings := PackedFloat32Array()
	scanline.fill(color)
	for y in range(first_y, stop_y):
		var row := float(y) + 0.5
		crossings.clear()
		var previous := polygon[-1]
		for point in polygon:
			if (previous.y > row) != (point.y > row):
				crossings.append(lerpf(previous.x, point.x, (row - previous.y) / (point.y - previous.y)))
			previous = point
		crossings.sort()
		for index in range(0, crossings.size() - 1, 2):
			var start := maxi(0, ceili(crossings[index] - 0.5))
			var stop := mini(page_size.x, ceili(crossings[index + 1] - 0.5))
			paint_span(y, start, stop, color)

func paint_span(y: int, start: int, stop: int, ink: Color) -> void:
	var x := start
	while x < stop:
		var origin := tile_origin(Vector2i(x, y))
		var end := mini(stop, origin.x + TILE_SIZE)
		var tile := writable_tile(origin)
		if tile:
			var local := Vector2i(x, y) - origin
			var rect := Rect2i(local, Vector2i(end - x, 1))
			if erasing or alpha_locked:
				for pixel_x in range(local.x, local.x + rect.size.x):
					var previous := tile.get_pixel(pixel_x, local.y)
					if previous.a == 0.0: continue
					var result := previous.lerp(ink, ink.a) if alpha_locked else previous
					result.a = previous.a if alpha_locked else previous.a * (1.0 - ink.a)
					tile.set_pixel(pixel_x, local.y, result)
			elif ink.a >= 1.0:
				tile.fill_rect(rect, ink)
			else:
				tile.blend_rect(scanline, Rect2i(Vector2i.ZERO, rect.size), local)
		x = end

func writable_tile(origin: Vector2i) -> Image:
	if changed.has(origin): return changed[origin]
	var previous: Dictionary = tiles.get(origin, {})
	var tile: Image
	if previous.is_empty():
		if erasing or alpha_locked: return null
		var dimensions := Vector2i(TILE_SIZE, TILE_SIZE).min(page_size - origin)
		tile = Image.create_empty(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	else:
		var asset := Raster.get_asset(previous)
		if asset.is_empty(): return null
		tile = asset.image.duplicate()
		tile.convert(Image.FORMAT_RGBA8)
	changed[origin] = tile
	return tile
