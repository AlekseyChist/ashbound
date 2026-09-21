shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Camera-facing AnimatedSprite3D, foot-anchored, already oriented on CPU.
// Geometry (VERTEX) is in meters and must NOT be modified.
// Depth is remapped so it corresponds to a physically UPRIGHT hero:
// the sprite leans backward visually, but its depth behaves as if the
// character stood upright at foot_world, so background objects cannot
// slice the torso. Normal occlusion from walls in front is preserved
// (no depth_test override, no forced near depth, no constant bias).

uniform sampler2D texture_albedo : source_color, filter_linear, repeat_disable;
uniform vec3 foot_world;
uniform vec3 upright_right; // horizontal unit camera right

varying vec3 desired_world;

void vertex() {
	// VERTEX is already in meters (pixel_size applied). Do not touch POSITION/VERTEX.
	desired_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV) * COLOR;
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.25;

	// Upright plane through foot_world: normal = cross(upright_right, up).
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 normal = normalize(cross(upright_right, up));
	vec3 camera_origin = INV_VIEW_MATRIX[3].xyz;

	// Intersect this fragment's camera ray with the upright plane.
	vec3 ray = desired_world - camera_origin;
	float denom = dot(ray, normal);
	float t = -1.0;
	if (abs(denom) >= 1e-6) {
		t = dot(foot_world - camera_origin, normal) / denom;
	}

	vec3 hit_world;
	if (t <= 0.0) {
		// Ray nearly parallel to the plane or behind the camera:
		// fall back to the actual desired world position depth.
		hit_world = desired_world;
	} else {
		hit_world = camera_origin + ray * t;
	}

	// Project the plane intersection into clip space.
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(hit_world, 1.0);

	// Protect clip.w BEFORE any depth division: keep the sign but never zero.
	float safe_w = abs(clip.w) < 1e-6 ? (clip.w < 0.0 ? -1e-6 : 1e-6) : clip.w;

	float depth;
	if (CURRENT_RENDERER == RENDERER_COMPATIBILITY) {
		// Compatibility: NDC z is in [-1, 1] -> map to [0, 1].
		depth = (clip.z / safe_w + 1.0) * 0.5;
	} else {
		// Forward+ / Mobile Vulkan: depth is already [0, 1].
		depth = clip.z / safe_w;
	}

	DEPTH = clamp(depth, 0.0, 1.0);
}
