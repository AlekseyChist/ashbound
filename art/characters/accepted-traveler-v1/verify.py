"""Read-only integrity check for the owner-accepted 0.19.4 reference."""
from pathlib import Path
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def verify():
    manifest = json.loads((HERE / 'manifest.json').read_text(encoding='utf-8'))
    failures = []
    for entry in manifest['files']:
        path = ROOT / entry['path']
        if not path.is_file():
            failures.append('missing: ' + entry['path'])
            continue
        data = path.read_bytes()
        if entry['hash_mode'] == 'lf-text':
            data = data.replace(b'\r\n', b'\n')
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            failures.append('changed: ' + entry['path'])
    resource = (HERE / 'traveler_frames.tres').read_text(encoding='utf-8')
    for relative in re.findall(r'path="res://([^"]+)"', resource):
        if not (ROOT / relative).is_file():
            failures.append('missing resource dependency: ' + relative)
    for key, expected in manifest['final_metadata'].items():
        match = re.search(r'^metadata/' + re.escape(key) + r' = ([0-9.]+)$', resource, re.M)
        if not match or abs(float(match[1]) - expected) > 1e-14:
            failures.append('wrong metadata: ' + key)
    if failures:
        raise SystemExit('\n'.join(failures))
    print('ACCEPTED_TRAVELER_OK files=%d version=0.19.4' % len(manifest['files']))


if __name__ == '__main__':
    verify()
