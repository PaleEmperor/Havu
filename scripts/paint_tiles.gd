extends RefCounted
## Paint a stroke into sparse, fixed-size image tiles. Existing tile images
## are copied on first write so history and duplicate layers stay independent.
const Art = preload("res://scripts/artwork.gd")
const Raster = preload("res://scripts/raster_asset.gd")
const TILE_SIZE := 128
const MAX_STAGED_TILES := 160
static var raster: Variant
static var raster_checked := false

var tiles := {}
var changed := {}
var page_size: Vector2i
var erasing: bool
var alpha_locked: bool
var scanline := Image.create_empty(TILE_SIZE, 1, false, Image.FORMAT_RGBA8)
var first_crossings := PackedFloat64Array()
var second_crossings := PackedFloat64Array()
var staged_samples := 0
var pending_dabs: Array = []
var next_dab := 0
var native_stroke := 0
var seeded_tiles := {}

func apply(layer: Dictionary, page: Vector2i, stroke: Dictionary, erase: bool) -> Dictionary:
	prepare_layer(layer, page)
	erasing = erase
	if erasing and alpha_locked: return {}
	for footprint in Art.paint_footprints(stroke):
		paint_polygon(footprint.polygon, footprint.color)
	return encode_result(layer)

func begin_android_stage() -> void:
	if not raster_checked:
		raster_checked = true
		if Engine.has_singleton("JavaClassWrapper"):
			raster = Engine.get_singleton("JavaClassWrapper").wrap("studio.havu.android.HavuPaintRaster")
	if raster == null: return
	native_stroke = raster.begin()

func cancel_stage() -> void:
	if native_stroke > 0: raster.discard(native_stroke)
	native_stroke = 0

func submit_android(stroke: Dictionary, count: int) -> bool:
	if count <= staged_samples: return true
	var footprints := Art.paint_footprints(stroke, staged_samples, count)
	if footprints.size() > 1024: return false
	var payload := PackedByteArray()
	var touched := {}
	var page := Rect2i(Vector2i.ZERO, page_size)
	for dab in footprints:
		var points: PackedVector2Array = dab.polygon
		if points.size() > 64: return false
		var bounds := Art.polygon_bounds(points)
		var start := Vector2i(bounds.position.floor())
		var stop := Vector2i(bounds.end.ceil())
		var visible := Rect2i(start, stop - start).intersection(page)
		if not visible.has_area(): continue
		var origin := tile_origin(visible.position)
		for y in range(origin.y, visible.end.y, TILE_SIZE):
			for x in range(origin.x, visible.end.x, TILE_SIZE):
				touched[Vector2i(x, y)] = true
		scanline.fill(dab.color)
		var offset := payload.size()
		payload.resize(offset + 24 + points.size() * 8)
		payload.encode_float(offset, bounds.position.x)
		payload.encode_float(offset + 4, bounds.position.y)
		payload.encode_float(offset + 8, bounds.end.x)
		payload.encode_float(offset + 12, bounds.end.y)
		payload.encode_u32(offset + 16, scanline.get_data().decode_u32(0))
		payload.encode_s32(offset + 20, points.size())
		offset += 24
		for point in points:
			payload.encode_float(offset, point.x)
			payload.encode_float(offset + 4, point.y)
			offset += 8
	var seeds := PackedByteArray()
	for origin: Vector2i in touched:
		var extent := (page_size - origin).min(Vector2i.ONE * TILE_SIZE)
		var data := PackedByteArray()
		if not seeded_tiles.has(origin):
			seeded_tiles[origin] = true
			if seeded_tiles.size() > MAX_STAGED_TILES: return false
			var image := writable_tile(origin)
			if not image: return false
			data = image.get_data()
		var offset := seeds.size()
		seeds.resize(offset + 20)
		seeds.encode_s32(offset, origin.x)
		seeds.encode_s32(offset + 4, origin.y)
		seeds.encode_s32(offset + 8, extent.x)
		seeds.encode_s32(offset + 12, extent.y)
		seeds.encode_s32(offset + 16, data.size())
		seeds.append_array(data)
	# Godot exposes this Java boolean as an integer on Android.
	if not seeds.is_empty() and not bool(raster.submit(native_stroke, payload, seeds)): return false
	staged_samples = count
	return true

func collect_android() -> bool:
	var output: Variant = raster.finish(native_stroke)
	native_stroke = 0
	if not output is PackedByteArray or (output.is_empty() and not seeded_tiles.is_empty()): return false
	var offset := 0
	while offset < output.size():
		if offset + 16 > output.size(): return false
		var origin := Vector2i(output.decode_s32(offset), output.decode_s32(offset + 4))
		var extent := Vector2i(output.decode_s32(offset + 8), output.decode_s32(offset + 12))
		var tile: Image = changed.get(origin)
		if not tile or tile.get_size() != extent: return false
		var length := extent.x * extent.y * 4
		offset += 16
		if offset + length > output.size(): return false
		tile.set_data(extent.x, extent.y, false, Image.FORMAT_RGBA8, output.slice(offset, offset+length))
		offset += length
	return true

func stage_stroke(stroke: Dictionary, budget_usec: int) -> void:
	# The join on a wet ribbon depends on the following sample.
	var sample_count: int = stroke.points.size()
	if budget_usec >= 0 and stroke.get("continuous_edges", false): sample_count -= 1
	if native_stroke > 0:
		if submit_android(stroke, sample_count):
			if budget_usec >= 0 or collect_android(): return
		cancel_stage()
		changed.clear()
		staged_samples = 0

	var deadline := Time.get_ticks_usec() + budget_usec
	while staged_samples < sample_count or not pending_dabs.is_empty():
		if pending_dabs.is_empty():
			var next := sample_count if budget_usec < 0 else mini(sample_count, staged_samples + 3)
			pending_dabs = Art.paint_footprints(stroke, staged_samples, next)
			staged_samples = next
		while next_dab < pending_dabs.size():
			var dab: Dictionary = pending_dabs[next_dab]
			paint_polygon(dab.polygon, dab.color)
			next_dab += 1
			if budget_usec >= 0 and Time.get_ticks_usec() >= deadline: return
		pending_dabs.clear()
		next_dab = 0
		if budget_usec >= 0 and Time.get_ticks_usec() >= deadline: break

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
	if first_y >= stop_y: return
	var row_count := stop_y - first_y
	first_crossings.resize(row_count)
	second_crossings.resize(row_count)
	first_crossings.fill(INF)
	second_crossings.fill(INF)
	var extra_crossings := {}
	var previous := polygon[-1]
	# Visit each edge only on rows that cross it. The same half-pixel rule
	# governs horizontal edges and coincident vertices as in span filling.
	for point in polygon:
		var from_y := maxi(first_y, ceili(minf(previous.y, point.y) - 0.5))
		var to_y := mini(stop_y, ceili(maxf(previous.y, point.y) - 0.5))
		for y in range(from_y, to_y):
			var row := y - first_y
			var crossing := lerpf(previous.x, point.x, (float(y) + 0.5 - previous.y) / (point.y - previous.y))
			if first_crossings[row] == INF: first_crossings[row] = crossing
			elif second_crossings[row] == INF: second_crossings[row] = crossing
			elif extra_crossings.has(row): extra_crossings[row].append(crossing)
			else: extra_crossings[row] = [first_crossings[row], second_crossings[row], crossing]
		previous = point
	if not erasing and not alpha_locked and color.a < 1.0: scanline.fill(color)
	for row in row_count:
		if second_crossings[row] == INF: continue
		var y := first_y + row
		if extra_crossings.has(row):
			var crossings: Array = extra_crossings[row]
			crossings.sort()
			for index in range(0, crossings.size() - 1, 2):
				paint_span(y, maxi(0, ceili(crossings[index] - 0.5)),
					mini(page_size.x, ceili(crossings[index + 1] - 0.5)), color)
		else:
			var left := minf(first_crossings[row], second_crossings[row])
			var right := maxf(first_crossings[row], second_crossings[row])
			paint_span(y, maxi(0, ceili(left - 0.5)), mini(page_size.x, ceili(right - 0.5)), color)

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
