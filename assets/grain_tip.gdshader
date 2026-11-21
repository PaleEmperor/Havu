shader_type canvas_item;
render_mode unshaded;

void vertex() {
	// Only the instanced grain mesh carries a phase marker.
	if (INSTANCE_CUSTOM.y > 0.5) {
		float variation = 0.7 + 0.3 * abs(sin(INSTANCE_CUSTOM.x + UV.x));
		vec2 direction = VERTEX;
		VERTEX *= variation;
		if (UV.y > 0.5) {
			mat4 to_canvas = CANVAS_MATRIX * MODEL_MATRIX;
			float pixels_per_unit = max(length(to_canvas[0].xy), 0.00001);
			VERTEX += direction * min(0.55 / pixels_per_unit, 0.4);
			COLOR.a = 0.0;
		}
	}
}
