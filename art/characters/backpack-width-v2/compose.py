"""Offline art restoration explicitly authorized by the owner, 2026-09-22.
Only complete RGBA atlas outputs; original body pixels outside painted gear
regions are copied verbatim. This is not a runtime equipment layer.
"""
from pathlib import Path
import re, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / 'assets/characters/courtyard'
OUT = ASSETS / 'painted-backpack'
GEN = Path(__file__).resolve().parent / 'donors'
(ROOT / '.tools').mkdir(exist_ok=True)
SHEETS = {
 'traveler-v1.png': ('side',GEN/'side.png','traveler-side-pack-v2.png'),
 'traveler-back-v1.png': ('back',GEN/'back.png','traveler-back-pack-v2.png'),
 'traveler-front-v1.png': ('front',GEN/'front.png','traveler-front-pack-v2.png'),
 'traveler-run-back-v3.png': ('back',OUT/'traveler-run-back-pack.png','traveler-run-back-pack-v2.png'),
 'traveler-run-front-v3.png': ('front',OUT/'traveler-run-front-pack.png','traveler-run-front-pack-v2.png'),
 'traveler-run-side-v3.png': ('side',OUT/'traveler-run-side-pack.png','traveler-run-side-pack-v2.png'),
 'traveler-pocket-v1.png': ('pocket',OUT/'traveler-pocket-pack.png','traveler-pocket-pack-v2.png'),
}

def regions():
 result = {}
 for resource in ['traveler_frames.tres','traveler_pocket_frames.tres']:
  text = (ASSETS/resource).read_text()
  ext = {ident:Path(path).name for path,ident in re.findall(r'\[ext_resource type="Texture2D" path="([^"]+)" id="([^"]+)"\]',text)}
  for ident,coords in re.findall(r'atlas = ExtResource\("([^"]+)"\)\s+region = Rect2\(([^)]+)\)',text):
   result.setdefault(ext[ident],set()).add(tuple(round(float(x.strip())) for x in coords.split(',')))
 return {name:sorted(rects,key=lambda r:(r[1]//315,r[0])) for name,rects in result.items()}

def head_anchor(image,rect):
 x,y,w,h=rect
 alpha=np.asarray(image)[y:y+h,x:x+w,3]
 yy,xx=np.nonzero(alpha>128)
 top=int(yy.min())+y
 head=np.asarray(image)[top+8:top+32,x:x+w,3]
 hy,hx=np.nonzero(head>128)
 return float(hx.mean())+x,top,int(yy.max()-yy.min()+1)

report=[]
reviews=[]
for name,rects in regions().items():
 view,donor_path,filename=SHEETS[name]
 original=Image.open(ASSETS/name).convert('RGBA')
 donor=Image.open(donor_path).convert('RGBA')
 assert original.size==donor.size
 result=Image.new('RGBA',original.size)
 base_canvas=Image.new('RGBA',original.size)
 fullmask=Image.new('L',original.size)
 for idx,rect in enumerate(rects):
  x,y,w,h=rect
  base_frame=original.crop((x,y,x+w,y+h))
  result.paste(base_frame,(x,y))
  base_canvas.paste(base_frame,(x,y))
  v=view if view!='pocket' else ('back' if y<440 else 'front' if y<830 else 'side')
  cx,top,height=head_anchor(original,rect)
  donor_rect=(max(0,x-45),max(0,y-6),min(original.width,x+w+45)-max(0,x-45),min(original.height,y+h+6)-max(0,y-6))
  dcx,dtop,_=head_anchor(donor,donor_rect)
  dx,dy=round(cx-dcx),top-dtop
  aligned=Image.new('RGBA',original.size)
  crop=donor.crop((donor_rect[0],donor_rect[1],donor_rect[0]+donor_rect[2],donor_rect[1]+donor_rect[3]))
  aligned.paste(crop,(donor_rect[0]+dx,donor_rect[1]+dy))
  mask=Image.new('L',original.size)
  draw=ImageDraw.Draw(mask)
  if v=='back':
   polygons=[[(-.105,.15),(.095,.15),(.135,.22),(.13,.445),(-.13,.445),(-.135,.22)]]
  elif v=='side':
   polygons=[[(-.23,.15),(-.07,.145),(.005,.215),(-.055,.31),(-.09,.405),(-.25,.405),(-.30,.31)]]
  else:
   polygons=[[(-.132,.165),(-.102,.157),(-.085,.24),(-.09,.39),(-.119,.39),(-.125,.25)],[(.092,.158),(.122,.17),(.115,.26),(.12,.39),(.09,.39),(.077,.24)]]
  for poly in polygons:
   draw.polygon([(round(cx+px*height),round(top+py*height)) for px,py in poly],fill=255)
  # Feather only the boundary of the authored gear edit; keep body edges exact.
  mask=mask.filter(ImageFilter.GaussianBlur(0.65))
  ma=np.array(mask)
  base=np.asarray(original)
  paint=np.asarray(aligned)
  if v!='side':
   # Frontal straps and the back panel lie inside the existing body silhouette.
   ma[base[:,:,3]<250]=0
  else:
   # Sleeve and skin remain in front of the bag. The gear may expand only
   # behind the shoulder; it may never broaden head, arm, legs or boots.
   r,g,b=base[:,:,:3].astype(float).transpose(2,0,1)
   sleeve=(r>85)&(g/r.clip(1)>.73)&(b/r.clip(1)>.55)&(base[:,:,3]>240)
   ma[sleeve]=0
  if v=='front':
   r,g,b=base[:,:,:3].astype(float).transpose(2,0,1)
   skin=(r>115)&(r>g*1.18)&(g>b*1.18)&(base[:,:,3]>240)
   ma[skin]=0
  # No donor alpha erosion of body pixels inside the torso.
  ma[(paint[:,:,3]<250)&(base[:,:,3]>0)]=0
  # Hard protection for the original hair/face/neck, independent of donor
  # colors. The back panel begins below the back of the head; frontal
  # straps remain outside the face, and the side bag stays behind it.
  head_bottom=top+int(height*{'back':.16,'front':.215,'side':.205}[v])
  ma[top:head_bottom,round(cx-height*.115):round(cx+height*.115)+1]=0
  mask=Image.fromarray(ma)
  result=Image.composite(aligned,result,mask)
  fullmask=Image.fromarray(np.maximum(np.asarray(fullmask),ma))
  report.append({'sheet':name,'index':idx,'view':v,'rect':list(rect),'alignment':[dx,dy],'gear_pixels':int((ma>0).sum())})
  # Contact sheet: exact same crop/scale for base and composed result.
  roi=(max(0,x-60),max(0,y-8),min(original.width,x+w+60),min(original.height,y+h+8))
  reviews.append((f'{name} {idx}',original.crop(roi),result.crop(roi)))
 result.save(OUT/filename)
 fullmask.save(ROOT/'.tools'/('width-mask-'+filename))
 changed=np.any(np.asarray(result)!=np.asarray(base_canvas),axis=2)
 assert not np.any(changed & (np.asarray(fullmask)==0))
 print(filename,len(rects),'poses',int(changed.sum()),'edited pixels')

(ROOT/'.tools/width-composition-manifest.json').write_text(json.dumps(report,indent=2))
for start in range(0,len(reviews),16):
 tilew,tileh=330,420
 board=Image.new('RGB',(tilew*4,tileh*4),(44,48,52))
 draw=ImageDraw.Draw(board)
 for n,(label,a,b) in enumerate(reviews[start:start+16]):
  col,row=n%4,n//4
  draw.text((col*tilew+8,row*tileh+5),label,fill='white')
  factor=min(155/a.width,390/a.height)
  dims=(round(a.width*factor),round(a.height*factor))
  for j,pic in enumerate([a,b]):
   pic=pic.resize(dims,Image.Resampling.LANCZOS)
   board.paste(pic,(col*tilew+j*165+(165-pic.width)//2,row*tileh+27),pic)
 board.save(ROOT/'.tools'/f'width-art-review-{start//16}.png')
