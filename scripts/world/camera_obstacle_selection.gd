extends RefCounted
## Explicit selectors for the reviewed producer mesh/material contracts.
const BAZAAR_CLOTH := ["DB awning", "DB stripe"]

static func mine_timber(portals: Array[Node3D]) -> Array[MeshInstance3D]:
 var selected: Array[MeshInstance3D] = []
 for portal in portals:
  if not is_instance_valid(portal): return []
  for mesh: MeshInstance3D in portal.find_children("*", "MeshInstance3D", true, false):
   if mesh.mesh != null and String(mesh.name).begins_with("portal "): selected.append(mesh)
 return selected

static func bazaar_cloth(models: Array[Node3D]) -> Array[MeshInstance3D]:
 var selected: Array[MeshInstance3D] = []
 for model in models:
  if not is_instance_valid(model): return []
  for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
   if mesh.mesh == null: continue
   var has_cloth := false
   for surface in mesh.mesh.get_surface_count():
    var material := mesh.get_active_material(surface)
    if material != null and material.resource_name in BAZAAR_CLOTH: has_cloth = true
   if not has_cloth: continue
   if mesh.mesh.get_surface_count() != 1:
    push_warning("Camera cloth mesh has multiple surfaces; split cloth before registration: " + str(mesh.get_path()))
    continue
   selected.append(mesh)
 return selected

