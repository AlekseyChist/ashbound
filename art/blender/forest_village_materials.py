"""Forest village shared materials with baked procedural base colors."""
import os
import pathlib

import bpy

PALETTE = {
    "oak": (0.22, 0.13, 0.07, 1.0),
    "plaster": (0.58, 0.49, 0.36, 1.0),
    "stone": (0.34, 0.34, 0.31, 1.0),
    "roof": (0.12, 0.10, 0.075, 1.0),
    "cloth": (0.52, 0.43, 0.31, 1.0),
    "iron": (0.065, 0.07, 0.07, 1.0),
    "straw": (0.47, 0.34, 0.16, 1.0),
}
ROUGH = {"oak": 0.9, "plaster": 0.95, "stone": 0.92, "roof": 0.9,
         "cloth": 0.95, "iron": 0.65, "straw": 0.93}
SIZE = 512


def _base_mat(key):
    mat = bpy.data.materials.get("Forest_" + key) or bpy.data.materials.new("Forest_" + key)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = ROUGH[key]
    if key == "iron":
        bsdf.inputs["Metallic"].default_value = 0.7
    r, g, b, a = PALETTE[key]
    mat.diffuse_color = (r, g, b, a)
    bsdf.inputs["Base Color"].default_value = (r, g, b, a)
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return mat


def _procedural(mat, key):
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    r, g, b, a = PALETTE[key]
    tex = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    if key in ("oak", "roof"):
        mapping.inputs["Scale"].default_value = (1.0, 14.0, 1.0)
        noise.inputs["Scale"].default_value = 3.0
    else:
        noise.inputs["Scale"].default_value = 6.0
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (r * 0.75, g * 0.75, b * 0.75, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (min(r * 1.15, 1), min(g * 1.15, 1), min(b * 1.15, 1), 1)
    nt.links.new(tex.outputs["UV"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs[0], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])


def _connect_baked(mat, img):
    """Final state: UV -> baked image texture -> Principled Base Color."""
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for link in list(bsdf.inputs["Base Color"].links):
        nt.links.remove(link)
    itex = nt.nodes.new("ShaderNodeTexImage")
    itex.image = img
    uv = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(uv.outputs["UV"], itex.inputs["Vector"])
    nt.links.new(itex.outputs["Color"], bsdf.inputs["Base Color"])


def _bake(mat, key, texture_dir):
    path = os.path.join(str(texture_dir), key + ".png")
    if os.path.exists(path):
        img = bpy.data.images.load(path)
        img.name = "Forest_" + key
        img.pack()
        _connect_baked(mat, img)
        return img
    old_engine = bpy.context.scene.render.engine
    plane_obj = None
    try:
        bpy.context.scene.render.engine = "CYCLES"
        bpy.context.scene.cycles.device = "CPU"
        bpy.context.scene.cycles.samples = 1
        bpy.ops.object.select_all(action="DESELECT")
        bpy.ops.mesh.primitive_plane_add(size=2.0, location=(0, 0, 0))
        plane_obj = bpy.context.view_layer.objects.active
        plane_obj.name = "BakePlane"
        plane_obj.data.materials.append(mat)
        img = bpy.data.images.new("Forest_" + key, SIZE, SIZE, alpha=False)
        nt = mat.node_tree
        itex = nt.nodes.new("ShaderNodeTexImage")
        itex.image = img
        nt.nodes.active = itex
        plane_obj.select_set(True)
        bpy.context.view_layer.objects.active = plane_obj
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        img.pack()
    finally:
        if plane_obj is not None and plane_obj.name in bpy.data.objects:
            bpy.data.objects.remove(plane_obj, do_unlink=True)
        bpy.context.scene.render.engine = old_engine
    _connect_baked(mat, img)
    return img


def make_materials(texture_dir: pathlib.Path) -> dict:
    os.makedirs(str(texture_dir), exist_ok=True)
    out = {}
    for key in PALETTE:
        mat = _base_mat(key)
        if key == "iron":
            out[key] = mat
            continue
        _procedural(mat, key)
        _bake(mat, key, texture_dir)
        out[key] = mat
    return out
