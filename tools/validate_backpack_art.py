"""Codex QA: compare protected source pixels, without running the art compositor.
Requires Pillow and numpy. Run from any directory with a suitable Python runtime.
"""
from pathlib import Path
import re
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/characters/courtyard'
PAIRS = {
    'traveler-v1.png': 'traveler-side-pack-v2.png',
    'traveler-back-v1.png': 'traveler-back-pack-v2.png',
    'traveler-front-v1.png': 'traveler-front-pack-v2.png',
    'traveler-run-back-v3.png': 'traveler-run-back-pack-v2.png',
    'traveler-run-front-v3.png': 'traveler-run-front-pack-v2.png',
    'traveler-run-side-v3.png': 'traveler-run-side-pack-v2.png',
    'traveler-pocket-v1.png': 'traveler-pocket-pack-v2.png',
}
images = {}
for bare, worn in PAIRS.items():
    a = Image.open(ASSETS / bare)
    b = Image.open(ASSETS / 'painted-backpack' / worn)
    assert a.size == b.size == (1254, 1254) and b.mode == 'RGBA', worn
    images[bare] = np.asarray(a.convert('RGBA')), np.asarray(b)

seen = set()
protected_pixels = 0
for name in ['traveler_frames.tres', 'traveler_pocket_frames.tres']:
    source = (ASSETS / name).read_text(encoding='utf-8')
    external = dict((ident, Path(file).name) for file, ident in re.findall(
        r'\[ext_resource type="Texture2D" path="([^"]+)" id="([^"]+)"\]', source))
    for ident, values in re.findall(r'atlas = ExtResource\("([^"]+)"\)\s+region = Rect2\(([^)]+)\)', source):
        x, y, width, height = (int(float(n)) for n in values.split(','))
        filename = external[ident]
        key = filename, x, y, width, height
        if key in seen:
            continue
        seen.add(key)
        bare, worn = images[filename]
        # Upper head and the entire lower half cannot be affected by a backpack.
        # Equality catches shape, placement AND pixel color changes, even when
        # a bounding box alone happens to retain its old width.
        for y0, y1 in [(y, y + int(height * .12)), (y + int(height * .55), y + height)]:
            a, b = bare[y0:y1, x:x+width], worn[y0:y1, x:x+width]
            assert np.array_equal(a, b), f'Protected body pixels changed: {key} rows {y0}:{y1}'
            protected_pixels += a.shape[0] * a.shape[1]
assert len(seen) == 84, len(seen)
print(f'ASHBOUND_BACKPACK_ART_OK poses={len(seen)} protected_pixels={protected_pixels}')
