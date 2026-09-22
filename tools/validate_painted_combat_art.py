"""Read-only Codex acceptance of generated RGBA animation atlases."""
from pathlib import Path
from PIL import Image
import numpy as np
import hashlib
import json

root = Path(__file__).resolve().parents[1]
folder = root / 'assets/vfx/painted-combat-v1'
records = []
failures = []
decoded_bytes = 0
for kind in ['hit', 'block', 'perfect_block', 'windup', 'swing']:
    file = folder / (kind + '.png')
    if not file.exists():
        failures.append(f'{kind}: missing atlas')
        continue
    im = Image.open(file)
    if im.mode != 'RGBA':
        failures.append(f'{kind}: expected original RGBA, got {im.mode}')
        continue
    a = np.asarray(im)
    h, w = a.shape[:2]
    decoded_bytes += a.nbytes
    if w != h or w % 2 or h % 2:
        failures.append(f'{kind}: cannot divide square sheet into exact 2x2 cells')
        continue
    if (a[:, :, 3] == 0).mean() < .40:
        failures.append(f'{kind}: insufficient real alpha background')
    cells, hashes = [], []
    for y in range(2):
        for x in range(2):
            cell = a[y*h//2:(y+1)*h//2, x*w//2:(x+1)*w//2]
            alpha = cell[:, :, 3]
            visible = alpha > 32
            if not visible.any():
                failures.append(f'{kind}: empty frame {len(cells)}')
                continue
            yy, xx = np.where(visible)
            if min(xx.min(), yy.min(), w//2-1-xx.max(), h//2-1-yy.max()) < 3:
                failures.append(f'{kind}: visible artwork crosses frame edge {len(cells)}')
            if not .004 < visible.mean() < .70:
                failures.append(f'{kind}: unreadable frame coverage {len(cells)}')
            hashes.append(hashlib.sha256(cell.tobytes()).hexdigest())
            cells.append({'coverage': round(float(visible.mean()), 4), 'bounds': [int(xx.min()), int(yy.min()), int(xx.max()), int(yy.max())]})
    if len(set(hashes)) != 4:
        failures.append(f'{kind}: four distinct animation frames required')
    records.append({'kind': kind, 'size': [w, h], 'alpha_zero_fraction': round(float((a[:,:,3] == 0).mean()), 4), 'cells': cells, 'sha256': hashlib.sha256(file.read_bytes()).hexdigest()})
if decoded_bytes > 48 * 1024 * 1024:
    failures.append('decoded five-atlas budget exceeds 48 MiB')
out = root / '.tools/painted-art-report.json'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({'atlases': records, 'decoded_bytes': decoded_bytes, 'failures': failures}, indent=2), encoding='utf-8')
for failure in failures:
    print('PAINTED_ART_FAIL:', failure)
if failures:
    raise SystemExit(1)
print(f'ASHBOUND_PAINTED_ART_OK atlases=5 frames=20 decoded_bytes={decoded_bytes}')
