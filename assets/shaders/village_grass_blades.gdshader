shader_type spatial;
// GRASS-01 variant "blades": opaque geometric blades, no texture and no discard (cheap on tiled mobile GPUs).
render_mode cull_disabled, diffuse_burley;
#include "res://assets/shaders/village_grass.gdshaderinc"

void fragment(){
	ALBEDO=grass_albedo(COLOR.r);
	GRASS_SURFACE
}
