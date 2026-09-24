shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool has_texture = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float effect_time = 0.0;
uniform float wind_strength = 0.15;
uniform vec2 wind_direction = vec2(0.85,0.53);
uniform float amplitude = 0.4;
uniform bool painted_weight = true;
uniform float wetness = 0.0;
void vertex(){
	vec3 origin=MODEL_MATRIX[3].xyz;
	float weight=clamp(painted_weight ? COLOR.a : VERTEX.y*1.4,0.0,1.0);
	float strength=clamp(wind_strength,0.0,1.0);
	vec2 direction=wind_direction/max(length(wind_direction),0.0001);
	// A slow wave crosses the whole grove; individual plants lag within it.
	float gust=0.6+0.4*sin(effect_time*0.65-dot(origin.xz,direction)*0.07);
	float phase=origin.x*0.39+origin.z*0.25;
	float rate=painted_weight ? 0.95 : 2.4;
	float sway=sin(effect_time*rate+phase)+0.18*sin(effect_time*rate*2.0+phase*1.3);
	float flutter=0.10*sin(effect_time*(painted_weight ? 2.8 : 7.2)+VERTEX.y*2.0+phase)*weight;
	float gain=1.0+1.1*smoothstep(0.25,1.0,strength);
	// Bound: (0.35 + 1 + 0.18 + 0.10) * 2.1 = 3.423 amplitudes.
	float bend=(0.35*strength+sway+flutter)*gust*strength*gain*amplitude*weight*weight;
	vec3 world_offset=vec3(direction.x,0.0,direction.y)*bend;
	VERTEX+=(inverse(MODEL_MATRIX)*vec4(world_offset,0.0)).xyz;
}
void fragment(){
	vec4 tex=has_texture ? texture(albedo_texture,UV) : vec4(1.0);
	ALBEDO=tex.rgb*tint.rgb*mix(0.9,0.72,wetness);
	ALPHA=tex.a;
	ALPHA_SCISSOR_THRESHOLD=0.4;
	ROUGHNESS=mix(0.93,0.62,wetness);
	SPECULAR=0.2;
}
