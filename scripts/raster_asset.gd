extends RefCounted

const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_EDGE := 4096
const MAX_TOTAL_PIXELS := 40 * 1024 * 1024
static var cached: Dictionary = {}
static var cache_order: Array[String] = []
static var cached_pixels := 0

static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return {"error": "Could not open the image."}
	var length := file.get_length()
	if length <= 0: return {"error": "The image is empty or could not be read."}
	if length > MAX_FILE_BYTES: return {"error": "Choose an image smaller than 8 MB."}
	var bytes := file.get_buffer(length)
	var kind := format_of(bytes)
	if kind.is_empty(): return {"error": "Choose a PNG, JPEG, or WebP image."}
	var image := decode(bytes, kind)
	if not image: return {"error": "Image could not be read. The maximum size is 4096 × 4096 pixels."}
	var payload := Marshalls.raw_to_base64(bytes)
	var key := payload.sha256_text()
	remember(key, image)
	return {"image_data": payload, "image_format": kind, "image_key": key, "extent": [image.get_width(), image.get_height()]}

static func format_of(bytes: PackedByteArray) -> String:
	if bytes.size() < 12: return ""
	if bytes.slice(0, 8).hex_encode() == "89504e470d0a1a0a": return "png"
	if bytes[0] == 255 and bytes[1] == 216 and bytes[2] == 255: return "jpeg"
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP": return "webp"
	return ""

static func decode(bytes: PackedByteArray, kind: String) -> Image:
	if bytes.is_empty() or bytes.size() > MAX_FILE_BYTES or format_of(bytes) != kind: return null
	var declared := declared_size(bytes, kind)
	if declared.x < 1 or declared.y < 1 or declared.x > MAX_EDGE or declared.y > MAX_EDGE: return null
	var image := Image.new()
	var result := ERR_INVALID_DATA
	match kind:
		"png": result = image.load_png_from_buffer(bytes)
		"jpeg": result = image.load_jpg_from_buffer(bytes)
		"webp": result = image.load_webp_from_buffer(bytes)
	if result != OK or image.is_empty() or image.get_width() > MAX_EDGE or image.get_height() > MAX_EDGE: return null
	return image

static func declared_size(bytes: PackedByteArray, kind: String) -> Vector2i:
	if kind == "png":
		if bytes.size() < 24: return Vector2i.ZERO
		return Vector2i(
			(bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19],
			(bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23])
	if kind == "jpeg":
		return jpeg_size(bytes)
	return webp_size(bytes)

static func jpeg_size(bytes: PackedByteArray) -> Vector2i:
	var index := 2
	while index + 4 < bytes.size() and bytes[index] == 255:
		while index < bytes.size() and bytes[index] == 255: index += 1
		if index + 2 >= bytes.size(): break
		var marker := int(bytes[index])
		index += 1
		if marker == 0xda or marker == 0xd9: break
		var length := (bytes[index] << 8) | bytes[index + 1]
		if length < 2 or index + length > bytes.size(): break
		# Start-of-frame markers carry dimensions. DHT, JPG, and DAC do not.
		if marker >= 0xc0 and marker <= 0xcf and marker not in [0xc4, 0xc8, 0xcc]:
			if length < 8: break
			return Vector2i((bytes[index + 5] << 8) | bytes[index + 6],
				(bytes[index + 3] << 8) | bytes[index + 4])
		index += length
	return Vector2i.ZERO

static func webp_size(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 25: return Vector2i.ZERO
	var chunk := bytes.slice(12, 16).get_string_from_ascii()
	match chunk:
		"VP8X":
			if bytes.size() < 30: return Vector2i.ZERO
			return Vector2i(1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16),
				1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16))
		"VP8 ":
			if bytes.size() < 30: return Vector2i.ZERO
			return Vector2i((bytes[26] | (bytes[27] << 8)) & 0x3fff,
				(bytes[28] | (bytes[29] << 8)) & 0x3fff)
		"VP8L":
			var dimensions := bytes.decode_u32(21)
			return Vector2i((dimensions & 0x3fff) + 1, ((dimensions >> 14) & 0x3fff) + 1)
	return Vector2i.ZERO

static func remember(key: String, image: Image) -> Dictionary:
	if cached.has(key): return cached[key]
	var pixels := image.get_width() * image.get_height()
	while not cache_order.is_empty() and cached_pixels + pixels > MAX_TOTAL_PIXELS:
		var oldest: String = cache_order.pop_front()
		cached_pixels -= cached[oldest].pixels
		cached.erase(oldest)
	var entry := {"image": image, "texture": null, "pixels": pixels}
	cached[key] = entry
	cache_order.append(key)
	cached_pixels += pixels
	return entry

static func get_asset(object: Dictionary) -> Dictionary:
	var key: String = object.image_key
	if cached.has(key): return cached[key]
	var image := decode(Marshalls.base64_to_raw(object.image_data), object.image_format)
	return remember(key, image) if image else {}

static func encode_png(image: Image) -> Dictionary:
	var payload := Marshalls.raw_to_base64(image.save_png_to_buffer())
	var key := payload.sha256_text()
	remember(key, image)
	return {"image_data": payload, "image_key": key, "image_format": "png",
		"extent": [image.get_width(), image.get_height()]}

static func texture(object: Dictionary) -> Texture2D:
	var entry := get_asset(object)
	if entry.is_empty(): return null
	if entry.texture == null: entry.texture = ImageTexture.create_from_image(display_image(entry.image))
	return entry.texture

static func display_image(source: Image) -> Image:
	var filtered := source.duplicate()
	# The sampled texture is separate from the pixels used for editing and saving.
	if filtered.detect_alpha() != Image.ALPHA_NONE:
		if filtered.get_format() != Image.FORMAT_RGBA8: filtered.convert(Image.FORMAT_RGBA8)
		filtered.fix_alpha_edges()
	filtered.generate_mipmaps()
	return filtered

static func pixel_at(object: Dictionary, point: Vector2) -> Color:
	var entry := get_asset(object)
	if entry.is_empty(): return Color.TRANSPARENT
	var image: Image = entry.image
	var pixel := Vector2i(point.floor()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	return image.get_pixelv(pixel)
