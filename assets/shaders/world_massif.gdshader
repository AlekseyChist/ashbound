shader_type spatial;
// WORLD-EDGES-01: the mountains beyond the map. Rock from a real scan projected from three sides
// (no UVs on the generated mesh), snow only high up and on gentler slopes; steep faces stay bare.
// The scene's height fog thins out upwards, which cut the snowy tops off from their feet (a range
// "floating" over the horizon); the range takes an even haze with distance instead.
render_mode diffuse_burley, fog_disabled;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_meters = 24.0;
uniform float snow_line = 330.0;
uniform float snow_fade = 60.0;
uniform vec3 rock_tint : source_color = vec3(0.72, 0.68, 0.62);
uniform vec3 snow_colour : source_color = vec3(0.86, 0.88, 0.9);
// The scene's depth fog (density and colour, set every frame), without its height part.
uniform vec3 fog_colour : source_color = vec3(0.62, 0.68, 0.7);
uniform float fog_density = 0.002;
// The scene also blends the sky into distant ground (aerial perspective); the range matches it with
// a stronger haze, or it stands out darker than the ridge in front of it.
uniform float haze_boost = 2.5;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy).rgb * w.x + texture(tex, p.xz).rgb * w.y + texture(tex, p.xy).rgb * w.z;
}

void fragment() {
	vec3 p = world_pos / rock_meters;
	vec3 rock = triplanar(rock_albedo, p, world_normal) * rock_tint;
	// Large-scale variation so the texture does not read as one tile.
	vec3 far_p = world_pos / (rock_meters * 7.0);
	rock *= mix(0.75, 1.15, triplanar(rock_albedo, far_p, world_normal).g);
	float flat_ground = smoothstep(0.55, 0.8, world_normal.y);
	float snow = smoothstep(snow_line - snow_fade, snow_line + snow_fade, world_pos.y) * flat_ground;
	float haze = 1.0 - exp(-fog_density * haze_boost * distance(world_pos, CAMERA_POSITION_WORLD));
	ALBEDO = mix(rock, snow_colour, snow) * (1.0 - haze);
	EMISSION = fog_colour * haze;
	ROUGHNESS = mix(0.92, 0.7, snow);
	NORMAL_MAP = triplanar(rock_normal, p, world_normal);
	NORMAL_MAP_DEPTH = mix(0.8, 0.2, snow);
}
