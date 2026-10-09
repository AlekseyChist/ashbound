"""Pack full painted keeper poses; reproduce resources from canonical game atlas."""
import argparse
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/characters/inn-v1'
CELL, GROUND, SCALE = 384, 378, .9
VIEWS = ('front', 'back', 'side')
CUTS = (0, 392, 771, 1150, 1536)
FLOORS = (389, 768, 1147, 1529)
ROOTS = (240, 535, 812)

def validate(image, label):
    box = image.getchannel('A').point(lambda v: 255 if v > 64 else 0).getbbox()
    if not box or min(box[:2]) <= 0 or box[2] >= image.width or box[3] >= image.height:
        raise ValueError(f'{label}: empty/clipped full figure {box}')

def pack(source):
    image = Image.open(source).convert('RGBA')
    if image.size != (1024, 1536):
        raise ValueError('Unexpected source dimensions')
    atlas = Image.new('RGBA', (CELL * 3, CELL * 4))
    for row in range(4):
        for col in range(3):
            whole = image.crop((col * 341, CUTS[row], min((col+1)*341,1024), CUTS[row+1]))
            validate(whole, f'source {row}/{col}')
            size = tuple(round(v*SCALE) for v in whole.size)
            scaled = whole.convert('RGBa').resize(size, Image.Resampling.LANCZOS).convert('RGBA')
            tile = Image.new('RGBA', (CELL,CELL))
            tile.alpha_composite(scaled, (round(CELL/2-(ROOTS[col]-col*341)*SCALE),
                                         round(GROUND-(FLOORS[row]-CUTS[row])*SCALE)))
            validate(tile, f'packed {row}/{col}')
            atlas.alpha_composite(tile, (col*CELL,row*CELL))
    return atlas

def resource():
    lines = ['[gd_resource type="SpriteFrames" load_steps=14 format=3]', '',
             '[ext_resource type="Texture2D" path="res://assets/characters/inn-v1/innkeeper-atlas.png" id="1"]','']
    for row in range(4):
        for col in range(3):
            i = row*3+col
            lines += [f'[sub_resource type="AtlasTexture" id="pose_{i}"]','atlas = ExtResource("1")',
                      f'region = Rect2({col*CELL}, {row*CELL}, {CELL}, {CELL})','filter_clip = true','']
    lines += ['[resource]', 'animations = [']
    clips = [(a,v) for a in ('idle','talk') for v in VIEWS]
    for n,(action,view) in enumerate(clips):
        col = VIEWS.index(view)
        ids = [col] if action == 'idle' else [3+col,6+col,9+col,6+col]
        frames = ', '.join(f'{{"duration": 1.0, "texture": SubResource("pose_{i}")}}' for i in ids)
        lines += ['{',f'"frames": [{frames}],','"loop": true,',f'"name": &"{action}_{view}",',
                  f'"speed": {4.0 if action == "talk" else 1.0}', '}' + (',' if n<len(clips)-1 else '')]
    lines += [']',f'metadata/baseline_offset_pixels = {GROUND-CELL/2}']
    for view in VIEWS:
        lines += [f'metadata/pixel_size_{view} = 0.0057',f'metadata/pixel_size_talk_{view} = 0.0057']
    return '\n'.join(lines)+'\n'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path)
    args = parser.parse_args()
    atlas = pack(args.source) if args.source else Image.open(DEST/'innkeeper-atlas.png').convert('RGBA')
    if atlas.size != (1152,1536):
        raise ValueError('Unexpected atlas dimensions')
    for row in range(4):
        for col in range(3):
            validate(atlas.crop((col*CELL,row*CELL,(col+1)*CELL,(row+1)*CELL)),f'atlas {row}/{col}')
    DEST.mkdir(parents=True,exist_ok=True)
    if args.source:
        atlas.save(DEST/'innkeeper-atlas.png')
    (DEST/'innkeeper_frames.tres').write_text(resource(),encoding='utf-8',newline='\n')
    print('INNKEEPER_PACK_OK 12 whole poses, 6 idle/talk clips; walk pending')

if __name__ == '__main__':
    main()
