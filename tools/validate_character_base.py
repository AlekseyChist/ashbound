"""Independent acceptance for the frozen-base art workflow (Codex QA).

Uses Pillow/numpy and the project's Godot executable. All fault injection and
Godot writes happen in a disposable project below .tools, never in live art.
"""
from pathlib import Path
from hashlib import sha256
import copy
import json
import re
import shutil
import subprocess
import tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = Path('art/characters/traveler-base-v1')
BUILDER = Path('scripts/tools/build_character_base_layers.gd')
ENGINE = ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
LOGS = ROOT / '.tools/character-base-qa'
MANIFEST = json.loads((ROOT / ART / 'manifest.json').read_text(encoding='utf-8'))

def hash_file(path):
    return sha256(path.read_bytes()).hexdigest()

def verify_pose_inventory():
    actual = {}
    for resource in MANIFEST['source_resources']:
        file = ROOT / resource['path']
        assert sha256(file.read_bytes().replace(b'\r\n',b'\n')).hexdigest() == resource['sha256'], file
        text = file.read_text(encoding='utf-8')
        external = {ident: path.removeprefix('res://') for path, ident in re.findall(
            r'\[ext_resource type="Texture2D" path="([^"]+)" id="([^"]+)"\]', text)}
        # Read the deployed SpriteFrames themselves, not the capture helper.
        for ident, coords, margins in re.findall(
                r'atlas = ExtResource\("([^"]+)"\)\s+region = Rect2\(([^)]+)\)\s+margin = Rect2\(([^)]+)\)', text):
            rect = tuple(int(float(v)) for v in coords.split(','))
            margin = tuple(float(v) for v in margins.split(','))
            actual[external[ident], rect] = margin
    declared = {(s['base_path'], tuple(p['rect'])): tuple(p['margin'])
                for s in MANIFEST['sheets'] for p in s['regions']}
    assert actual == declared and len(actual) == 84, 'Frozen pose inventory differs from deployed base'
    print('PASS deployed pose inventory and anchors: 84', flush=True)

def contact_sheet(export):
    font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 18)
    # Select actual clip entries, never guess an action from atlas row order.
    clips = {}
    for resource in MANIFEST['source_resources']:
        text = (ROOT/resource['path']).read_text(encoding='utf-8')
        external = {ident: path.removeprefix('res://') for path, ident in re.findall(
            r'\[ext_resource type="Texture2D" path="([^"]+)" id="([^"]+)"\]', text)}
        frames = {atlas_id: (external[texture_id], [int(float(v)) for v in coords.split(',')])
                  for atlas_id, texture_id, coords in re.findall(
                      r'\[sub_resource type="AtlasTexture" id="([^"]+)"\]\s+atlas = ExtResource\("([^"]+)"\)\s+region = Rect2\(([^)]+)\)', text)}
        for content, name in re.findall(r'"frames": \[(.*?)\],\s*"loop": [^,]+,\s*"name": &"([^"]+)"', text, re.S):
            first = re.search(r'SubResource\("([^"]+)"\)', content).group(1)
            clips[name] = frames[first]
    examples = [f'{action}_{view}' for action in ['idle','walk','run','attack','pocket'] for view in ['side','front','back']]
    sheets = {s['base_path']: s for s in MANIFEST['sheets']}
    board = Image.new('RGB', (1440, 1300), '#292d32')
    draw = ImageDraw.Draw(board)
    for i, name in enumerate(examples):
        source, rect = clips[name]
        s = sheets[source]
        x, y, w, h = rect
        roi = (max(0,x-55), max(0,y-4), min(1254,x+w+55), min(1254,y+h+4))
        base = Image.open(ROOT / s['base_path']).convert('RGBA').crop(roi)
        paint = Image.open(ROOT / s['paint_path']).convert('RGBA').crop(roi)
        result = Image.open(export / s['output_name']).convert('RGBA').crop(roi)
        ox, oy = (i % 3) * 480, (i // 3) * 260
        draw.text((ox+8,oy+6), f'{name}: base | paint | final', font=font, fill='white')
        scale = min(150/base.width, 220/base.height)
        size = (round(base.width*scale), round(base.height*scale))
        for j, picture in enumerate([base, paint, result]):
            picture = picture.resize(size, Image.Resampling.LANCZOS)
            board.paste(picture, (ox+j*160+(160-size[0])//2,oy+32), picture)
    board.save(LOGS / 'base-paint-final.png')

def main():
    LOGS.mkdir(parents=True, exist_ok=True)
    verify_pose_inventory()
    inputs = {str(ART/'manifest.json'), str(BUILDER)}
    inputs.update(r['path'] for r in MANIFEST['source_resources'])
    for s in MANIFEST['sheets']:
        inputs.update(s[k] for k in ['base_path', 'paint_path', 'mask_path', 'reference_path'])
    fingerprints = {f: hash_file(ROOT/f) for f in inputs}
    with tempfile.TemporaryDirectory(prefix='character-base-', dir=ROOT/'.tools') as directory:
        stage = Path(directory).resolve()
        assert stage.is_relative_to((ROOT/'.tools').resolve())
        for f in inputs:
            target = stage/f
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/f, target)
        (stage/'project.godot').write_text('[application]\nconfig/name="Character Base QA"\n', encoding='utf-8')
        output = stage/'.tools/character-base/export'

        def run(name, valid=True, args=()):
            before = {p.name: (hash_file(p), p.stat().st_mtime_ns) for p in output.glob('*.png')} if output.exists() else {}
            result = subprocess.run([str(ENGINE), '--headless', '--path', str(stage), '--script',
                                     'res://'+BUILDER.as_posix(), '--', *args],
                                    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=100)
            log = result.stdout+result.stderr
            (LOGS/(name+'.log')).write_text(log, encoding='utf-8')
            assert not re.search(r'SCRIPT ERROR:|^ERROR:', log, re.M), (name, log)
            if valid:
                assert result.returncode == 0 and 'ASHBOUND_CHARACTER_BASE_BUILD_OK sheets=7 poses=84' in log, (name, log)
            else:
                assert result.returncode != 0 and 'CHARACTER_BASE_BUILD_FAIL' in log and 'BUILD_OK' not in log, (name, log)
                after = {p.name: (hash_file(p), p.stat().st_mtime_ns) for p in output.glob('*.png')} if output.exists() else {}
                assert before == after, f'Failed validation changed prior output: {name}'
            print('PASS '+name, flush=True)

        run('baseline')
        total_pixels = 0
        for s in MANIFEST['sheets']:
            a = np.asarray(Image.open(ROOT/s['reference_path']).convert('RGBA'))
            b = np.asarray(Image.open(output/s['output_name']).convert('RGBA'))
            assert np.array_equal(a, b), 'Final image differs from 0.15.2: '+s['id']
            total_pixels += a.shape[0]*a.shape[1]
        assert len(list(output.glob('*.png'))) == 7
        print(f'PASS exact final RGBA: {total_pixels} pixels across 7 atlases', flush=True)
        final_export = LOGS/'export'
        final_export.mkdir(exist_ok=True)
        for file in output.glob('*.png'):
            shutil.copyfile(file, final_export/file.name)
        contact_sheet(final_export)

        # Git's autocrlf must not make a fresh checkout appear to change poses.
        for r in MANIFEST['source_resources']:
            file = stage/r['path']
            file.write_bytes(file.read_bytes().replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'))
        run('fresh-checkout-crlf')
        for r in MANIFEST['source_resources']:
            shutil.copyfile(ROOT/r['path'],stage/r['path'])

        def manifest_case(name, mutate):
            fixture = copy.deepcopy(MANIFEST)
            mutate(fixture)
            (stage/'.tools/fixture.json').write_text(json.dumps(fixture), encoding='utf-8')
            run(name, False, ['--manifest', 'res://.tools/fixture.json'])

        base_path = stage/MANIFEST['sheets'][0]['base_path']
        original_base = base_path.read_bytes()
        changed_base = Image.open(base_path).convert('RGBA')
        changed_base.putpixel((100,100),(255,0,0,255))
        changed_base.save(base_path)
        run('changed-base-image', False)
        base_path.write_bytes(original_base)
        manifest_case('changed-pose-resource', lambda m: m['source_resources'][0].update(sha256='0'*64))
        manifest_case('bad-json-type', lambda m: m.update(sheets='not an array'))
        manifest_case('bad-schema-type', lambda m: m.update(schema={}))
        manifest_case('fractional-canvas-size', lambda m: m['sheets'][0]['size'].__setitem__(0,1254.5))
        manifest_case('duplicate-output-name', lambda m: m['sheets'][-1].update(output_name=m['sheets'][0]['output_name']))
        manifest_case('windows-case-collision', lambda m: m['sheets'][-1].update(output_name=m['sheets'][0]['output_name'].removesuffix('.png').upper()+'.png'))
        manifest_case('windows-invalid-basename', lambda m: m['sheets'][-1].update(output_name='good.bad:name.png'))
        manifest_case('incomplete-last-sheet', lambda m: m['sheets'][-1].pop('mask_path'))
        manifest_case('fractional-rectangle', lambda m: m['sheets'][0]['regions'][0]['rect'].__setitem__(0, 86.5))
        manifest_case('rectangle-outside-canvas', lambda m: m['sheets'][0]['regions'][0]['rect'].__setitem__(2, 2000))
        manifest_case('unsafe-output-name', lambda m: m['sheets'][-1].update(output_name='../escape.png'))
        manifest_case('missing-paint', lambda m: m['sheets'][-1].update(paint_path=ART.as_posix()+'/layers/absent.png'))
        run('refuse-runtime-overwrite', False, ['--output-dir', 'res://assets/characters/courtyard'])

        s = MANIFEST['sheets'][0]
        mask_path = stage/s['mask_path']
        original_mask = mask_path.read_bytes()
        mask = Image.open(mask_path).convert('L')
        x,y,w,h = s['regions'][0]['rect']
        mask.putpixel((x+w//2,y+10),255)
        mask.save(mask_path)
        run('refuse-head-repaint', False)
        mask_path.write_bytes(original_mask)
        mask = Image.open(mask_path).convert('L')
        mask.putpixel((0,0),128)
        mask.save(mask_path)
        run('refuse-soft-mask', False)
        mask_path.write_bytes(original_mask)
        Image.new('L',(16,16)).save(mask_path)
        run('refuse-wrong-layer-size', False)
        mask_path.write_bytes(original_mask)

        # Prove this is editable equipment, not a disguised copy of old output.
        paint_path = stage/s['paint_path']
        paint = Image.open(paint_path).convert('RGBA')
        mask_array = np.asarray(Image.open(mask_path))
        paint_array = np.asarray(paint)
        yy,xx = np.nonzero((mask_array==255)&(paint_array[:,:,3]==255))
        px,py = int(xx[len(xx)//2]),int(yy[len(yy)//2])
        paint.putpixel((px,py),(17,211,103,255))
        paint.save(paint_path)
        run('allowed-equipment-repaint')
        edited = np.asarray(Image.open(output/s['output_name']).convert('RGBA'))
        expected = np.array(Image.open(ROOT/s['reference_path']).convert('RGBA'))
        expected[py,px] = [17,211,103,255]
        assert np.array_equal(edited,expected), 'Equipment edit affected other body pixels'
        for other in MANIFEST['sheets'][1:]:
            assert np.array_equal(np.asarray(Image.open(output/other['output_name'])),
                                  np.asarray(Image.open(ROOT/other['reference_path']))), other['id']
    assert all(hash_file(ROOT/f)==h for f,h in fingerprints.items()), 'Live inputs changed during QA'
    print(f'ASHBOUND_CHARACTER_BASE_QA_OK baseline_pixels={total_pixels} rejected=17 crlf=1 edit=1 inputs_unchanged=1', flush=True)

if __name__ == '__main__':
    main()
