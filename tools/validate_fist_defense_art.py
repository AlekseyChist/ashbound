"""Independent Codex QA for generated whole-body guard/hit atlas pairs.

Read-only pixel analysis; never repairs or resizes artwork to make it pass.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/characters/courtyard/fist-defense'


def bounds(mask):
    yy, xx = np.nonzero(mask)
    assert len(xx), 'empty pose/band'
    return np.array([xx.min(), yy.min(), xx.max() + 1, yy.max() + 1])


def compare_body(bare, worn):
    a, b = bare[:, :, 3] > 51, worn[:, :, 3] > 51
    box = bounds(a)
    height = box[3] - box[1]
    # Hair cap and lower legs cannot expand when a rucksack is equipped.
    bands = [(box[1], box[1] + round(height * .08)),
             (box[3] - round(height * .25), box[3])]
    records = []
    for lo, hi in bands:
        aa, bb = a[lo:hi], b[lo:hi]
        ba, bw = bounds(aa), bounds(bb)
        edge_drift = int(abs(ba - bw).max())
        width_drift = int(abs((ba[2] - ba[0]) - (bw[2] - bw[0])))
        overlap = float(np.count_nonzero(aa & bb) / np.count_nonzero(aa | bb))
        assert edge_drift <= 3 and width_drift <= 3, (edge_drift, width_drift)
        assert overlap >= .97, overlap
        assert np.array_equal(bare[lo:hi], worn[lo:hi]), 'protected body pixels changed'
        records.append(dict(edge_drift=edge_drift, width_drift=width_drift, silhouette_iou=overlap))
    assert abs(int(bounds(b)[3]) - int(box[3])) <= 3, 'sole drift'
    return records


def main():
    records, images, hashes = [], {}, {}
    for tech in ['novice', 'trained']:
        for suffix in ['', '-pack']:
            name = tech + suffix
            file = ART / (name + '.png')
            img = Image.open(file)
            assert img.size == (1254, 1254) and img.mode == 'RGBA', file
            arr = np.array(img)
            assert (arr[:, :, 3] == 0).mean() > .2, 'real transparency required'
            hashes[name] = hashlib.sha256(file.read_bytes()).hexdigest()
            images[name] = arr
            for row, action in enumerate(['guard', 'hit']):
                for col, view in enumerate(['front', 'back', 'side']):
                    cell = arr[row*627:(row+1)*627, col*418:(col+1)*418]
                    box = bounds(cell[:, :, 3] > 51)
                    assert box[0] >= 2 and box[1] >= 2 and box[2] <= 416 and box[3] <= 625, (name, action, view, box)
                    assert box[3] - box[1] >= 450, 'truncated or miniature figure'
                    records.append(dict(name=name, action=action, view=view, bounds=box.tolist()))
        for row, action in enumerate(['guard', 'hit']):
            for col, view in enumerate(['front', 'back', 'side']):
                sl = np.s_[row*627:(row+1)*627, col*418:(col+1)*418]
                measured = compare_body(images[tech][sl], images[tech+'-pack'][sl])
                records.append(dict(technique=tech, action=action, view=view, protected_bands=measured))
                assert not np.array_equal(images[tech][sl], images[tech+'-pack'][sl]), 'missing equipment variant'
    assert len(set(hashes.values())) == 4
    # Negative regression: a bag variant stretched sideways must be rejected.
    sample = images['novice'][:627, :418]
    bad = np.zeros_like(sample)
    bad[:, 9:409] = sample[:, np.linspace(40, 378, 400).astype(int)]
    try:
        compare_body(sample, bad)
    except AssertionError:
        pass
    else:
        raise AssertionError('stretch detector did not reject bad fixture')
    output = ROOT / '.tools/defense-poses-art-qa.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(dict(hashes=hashes, measurements=records), indent=2), encoding='utf8')
    print('ASHBOUND_DEFENSE_ART_OK poses=24 pairs=12 negative_stretch=rejected')


if __name__ == '__main__':
    main()
