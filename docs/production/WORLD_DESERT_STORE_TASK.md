# WORLD-DESERT-STORE — module for z1/z2/z10/z11

Base dev562e128; branch codex/desert-store-runtime; draftPR200.
Producer: Qwen/Claude exact93dc292. Codex: runtime, scene, independent QA.
One8x6 hall; existing VillageDoor, one supported ceiling lantern;
interior sleep guarded by occupancy/open/moving door; near/far/world light controls.
Four lots reuse the model; actual world placement is Claude's separate work.

Scope: exact build_desert_store.py, d_store_8x6.glb,
d_store_8x6.tscn, desert_store.gd, validate_desert_store.gd, this card.
No plan/world/lore/inventory changes, no second Qwen. QA/BLEND/frames local only.

## Current checks

- Exact source93dc restores two whole-stack obstacles; no producer code altered.
- Fresh Blender/import exit0, logs clean.
- Independent validator16legs/0failures/exit0: closed door, entry/exit, model floor,
  stack obstruction, occupancy/open/moving guards and near/far/external light.
- Occupied swing stops the leaf; after actor leaves it closes, no threshold weakening.
- 4128 nondegenerate textured UV triangles; vertex envelope
  x+-4.3,z-3.3..4.2,ymax3.98, within8x6 plus agreed roof/porch projections.
- Model roof blocks above ceiling; rear parapet drain has a clear opening.
- Actual PlayerRig/ordinary camera:20legs/day +20legs/night,42frames viewed,
  exits0/noERROR. Hero overlay had texture UID fallback warnings;
  isolated clean import does not certify a clean whole project.
- Claude217 accepts runtime/physics exact9e106e7; later test-only head separately sent.

## Open

Draft until four-lot placement, adjacent approaches, family/art comparison,
world lighting and actual APK/S23/FPS. Phone HOLD. Whole world is not accepted.
Previous missing-stack failures and QA-path correction retained locally;
no logs or screenshot galleries staged.
