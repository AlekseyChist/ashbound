"""Pack complete painted poses. No articulated parts, recoloring or morphing."""
from pathlib import Path
import hashlib, json
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LAB = HERE.parent / 'sprite-gait-lab'
OUTPUT = ROOT / 'assets/characters/courtyard/painted-motion-v2'
CELL, GROUND, SCALE = 384, 375, 0.53
# Existing runtime run_side pixel size is 0.9 * side. Compensate uniformly
# for the WHOLE run clip during packing, preserving legacy equipment metadata.
RUN_SCALE = SCALE / 0.9

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def build():
    pins = json.loads((HERE / 'pins.json').read_text(encoding='utf-8'))
    for relative, expected in pins.items():
        path = ROOT / relative
        if sha(path) != expected:
            raise ValueError('Source changed: ' + relative)
    data = json.loads((LAB / 'frames.js').read_text(encoding='utf-8').split('=', 1)[1].strip().rstrip(';'))
    walk, run = [], []
    for key in data['variants']['final']['frames']:
        pose = data['poses'][key]
        x, y, w, h = pose['rect']
        with Image.open(LAB / pose['file']) as image:
            assert image.mode == 'RGBA'
            art = image.crop((x, y, x+w, y+h))
        walk.append((key, art, tuple(pose['pivot']), 627/w))
    with Image.open(HERE / 'run-source.png') as image:
        assert image.mode == 'RGBA'
        assert abs(image.width / image.height - 2) < .01
        cw, ch = image.width/4, image.height/2
        for i in range(8):
            x, y = (i%4)*cw, (i//4)*ch
            art = image.crop((round(x), round(y), round(x+cw), round(y+ch)))
            mask = art.getchannel('A').point(lambda a: 255 if a > 96 else 0)
            bounds = mask.getbbox()
            head = mask.crop((0,0,art.width,round(ch*.24))).getbbox()
            assert bounds and head
            normalization = 627/cw
            run.append((str(i),art,(head[2]*normalization-60,bounds[3]*normalization),normalization))
    # Generated layout is not trusted as an anatomy label: actual phase inspection
    # places opposite-side toe-off/flight before that side's contact.
    order = [0,1,6,7,4,5,2,3]
    for i in [2,3,6,7]:
        key,art,(px,_),normalization = run[i]
        row = 0 if i < 4 else 4
        floor = max(run[row][2][1],run[row+1][2][1])
        run[i] = (key,art,(px,floor),normalization)
    outputs, manifest = {}, {'cell':CELL,'ground':GROUND,'walk_scale':SCALE,'run_scale':RUN_SCALE,'run_source_order':order,'clips':{}}
    for name, poses in [('walk',walk),('run',[run[i] for i in order])]:
        assert len(poses) == 8
        scale = RUN_SCALE if name == 'run' else SCALE
        atlas = Image.new('RGBA',(CELL*4,CELL*2))
        rows=[]
        for i,(key,art,(px,py),normalization) in enumerate(poses):
            size=(round(art.width*normalization*scale),round(art.height*normalization*scale))
            scaled=art.resize(size,Image.Resampling.LANCZOS)
            x,y=round(CELL/2-px*scale),round(GROUND-py*scale)
            b=scaled.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
            assert b and x+b[0]>=0 and y+b[1]>=0 and x+b[2]<CELL and y+b[3]<CELL, (name,i,b,x,y)
            cell=Image.new('RGBA',(CELL,CELL))
            cell.alpha_composite(scaled,(x,y))
            atlas.alpha_composite(cell,((i%4)*CELL,(i//4)*CELL))
            rows.append({'index':i,'source_pose':key,'pivot':[px,py],'offset':[x,y],'bounds':[x+b[0],y+b[1],x+b[2],y+b[3]]})
        outputs[name]=atlas
        manifest['clips'][name]=rows
    # Validate the complete batch before replacing any output.
    OUTPUT.mkdir(parents=True,exist_ok=True)
    for name,atlas in outputs.items():
        atlas.save(OUTPUT/(name+'.png'))
    (HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('PAINTED_MOTION_PACK_OK 16 complete drawings; fixed scale; RGBA')

if __name__ == '__main__':
    build()
