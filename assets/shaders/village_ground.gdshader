shader_type spatial;
render_mode diffuse_burley;
uniform float wetness : hint_range(0,1) = 0.0;
varying highp vec3 world;
float hash(vec2 p){vec3 q=fract(vec3(p.xyx)*0.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
	float grain=noise(world.xz*9.0)*.28+noise(world.xz*1.7)*.2;
	ALBEDO=COLOR.rgb*(.74+grain)*mix(1.0,.67,wetness);
	ROUGHNESS=mix(.96,.43,wetness);
	SPECULAR=.25;
}
