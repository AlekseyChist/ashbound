"""Codex refusal/repeatability checks in a temporary Godot project."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = Path('assets/characters/courtyard/enemy-preview')
GODOT = os.environ['ASHBOUND_GODOT']
OUTPUTS = ['wolf-atlas.png', 'guard-atlas.png', 'wolf_frames.tres', 'guard_frames.tres', 'build-manifest.txt']

with tempfile.TemporaryDirectory(prefix='ashbound-enemy-builder-') as directory:
    stage = Path(directory)
    shutil.copytree(ROOT / ART, stage / ART)
    (stage / 'scripts/tools').mkdir(parents=True)
    shutil.copyfile(ROOT / 'scripts/tools/build_corner_enemy_frames.gd', stage / 'scripts/tools/build_corner_enemy_frames.gd')
    (stage / 'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')

    def digests():
        return {name: hashlib.sha256((stage / ART / name).read_bytes()).hexdigest() for name in OUTPUTS}

    def run(args=()):
        return subprocess.run([GODOT, '--headless', '--path', str(stage), '--script', 'res://scripts/tools/build_corner_enemy_frames.gd', '--', *args], capture_output=True, text=True, timeout=90)

    original = (stage / ART / 'guard.png').read_bytes()
    baseline = digests()
    for case in ('unknown-flag', 'missing-second', 'wrong-dimensions', 'no-poses'):
        guard = stage / ART / 'guard.png'
        guard.write_bytes(original)
        if case == 'missing-second': guard.unlink()
        if case == 'wrong-dimensions': Image.new('RGBA', (32, 32)).save(guard)
        if case == 'no-poses': Image.new('RGBA', (1254, 1254)).save(guard)
        result = run(('--unknown-flag',) if case == 'unknown-flag' else ())
        output = result.stdout + result.stderr
        assert result.returncode != 0 and 'BUILD FAILED:' in output, (case, output)
        assert 'SCRIPT ERROR:' not in output, (case, output)
        assert digests() == baseline, 'partial output overwrite: ' + case
        print('PASS refusal ' + case)
    (stage / ART / 'guard.png').write_bytes(original)
    result = run()
    assert result.returncode == 0 and 'PACK_OK sheets=2 poses=36' in result.stdout, result.stdout + result.stderr
    assert 'SCRIPT ERROR:' not in result.stderr and 'ERROR:' not in result.stderr, result.stderr
    # Pack phase omits resource lines from its manifest until --with-frames.
    rebuilt = digests()
    assert all(rebuilt[name] == baseline[name] for name in OUTPUTS if name != 'build-manifest.txt'), 'rebuild changed atlas or existing frames'
    result = run()
    assert result.returncode == 0 and 'PACK_OK sheets=2 poses=36' in result.stdout, result.stdout + result.stderr
    assert digests() == rebuilt, 'second pack rebuild is not deterministic'
    print('ASHBOUND_ENEMY_BUILDER_OK refusals=4 repeatability=1')
