"""Bake a reproducible prop layer on the unchanged world terrain and road graph."""
from pathlib import Path
import hashlib
import json
import math
import random
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'docs/design/world-exploration-v1/starter-region.json'
BASE = ROOT / 'assets/world/graybox-v1'


def bake():
    spec = json.loads(SOURCE.read_text(encoding='utf8'))
    layout = json.loads((BASE / 'layout.json').read_text(encoding='utf8'))
    heights = np.fromfile(BASE / 'heights.bin', dtype='<f4').reshape(401, 401)

    def ground(x, z):
        gx, gz = x / 5, z / 5
        ix, iz = int(gx), int(gz)
        u, v = gx - ix, gz - iz
        a, b, c, d = map(float, (heights[iz, ix], heights[iz, ix + 1], heights[iz + 1, ix], heights[iz + 1, ix + 1]))
        return a + (b-a)*u + (c-a)*v if u+v <= 1 else d+(c-d)*(1-u)+(b-d)*(1-v)

    # Dense baked road points are <=2m apart; use exact segment distance, not point clearance.
    def segments(roads):
        a, b = [], []
        for road in roads:
            p = np.array(road['world_points'])[:, [0, 2]] + 1000
            a.extend(p[:-1]); b.extend(p[1:])
        return np.array(a), np.array(b)

    def distance(point, seg):
        a, b = seg
        delta = b-a
        t = np.clip(np.sum((point-a)*delta, axis=1)/np.sum(delta*delta, axis=1), 0, 1)
        return float(np.min(np.linalg.norm(point-a-t[:, None]*delta, axis=1)))

    all_roads = segments(layout['roads'])
    local_roads = [r for r in layout['roads'] if r['id'] in spec['routes']]
    local_segments = segments(local_roads)
    water = segments(layout['rivers'])
    houses = []
    for house in spec['houses']:
        x, z = house['center_xz']
        width, height, depth = house['size']
        yaw = math.atan2(155-x, 1420-z)  # local +Z doorway faces the square
        # Sample footprint densely; bury the foundation below the lowest ground corner.
        samples = [ground(x+math.cos(yaw)*a+math.sin(yaw)*b, z-math.sin(yaw)*a+math.cos(yaw)*b)
                   for a in np.linspace(-width/2, width/2, 7) for b in np.linspace(-depth/2, depth/2, 7)]
        bottom = min(samples)-.2
        houses.append({**house, 'origin': [x-1000, bottom, z-1000], 'yaw': yaw,
                       'foundation': max(samples)+.15-bottom})

    rng = random.Random(spec['seed'])
    trees = []
    x0, z0, x1, z1 = spec['bounds_xz']
    for z in range(z0, z1, spec['forest_grid_m']):
        for x in range(x0, x1, spec['forest_grid_m']):
            px, pz = x+rng.uniform(-4, 4), z+rng.uniform(-4, 4)
            scale, yaw = rng.uniform(.78, 1.3), rng.uniform(-math.pi, math.pi)
            if not (x0 <= px <= x1 and z0 <= pz <= z1): continue
            local_d = distance([px, pz], local_segments)
            if not spec['forest_path_distance_m'][0] <= local_d <= spec['forest_path_distance_m'][1]: continue
            if distance([px, pz], all_roads) < 13 or distance([px, pz], water) < 22: continue
            if any(math.hypot(px-c['center_xz'][0], pz-c['center_xz'][1]) < c['radius_m'] for c in spec['clearings']): continue
            if any(math.hypot(px-h['center_xz'][0], pz-h['center_xz'][1]) < 15 for h in houses): continue
            # Keep the lowland boundary open; this task is only the forest district.
            if pz > 1390+110*math.sin(px/200): continue
            y = ground(px, pz)
            # Trunks start slightly underground; avoid conspicuous steep-slope intersections.
            slopes = [abs(ground(px+dx, pz+dz)-y) for dx, dz in [(2, 0), (-2, 0), (0, 2), (0, -2)]]
            if max(slopes) > 1.2: continue
            trees.append([px-1000, y-.12, pz-1000, scale, yaw])

    lengths = {r['id']: sum(math.dist(a, b) for a, b in zip(r['world_points'], r['world_points'][1:])) for r in local_roads}
    files = [SOURCE, BASE/'heights.bin', BASE/'layout.json']
    output = {'version': spec['version'], 'source_sha256': {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
              'houses': houses, 'trees': trees, 'route_lengths_m': lengths, 'limits': spec['limits']}
    (BASE/'starter-region.json').write_text(json.dumps(output, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8', newline='\n')
    print(f'STARTER_BAKE_OK houses={len(houses)} trees={len(trees)} route_m={sum(lengths.values()):.1f}')


if __name__ == '__main__':
    bake()
