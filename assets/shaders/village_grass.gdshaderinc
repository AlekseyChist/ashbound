// GRASS-01 (D-083): shared grass look. Instance custom = ground colour (rgb) + random (a).
// UV.y runs 0 at the root to 1 at the tip. Wind uses the same inputs as village_foliage.gdshader.
uniform float effect_time = 0.0;
uniform float wind_strength = 0.15;
uniform vec2 wind_direction = vec2(0.85,0.53);
uniform float wetness = 0.0;
// Density thins with distance by dropping instances whose random is above the kept share.
uniform float fade_start = 18.0;
uniform float fade_end = 38.0;
uniform float far_share = 0.35;
varying vec3 ground_color;
varying float tip;

void vertex(){
	vec3 origin=MODEL_MATRIX[3].xyz;
	float distance_to_camera=distance(origin,CAMERA_POSITION_WORLD);
	float share=mix(1.0,far_share,smoothstep(fade_start,fade_end,distance_to_camera));
	share*=1.0-smoothstep(fade_end,fade_end+6.0,distance_to_camera);
	// Kept instances shrink in over the last tenth of their share instead of popping.
	float keep=smoothstep(share,share-.1,INSTANCE_CUSTOM.a);
	tip=UV.y;
	float strength=clamp(wind_strength,0.0,1.0);
	vec2 direction=wind_direction/max(length(wind_direction),0.0001);
	float gust=.6+.4*sin(effect_time*.65-dot(origin.xz,direction)*.07);
	float phase=origin.x*.73+origin.z*.51+INSTANCE_CUSTOM.a*6.0;
	float sway=sin(effect_time*1.9+phase)+.25*sin(effect_time*4.1+phase*1.7);
	float bend=(.2+.8*strength)*(.35*strength+sway*(.25+.75*strength))*gust*.16*tip*tip;
	vec3 world_offset=vec3(direction.x,0.0,direction.y)*bend;
	VERTEX*=keep;
	VERTEX+=(inverse(MODEL_MATRIX)*vec4(world_offset*keep,0.0)).xyz;
	ground_color=INSTANCE_CUSTOM.rgb;
}

vec3 grass_albedo(float variation){
	// Roots sit in the ground tone; tips are lighter and slightly warmer, like sunlit blades.
	vec3 root=ground_color*.62;
	vec3 top=ground_color*vec3(1.28,1.34,1.05);
	vec3 color=mix(root,top,smoothstep(0.0,1.0,tip));
	return color*mix(.88,1.1,variation)*mix(1.0,.72,wetness);
}

// Light the blades like the ground under them: no dark back faces, no shine.
#define GRASS_SURFACE NORMAL=normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);ROUGHNESS=mix(.95,.8,wetness);SPECULAR=.05;
