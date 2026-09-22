"""Capture existing published artwork as editable source layers.

Offline image preparation by Codex, following the owner's explicit permission.
Writes only a new .tools/character-base-capture directory by default. The frozen
manifest/layers in this art directory are intentionally not rewritten.
"""
from pathlib import Path
from hashlib import sha256
import json
import re
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ART = 'art/characters/traveler-base-v1'
OUT = ROOT / '.tools/character-base-capture'
ASSETS = 'assets/characters/courtyard'
PAIRS = {
    'traveler-v1.png': ('side', 'traveler-side-pack-v2.png'),
    'traveler-back-v1.png': ('back', 'traveler-back-pack-v2.png'),
    'traveler-front-v1.png': ('front', 'traveler-front-pack-v2.png'),
    'traveler-run-back-v3.png': ('run-back', 'traveler-run-back-pack-v2.png'),
    'traveler-run-front-v3.png': ('run-front', 'traveler-run-front-pack-v2.png'),
    'traveler-run-side-v3.png': ('run-side', 'traveler-run-side-pack-v2.png'),
    'traveler-pocket-v1.png': ('pocket', 'traveler-pocket-pack-v2.png'),
}

def digest(path):
    return sha256((ROOT / path).read_bytes()).hexdigest()

def text_digest(path):
    return sha256((ROOT / path).read_bytes().replace(b'\r\n', b'\n')).hexdigest()

def capture():
    if OUT.exists():
        raise SystemExit('Capture output already exists; preserve it or choose a fresh checkout.')
    poses = {filename: {} for filename in PAIRS}
    resources = []
    for name in ['traveler_frames.tres', 'traveler_pocket_frames.tres']:
        path = f'{ASSETS}/{name}'
        resources.append({'path': path, 'sha256': text_digest(path)})
        text = (ROOT / path).read_text(encoding='utf-8')
        external = {ident: Path(file).name for file, ident in re.findall(
            r'\[ext_resource type="Texture2D" path="([^"]+)" id="([^"]+)"\]', text)}
        for block in re.findall(r'\[sub_resource type="AtlasTexture"[^\]]+\]\n([^\[]+)', text):
            ident = re.search(r'atlas = ExtResource\("([^"]+)"\)', block).group(1)
            rect = tuple(int(float(n)) for n in re.search(r'region = Rect2\(([^)]+)\)', block).group(1).split(','))
            margin = [float(n) for n in re.search(r'margin = Rect2\(([^)]+)\)', block).group(1).split(',')]
            poses[external[ident]][rect] = margin
    assert sum(map(len, poses.values())) == 84
    sheets = []
    pending = []
    for filename, (key, worn) in PAIRS.items():
        base_path = f'{ASSETS}/{filename}'
        reference = f'{ASSETS}/painted-backpack/{worn}'
        original = Image.open(ROOT / base_path).convert('RGBA')
        finished = Image.open(ROOT / reference).convert('RGBA')
        assert original.size == finished.size == (1254, 1254)
        base = Image.new('RGBA', original.size)
        regions = []
        for i, (rect, margin) in enumerate(sorted(poses[filename].items(), key=lambda p: (p[0][1] // 315, p[0][0]))):
            x, y, w, h = rect
            base.paste(original.crop((x, y, x+w, y+h)), (x, y))
            regions.append({'id': f'{key}-{i:02}', 'rect': list(rect), 'margin': margin})
        a, b = np.asarray(base), np.asarray(finished)
        changed = np.any(a != b, axis=2)
        paint = np.zeros_like(b)
        paint[changed] = b[changed]
        # Binary replacement preserves exact RGBA, including partially transparent
        # edges. Ordinary source-over would darken or thicken those edge pixels.
        mask = np.where(changed, 255, 0).astype('uint8')
        paint_name, mask_name = f'{key}-backpack.png', f'{key}-mask.png'
        pending.extend([(paint_name, Image.fromarray(paint)), (mask_name, Image.fromarray(mask))])
        sheets.append({'id': key, 'base_path': base_path, 'base_sha256': digest(base_path),
                       'size': list(original.size), 'regions': regions,
                       'paint_path': f'{ART}/layers/{paint_name}', 'mask_path': f'{ART}/layers/{mask_name}',
                       'output_name': worn, 'reference_path': reference,
                       'reference_sha256': digest(reference)})
    (OUT / 'layers').mkdir(parents=True)
    for name, image in pending:
        image.save(OUT / 'layers' / name)
    manifest = {'schema': 1, 'base_id': 'traveler-clothed-v1', 'pose_count': 84,
                'composition': 'replace_rgba_binary_mask', 'source_resources': resources,
                'sheets': sheets}
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'CHARACTER_BASE_CAPTURE_OK sheets={len(sheets)} poses=84 layers={len(pending)} output={OUT}')

if __name__ == '__main__':
    capture()
