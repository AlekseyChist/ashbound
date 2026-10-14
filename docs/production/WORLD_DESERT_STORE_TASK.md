# WORLD-DESERT-STORE — one store module for z1/z2/z10/z11

Base: origin/dev 562e128. Branch codex/desert-store-runtime.
Source producer: Claude/Qwen 4db3944; exact generator read, static preview improved.
Blocking source defect: timber stack colliders removed (8 in 9acf, 0 in4db), returned283.
Codex owns this runtime/scenes/independent validation; no second Qwen.

Result: native 8x6 module with existing VillageDoor, one supported ceiling lantern,
interior sleep guarded by occupancy/open/moving door, near/far/world light controls.
Four plan plots reuse the module; placement is Claude's separately owned work.
Allowed: build_desert_store.py exact handed-off source, d_store_8x6.glb,
scenes/buildings/world-architecture-v1/d_store_8x6.tscn,
scripts/buildings/desert_store.gd, scripts/tools/validate_desert_store.gd, this card.
No plan, world, lore, weapon/inventory feature changes.
All logs, fixtures, BLEND, screenshots in local/qa/desert-store only.

Checks: true model floor, closed door blocking, ordinary entry/exit, clear central
1.2m aisle, grain/timber access, stack obstruction and roof envelope/drain/UV;
occupancy/door visibility guards and near/far/external light state.
Then actual PlayerRig/ordinary camera day/night, family/placement and mobile limits.
No green code claim or commit of incomplete asset based on known missing collision.

Current QA: fresh isolated import0; 14 movement legs, door/floor/visibility/light
checks complete. Two expected failures remain: both timber stack obstruction rays
are empty on producer4db3944. Overall validator exit1, not PASS.
QA r1 targeted an open leaf outside the central lane; r2 uses x-.6 at that entry
approach and retains both timber expectations. No source geometry changed.
No model committed or PR created before producer collision correction.

Producer93dc292 restores two full-stack obstacles; fresh Blender/import exit0.
The same independent runtime validator now passes14legs with zero failures, exit0.
Actual PlayerRig/ordinary camera isolated module:20legs/day +20legs/night,42frames
viewed, exits0/noERROR. Hero QA used existing imported dependency overlays and
texture UID fallback warnings; not a clean whole-project/mobile/FPS approval.
Draft for Claude peer review. World placement/family comparison/roof-drain-UV
geometry audit/door-swing occupied-actor regression/mobile remain explicit work.
Earlier 4db failures preserved in local; tested model cannot silently lose stacks.
