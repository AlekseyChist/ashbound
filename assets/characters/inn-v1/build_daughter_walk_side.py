"""Rebuild the resource from the retained whole-pose game atlas (Python stdlib)."""
from pathlib import Path
import hashlib

HERE = Path(__file__).resolve().parent
ATLAS = HERE / 'daughter-walk-side.png'
EXPECTED = '42c9d3de6404acccc7b0f8766b0815dca500d806f6907855df58b59bffaca1f5'
PIXEL_SIZE = 1.70 / 410.0

def build():
    assert hashlib.sha256(ATLAS.read_bytes()).hexdigest() == EXPECTED, 'Unexpected source atlas'
    rows = ['[gd_resource type="SpriteFrames" load_steps=10 format=3]', '',
            '[ext_resource type="Texture2D" path="res://assets/characters/inn-v1/daughter-walk-side.png" id="1"]', '']
    for i in range(8):
        rows += [f'[sub_resource type="AtlasTexture" id="pose_{i}"]', 'atlas = ExtResource("1")',
                 f'region = Rect2({i%4*384}, {i//4*512}, 384, 512)', 'filter_clip = true', '']
    poses = ',\n'.join(f'{{"duration": 1.0, "texture": SubResource("pose_{i}")}}' for i in range(8))
    rows += ['[resource]', 'animations = [{', '"frames": [', poses, '],',
             '"loop": true,', '"name": &"walk_side",', '"speed": 15.0', '}]',
             f'metadata/pixel_size_side = {PIXEL_SIZE}',
             f'metadata/pixel_size_walk_side = {PIXEL_SIZE}',
             'metadata/baseline_offset_pixels = 248.0', '']
    (HERE/'daughter_walk_side_frames.tres').write_text('\n'.join(rows), encoding='utf-8')
    print('DAUGHTER_WALK_RESOURCE_BUILT frames=8 cell=384x512 baseline=504')

if __name__ == '__main__':
    build()
