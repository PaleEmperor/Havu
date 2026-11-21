shader_type canvas_item;
render_mode unshaded;

void vertex() {
	// The rim carries its outward direction in UV. Keep its width in
	// framebuffer pixels even when the artwork transform changes.
	if (UV.x > 8.0 && UV.y > 8.0) {
		vec2 direction = UV - vec2(16.0);
		mat4 local_to_canvas = CANVAS_MATRIX * MODEL_MATRIX;
		float pixels_per_unit = length(local_to_canvas[0].xy);
		VERTEX += direction * (0.85 / max(pixels_per_unit, 0.00001));
	}
}
