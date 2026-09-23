"""Pack one coherent walking sheet. Whole cells only; one fixed transform for all poses."""
from pathlib import Path
from PIL import Image
import json,hashlib
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
CELL=384
SCALE=0.75
OFFSET=(0,56)

def build():
    pins=json.loads((HERE/'source-pins.json').read_text())
    for p,h in pins.items():assert hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h,p
    with Image.open(HERE/'walk-source-v2.png') as src:
        assert src.mode=='RGBA' and src.size==(1774,887)
        atlas=Image.new('RGBA',(1536,768));rows=[]
        for i in range(8):
            rect=(round((i%4)*src.width/4),round((i//4)*src.height/2),round((i%4+1)*src.width/4),round((i//4+1)*src.height/2))
            cell=src.crop(rect)
            cell=cell.resize((round(cell.width*SCALE),round(cell.height*SCALE)),Image.Resampling.LANCZOS)
            packed=Image.new('RGBA',(CELL,CELL));packed.alpha_composite(cell,OFFSET)
            b=packed.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
            assert b and b[0]>0 and b[1]>0 and b[2]<CELL and b[3]<CELL,(i,b)
            atlas.alpha_composite(packed,((i%4)*CELL,(i//4)*CELL))
            rows.append({'frame':i,'source_rect':rect,'whole_cell_scale':SCALE,'whole_cell_offset':OFFSET,'alpha_bounds':b})
        atlas.save(HERE/'walk-atlas.png')
    (HERE/'packing.json').write_text(json.dumps({'rows':rows,'per_pose_fitting':False,'limb_transforms':False},indent=2)+'\n',encoding='utf8')
    print('WALK_CONSISTENCY_PACK_OK cells=8 fixed_scale=0.75 fixed_offset=0,56')

if __name__=='__main__':build()
