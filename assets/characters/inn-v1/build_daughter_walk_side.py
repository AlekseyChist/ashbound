"""Rebuild checkpoint walk resources from retained whole-pose atlases (stdlib)."""
from pathlib import Path
import hashlib

HERE = Path(__file__).resolve().parent
VIEWS = {
    'side': ('42c9d3de6404acccc7b0f8766b0815dca500d806f6907855df58b59bffaca1f5', 410.0),
    'back': ('79584239ea1f8912b8f08f83ed2fa602a2e1c6a7a72cf658a50b1d044a1da2f2', 482.0),
}

def build(view, expected, body_height):
    atlas = HERE / f'daughter-walk-{view}.png'
    pixel_size = 1.70 / body_height
    assert hashlib.sha256(atlas.read_bytes()).hexdigest() == expected, 'Unexpected source atlas'
    rows = ['[gd_resource type="SpriteFrames" load_steps=10 format=3]', '',
            f'[ext_resource type="Texture2D" path="res://assets/characters/inn-v1/daughter-walk-{view}.png" id="1"]', '']
    for i in range(8):
        rows += [f'[sub_resource type="AtlasTexture" id="pose_{i}"]', 'atlas = ExtResource("1")',
                 f'region = Rect2({i%4*384}, {i//4*512}, 384, 512)', 'filter_clip = true', '']
    poses = ',\n'.join(f'{{"duration": 1.0, "texture": SubResource("pose_{i}")}}' for i in range(8))
    rows += ['[resource]', 'animations = [{', '"frames": [', poses, '],',
             '"loop": true,', f'"name": &"walk_{view}",', '"speed": 15.0', '}]',
             f'metadata/pixel_size_{view} = {pixel_size}',
             f'metadata/pixel_size_walk_{view} = {pixel_size}',
             'metadata/baseline_offset_pixels = 248.0', '']
    (HERE/f'daughter_walk_{view}_frames.tres').write_text('\n'.join(rows), encoding='utf-8')
    print(f'DAUGHTER_WALK_RESOURCE_BUILT view={view} frames=8 cell=384x512 baseline=504')

if __name__ == '__main__':
    for view, (expected, body_height) in VIEWS.items():
        build(view, expected, body_height)
