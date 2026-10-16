extends Node
## One world-level owner per SpringArm; independent groups share its camera-only layer.
## Runtime integration must replace the legacy per-module mask owners.
const CAMERA_LAYER := 64
const OWNER_META := &"_ashbound_camera_obstacle_owner"
var arm: SpringArm3D
var _original_camera_bit := 0
var _holding_layer := false
var _groups: Dictionary = {}
var _entries: Dictionary = {}

func configure(spring: SpringArm3D) -> bool:
 if not is_inside_tree() or not is_instance_valid(spring): return false
 if spring.has_meta(OWNER_META):
  var owner_ref = spring.get_meta(OWNER_META)
  if owner_ref is WeakRef:
   var other = owner_ref.get_ref()
   if is_instance_valid(other) and other != self: return false
 if arm == spring: return true
 _detach_arm()
 arm = spring
 arm.set_meta(OWNER_META, weakref(self))
 if not _entries.is_empty(): _acquire_layer()
 return true

## Replaces one group atomically: invalid input preserves the existing group.
func register_group(key: StringName, meshes: Array[MeshInstance3D]) -> bool:
 if not is_instance_valid(arm) or key == &"" or meshes.is_empty(): return false
 var selected: Dictionary = {}
 for mesh in meshes:
  if not is_instance_valid(mesh) or not mesh.is_inside_tree() or mesh.mesh == null: return false
  var id := mesh.get_instance_id()
  if selected.has(id): continue
  if _entries.has(id):
   if not is_instance_valid(_entries[id].body): return false
   selected[id] = {"mesh":mesh,"shape":null}
  else:
   if mesh.mesh.get_faces().is_empty(): return false
   var shape := mesh.mesh.create_trimesh_shape()
   if shape == null: return false
   shape.backface_collision = true
   selected[id] = {"mesh":mesh,"shape":shape}
 # Add references before removing old membership, so unchanged meshes never lose their body.
 for id in selected:
  if not _entries.has(id):
   var body := StaticBody3D.new()
   body.name = "SharedCameraObstacle"
   body.collision_layer = CAMERA_LAYER
   body.collision_mask = 0
   var collision := CollisionShape3D.new()
   collision.shape = selected[id].shape
   body.add_child(collision)
   selected[id].mesh.add_child(body)
   _entries[id] = {"body":body,"references":0}
  _entries[id].references += 1
 _remove_members(_groups.get(key, []))
 _groups[key] = selected.keys()
 _acquire_layer()
 return true

func remove_group(key: StringName) -> void:
 if not _groups.has(key): return
 _remove_members(_groups[key])
 _groups.erase(key)
 if _entries.is_empty(): _release_layer()

func _remove_members(ids: Array) -> void:
 for id in ids:
  if not _entries.has(id): continue
  _entries[id].references -= 1
  if _entries[id].references > 0: continue
  var body = _entries[id].body
  if is_instance_valid(body):
   body.collision_layer = 0
   body.queue_free()
  _entries.erase(id)

func body_count() -> int:
 var count := 0
 for entry in _entries.values():
  if is_instance_valid(entry.body): count += 1
 return count

func group_count() -> int: return _groups.size()
func has_group(key: StringName) -> bool: return _groups.has(key)

func _acquire_layer() -> void:
 if not is_instance_valid(arm): return
 if not _holding_layer:
  _original_camera_bit = arm.collision_mask & CAMERA_LAYER
  _holding_layer = true
 arm.collision_mask |= CAMERA_LAYER

func _release_layer() -> void:
 if _holding_layer and is_instance_valid(arm):
  arm.collision_mask = (arm.collision_mask & ~CAMERA_LAYER) | _original_camera_bit
 _holding_layer = false
 _original_camera_bit = 0

func _detach_arm() -> void:
 _release_layer()
 if is_instance_valid(arm) and arm.has_meta(OWNER_META):
  var owner_ref = arm.get_meta(OWNER_META)
  if owner_ref is WeakRef and owner_ref.get_ref() == self: arm.remove_meta(OWNER_META)
 arm = null

func restore() -> void:
 for key in _groups.keys(): remove_group(key)
 _detach_arm()

func _exit_tree() -> void: restore()

