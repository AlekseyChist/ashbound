"""Pack whole painted cells; no per-pose scale, limbs, masks or bbox fitting.

The committed atlas is the canonical painted input. Without --source-root,
reproduce its SpriteFrames resource. --source-root additionally repacks the
selected original local sheets with the fixed recipe below.
"""
import argparse
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/characters/inn-v1'
CELL = 384
GROUND = 378
SCALE = .75
VIEWS = ('front', 'back', 'side')
ACTIONS = ('idle', 'windup', 'attack', 'hit', 'guard')
RECIPES = {
    'leader': {
        'states': ('leader-states-v2.png', [0, 348, 646, 936, 1208, 1536], [338, 637, 930, 1201, 1509], [202, 511, 835]),
        'side': ('leader-walk-side-v4.png', [502, 421], [0,384,768,1152,1536], [0,512,1024]),
        'fb': ('leader-walk-front-back-v1.png', [0, 328, 638, 943, 1254], [325, 635, 943, 1245]),
        'pixels': (.0078, .0074, .0074),
    },
    'brute': {
        'states': ('brute-states-v2.png', [0,329,630,925,1205,1536], [306,609,903,1180,1481], [203,512,847]),
        'side': ('brute-walk-side-v3.png', [424,423], [0,444,887,1331,1774], [0,444,887]),
        'fb': ('brute-walk-front-back-v1.png', [0,353,680,977,1254], [350,676,975,1243]),
        'back': ('brute-walk-back-v2.png', [497,465]),
        'pixels': (.0095,.0112,.0074,.0055),
    },
    'young': {
        'states': ('young-states-v1.png', [0,350,653,949,1219,1536], [347,650,945,1218,1518], [204,512,836]),
        'side': ('young-walk-side-v1.png', [494,466], [0,384,768,1152,1536], [0,512,1024]),
        'fb': ('young-walk-front-back-v1.png', [0,317,630,938,1254], [316,628,936,1245]),
        'pixels': (.00705,.0061,.00748),
    },
}

def pose_list():
    return [(a, v, 0) for a in ACTIONS for v in VIEWS] + [('walk', v, i) for v in VIEWS for i in range(8)]

def bounds_ok(image, context):
    a = image.getchannel('A').point(lambda v: 255 if v > 64 else 0)
    b = a.getbbox()
    if not b or min(b[:2]) <= 0 or b[2] >= image.width or b[3] >= image.height:
        raise ValueError(f'{context}: empty or clipped whole figure: {b}')

def pack(source_root, recipe):
    result = Image.new('RGBA', (4*CELL, 10*CELL))
    sources = {k: Image.open(source_root / recipe[k][0]).convert('RGBA') for k in ('states', 'side', 'fb')}
    if 'back' in recipe:
        sources['back'] = Image.open(source_root / recipe['back'][0]).convert('RGBA')
    for index, (action, view, frame) in enumerate(pose_list()):
        if action != 'walk':
            row, col = ACTIONS.index(action), VIEWS.index(view)
            _, cuts, floors, roots = recipe['states']
            rect = (col*341, cuts[row], min((col+1)*341,1024), cuts[row+1])
            anchor_x, ground = roots[col]-col*341, floors[row]-cuts[row]
            source = sources['states']
        elif view == 'side':
            row, col = divmod(frame, 4)
            _, floors, xcuts, ycuts = recipe['side']
            rect = (xcuts[col],ycuts[row],xcuts[col+1],ycuts[row+1])
            anchor_x, ground = (xcuts[col+1]-xcuts[col])/2, floors[row]
            source = sources['side']
        elif view == 'back' and 'back' in recipe:
            row,col = divmod(frame,4)
            rect = (col*384,row*512,(col+1)*384,(row+1)*512)
            anchor_x,ground = 192,recipe['back'][1][row]
            source = sources['back']
        else:
            row, col = divmod(frame, 4)
            row += 0 if view == 'front' else 2
            _, cuts, floors = recipe['fb']
            xcuts = [0,314,628,942,1254]
            # Include the transparent separating scanline on both neighbouring
            # whole cells. No pose pixels are shared or trimmed.
            rect = (xcuts[col],cuts[row],xcuts[col+1],cuts[row+1])
            anchor_x, ground = 157, floors[row]-cuts[row]
            source = sources['fb']
            rect = (rect[0],rect[1],rect[2],min(rect[3]+1,source.height))
        whole = source.crop(rect)
        bounds_ok(whole, f'source {action}_{view}/{frame}')
        size = (round(whole.width*SCALE), round(whole.height*SCALE))
        scaled = whole.convert('RGBa').resize(size, Image.Resampling.LANCZOS).convert('RGBA')
        tile = Image.new('RGBA', (CELL,CELL))
        offset = (round(CELL/2-anchor_x*SCALE), round(GROUND-ground*SCALE))
        tile.alpha_composite(scaled, offset)
        bounds_ok(tile, f'packed {action}_{view}/{frame}')
        result.alpha_composite(tile, ((index%4)*CELL,(index//4)*CELL))
    return result

def resource(kind, recipe):
    poses = pose_list()
    lines = ['[gd_resource type="SpriteFrames" load_steps=41 format=3]', '',
             f'[ext_resource type="Texture2D" path="res://assets/characters/inn-v1/thug_{kind}-atlas.png" id="1"]', '']
    for i in range(len(poses)):
        lines += [f'[sub_resource type="AtlasTexture" id="pose_{i}"]', 'atlas = ExtResource("1")',
                  f'region = Rect2({i%4*CELL}, {i//4*CELL}, {CELL}, {CELL})', 'filter_clip = true', '']
    lines += ['[resource]', 'animations = [']
    clips = [(a,v) for a in (*ACTIONS,'walk') for v in VIEWS]
    for n,(a,v) in enumerate(clips):
        ids = [i for i,p in enumerate(poses) if p[:2] == (a,v)]
        entries = ', '.join(f'{{"duration": 1.0, "texture": SubResource("pose_{i}")}}' for i in ids)
        lines += ['{', f'"frames": [{entries}],', f'"loop": {str(a in ("idle","walk")).lower()},',
                  f'"name": &"{a}_{v}",', f'"speed": {15.0 if a == "walk" else 1.0}', '}' + (',' if n<len(clips)-1 else '')]
    lines += [']', f'metadata/baseline_offset_pixels = {GROUND-CELL/2}']
    state_px, side_px, fb_px = recipe['pixels'][:3]
    back_px = recipe['pixels'][3] if len(recipe['pixels']) == 4 else fb_px
    for v in VIEWS:
        lines += [f'metadata/pixel_size_{v} = {state_px}',
                  f'metadata/pixel_size_walk_{v} = {side_px if v == "side" else back_px if v == "back" else fb_px}']
    return '\n'.join(lines)+'\n'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path)
    parser.add_argument('--kind', choices=RECIPES, default='leader')
    args = parser.parse_args()
    recipe = RECIPES[args.kind]
    atlas = pack(args.source_root, recipe) if args.source_root else Image.open(DEST/f'thug_{args.kind}-atlas.png').convert('RGBA')
    assert atlas.size == (1536,3840)
    for i in range(39):
        x,y = i%4*CELL,i//4*CELL
        bounds_ok(atlas.crop((x,y,x+CELL,y+CELL)), f'atlas pose {i}')
    # Validate all inputs before replacing output.
    DEST.mkdir(parents=True, exist_ok=True)
    if args.source_root:
        atlas.save(DEST/f'thug_{args.kind}-atlas.png')
    (DEST/f'thug_{args.kind}_frames.tres').write_text(resource(args.kind,recipe),encoding='utf-8',newline='\n')
    print(f'INN_PACK_OK {args.kind}: 39 whole poses, 18 clips, fixed clip scale, no clipping')

if __name__ == '__main__':
    main()
