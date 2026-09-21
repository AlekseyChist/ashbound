# Промпты перерисовки рюкзака

2026-09-21. Built-in image_gen, режим редактирования по существующим атласам. Результаты скопированы в эту папку без обработки пикселей. Это два первых художественных листа, ещё не подключённые игровые ресурсы.

## traveler-back-pack.png

Исходная пара без рюкзака: `assets/characters/courtyard/traveler-back-v1.png`.

```text
Use case: identity-preserve.
Asset type: ASHBOUND painted 2D character sprite atlas, matching backpack-on counterpart of the existing backpack-off atlas.
Edit target: the provided 4 by 4 atlas of the traveler seen from behind. Preserve EXACTLY its 16 cells, character identity, body sizes, silhouettes of arms and legs, foot placements, poses, frame order, neutral diffuse lighting, clothing colors and original hand-painted ink texture. Rows 1 and 2 are eight walking frames, row 3 four idle poses, row 4 four unarmed punching poses. Do not add any weapons. Keep exactly these poses and crop-free spacing, no re-layout. Genuine transparent alpha background.
Change: in EVERY cell hand-paint a modest weathered brown leather travel backpack worn on the man's back, flap with one brass buckle, two shoulder straps, small tightly rolled bedroll attached beneath. Integrate it INTO each complete figure painting. The backpack conforms to the changing back angle and shoulder rotation of that exact frame, with individual foreshortening, contact shadow, straps disappearing naturally under the arms, subtle matching cloth compression. During the punch the pack twists with the torso. No pasted accessory appearance, no separate layer floating over the body, no identical rigid backpack reused over every pose. Do not cover hair or neck, do not extend below belt significantly. Keep all sixteen characters at the original scale, no enlargement, no childlike proportions, no change to shirt, coat length, boots, hair or anatomy. Keep fully transparent empty space and no cast floor shadows. No lettering, cell borders, captions or watermarks. Output a square full sprite atlas at the highest useful resolution.
```

## traveler-run-side-pack.png

Исходная пара без рюкзака: `assets/characters/courtyard/traveler-run-side-v3.png`. Дополнительный ориентир конструкции — новый задний лист выше.

```text
Use case: identity-preserve.
Asset type: complete painted character sprites for ASHBOUND, backpack-on variant.
Image 1 EDIT TARGET: existing 4 by 4 atlas, traveler facing screen RIGHT. Keep precisely all 16 original poses and positions, original body/head/boot sizes, feet and ground anchors, coat length, face, hair, ink linework and colors. The top TWO rows are 8 running frames; third row 4 standing idle poses; fourth row 4 unarmed punch poses. No weapons. Output the same square atlas with genuinely transparent alpha and the same 4x4 layout. Do not relayout, zoom, change pose, crop, or change proportions.
Image 2 DESIGN REFERENCE ONLY: same travel backpack painted into rear-view sprites: modest worn brown leather, curved flap, single brass buckle, small tightly rolled charcoal bedroll horizontally below it. Match its construction, restrained size and colors, NOT the rear viewpoint.
Primary edit: hand-paint that backpack as an integrated part of EACH of the 16 right-facing figures, with a convincing side view behind the shoulder, shoulder straps wrapping naturally over the shirt, contact shadows and shirt creases beneath. In the running poses the entire backpack inclines forward together with the angled spine; in punching frames its perspective twists with the exact torso. Paint occlusion and physical contact separately for each pose. Do not stamp one rigid upright backpack onto all frames. Preserve all existing unoccluded anatomy; never cover or change the face or head. Keep backpack compact from below neck to belt. Maintain identical character scale to input so toggling the backpack cannot make the hero larger. Transparent empty cell margins, no text, no watermarks, no borders, no ground shadows.
```
