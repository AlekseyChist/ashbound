"""Bake author-approved cutout artwork into complete RGBA frames; no runtime rig.

Source images are read only. Coordinates and phase tables are artist data in rig.json.
"""
import argparse, hashlib, json, math, shutil, tempfile
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageChops, ImageEnhance, ImageFilter

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
SIZE=384
SCALE=3
def rgba(path): return Image.open(path).convert('RGBA')
def mask(poly, size=(313,313)):
    m=Image.new('L',(size[0]*SCALE,size[1]*SCALE)); ImageDraw.Draw(m).polygon([(x*SCALE,y*SCALE) for x,y in poly],fill=255)
    return m.resize(size,Image.Resampling.LANCZOS)
def part(image,poly):
    p=image.copy();p.putalpha(ImageChops.multiply(p.getchannel('A'),mask(poly)));return p
def affine(image,origin,target,angle=0,scale=1):
    # Inverse sampling in premultiplied alpha prevents dark transparent-edge fringes.
    c,s=math.cos(angle)/scale,math.sin(angle)/scale
    x,y=target;ox,oy=origin
    coeff=(c/SCALE,s/SCALE,ox-c*x-s*y,-s/SCALE,c/SCALE,oy+s*x-c*y)
    return image.convert('RGBa').transform((SIZE*SCALE,SIZE*SCALE),Image.Transform.AFFINE,coeff,Image.Resampling.BICUBIC).convert('RGBA')
def bone(image,a,b,start,end):
    old=math.atan2(b[1]-a[1],b[0]-a[0]);new=math.atan2(end[1]-start[1],end[0]-start[0])
    return affine(image,a,start,new-old)
def knee(hip,ankle,l1,l2):
    dx,dy=ankle[0]-hip[0],ankle[1]-hip[1];dist=math.hypot(dx,dy)
    if dist>l1+l2+0.2:raise ValueError('Unreachable ankle '+str((hip,ankle,dist,l1+l2)))
    along=(l1*l1-l2*l2+dist*dist)/(2*dist);side=math.sqrt(max(0,l1*l1-along*along))
    return (hip[0]+along*dx/dist+side*dy/dist, hip[1]+along*dy/dist-side*dx/dist)
def shade(image,factor):
    a=image.getchannel('A');im=ImageEnhance.Brightness(image).enhance(factor);im.putalpha(a);return im
def source_parts(cfg):
    image=rgba(ROOT/cfg['source']).crop(tuple(cfg['crop']))
    parts={name:part(image,p) for name,p in cfg['parts'].items()}
    body=parts['torso']
    # Restore the vest under the movable shoulder using existing leather pixels,
    # restricted to an explicitly drawn hidden-surface patch; never the head.
    patch=cfg['vest_patch']; leather=image.crop(tuple(patch['sample'])).resize(tuple(patch['size']),Image.Resampling.BICUBIC)
    at=patch['at']; lm=mask(patch['polygon']).crop((at[0],at[1],at[0]+leather.width,at[1]+leather.height))
    leather.putalpha(ImageChops.multiply(leather.getchannel('A'),lm));body.alpha_composite(leather,tuple(at))
    for patch in cfg.get('repairs',[]):
        tex=image.crop(tuple(patch['sample'])).resize(tuple(patch['size']),Image.Resampling.BICUBIC)
        at=patch['at'];m=mask(patch['polygon']).crop((at[0],at[1],at[0]+tex.width,at[1]+tex.height))
        tex.putalpha(ImageChops.multiply(tex.getchannel('A'),m));body.alpha_composite(tex,tuple(at))
    body.putalpha(ImageChops.multiply(body.getchannel('A'),mask(cfg['parts']['torso'])))
    # The upper thigh was hidden by a coat in the source. Extend its actual
    # trouser texture under the coat; never rotate fragments of the coat as a leg.
    patch=cfg['thigh_patch'];tex=image.crop(tuple(patch['sample'])).resize((313,313),Image.Resampling.BICUBIC)
    thigh=part(tex,cfg['parts']['thigh'])
    # Retain the exposed original trouser detail below the marked hem.
    detail=part(image,patch['detail']);thigh.alpha_composite(detail);parts['thigh']=thigh
    # Subtle outer contour, leaving the joint caps unoutlined for overlap.
    d=ImageDraw.Draw(parts['thigh']);
    for edge in patch['edges']:d.line(edge,fill=(43,36,31,220),width=2)
    packed=body.copy()
    original_pack=rgba(ROOT/cfg['packed_source']).crop(tuple(cfg['crop']))
    # Old matched accessory edits are used only as baked production pixels.
    a=np.array(original_pack);b=np.array(image); changed=np.any(a!=b,axis=2)
    accessory=original_pack.copy();allowed=np.array(mask(cfg['pack_area']))>127
    protected=np.array(mask(cfg['protected_head']).filter(ImageFilter.MaxFilter(7)))>0
    allowed &= ~protected
    arm_mask=np.array(mask(cfg['parts']['arm']))>0
    # Shoulder strap paint on the original sleeve belongs to that moving sleeve,
    # not to the static vest repair behind it.
    allowed &= ~arm_mask
    arm_pack=original_pack.copy();arm_pack.putalpha(parts['arm'].getchannel('A'))
    parts['arm_pack']=arm_pack
    accessory.putalpha(Image.fromarray(np.where(changed & allowed,a[:,:,3],0).astype('uint8')))
    packed.alpha_composite(accessory)
    parts['torso_pack']=packed
    return parts
def validate(config):
    if config.get('schema')!=1:raise ValueError('Unsupported rig schema')
    for filename,expected in config['source_sha256'].items():
        if hashlib.sha256((ROOT/filename).read_bytes()).hexdigest()!=expected:
            raise ValueError('Source hash mismatch: '+filename)
    if set(config['actions'])!={'walk','run'}:raise ValueError('Expected walk and run')
    for action,cfg in config['actions'].items():
        for key in ['hip_y','ankles','sole_y','foot_angles','arm_angles']:
            if len(cfg[key])!=8:raise ValueError('Expected eight phases: '+action+'/'+key)
        for key in ['hip_y','sole_y','foot_angles','arm_angles']:
            if not all(math.isfinite(v) for v in cfg[key]):raise ValueError('Non-finite pose parameter')
        if cfg['fps']!=15:raise ValueError('Pose rate changed without contract update')
        if cfg['hip_y'][:4]!=cfg['hip_y'][4:]:raise ValueError('Half cycles must share body height')
        for src in ['source','packed_source']:
            if cfg[src] not in config['source_sha256']:raise ValueError('Unpinned source')
        if max(cfg['sole_y'])!=374:raise ValueError('Foot baseline must remain 374')

def build(config,out):
    validate(config)
    out=out.resolve()
    if not out.is_relative_to(ROOT):raise ValueError('Output must remain inside project')
    out.parent.mkdir(parents=True,exist_ok=True)
    # All frames must finish before replacing any prior exported file.
    with tempfile.TemporaryDirectory(prefix='gait-bake-',dir=out.parent) as tmp:
        draft=Path(tmp);_bake(config,draft)
        manifest={'schema':1,'cell':[384,384],'grid':[4,2],'baseline':374,
            'frames_per_clip':8,'pose_fps':15,'source_sha256':config['source_sha256'],
            'rig_sha256':hashlib.sha256(json.dumps(config,sort_keys=True).encode()).hexdigest(),
            'atlases':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in draft.glob('*.png') if '-part-' not in p.name and p.stem[-1] not in '01234567'}}
        (draft/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
        out.mkdir(parents=True,exist_ok=True)
        for p in draft.iterdir():shutil.copyfile(p,out/p.name)
    print('BAKED poses=32 output='+str(out))

def _bake(config,out):
    out.mkdir(parents=True,exist_ok=True)
    all_poses=[]
    for action,cfg in config['actions'].items():
        parts=source_parts(cfg); results={False:[],True:[]}
        joints=cfg['joints']; l1=math.dist(joints['hip'],joints['knee']);l2=math.dist(joints['knee'],joints['ankle'])
        py,px=np.where(np.array(parts['foot'].getchannel('A'))>127)
        sole=[]
        for angle in cfg['foot_angles']:
            a=math.radians(angle)
            sole.append(float(np.max((px-joints['ankle'][0])*math.sin(a)+(py-joints['ankle'][1])*math.cos(a))))
        for i in range(8):
            hip=(192,cfg['hip_y'][i]);pose={'action':action,'frame':i,'hip':hip,'legs':[],'hands':[]}
            layer=Image.new('RGBA',(SIZE*SCALE,SIZE*SCALE))
            for near in [False,True]:
                phase=i if near else (i+4)%8
                ankle=(192+cfg['ankles'][phase][0],cfg['sole_y'][phase]-sole[phase]); k=knee(hip,ankle,l1,l2)
                f=1 if near else config['far_limb_shade']
                for name,a,b,start,end in [('thigh',joints['hip'],joints['knee'],hip,k),('shin',joints['knee'],joints['ankle'],k,ankle)]:
                    layer.alpha_composite(bone(shade(parts[name],f),a,b,start,end))
                layer.alpha_composite(affine(shade(parts['foot'],f),joints['ankle'],ankle,math.radians(cfg['foot_angles'][phase])))
                pose['legs'].append({'near':near,'ankle':ankle,'knee':k,'phase':phase})
            torso_at=(192,hip[1]); off=(hip[0]-joints['hip'][0],hip[1]-joints['hip'][1])
            shoulder=(joints['shoulder'][0]+off[0],joints['shoulder'][1]+off[1])
            for packed in [False,True]:
                im=layer.copy()
                far_phase=(i+4)%8
                im.alpha_composite(affine(shade(parts['arm'],config['far_limb_shade']),joints['shoulder'],(shoulder[0]-5,shoulder[1]+1),math.radians(cfg['arm_angles'][far_phase])))
                im.alpha_composite(affine(parts['torso_pack' if packed else 'torso'],joints['hip'],torso_at))
                im.alpha_composite(affine(parts['arm_pack' if packed else 'arm'],joints['shoulder'],shoulder,math.radians(cfg['arm_angles'][i])))
                im=im.resize((SIZE,SIZE),Image.Resampling.LANCZOS)
                results[packed].append(im)
                im.save(out/f'{action}-{"pack" if packed else "bare"}-{i}.png')
            for near in [False,True]:
                phase=i if near else (i+4)%8;a=math.radians(cfg['arm_angles'][phase]);dx,dy=np.array(joints['hand'])-np.array(joints['shoulder'])
                pose['hands'].append({'near':near,'xy':[shoulder[0]+dx*math.cos(a)-dy*math.sin(a),shoulder[1]+dx*math.sin(a)+dy*math.cos(a)]})
            all_poses.append(pose)
        for packed,frames in results.items():
            atlas=Image.new('RGBA',(SIZE*4,SIZE*2))
            for i,im in enumerate(frames):atlas.alpha_composite(im,((i%4)*SIZE,(i//4)*SIZE))
            atlas.save(out/f'{action}-{"pack" if packed else "bare"}.png')
            bg=[]
            for im in frames:
                p=Image.new('RGBA',im.size,'#66625b');p.alpha_composite(im);bg.append(p.convert('RGB'))
            bg[0].save(out/f'{action}-{"pack" if packed else "bare"}.gif',save_all=True,append_images=bg[1:],duration=1000/cfg['fps'],loop=0,disposal=2)
        for n,p in parts.items():p.save(out/f'{action}-part-{n}.png')
    (out/'poses.json').write_text(json.dumps(all_poses,indent=2)+'\n',encoding='utf8')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path,default=ROOT/'.tools/side-gait-art');args=parser.parse_args()
    build(json.loads((HERE/'rig.json').read_text(encoding='utf8')),args.out)
