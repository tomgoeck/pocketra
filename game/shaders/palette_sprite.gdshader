

shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform sampler2D palette : filter_nearest, repeat_disable;
uniform sampler2D frame_table : filter_nearest, repeat_disable;
uniform float palette_rows = 1.0;
uniform float shadow_alpha = 0.55;


uniform float water_base = 96.0;
uniform float water_range = 7.0;
uniform float water_phase = 0.0;


varying highp vec2 atlas_uv0;
varying highp vec2 atlas_uv_size;
varying flat highp float player_row;

void vertex() {
	int frame = int(INSTANCE_CUSTOM.x + 0.5);
	vec4 rect = texelFetch(frame_table, ivec2(frame, 0), 0);
	vec4 px = texelFetch(frame_table, ivec2(frame, 1), 0);
	atlas_uv0 = rect.xy;
	atlas_uv_size = rect.zw;
	player_row = INSTANCE_CUSTOM.y;

	VERTEX *= px.xy;
}

void fragment() {
	highp vec2 uv = atlas_uv0 + UV * atlas_uv_size;
	highp float idx = floor(texture(atlas, uv).r * 255.0 + 0.5);
	if (idx < 0.5) {
		discard;
	}


	if (player_row < -0.5 || (idx < 4.5 && idx > 3.5)) {
		COLOR = vec4(0.0, 0.0, 0.0, shadow_alpha);
	} else {

		highp float wo = idx - water_base;
		if (wo >= 0.0 && wo < water_range) {
			idx = water_base + mod(wo - water_phase, water_range);
		}
		highp vec2 puv = vec2((idx + 0.5) / 256.0, (player_row + 0.5) / palette_rows);
		COLOR = texture(palette, puv);
	}
}
