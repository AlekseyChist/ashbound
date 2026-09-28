shader_type sky;
// CLOUDS-01 (owner 28 Sep: "clouds in the sky, different ones for different weather"): the procedural
// sky's gradient and sun (same colours as before, set by village_atmosphere.gd) with a cloud layer
// drifting on the wind. Weather sets how much of the sky is covered, how dark the clouds are and how
// fast and stretched they run. Four octaves of noise, a three-octave light probe; the reflection
// cubemap gets the plain sky (the overcast colours already dim it). The half-resolution pass banded
// the clouds into steps (8-bit alpha), so they are drawn in the main pass, with a slight dither.
uniform vec3 sky_top_color : source_color = vec3(0.21, 0.35, 0.4);
uniform vec3 sky_horizon_color : source_color = vec3(0.52, 0.58, 0.53);
uniform vec3 ground_bottom_color : source_color = vec3(0.03, 0.05, 0.035);
uniform vec3 ground_horizon_color : source_color = vec3(0.52, 0.58, 0.53);
uniform float sky_curve = 0.2;
uniform float ground_curve = 0.02;
uniform float sun_angle_max = 0.52;
uniform float sun_curve = 0.15;
// 0 a few fair-weather clouds .. 1 the whole sky.
uniform float cover = 0.2;
// 0 white .. 1 heavy dark storm clouds.
uniform float heaviness = 0.0;
// Wind: drift speed (sky units per second) and how much the clouds are drawn out along it.
uniform float drift = 0.006;
uniform float streak = 0.0;
uniform vec2 wind_direction = vec2(0.8, 0.6);
uniform float daylight = 1.0;
uniform vec3 cloud_lit : source_color = vec3(0.96, 0.95, 0.92);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.58, 0.62);
uniform vec3 storm_shade : source_color = vec3(0.16, 0.18, 0.21);

float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p, int octaves) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < octaves; i++) { v += a * noise(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; }
	return v / (1.0 - pow(0.5, float(octaves)));
}

vec3 plain_sky(vec3 dir) {
	float v_angle = acos(clamp(dir.y, -1.0, 1.0));
	vec3 col;
	if (dir.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		col = mix(sky_horizon_color, sky_top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	} else {
		float c = (v_angle - PI * 0.5) / (PI * 0.5);
		col = mix(ground_horizon_color, ground_bottom_color, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float sun_angle = acos(clamp(dot(LIGHT0_DIRECTION, dir), -1.0, 1.0));
		// The sun hides behind a covered sky.
		vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY * (1.0 - 0.85 * cover * heaviness);
		if (sun_angle < LIGHT0_SIZE) {
			col = sun;
		} else if (sun_angle < sun_angle_max) {
			float c2 = (sun_angle - LIGHT0_SIZE) / (sun_angle_max - LIGHT0_SIZE);
			col = mix(sun, col, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
		}
	}
	return col;
}

// The cloud layer seen along `dir`: rgb colour, a coverage.
vec4 clouds(vec3 dir) {
	if (dir.y <= 0.0) return vec4(0.0);
	// A flat layer overhead: points further out come closer to the horizon.
	vec2 p = dir.xz / (dir.y + 0.12);
	vec2 w = normalize(wind_direction);
	// Along the wind the shapes are drawn out when it blows hard.
	vec2 along = vec2(dot(p, w), dot(p, vec2(-w.y, w.x)));
	along.x *= mix(1.0, 0.35, streak);
	vec2 q = along * 1.6 - vec2(TIME * drift * 60.0, 0.0);
	float n = fbm(q, 4) * 0.94;
	float edge = mix(0.72, 0.18, cover);
	float density = smoothstep(edge, edge + mix(0.18, 0.3, cover), n);
	// Lit from the sun's side: denser further along towards it means shade.
	float toward = 0.0;
	if (LIGHT0_ENABLED) {
		vec2 s = normalize(LIGHT0_DIRECTION.xz + vec2(1e-4));
		toward = fbm(q + vec2(dot(s, w), dot(s, vec2(-w.y, w.x))) * 0.12, 3) * 0.94;
	}
	float shade = clamp((toward - n) * 3.0 + 0.55, 0.0, 1.0);
	vec3 base = mix(cloud_shade, storm_shade, heaviness);
	vec3 col = mix(base, cloud_lit * mix(1.0, 0.45, heaviness), shade * (1.0 - 0.85 * heaviness));
	col *= mix(0.08, 1.0, daylight);
	if (LIGHT0_ENABLED) col = mix(col, col * LIGHT0_COLOR, 0.35);
	// Thinner towards the horizon, where the haze takes over.
	density *= smoothstep(0.0, 0.18, dir.y);
	return vec4(col, density);
}

void sky() {
	vec3 col = plain_sky(EYEDIR);
	if (!AT_CUBEMAP_PASS) {
		vec4 c = clouds(EYEDIR);
		col = mix(col, c.rgb, c.a);
		// A slight dither breaks the 8-bit steps of the smooth gradients.
		col += (hash(FRAGCOORD.xy) - 0.5) / 255.0;
	}
	COLOR = col;
}
