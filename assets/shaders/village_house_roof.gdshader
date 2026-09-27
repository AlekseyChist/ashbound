shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
// UV follows the existing 16 x 22 shingle layout, not a second tile grid.
// H01 slope = 3.6*sqrt(2) metres; depth = 8.9 metres. Wood tile = .6 m.
const vec2 GRAIN_SCALE = vec2(8.9/22.0/.6,3.6*1.41421356237/16.0/.6);
float tile_hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
	vec2 grain=UV*GRAIN_SCALE;
	vec2 cell=floor(UV);
	float aa=max(fwidth(UV.y),.005);
	float seam=smoothstep(0.0,.035+aa,fract(UV.y));
	float variation=.83+.25*tile_hash(cell);
	ALBEDO=texture(albedo_map,grain).rgb*vec3(.72,.75,.8)*variation*mix(.74,1.0,seam);
	NORMAL_MAP=texture(normal_map,grain).rgb;
	NORMAL_MAP_DEPTH=.7;
	ROUGHNESS=max(.82,texture(roughness_map,grain).r);
	SPECULAR=.10;
}
