

shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D atlas0 : filter_nearest, repeat_disable;
uniform sampler2D atlas1 : filter_nearest, repeat_disable;
uniform sampler2D atlas2 : filter_nearest, repeat_disable;
uniform sampler2D atlas3 : filter_nearest, repeat_disable;
uniform sampler2D atlas4 : filter_nearest, repeat_disable;
uniform sampler2D atlas5 : filter_nearest, repeat_disable;
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


varying flat int atlas_page;


int byte_at(float value) {
	return int(floor(value * 255.0 + 0.5));
}

void vertex() {
	int frame = byte_at(INSTANCE_CUSTOM.r) + 256 * byte_at(INSTANCE_CUSTOM.g);
	int table_width = textureSize(frame_table, 0).x;
	ivec2 cell = ivec2(frame % table_width, (frame / table_width) * 2);
	vec4 position = texelFetch(frame_table, cell, 0);
	vec4 info = texelFetch(frame_table, cell + ivec2(0, 1), 0);
	int x = byte_at(position.r) + 256 * byte_at(position.g);
	int y = byte_at(position.b) + 256 * byte_at(position.a);
	int width = byte_at(info.r);
	int height = byte_at(info.g);


	highp vec2 atlas_size = vec2(textureSize(atlas0, 0));
	atlas_uv0 = vec2(float(x), float(y)) / atlas_size;
	atlas_uv_size = vec2(float(width), float(height)) / atlas_size;

	player_row = float(byte_at(INSTANCE_CUSTOM.b) - 1);
	atlas_page = byte_at(info.b);

	VERTEX *= vec2(float(width), float(height));
}

void fragment() {
	highp vec2 uv = atlas_uv0 + UV * atlas_uv_size;


	highp float raw;
	if (atlas_page == 0) {
		raw = texture(atlas0, uv).r;
	} else if (atlas_page == 1) {
		raw = texture(atlas1, uv).r;
	} else if (atlas_page == 2) {
		raw = texture(atlas2, uv).r;
	} else if (atlas_page == 3) {
		raw = texture(atlas3, uv).r;
	} else if (atlas_page == 4) {
		raw = texture(atlas4, uv).r;
	} else {
		raw = texture(atlas5, uv).r;
	}
	highp float idx = floor(raw * 255.0 + 0.5);
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
