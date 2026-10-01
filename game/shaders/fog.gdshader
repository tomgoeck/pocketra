

shader_type canvas_item;
uniform highp sampler2D vis : filter_linear, repeat_disable;

uniform highp float fog_alpha = 0.45;

void fragment() {
	highp float v = clamp(texture(vis, UV).r * 255.0, 0.0, 2.0);

	highp float shroud = mix(1.0, fog_alpha, clamp(v, 0.0, 1.0));
	highp float fog = mix(fog_alpha, 0.0, clamp(v - 1.0, 0.0, 1.0));
	highp float a = mix(shroud, fog, step(1.0, v));
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
