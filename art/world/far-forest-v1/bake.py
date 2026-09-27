# WORLD-DRESS-01A (D-097): bake where forest clumps stand on the 2 x 2 km world map.
# Input: assets/world/graybox-v1 (layout.json, heights.bin, colors.bin). Output:
# assets/world/far-forest-v1/instances.bin = float32 records (map_x, map_z, scale, yaw, tint).
# Deterministic: same inputs and SEED give the same file. Run: python art/world/far-forest-v1/bake.py
import json, math, os, random, struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
SRC = os.path.join(ROOT, 'assets/world/graybox-v1')
# FOREST_OUT: write elsewhere first when Windows folder protection blocks Python in Documents; copy after.
OUT = os.environ.get('FOREST_OUT', os.path.join(ROOT, 'assets/world/far-forest-v1/instances.bin'))
SEED = 270926
N, S = 401, 5.0
CELL = 8.0                      # one candidate per 8 x 8 m cell, jittered
TREELINE = (280.0, 330.0)       # metres: forest thins out, then stops
SLOPE = (30.0, 38.0)            # degrees: thins out, then stops
# Places kept clear (map metres). The village and the trail to the inn keep their own real trees.
VILLAGE_RECT = (45.0, 1335.0, 270.0, 1510.0)
VILLAGE_CLEAR = 120.0
TRAIL_CLEAR = 50.0
CITY_CLEAR = 140.0
RUINS = ((1180.0, 1230.0), 150.0)   # atlas v1: the dead plateau with the capital ruins stays bare
SITE_CLEAR = {'settlement': 45.0, 'tavern': 40.0, 'cave': 25.0, 'mine': 45.0, 'lake': 20.0, 'spring_cave': 30.0}
ROAD_MARGIN = 5.0
RIVER_MARGIN = 4.0

layout = json.load(open(os.path.join(SRC, 'layout.json'), encoding='utf-8'))
H = struct.unpack('<%df' % (N * N), open(os.path.join(SRC, 'heights.bin'), 'rb').read())
C = struct.unpack('<%df' % (N * N * 4), open(os.path.join(SRC, 'colors.bin'), 'rb').read())

def height(x, z):
    gx = min(max(x / S, 0.0), N - 1.001); gz = min(max(z / S, 0.0), N - 1.001)
    i, j = int(gx), int(gz); u, v = gx - i, gz - j
    a, b = H[j * N + i], H[j * N + i + 1]; c, d = H[(j + 1) * N + i], H[(j + 1) * N + i + 1]
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v

def colour(x, z):
    i = min(max(int(round(x / S)), 0), N - 1); j = min(max(int(round(z / S)), 0), N - 1)
    k = (j * N + i) * 4
    return C[k], C[k + 1], C[k + 2]

def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)

# Biome weight from the baked map colour: conifer forest green -> 1, lowland teal -> sparse, else none.
def biome(x, z):
    r, g, b = colour(x, z)
    forest = smooth(0.03, 0.07, g - max(r, b))
    lowland = smooth(0.02, 0.05, g - r) * smooth(0.16, 0.19, b)
    return max(forest * (1.0 - 0.65 * lowland), 0.35 * lowland)

def slope_deg(x, z):
    dx = (height(x + 2.5, z) - height(x - 2.5, z)) / 5.0
    dz = (height(x, z + 2.5) - height(x, z - 2.5)) / 5.0
    return math.degrees(math.atan(math.hypot(dx, dz)))

# Value noise for forest masses and clearings (two octaves, ~150 m and ~50 m).
rng = random.Random(SEED)
LAT = {}
def lattice(ix, iz, octave):
    key = (ix, iz, octave)
    if key not in LAT:
        LAT[key] = random.Random(hash(key) ^ SEED).random()
    return LAT[key]
def value_noise(x, z, size, octave):
    gx, gz = x / size, z / size
    i, j = math.floor(gx), math.floor(gz); u, v = gx - i, gz - j
    u, v = u * u * (3 - 2 * u), v * v * (3 - 2 * v)
    a, b = lattice(i, j, octave), lattice(i + 1, j, octave)
    c, d = lattice(i, j + 1, octave), lattice(i + 1, j + 1, octave)
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v
def masses(x, z):
    return 0.7 * value_noise(x, z, 150.0, 1) + 0.3 * value_noise(x, z, 50.0, 2)

def seg_dist(px, pz, ax, az, bx, bz):
    vx, vz = bx - ax, bz - az
    l2 = vx * vx + vz * vz
    t = 0.0 if l2 == 0 else min(max(((px - ax) * vx + (pz - az) * vz) / l2, 0.0), 1.0)
    return math.hypot(px - (ax + t * vx), pz - (az + t * vz))

# Clear corridors: (polyline, half width to keep clear)
corridors = []
for road in layout['roads']:
    pts = [(p[0], p[1]) for p in road['points']]
    clear = float(road.get('width_m', 6.0)) * 0.5 + ROAD_MARGIN
    if road['id'] == 'start_trail':
        clear = max(clear, TRAIL_CLEAR)
    corridors.append((pts, clear))
for river in layout['rivers']:
    pts = [(p[0], p[1]) for p in river['points']]
    widths = river.get('widths_m') or [12.0]
    corridors.append((pts, max(widths) * 0.5 + RIVER_MARGIN))
# Bucket corridor segments on a coarse grid for quick distance checks.
BUCKET = 100.0
buckets = {}
for pts, clear in corridors:
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        x0, x1 = sorted((ax, bx)); z0, z1 = sorted((az, bz))
        for bi in range(int((x0 - clear) // BUCKET), int((x1 + clear) // BUCKET) + 1):
            for bj in range(int((z0 - clear) // BUCKET), int((z1 + clear) // BUCKET) + 1):
                buckets.setdefault((bi, bj), []).append((ax, az, bx, bz, clear))

def in_corridor(x, z):
    for ax, az, bx, bz, clear in buckets.get((int(x // BUCKET), int(z // BUCKET)), ()):
        if seg_dist(x, z, ax, az, bx, bz) < clear:
            return True
    return False

discs = [((c['point'][0], c['point'][1]), CITY_CLEAR) for c in layout['cities']]
discs.append(RUINS)
for s in layout['sites']:
    discs.append(((s['point'][0], s['point'][1]), SITE_CLEAR.get(s['kind'], 30.0)))
lakes = [(l['center'][0], l['center'][1], l['radii_m'][0] + 10.0, l['radii_m'][1] + 10.0) for l in layout['lakes']]

def village_distance(x, z):
    x0, z0, x1, z1 = VILLAGE_RECT
    return math.hypot(max(x0 - x, 0.0, x - x1), max(z0 - z, 0.0, z - z1))

SEA = layout.get('sea')
def seaside(x, z):
    # D-099: no trees in the water, on the beach or on the cliff edge.
    if not SEA:
        return False
    xs = [p[0] for p in SEA['coast']]; zs = [p[1] for p in SEA['coast']]
    for k in range(len(xs) - 1):
        if xs[k] <= x <= xs[k + 1]:
            t = (x - xs[k]) / (xs[k + 1] - xs[k])
            return z > zs[k] + t * (zs[k + 1] - zs[k]) - 25.0 or height(x, z) < SEA['level'] + 3.0
    return False

def blocked(x, z):
    if x < 8 or z < 8 or x > 1992 or z > 1992:
        return True
    if seaside(x, z):
        return True
    if village_distance(x, z) < VILLAGE_CLEAR:
        return True
    for (cx, cz), r in discs:
        if (x - cx) ** 2 + (z - cz) ** 2 < r * r:
            return True
    for cx, cz, rx, rz in lakes:
        if ((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2 < 1.0:
            return True
    return in_corridor(x, z)

records = []
counts = {'candidates': 0, 'biome': 0, 'terrain': 0, 'clear': 0, 'kept': 0}
steps = int(2000 / CELL)
for j in range(steps):
    for i in range(steps):
        counts['candidates'] += 1
        x = (i + 0.5 + (rng.random() - 0.5) * 0.9) * CELL
        z = (j + 0.5 + (rng.random() - 0.5) * 0.9) * CELL
        roll, scale_roll, yaw_roll, tint_roll = rng.random(), rng.random(), rng.random(), rng.random()
        w = biome(x, z)
        if w <= 0.0:
            counts['biome'] += 1
            continue
        h = height(x, z)
        w *= 1.0 - smooth(*TREELINE, h)
        w *= 1.0 - smooth(*SLOPE, slope_deg(x, z))
        if w <= 0.0:
            counts['terrain'] += 1
            continue
        # Forest masses with clearings: below 0.38 open ground, above 0.55 full density.
        p = w * smooth(0.38, 0.55, masses(x, z))
        if roll >= p:
            counts['biome'] += 1
            continue
        if blocked(x, z):
            counts['clear'] += 1
            continue
        scale = 0.9 + 0.7 * scale_roll * scale_roll
        records.append((x, z, scale, yaw_roll * math.tau, 0.86 + 0.24 * tint_roll))
counts['kept'] = len(records)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'wb') as f:
    for r in records:
        f.write(struct.pack('<5f', *r))
print('FAR_FOREST_BAKE', json.dumps(counts), 'bytes', os.path.getsize(OUT))
