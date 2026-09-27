"""Read-only material comparison using the real SpriteFrames atlas rectangles."""
from pathlib import Path
import json,re
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'.tools/guard-palette-qa/.tools/guard-palette/export'

def frame(resource,clip,index=0,override=None):
    text=(ROOT/resource).read_text(encoding='utf8')
    ext=dict((b,a) for a,b in re.findall(r'\[ext_resource type="Texture2D" path="res://([^"]+)" id="([^"]+)"\]',text))
    clips=dict((b,a) for a,b in re.findall(r'"frames": \[(.*?)\],\s*"loop": \d+,\s*"name": &"([^"]+)"',text,re.S))
    rid=re.findall(r'SubResource\("([^"]+)"\)',clips[clip])[index]
    part=re.search(r'\[sub_resource type="AtlasTexture" id="'+re.escape(rid)+r'"\]\s*(.*?)(?=\[|$)',text,re.S)[1]
    atlas=ext[re.search(r'atlas = ExtResource\("([^"]+)"\)',part)[1]]
    x,y,w,h=map(float,re.search(r'region = Rect2\(([^)]+)\)',part)[1].split(','))
    return np.array(Image.open(override or ROOT/atlas))[int(y):int(y+h),int(x):int(x+w)]

def masks(a):
    rgb=a[:,:,:3].astype(float);r,g,b=rgb.transpose(2,0,1)
    yy=np.where(a[:,:,3]>250)[0];y=(np.arange(a.shape[0])[:,None]-yy.min())/(yy.max()-yy.min()+1)
    v=a[:,:,3]>250;lum=rgb@np.array([.2126,.7152,.0722])
    return {'coat':v&(y>.40)&(y<.63)&(r>g*1.12)&(g>b*1.1)&(lum>30),
      'shirt':v&(y>.16)&(y<.42)&(r<g*1.16)&(g<b*1.20)&(lum>60),
      'pants':v&(y>.65)&(y<.81)&(r<g*1.19)&(g<b*1.22)&(lum>25),
      'boots':v&(y>.84)&(r>g*1.12)&(g>b*1.1)&(lum>30)}

def values(a,select=None):
    lum=a[:,:,:3]@np.array([.2126,.7152,.0722])
    return {k:np.quantile(lum[m],[.2,.5,.8]).round(2).tolist() for k,m in (select or masks(a)).items() if m.sum()>20}

rows=[]; records=[]
for pack in [False,True]:
    name='trained'+('_pack' if pack else '')
    oldbase=ROOT/'art/characters/fist-defense-v1/base/trained.png'
    original=np.array(Image.open(oldbase))
    if pack:
        recipe=json.loads((ROOT/'art/characters/fist-defense-palette-v1/palette.json').read_text())
        paint=np.array(Image.open(ROOT/recipe['paint']))
        for x,y,w,h in recipe['regions']:original[y:y+h,x:x+w]=paint[y:y+h,x:x+w]
    # Only a temporary QA source, never a game asset.
    original_path=ROOT/'.tools'/('original-'+name+'.png');Image.fromarray(original).save(original_path)
    for view in ['front','back','side']:
        prefix='assets/characters/courtyard/'
        idle=frame(prefix+'fist-preview/'+name+'_frames.tres','idle_'+view)
        attack=frame(prefix+'fist-preview/'+name+'_frames.tres','attack_'+view,1)
        before=frame(prefix+'fist-defense/'+name+'_frames.tres','guard_'+view,override=original_path)
        after=frame(prefix+'fist-defense/'+name+'_frames.tres','guard_'+view,override=OUT/('trained-pack.png' if pack else 'trained.png'))
        fixed=masks(before); vals={k:values(a,fixed if k in ['before','after'] else None) for k,a in [('idle',idle),('attack',attack),('before',before),('after',after)]}
        target=vals['idle']['coat'][1];old=vals['before']['coat'][1];new=vals['after']['coat'][1]
        assert abs(new-target)<abs(old-target)*.6+1,(view,pack,old,new,target)
        assert .85<new/target<1.15,(view,pack,new/target)
        records.append({'pack':pack,'view':view,'materials':vals})
        row=Image.new('RGB',(1120,540),(53,52,49)); draw=ImageDraw.Draw(row)
        for i,(label,a) in enumerate([('IDLE',idle),('OLD GUARD',before),('CORRECTED GUARD',after),('ATTACK',attack)]):
            im=Image.fromarray(a);box=im.getbbox();im=im.crop(box)
            factor=min(255/im.width,480/im.height)
            im=im.resize((round(im.width*factor),round(im.height*factor)),Image.Resampling.LANCZOS)
            row.paste(im,(i*280+(280-im.width)//2,535-im.height),im)
            draw.text((i*280+12,10),label+' / '+view+(' / PACK' if pack else ''),fill='white')
        rows.append(row)
canvas=Image.new('RGB',(1120,540*len(rows)))
for i,row in enumerate(rows):canvas.paste(row,(0,540*i))
canvas.save(ROOT/'.tools/guard-palette-comparison.png')
(ROOT/'.tools/guard-palette-measurements.json').write_text(json.dumps(records,indent=2),encoding='utf8')
for r in records:
    v=r['materials'];print(r['view'],r['pack'],'coat',v['before']['coat'][1],'->',v['after']['coat'][1],'idle',v['idle']['coat'][1])
print('ASHBOUND_GUARD_PALETTE_MEASUREMENT_OK views=6')
