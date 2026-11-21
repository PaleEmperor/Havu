shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform bool filter_overview = false;

varying float opacity;

void vertex() {
	opacity = COLOR.a;
}

void fragment() {
	vec4 sample_color = texture(TEXTURE, UV);
	if (filter_overview) {
		// Average the premultiplied colors across the display pixel.
		vec2 dx = dFdx(UV) * 0.25;
		vec2 dy = dFdy(UV) * 0.25;
		sample_color = 0.25 * (
			texture(TEXTURE, UV - dx - dy) +
			texture(TEXTURE, UV + dx - dy) +
			texture(TEXTURE, UV - dx + dy) +
			texture(TEXTURE, UV + dx + dy)
		);
	}
	COLOR = sample_color * opacity;
}
