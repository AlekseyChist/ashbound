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
	float weight=painted_weight ? COLOR.a : clamp(VERTEX.y*1.4,0.0,1.0);
	float gust=0.65+0.35*sin(effect_time*0.47+origin.z*0.13);
	float sway=sin(effect_time*1.8+origin.x*0.39+origin.z*0.25)+0.23*sin(effect_time*4.1+VERTEX.y*2.0);
	vec3 world_offset=vec3(wind_direction.x,0.0,wind_direction.y)*sway*gust*wind_strength*amplitude*weight*weight;
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
