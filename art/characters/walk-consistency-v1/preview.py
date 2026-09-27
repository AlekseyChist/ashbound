"""Codex QA and review media from a fixed Godot camera, without modifying game assets."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,sys,hashlib,subprocess,statistics
A=Path(__file__).resolve().parent
ROOT=A.parents[2]
C=Path(sys.argv[1])
F=ImageFont.truetype(str(ROOT/'assets/ui/fonts/OpenSans-SemiBold.ttf'),19)
S=ImageFont.truetype(str(ROOT/'assets/ui/fonts/OpenSans-SemiBold.ttf'),15)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
expected=sha(A/'walk-atlas.png')
subprocess.run([sys.executable,str(A/'build.py')],check=True)
assert sha(A/'walk-atlas.png')==expected
rows=json.loads((C/'metrics.json').read_text(encoding='utf8'))
assert len(rows)==160 and len({(x['camera_position'],x['camera_fov']) for x in rows})==1
pairs={}
for row in rows:pairs.setdefault((row['view'],row['action'],row['frame']),{})[row['variant']]=row
unchanged=0
for key,p in pairs.items():
    assert p['before']['pixel_size']==p['candidate']['pixel_size']
    assert p['before']['candidate_factor']==p['candidate']['candidate_factor']
    if not (key[0] in ['side','left'] and key[1]=='walk'):
        for kind in ['cell','game']:
            name='%s-%s-%d-'%key+kind+'.png'
            assert (C/'before'/name).read_bytes()==(C/'candidate'/name).read_bytes(),name
        unchanged+=1
metrics={}
for v in ['before','candidate']:
    widths=[];tops=[];centres=[];floors=[];unique=[]
    for i in range(8):
        p=C/v/f'side-walk-{i}-cell.png';im=Image.open(p)
        assert im.mode=='RGBA' and im.size==(384,384)
        mask=im.getchannel('A').point(lambda a:255 if a>96 else 0);b=mask.getbbox()
        assert b and 0<b[0]<b[2]<384 and 0<b[1]<b[3]<384
        head=mask.crop((140,60,250,130)).getbbox()
        widths.append(head[2]-head[0]);tops.append(b[1]);centres.append((head[0]+head[2])/2+140);floors.append(b[3]);unique.append(sha(p))
    assert len(set(unique))==8
    metrics[v]={'head_silhouette_top':tops,'head_roi_width':widths,'head_roi_centre_x':centres,'sole_y':floors}
    if v=='candidate':
        assert max(tops)-min(tops)<=3, 'Visible head bob exceeds 1% body height'
        assert max(widths)-min(widths)<=.05*statistics.median(widths),'Head width varies more than 5%'
        assert max(floors)-min(floors)<=3,'Ground contact drifts'

def panel(v,action,i=0,view='side'):
    return Image.open(C/v/f'{view}-{action}-{i}-game.png').crop((445,245,835,665)).resize((300,323),Image.Resampling.LANCZOS)

def movie_frame(i):
    im=Image.new('RGB',(960,410),'#252b30');d=ImageDraw.Draw(im)
    for x,(v,action,title) in enumerate([('before','walk','Ходьба до'),('candidate','walk','Новая ходьба'),('candidate','run','Выбранный бег · без правок')]):
        d.text((x*320+8,12),title,font=S,fill='white');im.paste(panel(v,action,i),(x*320+10,48))
    d.text((12,383),'Одна камера · целые рисованные позы · показ на месте',font=S,fill='#c8c7c4')
    return im
frames=[movie_frame(i) for i in range(8)]
frames[0].save(A/'comparison.png')
strip=Image.new('RGB',(480,205*8))
for i,im in enumerate(frames):strip.paste(im.resize((480,205)),(0,i*205))
palette=strip.quantize(colors=256)
quant=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
for name,duration in [('comparison.gif',[70,60,70,70,60,70,70,60]),('comparison-slow.gif',140)]:
    quant[0].save(A/name,save_all=True,append_images=quant[1:],duration=duration,loop=0,optimize=False,disposal=1)

# New walk compared with the unchanged idle and approved run.
im=Image.new('RGB',(960,410),'#252b30');d=ImageDraw.Draw(im)
for x,(action,title) in enumerate([('idle','Стойка'),('walk','Новая ходьба'),('run','Выбранный бег')]):
    d.text((x*320+12,12),title,font=F,fill='white');im.paste(panel('candidate',action),(x*320+10,48))
im.save(A/'set-comparison.png')
# No independent fitting of upper-body crops: same coordinates in every cell.
im=Image.new('RGB',(1600,520),'#252b30');d=ImageDraw.Draw(im)
for row,v in enumerate(['before','candidate']):
    d.text((10,row*260+4),'Было: голова и корпус' if row==0 else 'Новая серия: голова и корпус',font=F,fill='white')
    for i in range(8):
        cell=Image.open(C/v/f'side-walk-{i}-cell.png').crop((115,55,280,230)).resize((198,210))
        bg=Image.new('RGBA',cell.size,'#756f62');bg.alpha_composite(cell);im.paste(bg.convert('RGB'),(i*200,row*260+45));d.text((i*200+5,row*260+24),str(i+1),font=S,fill='white')
im.save(A/'upper-body-strip.png')
result={'poses':160,'same_camera':True,'unchanged_pose_pairs':unchanged,'comparison_scale':{'walk_side':.95,'run_side':.9,'run_front_back':1/.9},'head_roi':(140,60,250,130),'metrics':metrics,'note':'Geometric signals supplement visual review; they do not prove identical identity or artistic approval.'}
(A/'checks.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
(A/'artifacts.json').write_text(json.dumps({p.name:sha(p) for p in A.glob('*') if p.suffix in ['.png','.gif']},indent=2)+'\n',encoding='utf8')
print('WALK_CONSISTENCY_QA_OK poses=160 unchanged_pairs='+str(unchanged)+' atlas_repeatable=1')
print(json.dumps(metrics))
