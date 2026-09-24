shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;
uniform sampler2D cover_heights : filter_linear, repeat_disable;
uniform vec3 volume_center;
uniform float effect_time=0.0;
uniform float intensity=0.0;
uniform float wind_strength=0.0;
uniform float daylight=1.0;
uniform bool splash=false;
varying vec3 rain_world;
varying float phase;
float cover(vec2 at){return texture(cover_heights,(at+vec2(95.5))/vec2(226.0,176.0)).r;}
void vertex(){
	vec3 at=MODEL_MATRIX[3].xyz;
	phase=fract(INSTANCE_CUSTOM.x+effect_time*(1.3+INSTANCE_CUSTOM.y));
	vec2 drift=vec2(0.85,0.53)*effect_time*wind_strength*2.0;
	at.xz=volume_center.xz+mod(at.xz-volume_center.xz+drift+vec2(13.0),vec2(26.0))-vec2(13.0);
	if(splash){
		at.y=cover(at.xz)+0.045;
		at.xz+=VERTEX.xz*(0.12+phase*0.7);
	}else{
		at.y=volume_center.y-2.0+(1.0-phase)*14.0;
		at+=INV_VIEW_MATRIX[0].xyz*VERTEX.x+normalize(vec3(-0.85*wind_strength*0.4,1.0,-0.53*wind_strength*0.4))*VERTEX.y;
	}
	rain_world=at;
	VERTEX=(VIEW_MATRIX*vec4(at,1.0)).xyz;
}
void fragment(){
	if(rain_world.y<cover(rain_world.xz)+0.025) discard;
	float shape;
	if(splash){
		float radius=length(UV-vec2(0.5));
		shape=(1.0-smoothstep(0.035,0.075,abs(radius-0.32)))*(1.0-phase);
	}else{
		shape=(1.0-smoothstep(0.1,0.5,abs(UV.x-0.5)))*sin(UV.y*3.14159);
	}
	float distance_fade=smoothstep(0.55,2.0,length(rain_world-INV_VIEW_MATRIX[3].xyz));
	ALBEDO=mix(vec3(0.07,0.1,0.15),vec3(0.40,0.52,0.57),daylight);
	ALPHA=shape*intensity*distance_fade*(splash ? 0.28 : 0.38);
}
