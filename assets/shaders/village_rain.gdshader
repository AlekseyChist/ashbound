shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;
uniform sampler2D cover_heights : filter_linear, repeat_disable;
uniform vec3 volume_center;
uniform float effect_time=0.0;
uniform float intensity=0.0;
uniform float wind_strength=0.0;
uniform float daylight=1.0;
uniform bool splash=false;
// WEATHER-BIOME-01: 1 = snow (the mountains): slow swaying flakes, soft white dots, no splashes.
uniform float snow=0.0;
// The measured cover map: x/z of its corner and its size in metres (the village, or a window round the hero).
uniform vec4 cover_rect=vec4(-95.5,-95.5,226.0,176.0);
varying vec3 rain_world;
varying float phase;
float cover(vec2 at){
	vec2 uv=(at-cover_rect.xy)/cover_rect.zw;
	// Outside the measured area the terrain itself hides drops; no floating splashes.
	if(any(lessThan(uv,vec2(0.0)))||any(greaterThan(uv,vec2(1.0)))) return -1.0e6;
	return texture(cover_heights,uv).r;
}
void vertex(){
	vec3 at=MODEL_MATRIX[3].xyz;
	phase=fract(INSTANCE_CUSTOM.x+effect_time*(1.3+INSTANCE_CUSTOM.y)*mix(1.0,0.17,snow));
	vec2 drift=vec2(0.85,0.53)*effect_time*wind_strength*2.0;
	drift+=snow*0.7*vec2(sin(effect_time*1.1+INSTANCE_CUSTOM.x*23.0),cos(effect_time*0.9+INSTANCE_CUSTOM.y*17.0));
	at.xz=volume_center.xz+mod(at.xz-volume_center.xz+drift+vec2(13.0),vec2(26.0))-vec2(13.0);
	if(splash){
		at.y=cover(at.xz)+0.045;
		at.xz+=VERTEX.xz*(0.12+phase*0.7);
	}else{
		at.y=volume_center.y-2.0+(1.0-phase)*14.0;
		vec3 fall=normalize(vec3(-0.85*wind_strength*0.4,1.0,-0.53*wind_strength*0.4));
		// A flake is a small square facing the camera; a drop a long streak along the fall.
		at+=INV_VIEW_MATRIX[0].xyz*VERTEX.x*mix(1.0,2.2,snow)+mix(fall,INV_VIEW_MATRIX[1].xyz,snow)*VERTEX.y*mix(1.0,0.16,snow);
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
		float streak=(1.0-smoothstep(0.1,0.5,abs(UV.x-0.5)))*sin(UV.y*3.14159);
		float flake=1.0-smoothstep(0.15,0.5,length(UV-vec2(0.5)));
		shape=mix(streak,flake,snow);
	}
	float distance_fade=smoothstep(0.55,2.0,length(rain_world-INV_VIEW_MATRIX[3].xyz));
	ALBEDO=mix(mix(vec3(0.07,0.1,0.15),vec3(0.40,0.52,0.57),daylight),mix(vec3(0.35,0.37,0.4),vec3(0.95,0.96,0.98),daylight),snow);
	ALPHA=shape*intensity*distance_fade*(splash ? 0.28*(1.0-snow) : mix(0.38,0.85,snow));
}
