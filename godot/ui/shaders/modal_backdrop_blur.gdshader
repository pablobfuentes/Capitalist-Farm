shader_type canvas_item;

uniform sampler2D snap_texture : filter_linear, repeat_disable;
uniform float blur_strength : hint_range(0.0, 6.0) = 2.2;
uniform vec4 dim_color : source_color = vec4(0.08, 0.08, 0.1, 0.18);

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE * blur_strength;
	vec4 c = texture(snap_texture, UV) * 0.16;
	c += texture(snap_texture, UV + vec2(ps.x, 0.0)) * 0.12;
	c += texture(snap_texture, UV - vec2(ps.x, 0.0)) * 0.12;
	c += texture(snap_texture, UV + vec2(0.0, ps.y)) * 0.12;
	c += texture(snap_texture, UV - vec2(0.0, ps.y)) * 0.12;
	c += texture(snap_texture, UV + ps) * 0.09;
	c += texture(snap_texture, UV - ps) * 0.09;
	c += texture(snap_texture, UV + vec2(ps.x, -ps.y)) * 0.07;
	c += texture(snap_texture, UV + vec2(-ps.x, ps.y)) * 0.07;
	COLOR = vec4(mix(c.rgb, dim_color.rgb, dim_color.a), 1.0);
}
