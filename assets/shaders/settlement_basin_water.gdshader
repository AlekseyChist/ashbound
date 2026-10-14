shader_type spatial;
render_mode blend_mix, cull_disabled;
// Small masonry bowls need no depth-buffer shoreline reconstruction.
// Animated world-space ripples work in Compatibility as well as Mobile.
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
    vec2 p = world_pos.xz * 0.65;
    vec2 drift = vec2(TIME * 0.045, -TIME * 0.028);
    float ripple = noise(p + drift) * 0.65 + noise(p * 2.1 - drift) * 0.35;
    vec2 slope = vec2(noise(p + drift + vec2(0.08, 0.0)) - noise(p + drift - vec2(0.08, 0.0)), noise(p + drift + vec2(0.0, 0.08)) - noise(p + drift - vec2(0.0, 0.08)));
    NORMAL_MAP = normalize(vec3(-slope * 0.8, 1.0)) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 1.0;
    ALBEDO = mix(vec3(0.10, 0.20, 0.21), vec3(0.18, 0.29, 0.27), ripple);
    ROUGHNESS = 0.22;
    SPECULAR = 0.55;
    ALPHA = 0.86;
}
