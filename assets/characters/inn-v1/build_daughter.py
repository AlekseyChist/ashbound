"""Reproduce the full SpriteFrames from the retained whole-pose PNGs; stdlib only."""
from pathlib import Path
import hashlib

HERE = Path(__file__).resolve().parent
VIEWS = ('front', 'back', 'side')
STATES = ('idle', 'windup', 'attack', 'hit', 'out', 'guard')
HASHES = {
    'walk-side': '42c9d3de6404acccc7b0f8766b0815dca500d806f6907855df58b59bffaca1f5',
    'walk-back': '79584239ea1f8912b8f08f83ed2fa602a2e1c6a7a72cf658a50b1d044a1da2f2',
    'walk-front': 'bf64eae20a024e0ee5ba9db6a157bbab310e6f40d3535cd5b3843f2d7def398a',
    'run-front': '7198131f42daaa5d48149af4ffc35e0b00acb1811a0c8163f8bac4e5b5030be7',
    'run-back': 'caf9789622ebc2f982b3d9540d88c0253cf12bf365b15b2cac98e44b93df97d3',
    'run-side': '459817805b28a14bb46eb4fd3a6ea953dab286529aa58c96b9fe96fedd94537d',
    'states': 'fcbebdf589e45c0821484f138e4f9e531048733f61d4dc8d33a0a5c893c86ccd',
}
# One calibration for every pose of a clip. Running lean/flight is not height-fitted.
HEIGHTS = {
    'walk_front': 493.0, 'walk_back': 482.0, 'walk_side': 410.0,
    'run_front': 493.0, 'run_back': 482.0, 'run_side': 440.0,
}
STATE_HEIGHTS = {'front': 490*.75, 'back': 489*.75, 'side': 487*.75}

def build():
    for key, expected in HASHES.items():
        actual = hashlib.sha256((HERE/f'daughter-{key}.png').read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f'Changed retained source: {key}')
    rows = ['[gd_resource type="SpriteFrames" load_steps=74 format=3]', '']
    for key in HASHES:
        rows += [f'[ext_resource type="Texture2D" path="res://assets/characters/inn-v1/daughter-{key}.png" id="{key}"]', '']
    clips = []
    for action in ('idle', 'walk', 'run', 'windup', 'attack', 'hit', 'out', 'guard'):
        for view in VIEWS:
            name = f'{action}_{view}'
            count = 8 if action in ('walk', 'run') else 1
            poses = []
            for i in range(count):
                pose_id = f'{name}_{i}'
                if count == 8:
                    key = f'{action}-{view}'
                    x, y = i%4*384, i//4*512
                else:
                    key = 'states'
                    x, y = VIEWS.index(view)*384, STATES.index(action)*512
                rows += [f'[sub_resource type="AtlasTexture" id="{pose_id}"]',
                         f'atlas = ExtResource("{key}")', f'region = Rect2({x}, {y}, 384, 512)',
                         'filter_clip = true', '']
                poses.append(f'{{"duration": 1.0, "texture": SubResource("{pose_id}")}}')
            loop = 'true' if action in ('idle', 'walk', 'run') else 'false'
            clips.append('{\n"frames": [\n'+',\n'.join(poses)+
                         f'\n],\n"loop": {loop},\n"name": &"{name}",\n"speed": 15.0\n}}')
    rows += ['[resource]', 'animations = [\n'+',\n'.join(clips)+'\n]',
             'metadata/baseline_offset_pixels = 248.0']
    for view in VIEWS:
        rows.append(f'metadata/pixel_size_{view} = {1.70/STATE_HEIGHTS[view]}')
    for action in ('idle', 'walk', 'run', 'windup', 'attack', 'hit', 'out', 'guard'):
        for view in VIEWS:
            height = HEIGHTS.get(f'{action}_{view}', STATE_HEIGHTS[view])
            rows.append(f'metadata/pixel_size_{action}_{view} = {1.70/height}')
    (HERE/'daughter_frames.tres').write_text('\n'.join(rows)+'\n', encoding='utf-8')
    print('DAUGHTER_FULL_RESOURCE_BUILT clips=24 whole_poses=66 cell=384x512 baseline=504')

if __name__ == '__main__':
    build()
