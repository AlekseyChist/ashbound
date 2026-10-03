"""INN-TEMP-FRAMES (owner 3 Oct 2026: "add the new characters" now, before Codex's full sets).

Temporary game frames from the owner-approved sheets (D-111/D-114):
- daughter: daughter-motion-proof-v2.png (RGBA): idle front/back/side, guard, 8 side walk phases;
- three moneylender's men: thugs-concept-v1.png (RGB, grey paper): one pose each, cut from the paper.
Whole figures are copied 1:1 (no per-frame bbox scaling, D-059 rule): one scale per character from its
standing height, feet on y=492 in 512x512 cells like guard_frames. Codex's inn-v1 sets replace these.
Output: <game>/assets/characters/inn-temp/<name>-atlas.png + <name>_frames.tres
"""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

MAIN = Path(r"C:/Users/prost/Documents/AshBound")
GAME = Path(r"C:/Users/prost/ashbound-wt-review")
OUT = GAME / "assets" / "characters" / "inn-temp"
QA = MAIN / "local" / "qa" / "inn-temp-frames"
CELL = 512
FEET_Y = 492
BASELINE = 236.0  # cell centre to the feet, as guard_frames
HEIGHTS = {"daughter": 1.70, "thug_leader": 1.80, "thug_brute": 1.88, "thug_young": 1.72}


def components(alpha: np.ndarray, threshold: int = 30, min_px: int = 4000):
    """Bounding boxes of 8-connected opaque parts, large ones only, left-to-right/top-to-bottom."""
    h, w = alpha.shape
    seen = np.zeros_like(alpha, dtype=bool)
    solid = alpha > threshold
    boxes = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if not solid[y, x] or seen[y, x]:
                continue
            q = deque([(y, x)])
            seen[y, x] = True
            x0 = x1 = x
            y0 = y1 = y
            count = 0
            while q:
                cy, cx = q.popleft()
                count += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and solid[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            if count >= min_px:
                boxes.append((x0, y0, x1 + 1, y1 + 1, count))
    return boxes


def cut_paper(rgb: np.ndarray, tolerance: float = 30.0) -> np.ndarray:
    """Alpha for figures on grey paper: flood the paper from the borders by colour distance."""
    h, w, _ = rgb.shape
    img = rgb.astype(np.float32)
    paper = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        q.append((0, x)); q.append((h - 1, x))
    for y in range(h):
        q.append((y, 0)); q.append((y, w - 1))
    ref = np.median(np.concatenate([img[0], img[-1], img[:, 0], img[:, -1]]), axis=0)
    while q:
        y, x = q.popleft()
        if paper[y, x]:
            continue
        if np.linalg.norm(img[y, x] - ref) > tolerance:
            continue
        paper[y, x] = True
        if y > 0: q.append((y - 1, x))
        if y < h - 1: q.append((y + 1, x))
        if x > 0: q.append((y, x - 1))
        if x < w - 1: q.append((y, x + 1))
    # The pale ground shadow under the boots: low-colour light paper joined to the paper, bottom fifth only
    # (shirts are light too, but no shirt reaches down there).
    lum = img.mean(axis=2)
    chroma = img.max(axis=2) - img.min(axis=2)
    pale = (lum > 120) & (chroma < 26)
    zone = np.zeros((h, w), dtype=bool)
    zone[int(h * 0.80):, :] = True
    q = deque(zip(*np.nonzero(paper & zone)))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and zone[ny, nx] and pale[ny, nx] and not paper[ny, nx]:
                paper[ny, nx] = True
                q.append((ny, nx))
    # Paper shut in between the legs: closed grey patches of paper colour (low colour, near the paper).
    near = (np.linalg.norm(img - ref, axis=2) < 40) & (chroma < 22) & ~paper
    seen = np.zeros((h, w), dtype=bool)
    for sy, sx in zip(*np.nonzero(near)):
        if seen[sy, sx]:
            continue
        region = [(sy, sx)]
        seen[sy, sx] = True
        i = 0
        while i < len(region):
            y, x = region[i]
            i += 1
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    region.append((ny, nx))
        if len(region) >= 600:
            ys, xs = zip(*region)
            paper[list(ys), list(xs)] = True
    alpha = np.where(paper, 0, 255).astype(np.uint8)
    # Soften the cut edge by one pixel against the paper.
    edge = (alpha == 255) & (np.roll(paper, 1, 0) | np.roll(paper, -1, 0) | np.roll(paper, 1, 1) | np.roll(paper, -1, 1))
    alpha[edge] = 160
    return alpha


def place(figure: Image.Image) -> Image.Image:
    """A whole figure in a 512 cell, feet on FEET_Y, centred; never scaled."""
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    w, h = figure.size
    if h > FEET_Y or w > CELL:
        raise ValueError(f"figure {w}x{h} does not fit the cell")
    cell.paste(figure, ((CELL - w) // 2, FEET_Y - h), figure)
    return cell


def write(name: str, frames: dict, stand_height_px: int) -> None:
    """frames: animation -> list of cell images. Writes the atlas and the SpriteFrames .tres."""
    cells = []
    index = {}
    for anim, imgs in frames.items():
        index[anim] = []
        for img in imgs:
            key = id(img)
            if key not in {id(c) for c in cells}:
                cells.append(img)
            index[anim].append([id(c) for c in cells].index(key))
    cols = 4
    rows = (len(cells) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * CELL, rows * CELL), (0, 0, 0, 0))
    for i, img in enumerate(cells):
        atlas.paste(img, ((i % cols) * CELL, (i // cols) * CELL))
    OUT.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT / f"{name}-atlas.png", optimize=True)
    pixel = HEIGHTS[name] / stand_height_px
    lines = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (len(cells) + 2), "",
             f'[ext_resource type="Texture2D" path="res://assets/characters/inn-temp/{name}-atlas.png" id="1_atlas"]', ""]
    for i in range(len(cells)):
        lines += [f'[sub_resource type="AtlasTexture" id="cell_{i}"]', 'atlas = ExtResource("1_atlas")',
                  f"region = Rect2({(i % cols) * CELL}, {(i // cols) * CELL}, {CELL}, {CELL})", "filter_clip = true", ""]
    anims = []
    for anim, ids in frames.items():
        fr = ", ".join('{\n"duration": 1.0,\n"texture": SubResource("cell_%d")\n}' % index[anim][k] for k in range(len(ids)))
        anims.append('{\n"frames": [%s],\n"loop": true,\n"name": &"%s",\n"speed": 5.0\n}' % (fr, anim))
    lines += ["[resource]", "animations = [" + ", ".join(anims) + "]",
              f"metadata/pixel_size_front = {pixel}", f"metadata/pixel_size_back = {pixel}",
              f"metadata/pixel_size_side = {pixel}", f"metadata/baseline_offset_pixels = {BASELINE}", ""]
    (OUT / f"{name}_frames.tres").write_text("\n".join(lines), encoding="utf-8")
    print("FRAMES", name, "cells", len(cells), "pixel_size %.5f" % pixel, "height_px", stand_height_px)


def daughter() -> None:
    sheet = Image.open(MAIN / "local/previews/inn-daughter-motion-01/daughter-motion-proof-v2.png").convert("RGBA")
    alpha = np.array(sheet.getchannel("A"))
    boxes = components(alpha)
    # The proof sheet is a 4x3 grid: order by the cell each figure stands in.
    boxes.sort(key=lambda b: (int(((b[1] + b[3]) / 2) // (alpha.shape[0] / 3)), int(((b[0] + b[2]) / 2) // (alpha.shape[1] / 4))))
    if len(boxes) != 12:
        raise SystemExit(f"daughter sheet: expected 12 figures, found {len(boxes)}")
    figs = [place(sheet.crop(b[:4])) for b in boxes]
    front, back, side, guard = figs[:4]
    walk = figs[4:]
    stand_h = boxes[0][3] - boxes[0][1]
    QA.mkdir(parents=True, exist_ok=True)
    frames = {
        "idle_front": [front], "idle_back": [back], "idle_side": [side],
        "walk_front": [front], "walk_back": [back], "walk_side": walk,
        "windup_front": [guard], "windup_back": [back], "windup_side": [guard],
        "attack_front": [guard], "attack_back": [back], "attack_side": [guard],
        "hit_front": [front], "hit_back": [back], "hit_side": [side],
    }
    write("daughter", frames, stand_h)


def thugs() -> None:
    sheet = Image.open(MAIN / "local/previews/moneylender-thugs-art-01/thugs-concept-v1.png").convert("RGB")
    rgb = np.array(sheet)
    alpha = cut_paper(rgb)
    rgba = Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
    QA.mkdir(parents=True, exist_ok=True)
    rgba.save(QA / "thugs-cut.png")
    boxes = components(alpha, threshold=100, min_px=20000)
    boxes.sort(key=lambda b: b[0])
    if len(boxes) != 3:
        raise SystemExit(f"thugs sheet: expected 3 figures, found {len(boxes)} {boxes}")
    # The concept figures are taller than a cell: one shared downscale keeps their relative heights.
    tallest = max(b[3] - b[1] for b in boxes)
    scale = min(1.0, 460.0 / tallest)
    for name, box in zip(["thug_leader", "thug_brute", "thug_young"], boxes):
        fig = rgba.crop(box[:4])
        if scale < 1.0:
            fig = fig.resize((round(fig.width * scale), round(fig.height * scale)), Image.LANCZOS)
        cell = place(fig)
        frames = {f"{a}_{v}": [cell] for a in ("idle", "walk", "windup", "attack", "hit") for v in ("front", "back", "side")}
        write(name, frames, fig.height)


if __name__ == "__main__":
    daughter()
    thugs()
