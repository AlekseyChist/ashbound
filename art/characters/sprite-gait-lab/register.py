"""Register complete sprite drawings for preview. Never warp/rotate body parts.
Raw built-in imagegen outputs remain unchanged. Requires Pillow.
"""
from pathlib import Path
from PIL import Image
import hashlib,json

ROOT=Path(__file__).resolve().parent
data=json.loads((ROOT/'source-poses.json').read_text(encoding='utf-8'))
rows=[]
for key,pose in data['poses'].items():
    source=ROOT/pose['file']
    image=Image.open(source)
    assert image.mode=='RGBA', source
    x,y,w,h=pose['rect']
    assert x>=0 and y>=0 and x+w<=image.width and y+h<=image.height
    cell=image.crop((x,y,x+w,y+h))
    mask=cell.getchannel('A').point(lambda a:255 if a>96 else 0)
    bounds=mask.getbbox()
    head=mask.crop((0,0,w,round(h*150/627))).getbbox()
    assert bounds and head and head[2]-head[0]>40
    # Common facing direction: register the right edge of the head silhouette.
    # This translates each COMPLETE drawing, keeping its own body/limb proportions.
    pose['pivot']=[round(head[2]*627/w-60,2),round(bounds[3]*627/h,2)]
    rows.append({'pose':key,'file':pose['file'],'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'pivot':pose['pivot'],'foreground_bounds':bounds})
data['notes']='Whole drawings translated only: head silhouette right edge has common X; sole has common Y. One fixed normalization from source cell resolution to 627 units. No pose-specific fitting, body-part transforms, color changes or morphing.'
(ROOT/'frames.js').write_text('const LAB = '+json.dumps(data,ensure_ascii=False,indent=2)+';\n',encoding='utf-8')
(ROOT/'registration.json').write_text(json.dumps({'canvas':627,'method':data['notes'],'poses':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('SPRITE_LAB_PACK_OK complete poses=%d; raw RGBA preserved'%len(rows))
