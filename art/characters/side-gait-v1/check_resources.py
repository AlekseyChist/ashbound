"""Compare loaded resource declarations with the pre-task git baseline, not builder logic."""
import json,re,subprocess,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
BASE='0fa35a96231775ca4f0b37a085ed0aaf51745c69'
def parse(s):
    external={}
    for block in re.findall(r'\[ext_resource[^\]]+\]',s):
        fields=dict(re.findall(r'(\w+)="([^"]+)"',block));external[fields['id']]=fields['path']
    sub={}
    for ident,body in re.findall(r'\[sub_resource type="AtlasTexture" id="([^"]+)"\](.*?)(?=\[)',s,re.S):
        tex=re.search(r'atlas = ExtResource\("([^"]+)"\)',body).group(1)
        rect=lambda key:tuple(float(v) for v in re.search(key+r' = Rect2\(([^)]+)\)',body).group(1).split(',')) if key+' = Rect2' in body else (0.,0.,0.,0.)
        sub[ident]={'path':external[tex],'rect':rect('region'),'margin':rect('margin'),'clip':'filter_clip = true' in body}
    clips={}
    for frames,loop,name,speed in re.findall(r'"frames": \[(.*?)\],\s*"loop": (true|false|1|0),\s*"name": &"([^"]+)",\s*"speed": ([\d.]+)',s,re.S):
        entries=[]
        for duration,ident in re.findall(r'"duration": ([\d.]+),\s*"texture": SubResource\("([^"]+)"\)',frames):
            entries.append({'duration':float(duration),'texture':sub[ident]})
        clips[name]={'frames':entries,'loop':loop in ['true','1'],'speed':float(speed)}
    metadata={k:float(v) for k,v in re.findall(r'metadata/(\w+) = ([\d.]+)',s)}
    return clips,metadata
count=0
for name in ['traveler_frames.tres','traveler_backpack_frames.tres']:
    p='assets/characters/courtyard/'+name
    old,om=parse(subprocess.check_output(['git','show',BASE+':'+p],cwd=ROOT).decode('utf8'))
    new,nm=parse((ROOT/p).read_text(encoding='utf8'))
    assert old.keys()==new.keys() and om.keys()==nm.keys()
    assert all(abs(om[k]-nm[k])<1e-12 for k in om),'Metadata changed'
    for clip,expected in old.items():
        actual=new[clip]
        if clip not in ['walk','walk_side','run_side']:
            assert actual==expected,('Unrelated clip changed',name,clip)
        else:
            assert actual['speed']==expected['speed'] and actual['loop']==expected['loop']
            assert len(actual['frames'])==len(expected['frames'])==8
            for i,(a,e) in enumerate(zip(actual['frames'],expected['frames'])):
                assert a['duration']==e['duration']
                t=a['texture'];action='run' if clip=='run_side' else 'walk';variant='pack' if 'backpack' in name else 'bare'
                assert t['path'].endswith(f'side-gait-v1/{action}-{variant}.png')
                assert t['rect']==((i%4)*384,(i//4)*384,384,384) and t['margin']==(0,0,0,0) and t['clip']
        count+=1
print(f'ASHBOUND_SIDE_GAIT_RESOURCES_OK clips={count} metadata=unchanged unrelated=unchanged')
