"""Independent read-only pixel QA for the enemy atlas builder (Codex)."""
from pathlib import Path
import hashlib, json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/characters/courtyard/enemy-preview'

def components(image):
    """Run-length/union-find implementation independent from Godot flood fill."""
    parent, runs, previous = [], [], []
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for y, row in enumerate(image[:, :, 3] > 30):
        edges = np.flatnonzero(np.diff(np.r_[False, row, False].astype(np.int8)))
        current = []
        for x0, x1 in edges.reshape(-1, 2):
            i = len(parent)
            parent.append(i); runs.append((int(x0), y, int(x1), y+1)); current.append(i)
            for j in previous:
                if runs[j][2] >= x0 and runs[j][0] <= x1:
                    parent[find(j)] = find(i)
        previous = current
    labels = np.full(image.shape[:2], -1, dtype=np.int32)
    for i, (x0, y, x1, _) in enumerate(runs): labels[y, x0:x1] = find(i)
    ids, counts = np.unique(labels, return_counts=True)
    figures = []
    for ident, count in zip(ids, counts):
        if ident < 0 or count < 1800: continue
        mask = labels == ident
        yy, xx = np.nonzero(mask)
        box = [int(xx.min()), int(yy.min()), int(xx.max()+1), int(yy.max()+1)]
        center = (box[0]+box[2])/2
        figures.append(dict(mask=mask, bounds=box, column=0 if center < 450 else 1 if center < 760 else 2))
    return sorted(figures, key=lambda f:(f['column'],f['bounds'][1]))

def bounds(mask):
    yy, xx = np.nonzero(mask)
    assert xx.size, 'empty packed pose'
    return int(xx.min()), int(yy.min()), int(xx.max()+1), int(yy.max()+1)

def check_pose(source, packed, figure, ground):
    x0,y0,x1,y1 = figure['bounds']
    expected = source[y0:y1,x0:x1].copy()
    expected[~figure['mask'][y0:y1,x0:x1]] = 0
    ax0,ay0,ax1,ay1 = bounds(packed[:,:,3] > 0)
    assert (ax1-ax0,ay1-ay0) == (x1-x0,y1-y0), 'silhouette resized or foreign pixels leaked'
    assert ay1-1 == ground, ('foot anchor/air gap', ay1-1, ground)
    assert ax0 > 1 and ax1 < 511 and ay0 > 1, 'clipped figure'
    assert np.array_equal(packed[ay0:ay1,ax0:ax1],expected), 'source pixels changed or neighbouring pose leaked'
    return int(np.count_nonzero(expected[:,:,3]))

def main():
    report, total = {}, 0
    for kind in ['wolf','guard']:
        source = np.array(Image.open(ART/(kind+'.png')))
        output = np.array(Image.open(ART/(kind+'-atlas.png')))
        assert source.shape == (1254,1254,4)
        assert output.shape == (3072,1536,4)
        figures = components(source)
        assert len(figures) == 18
        for col in range(3):
            poses = [f for f in figures if f['column']==col]
            assert len(poses)==6
            for row, figure in enumerate(poses):
                packed = output[row*512:(row+1)*512,col*512:(col+1)*512]
                total += check_pose(source,packed,figure,480 if kind=='wolf' and row==4 else 492)
        report[kind] = {'source_sha256':hashlib.sha256((ART/(kind+'.png')).read_bytes()).hexdigest(),
                        'atlas_sha256':hashlib.sha256((ART/(kind+'-atlas.png')).read_bytes()).hexdigest()}
        # A foreign head fragment in a packed cell must be rejected.
        packed = output[:512,:512].copy()
        packed[5,5] = (80,50,20,255)
        try: check_pose(source,packed,figures[0],492)
        except AssertionError: pass
        else: raise AssertionError('foreign-fragment negative control accepted')
    out=ROOT/'.tools/enemy-art-qa.json'; out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps({'hashes':report,'exact_pixels':total},indent=2))
    print(f'ASHBOUND_CORNER_ENEMY_ART_OK poses=36 exact_pixels={total} negative_controls=2')

if __name__=='__main__': main()
