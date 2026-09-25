shader_type spatial;
// GRASS-01 variant "cards": crossed quads with an alpha-cut blade texture (grey = shade, alpha = shape).
render_mode cull_disabled, diffuse_burley;
#include "res://assets/shaders/village_grass.gdshaderinc"
uniform sampler2D blades_texture : filter_linear_mipmap, repeat_disable;

void fragment(){
	vec4 texel=texture(blades_texture,UV);
	ALBEDO=grass_albedo(COLOR.r)*mix(.8,1.12,texel.r);
	ALPHA=texel.a;
	ALPHA_SCISSOR_THRESHOLD=.5;
	GRASS_SURFACE
}
