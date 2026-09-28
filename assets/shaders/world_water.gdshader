shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// WATER-01 (owner 27 Sep: living water): rivers flow - ripples run downstream (faster on steep
// stretches), foam gathers along the banks and over rapids; the lake and the sea ripple and swell.
// No textures: two layers of value noise make the ripples, so it stays cheap on a phone.
// River mesh: UV.x across (0..1), UV.y along the flow in metres; UV2.x width in metres, UV2.y the
// stretch's steepness (0 calm .. 1 rapids). Still water (lake, sea): world coordinates.
uniform bool river = true;
uniform vec3 shallow_colour : source_color = vec3(0.24, 0.42, 0.44);
uniform vec3 deep_colour : source_color = vec3(0.07, 0.18, 0.24);
uniform vec3 foam_colour : source_color = vec3(0.86, 0.9, 0.9);
uniform float flow_speed = 0.9;
uniform float ripple_metres = 2.2;
uniform float wetness_gloss = 0.06;
// SHORE-SOFT-01 (owner 28 Sep: "the river banks are triangular"): where the water plane cuts the 5 m
// ground triangles its edge ran in straight saw teeth. Now the water thins out over the last
// shore_fade metres of water in front of the ground (depth buffer) and a thin foam line follows the
// wet edge, so the shore reads as a soft line, not the triangles.
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float shore_fade = 0.9;
uniform float shore_foam = 0.45;

varying vec3 world_pos;

float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// Gradient of the noise (finite differences), for a ripple normal.
vec2 slope(vec2 p) {
	float e = 0.08;
	return vec2(noise(p + vec2(e, 0.0)) - noise(p - vec2(e, 0.0)), noise(p + vec2(0.0, e)) - noise(p - vec2(0.0, e))) / (2.0 * e);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p;
	vec2 drift1;
	vec2 drift2;
	float rapids = 0.0;
	float edge = 1.0;
	if (river) {
		rapids = clamp(UV2.y, 0.0, 1.0);
		float speed = flow_speed * (1.0 + 2.5 * rapids);
		p = vec2(UV.x * UV2.x, UV.y) / ripple_metres;
		drift1 = vec2(0.0, -TIME * speed / ripple_metres);
		drift2 = vec2(TIME * 0.05, -TIME * speed * 1.35 / ripple_metres);
		edge = min(UV.x, 1.0 - UV.x) * UV2.x;   // metres from the nearer side of the ribbon
	} else {
		p = world_pos.xz / (ripple_metres * 2.5);
		drift1 = vec2(TIME * 0.06, TIME * 0.035);
		drift2 = vec2(-TIME * 0.045, TIME * 0.07);
	}
	vec2 g = slope(p + drift1) * 0.6 + slope(p * 2.3 + drift2) * 0.4;
	float strength = mix(0.35, 0.9, rapids);
	NORMAL_MAP = normalize(vec3(-g * strength, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// Lighter where the ribbon meets the bank (the bed is close there), deep in the middle.
	float shore = river ? smoothstep(4.5, 1.0, edge) : 0.0;
	vec3 colour = mix(deep_colour, shallow_colour, max(shore, 0.35 * fresnel));
	// Foam: in a band along the banks and over the rapids, broken by the moving noise.
	float churn = noise((p + drift1 * 1.6) * 3.1);
	float foam = river ? max(smoothstep(3.6, 3.0, edge) * 0.55, rapids * 0.8) * smoothstep(0.45, 0.8, churn) : 0.0;
	// Water in front of the ground behind it along the view ray (metres).
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float thickness = -behind.z / behind.w + VERTEX.z;
	float line = (1.0 - smoothstep(0.0, shore_foam, thickness)) * smoothstep(0.3, 0.7, noise(p * 4.0 + drift1 * 2.0) + 0.35);
	foam = max(foam, line * 0.8);
	ALBEDO = mix(colour, foam_colour, foam);
	ROUGHNESS = mix(wetness_gloss, 0.6, foam);
	SPECULAR = 0.55;
	ALPHA = mix(0.86, 1.0, foam) * smoothstep(0.0, shore_fade, thickness);
}
