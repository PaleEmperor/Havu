extends RefCounted
## Godot's transparent 2D viewport returns premultiplied RGB. PNG needs straight RGB.
static func straighten_alpha(image: Image) -> void:
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	for offset in range(0, bytes.size(), 4):
		var alpha: int = bytes[offset + 3]
		if alpha == 0 or alpha == 255: continue
		var restore := 255.0 / alpha
		bytes[offset] = mini(255, roundi(bytes[offset] * restore))
		bytes[offset + 1] = mini(255, roundi(bytes[offset + 1] * restore))
		bytes[offset + 2] = mini(255, roundi(bytes[offset + 2] * restore))
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes)
