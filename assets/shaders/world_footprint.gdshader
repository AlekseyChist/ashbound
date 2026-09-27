shader_type spatial;
// SNOW-01 / SAND-01: a boot print pressed into snow or sand: a shaded hollow over the ground.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 shade : source_color = vec3(0.12, 0.1, 0.09);
uniform float now = 0.0;
uniform float lifetime = 60.0;
// When this print was made and how deep it is (snow deeper than sand).
instance uniform float made = -1000.0;
instance uniform float depth = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// A sole: a wider front, a narrower heel, a gap between them.
	float front = 1.0 - smoothstep(0.55, 0.85, length(vec2(p.x * 1.15, (p.y + 0.35) * 1.4)));
	float heel = 1.0 - smoothstep(0.45, 0.75, length(vec2(p.x * 1.3, (p.y - 0.55) * 1.9)));
	float sole = max(front, heel);
	float fade = 1.0 - smoothstep(lifetime * 0.6, lifetime, now - made);
	ALBEDO = shade;
	ROUGHNESS = 1.0;
	ALPHA = depth * sole * fade;
}
