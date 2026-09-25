"""Coordinator checks exported geometry, independent of generator-reported stats."""
from pathlib import Path
import json, struct, math, hashlib
ROOT = Path(__file__).resolve().parents[3]
NAMES = ['pine_tall', 'spruce', 'pine_young', 'boulder', 'stump', 'fern', 'grass']
out = {}
for name in NAMES:
    p = ROOT/'assets/environment/village-forest-v1'/f'{name}.glb'
    b = p.read_bytes()
    magic,version,length = struct.unpack_from('<III',b)
    assert magic == 0x46546c67 and version == 2 and length == len(b), name
    n = struct.unpack_from('<I',b,12)[0]; g = json.loads(b[20:20+n])
    assert not g.get('cameras') and 'KHR_lights_punctual' not in g.get('extensions',{}), name
    triangles = 0
    low = [float('inf')]*3; high = [float('-inf')]*3
    for mesh in g['meshes']:
        assert len(mesh['primitives']) <= 3, name
        for primitive in mesh['primitives']:
            triangles += g['accessors'][primitive['indices']]['count']//3
            position = g['accessors'][primitive['attributes']['POSITION']]
            assert all(math.isfinite(v) for v in position['min']+position['max']), name
            for i in range(3):
                low[i] = min(low[i],position['min'][i]); high[i] = max(high[i],position['max'][i])
    assert triangles <= (5000 if name.startswith('pine') or name=='spruce' else 1500), (name,triangles)
    assert len(g['meshes']) <= 3 and len(g.get('materials',[])) <= 3, name
    assert (ROOT/'art/blender/village-forest-v1'/f'{name}.blend').exists(), name
    assert (ROOT/'local/previews/village-forest-v1'/f'{name}.png').exists(), name
    out[name] = {'triangles':triangles,'mesh_count':len(g['meshes']),'materials':len(g.get('materials',[])), 'sha256':hashlib.sha256(b).hexdigest()}
(ROOT/'art/blender/village-forest-v1/checks.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print('FOREST_KIT_CHECKS_PASS assets=7',json.dumps(out))
