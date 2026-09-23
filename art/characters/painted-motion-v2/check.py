"""Codex QA: resource preservation, complete silhouettes, reproducible art and fail-safe builder."""
import re,subprocess,hashlib,sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
BASE='d3e54046fcd746c17b8888ad91916f5e4163f885'
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

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
p='assets/characters/courtyard/traveler_frames.tres'
old,om=parse(subprocess.check_output(['git','show',BASE+':'+p],cwd=ROOT).decode('utf8'))
new,nm=parse((ROOT/p).read_text(encoding='utf8'))
assert old.keys()==new.keys() and om.keys()==nm.keys()
assert all(abs(om[k]-nm[k])<1e-12 for k in om), 'Legacy equipment metadata changed'
assert abs(nm['pixel_size_run_side']/nm['pixel_size_side']-.9)<1e-12
changed={'walk','walk_side','run_side'}
for clip,expected in old.items():
 actual=new[clip]
 if clip not in changed:
  assert actual==expected,('Unrelated clip changed',clip)
 else:
  assert actual['speed']==expected['speed'] and actual['loop']==expected['loop']
  assert len(actual['frames'])==len(expected['frames'])==8
  for i,(a,e) in enumerate(zip(actual['frames'],expected['frames'])):
   assert a['duration']==e['duration']
   t=a['texture'];action='run' if clip=='run_side' else 'walk'
   assert t['path'].endswith(f'painted-motion-v2/{action}.png')
   assert t['rect']==((i%4)*384,(i//4)*384,384,384) and t['margin']==(0,0,0,0) and t['clip']
p='assets/characters/courtyard/traveler_backpack_frames.tres'
assert (ROOT/p).read_bytes()==subprocess.check_output(['git','show',BASE+':'+p],cwd=ROOT)
outputs=[ROOT/'assets/characters/courtyard/painted-motion-v2'/n for n in ['walk.png','run.png']]
before=[sha(p) for p in outputs]
subprocess.run([sys.executable,str(Path(__file__).with_name('build.py'))],check=True)
assert before==[sha(p) for p in outputs]
for path in outputs:
 im=Image.open(path)
 assert im.mode=='RGBA' and im.size==(1536,768)
 digests=[];heights=[];ground=[]
 for i in range(8):
  cell=im.crop(((i%4)*384,(i//4)*384,(i%4+1)*384,(i//4+1)*384))
  b=cell.getchannel('A').point(lambda a:255 if a>96 else 0).getbbox()
  assert b and b[0]>0 and b[1]>0 and b[2]<384 and b[3]<384
  heights.append(b[3]-b[1]);ground.append(b[3])
  digests.append(hashlib.sha256(cell.tobytes()).hexdigest())
 assert len(set(digests))==8, 'Repeated pose'
 runtime_scale=.9 if path.name=='run.png' else 1.0
 assert min(heights)*runtime_scale>=.85*302, ('Crouched displayed silhouette',path.name,heights)
 if path.name=='run.png':
  assert max(ground)-min(ground)>=12,'No visible flight phase'
 print(path.name,'silhouette heights',heights,'sole positions',ground)
print('ASHBOUND_PAINTED_MOTION_ASSETS_OK clips='+str(len(new))+' legacy=unchanged repeatable=1')
