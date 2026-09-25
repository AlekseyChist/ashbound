shader_type spatial;
render_mode diffuse_burley;
uniform float wetness : hint_range(0,1) = 0.0;
uniform bool detail_enabled = true;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_meters = 1.4;
uniform float path_meters = 3.2;
varying highp vec3 world;
float hash(vec2 p){vec3 q=fract(vec3(p.xyx)*0.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){
	world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	// Terrain is fixed in world space, UV u = +X, v = +Z. Build the missing tangent frame.
	TANGENT=normalize(vec3(1.0,-NORMAL.x/max(NORMAL.y,.001),0.0));
	BINORMAL=normalize(cross(TANGENT,NORMAL));
}
void fragment(){
	float damp=clamp(wetness,0.0,1.0);
	if(detail_enabled){
		vec2 guv=world.xz/max(grass_meters,.01);
		vec2 puv=world.xz/max(path_meters,.01);
		float road=smoothstep(.08,.92,COLOR.a);
		// Far ground (the world map around the village) fades to its mean tone: no tiling moire.
		float near=1.0-smoothstep(60.0,200.0,distance(world,CAMERA_POSITION_WORLD));
		vec3 grass=texture(grass_albedo,guv).rgb;
		vec3 dirt=texture(path_albedo,puv).rgb;
		// Measured linear means of unchanged source images. Keep our palette and their surface detail.
		vec3 detail=mix(grass/vec3(.060315,.109109,.022630),dirt/vec3(.152341,.108615,.063908),road);
		float macro=.93+.14*mix(.5,noise(world.xz*.12),near);
		ALBEDO=COLOR.rgb*mix(vec3(1.0),clamp(detail,vec3(.16),vec3(3.0)),.78*near)*macro*mix(1.0,.67,damp);
		vec3 n=mix(texture(grass_normal,guv).rgb,texture(path_normal,puv).rgb,road);
		NORMAL_MAP=n;
		NORMAL_MAP_DEPTH=mix(.38,.52,road)*near;
		float rough=mix(texture(grass_roughness,guv).r,texture(path_roughness,puv).r,road);
		ROUGHNESS=mix(clamp(rough,.72,1.0),.43,damp);
	}else{
		float grain=noise(world.xz*9.0)*.28+noise(world.xz*1.7)*.2;
		ALBEDO=COLOR.rgb*(.74+grain)*mix(1.0,.67,damp);
		ROUGHNESS=mix(.96,.43,damp);
		NORMAL_MAP=vec3(.5,.5,1.0);
		NORMAL_MAP_DEPTH=0.0;
	}
	SPECULAR=.25;
}
