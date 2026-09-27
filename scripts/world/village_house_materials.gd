extends RefCounted
## H01 material study A. Instance-local UV/tangents; imported GLB stays immutable.
const Catalog=preload("res://scripts/world/village_house_material_catalog.gd")
const ROLES=["shell","gable","roof","foundation","chimney","canopy","door","shutter"]
const METRES={"plaster":1.5,"oak":.6,"roof":.6,"stone":2.0}
var originals: Array[Dictionary]=[]

func apply(model: Node3D, id: String) -> void:
	if id!="H01" or not originals.is_empty():return
	var materials: Dictionary={}
	for kind in METRES:materials[kind]=Catalog.create(kind)
	for item in model.find_children("*","MeshInstance3D",true,false):
		var instance:=item as MeshInstance3D
		var metadata: Dictionary=instance.get_meta("extras",{})
		if not str(metadata.get("part_role","")) in ROLES:continue
		var source:=instance.mesh
		var replacement:=ArrayMesh.new()
		var changed:=false
		var space: Transform3D=model.global_transform.affine_inverse()*instance.global_transform
		for surface in range(source.get_surface_count()):
			var material:=source.surface_get_material(surface)
			var kind: String=material.resource_name.trim_prefix("Forest_") if material else ""
			var arrays:=source.surface_get_arrays(surface)
			if materials.has(kind):
				arrays=arrays.duplicate(true)
				map_uv(arrays,space,kind)
				changed=true
			replacement.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
			replacement.surface_set_material(surface,materials.get(kind,material))
		if changed:
			# Rebuild tangents for the new UV basis, preserving imported normals.
			var tangent_mesh:=ArrayMesh.new()
			for surface in range(replacement.get_surface_count()):
				var st:=SurfaceTool.new();st.create_from(replacement,surface)
				st.generate_tangents();st.commit(tangent_mesh)
				tangent_mesh.surface_set_material(surface,replacement.surface_get_material(surface))
			originals.append({"node":instance,"mesh":source,"detailed":tangent_mesh})
			instance.mesh=tangent_mesh

func set_enabled(enabled: bool) -> void:
	for record in originals:record.node.mesh=record.detailed if enabled else record.mesh

func root_of(parents: PackedInt32Array, index: int) -> int:
	while parents[index]!=index:
		parents[index]=parents[parents[index]];index=parents[index]
	return index

func map_uv(arrays: Array, space: Transform3D, kind: String) -> void:
	var local: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var points:=PackedVector3Array();var uv:=PackedVector2Array()
	points.resize(local.size());uv.resize(local.size())
	for i in range(local.size()):points[i]=space*local[i]
	var grain: Dictionary={}
	var roots:=PackedInt32Array();roots.resize(local.size())
	if kind=="oak":
		# Position welding is ONLY for connectivity analysis, never mesh geometry.
		var welded: Dictionary={}
		for i in range(local.size()):
			roots[i]=i
			var key:=Vector3i((points[i]*10000.0).round())
			if welded.has(key):roots[i]=welded[key]
			else:welded[key]=i
		for triangle in range(0,indices.size(),3):
			var a:=root_of(roots,indices[triangle])
			for corner in [1,2]:roots[root_of(roots,indices[triangle+corner])]=a
		var groups: Dictionary={}
		for i in range(local.size()):
			var root:=root_of(roots,i);roots[i]=root
			if not groups.has(root):groups[root]=PackedVector3Array()
			groups[root].append(points[i])
		for root in groups:
			var center:=Vector3.ZERO
			for point in groups[root]:center+=point
			center/=groups[root].size()
			var covariance:=Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
			for point in groups[root]:
				var d: Vector3=point-center
				covariance.x+=d*d.x;covariance.y+=d*d.y;covariance.z+=d*d.z
			var axis:=Vector3(1,.73,.37).normalized()
			for iteration in range(12):axis=(covariance*axis).normalized()
			grain[root]=axis
	var normal_basis:=space.basis.inverse().transposed()
	for i in range(local.size()):
		var normal: Vector3=(normal_basis*normals[i]).normalized()
		var axis: Vector3=grain[roots[i]] if kind=="oak" else (Vector3.RIGHT if kind=="roof" else Vector3.DOWN)
		var v:=axis-normal*axis.dot(normal)
		if v.length_squared()<.01:
			axis=Vector3.FORWARD if absf(normal.z)<.9 else Vector3.RIGHT
			v=axis-normal*axis.dot(normal)
		v=v.normalized()
		var u:=v.cross(normal).normalized()
		uv[i]=Vector2(points[i].dot(u),points[i].dot(v))/float(METRES[kind])
		if kind=="roof":
			# Contract from forest-village-v1/build-data.json and shell.py: existing
			# 16 rows per slope / 22 columns, overhang .6/.45. No geometry changes.
			uv[i]=Vector2((points[i].z+4.45)/(8.9/22.0),absf(points[i].x)/(3.6/16.0))
	arrays[Mesh.ARRAY_TEX_UV]=uv
