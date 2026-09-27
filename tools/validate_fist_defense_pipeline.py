"""Codex QA for Ollama's offline composition/build scripts, in an isolated project.

Run .tools/prepare-defense-poses-stage.mjs before this local development harness.
Only validated equipment PNGs and SpriteFrames are copied back by the coordinator.
"""
from pathlib import Path
import copy
import hashlib
import json
import shutil
import subprocess
import re
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / '.tools/export-staging/defense-poses'
GODOT = ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
ART = 'assets/characters/courtyard/fist-defense'
WORK = STAGE / '.tools/defense-pipeline-qa'
WORK.mkdir(parents=True, exist_ok=True)


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def snapshot(directory):
    return {p.name: (digest(p), p.stat().st_mtime_ns) for p in directory.glob('*') if p.is_file()}


def run(name, script, args, ok, marker):
    result = subprocess.run([str(GODOT), '--headless', '--path', str(STAGE), '--script', 'res://scripts/tools/'+script+'.gd', '--', *args], capture_output=True, timeout=90)
    output = (result.stdout + result.stderr).decode('utf8', errors='replace')
    (WORK / (name+'.log')).write_text(output, encoding='utf8')
    assert not re.search(r'SCRIPT ERROR:|^ERROR:', output, re.M), (name, output[-2500:])
    assert (result.returncode == 0) == ok and marker in output, (name, result.returncode, output[-2500:])
    if not ok:
        assert '_OK ' not in output, (name, 'success printed after failure')
    print('PASS', name, flush=True)


def composition():
    original = json.loads((STAGE / 'art/characters/fist-defense-v1/equipment.json').read_text(encoding='utf8'))
    outputs = STAGE / '.tools/defense-equipment/export'
    inputs = {p: digest(STAGE / p) for s in original['sheets'] for p in [s['base'], s['paint']]}
    run('compose-valid', 'compose_fist_defense_equipment', [], True, 'ASHBOUND_DEFENSE_EQUIPMENT_OK sheets=2')
    for sheet in original['sheets']:
        base = np.array(Image.open(STAGE / sheet['base']))
        paint = np.array(Image.open(STAGE / sheet['paint']))
        expected = base.copy()
        for x, y, w, h in sheet['regions']:
            expected[y:y+h, x:x+w] = paint[y:y+h, x:x+w]
        actual = np.array(Image.open(outputs / (sheet['id']+'-pack.png')))
        assert np.array_equal(actual, expected), 'composition differs from authored mask'
        assert np.any(actual != base), 'equipment was not added'
    before = snapshot(outputs)
    cases = {}
    def case(name, modify):
        data = copy.deepcopy(original)
        modify(data)
        cases[name] = data
    case('hash', lambda d: d['sheets'][0].update(base_sha256='0'*64))
    case('fraction', lambda d: d['sheets'][0]['regions'][0].__setitem__(0, 1.5))
    case('outside', lambda d: d['sheets'][1]['regions'][0].__setitem__(2, 2000))
    case('duplicate', lambda d: d['sheets'][1].update(id='novice'))
    case('empty', lambda d: d['sheets'][0].update(regions=[]))
    case('schema', lambda d: d.update(schema=9))
    case('type', lambda d: d['sheets'].__setitem__(0, 'bad'))
    case('missing', lambda d: d['sheets'][1].update(paint='art/nonexistent.png'))
    case('traversal', lambda d: d['sheets'][0].update(base='../outside.png'))
    bad_image = WORK / 'wrong-size.png'
    Image.new('RGBA', (20,20)).save(bad_image)
    case('size', lambda d: d['sheets'][1].update(paint='.tools/defense-pipeline-qa/wrong-size.png', paint_sha256=digest(bad_image)))
    for name, data in cases.items():
        (WORK / 'fixture.json').write_text(json.dumps(data), encoding='utf8')
        run('compose-'+name, 'compose_fist_defense_equipment', ['--manifest=res://.tools/defense-pipeline-qa/fixture.json'], False, 'ASHBOUND_DEFENSE_EQUIPMENT_FAIL')
        assert snapshot(outputs) == before, 'invalid input overwrote output '+name
    run('compose-output-escape', 'compose_fist_defense_equipment', ['--out-dir=res://.tools/../assets/'], False, 'ASHBOUND_DEFENSE_EQUIPMENT_FAIL')
    assert snapshot(outputs) == before
    assert all(digest(STAGE / p) == sha for p, sha in inputs.items()), 'source mutation'
    for sheet in original['sheets']:
        shutil.copy2(outputs / (sheet['id']+'-pack.png'), STAGE / ART / (sheet['id']+'-pack.png'))
    print('COMPOSITION_EXACT_SOURCE_PRESERVATION_AND_11_REFUSALS_PASS', flush=True)


def frames():
    outputs = WORK / 'frames'
    source = WORK / 'source'
    source.mkdir(exist_ok=True)
    for p in (STAGE / ART).glob('*.png'):
        shutil.copy2(p, source / p.name)
    out_arg = '--out-dir=res://.tools/defense-pipeline-qa/frames/'
    marker = 'ASHBOUND_FIST_DEFENSE_FRAMES_FAILED'
    run('frames-valid', 'build_fist_defense_frames', [out_arg], True, 'ASHBOUND_FIST_DEFENSE_FRAMES_OK poses=24')
    assert set(snapshot(outputs)) == {t+s+'_frames.tres' for t in ['novice','trained'] for s in ['', '_pack']}
    before = snapshot(outputs)
    src_arg = '--source-dir=res://.tools/defense-pipeline-qa/source/'
    target = source / 'trained-pack.png'
    original = target.read_bytes()
    for name in ['missing', 'size', 'empty-cell', 'border']:
        target.write_bytes(original)
        if name == 'missing':
            target.unlink()
        elif name == 'size':
            Image.new('RGBA', (100,100)).save(target)
        else:
            arr = np.array(Image.open(target))
            if name == 'empty-cell': arr[:627, :418] = 0
            else: arr[0, 0] = [255,0,0,255]
            Image.fromarray(arr).save(target)
        run('frames-'+name, 'build_fist_defense_frames', [src_arg, out_arg], False, marker)
        assert snapshot(outputs) == before, 'invalid frame input overwrote output'
    target.write_bytes(original)
    for name, args in [('escape', ['--out-dir=res://.tools/../assets/']), ('old-output', ['--out-dir=res://assets/characters/courtyard/fist-preview/']), ('unknown', ['--nonsense']), ('missing-value', ['--out-dir'])]:
        run('frames-'+name, 'build_fist_defense_frames', args, False, marker)
        assert snapshot(outputs) == before
    print('FRAME_PREFLIGHT_AND_8_REFUSALS_PASS', flush=True)


if __name__ == '__main__':
    import sys
    if '--frames-only' not in sys.argv: composition()
    if '--composition-only' not in sys.argv: frames()
    print('ASHBOUND_DEFENSE_PIPELINE_OK', flush=True)
