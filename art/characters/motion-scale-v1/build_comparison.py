"""Lay out Godot captures without altering poses or normalizing their bounds."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json,sys,hashlib
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
CAP=Path(sys.argv[1])
FONT=ROOT/'assets/ui/fonts/OpenSans-SemiBold.ttf'
font=ImageFont.truetype(str(FONT),22)
small=ImageFont.truetype(str(FONT),17)
CROP=(445,245,835,665)
W,H=300,323

def panel(variant,view,action,i=0):
    p=CAP/variant/f'{view}-{action}-{i}-game.png'
    im=Image.open(p)
    assert im.size==(1280,720)
    return im.crop(CROP).resize((W,H),Image.Resampling.LANCZOS)

def grid(variant):
    im=Image.new('RGB',(960,1160),'#252b30');d=ImageDraw.Draw(im)
    d.text((18,12),'Сейчас: 0.19.3' if variant=='before' else 'Проба: согласованный масштаб',font=font,fill='white')
    names={'back':'От камеры','front':'К камере','side':'Боком'}
    for y,v in enumerate(names):
        for x,(a,label) in enumerate([('idle','Стойка'),('walk','Ходьба'),('run','Бег')]):
            top=58+y*360
            d.text((x*320+12,top),names[v]+' / '+label,font=small,fill='white')
            im.paste(panel(variant,v,a),(x*320+10,top+28))
    im.save(OUT/(variant+'-all-views.png'))

def side_row_pair(i):
    im=Image.new('RGB',(960,858),'#252b30');d=ImageDraw.Draw(im)
    for y,variant in enumerate(['before','candidate']):
        top=y*420
        d.text((15,top+10),'Сейчас на телефоне' if y==0 else 'Проба масштаба · рисунки прежние',font=font,fill='white')
        for x,(a,label) in enumerate([('idle','Стойка'),('walk','Ходьба'),('run','Бег')]):
            d.text((x*320+12,top+44),label,font=small,fill='white')
            im.paste(panel(variant,'side',a,0 if a=='idle' else i),(x*320+10,top+72))
    return im

rows=json.loads((CAP/'metrics.json').read_text(encoding='utf8'))
assert len(rows)==120
assert len({(x['camera_position'],x['camera_fov']) for x in rows})==1
pairs={}
for x in rows:pairs.setdefault((x['view'],x['action'],x['frame']),{})[x['variant']]=x
for key,pair in pairs.items():
    a,b=pair['before'],pair['candidate'];assert a['source_pixel_size']==b['source_pixel_size']
    name='%s-%s-%d-cell.png'%key
    assert (CAP/'before'/name).read_bytes()==(CAP/'candidate'/name).read_bytes(),'Artwork changed'
    assert abs(b['pixel_size']/a['pixel_size']-b['candidate_factor'])<1e-6
    assert abs(a['body_y']/a['pixel_size']-182)<1e-4 and abs(b['body_y']/b['pixel_size']-182)<1e-4
for variant in ['before','candidate']:grid(variant)
frames=[side_row_pair(i) for i in range(8)]
frames[0].save(OUT/'side-before-after.png')
# One shared palette avoids per-frame palette shimmer in a diagnostic GIF.
strip=Image.new('RGB',(480,429*8))
for i,im in enumerate(frames):strip.paste(im.resize((480,429)),(0,429*i))
palette=strip.quantize(colors=256)
frames=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
frames[0].save(OUT/'side-before-after.gif',save_all=True,append_images=frames[1:],duration=[70,60,70,70,60,70,70,60],loop=0,optimize=False,disposal=1)
(OUT/'metrics.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*') if p.suffix in ['.png','.gif']}
(OUT/'artifacts.json').write_text(json.dumps({'source_commit':'267feedb6cc6f09debaf202a7a1835330e315042','poses':120,'same_camera':True,'same_raw_artwork':True,'fixed_crop':CROP,'artifacts':manifest},indent=2)+'\n',encoding='utf8')
print('MOTION_SCALE_LAYOUT_OK poses=120 camera=constant art=unchanged no_bbox_normalization')
