"""Coordinator checks: preserved geography, spatial clearances and deterministic prop bake."""
from pathlib import Path
import hashlib
import json
import math
import subprocess
import sys
import numpy as np

R = Path(__file__).resolve().parents[1]
B = R/'assets/world/graybox-v1'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
layer_path = B/'starter-region.json'
layer = json.loads(layer_path.read_text(encoding='utf8'))
spec = json.loads((R/'docs/design/world-exploration-v1/starter-region.json').read_text(encoding='utf8'))
layout = json.loads((B/'layout.json').read_text(encoding='utf8'))

# The committed world topography and graph are not part of this change.
for rel in ['heights.bin', 'colors.bin', 'layout.json']:
    original = subprocess.check_output(['git', 'show', '7de6c1e:assets/world/graybox-v1/'+rel], cwd=R)
    assert hashlib.sha256(original).hexdigest() == sha(B/rel), 'Changed base geography: '+rel
for path, digest in layer['source_sha256'].items():
    assert sha(R/path) == digest, 'Stale bake: '+path
before = sha(layer_path)
subprocess.run([sys.executable, '-X', 'utf8', str(R/'art/world/graybox-v1/build_starter.py')], cwd=R, check=True)
assert sha(layer_path) == before, 'Non-deterministic prop placement'
assert len(layer['houses']) == 5 and 300 <= len(layer['trees']) <= 700
assert 1000 < sum(layer['route_lengths_m'].values()) < 1100

# Independent segment projection and road-clearance check against the baked world graph.
segments = [(a, b) for road in layout['roads'] for a, b in zip(road['world_points'], road['world_points'][1:])]
a = np.array([[p[0], p[2]] for p, q in segments]); b = np.array([[q[0], q[2]] for p, q in segments])
d = b-a
def road_distance(point):
    t = np.clip(((point-a)*d).sum(axis=1)/(d*d).sum(axis=1), 0, 1)
    return float(np.min(np.linalg.norm(point-a-t[:, None]*d, axis=1)))

for tree in layer['trees']:
    x, y, z, scale, yaw = tree
    assert all(math.isfinite(v) for v in tree)
    assert road_distance([x, z])-2.6*scale > 9, 'Canopy occludes road corridor'
    for c in spec['clearings']:
        assert math.hypot(x+1000-c['center_xz'][0], z+1000-c['center_xz'][1]) >= c['radius_m']
for house in layer['houses']:
    x, y, z = house['origin']; w, h, depth = house['size']
    radius = math.hypot(w, depth)/2+.5
    assert road_distance([x, z])-radius > 6, 'House blocks route'
    assert .3 <= house['foundation'] < 2.0, 'Foundation unexpectedly tall'
    assert math.hypot(x+845, z-420)-radius > 15, 'Starter spawn not clear'
print(f"WORLD_STARTER_DATA_OK houses=5 trees={len(layer['trees'])} immutable_geography=true repeatable=true")
