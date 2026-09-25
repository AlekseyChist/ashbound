import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
import math
from mathutils import Vector
import buildings_common as C


def _tag(obj, spec, role, face=None):
    obj["building_id"] = spec["id"]
    obj["part_role"] = role
    if face is not None:
        obj["face"] = face


def _apply_bool(target, cutter, op='DIFFERENCE'):
    m = target.modifiers.new("bool", 'BOOLEAN')
    m.operation = op
    m.object = cutter
    m.solver = 'EXACT'
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def _face_normal(face):
    return {'front': Vector((0, -1, 0)), 'rear': Vector((0, 1, 0)),
            'right': Vector((1, 0, 0)), 'left': Vector((-1, 0, 0))}[face]


def _build_wall(spec, face, mat):
    w, d, floor, wt, th = spec['width'], spec['depth'], spec['floor'], spec['wall_top'], spec['thickness']
    hw, hd = w / 2, d / 2
    if face == 'front':
        loc, size = Vector((0, -hd + th / 2, floor + (wt - floor) / 2)), (w, th, wt - floor)
    elif face == 'rear':
        loc, size = Vector((0, hd - th / 2, floor + (wt - floor) / 2)), (w, th, wt - floor)
    elif face == 'right':
        loc, size = Vector((hw - th / 2, 0, floor + (wt - floor) / 2)), (th, d, wt - floor)
    else:
        loc, size = Vector((-hw + th / 2, 0, floor + (wt - floor) / 2)), (th, d, wt - floor)
    wall = C.box(f"{spec['id']}_wall_{face}", loc, size, mat)
    _tag(wall, spec, 'shell', face)
    for op in spec['openings']:
        if op['face'] != face:
            continue
        cx, cz, ow, oh = op['center'], op['bottom'], op['width'], op['height']
        n = _face_normal(face)
        if face in ('front', 'rear'):
            cloc = Vector((cx, loc.y, cz + oh / 2))
            csize = (ow, th + .4, oh)
        else:
            cloc = Vector((loc.x, cx, cz + oh / 2))
            csize = (th + .4, ow, oh)
        cutter = C.box(f"cut_{op['id']}", cloc, csize, mat)
        _apply_bool(wall, cutter)
    return wall


def _build_log_wall(spec, face, mat):
    """Horizontal round logs of a log cabin; the two wall pairs are offset by half a log
    (as in a real corner joint) and the log ends stick out past the corners."""
    w, d, floor, wt, th = spec['width'], spec['depth'], spec['floor'], spec['wall_top'], spec['thickness']
    hw, hd = w / 2, d / 2
    dia = spec.get('log_diameter', 0.3)
    out = spec.get('log_overhang', 0.35)
    step = dia * 0.92
    offset = step / 2 if face in ('right', 'left') else 0.0
    if face in ('front', 'rear'):
        length = w + 2 * out
        y = -hd + th / 2 if face == 'front' else hd - th / 2
    else:
        length = d + 2 * out
        x = hw - th / 2 if face == 'right' else -hw + th / 2
    logs = []
    z = floor + dia / 2 + offset
    i = 0
    while z + dia / 2 <= wt + 0.001:
        if face in ('front', 'rear'):
            loc = Vector((0, y, z))
            rot = (0, math.pi / 2, 0)
        else:
            loc = Vector((x, 0, z))
            rot = (math.pi / 2, 0, 0)
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=dia / 2, depth=length, location=loc, rotation=rot)
        log = bpy.context.active_object
        log.name = f"{spec['id']}_log_{face}_{i}"
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        log.data.materials.clear()
        log.data.materials.append(mat)
        C._link(log)
        for op in spec['openings']:
            if op['face'] != face:
                continue
            cx, cz, ow, oh = op['center'], op['bottom'], op['width'], op['height']
            if z + dia / 2 <= cz or z - dia / 2 >= cz + oh:
                continue
            if face in ('front', 'rear'):
                cloc = Vector((cx, y, cz + oh / 2))
                csize = (ow, dia + .6, oh)
            else:
                cloc = Vector((x, cx, cz + oh / 2))
                csize = (dia + .6, ow, oh)
            cutter = C.box(f"cut_{op['id']}_{i}", cloc, csize, mat)
            _apply_bool(log, cutter)
        logs.append(log)
        z += step
        i += 1
    # Join the logs of this wall into one object.
    bpy.ops.object.select_all(action='DESELECT')
    for log in logs:
        log.select_set(True)
    bpy.context.view_layer.objects.active = logs[0]
    bpy.ops.object.join()
    wall = bpy.context.active_object
    wall.name = f"{spec['id']}_wall_{face}"
    _tag(wall, spec, 'shell', face)
    return wall


def _build_gable(spec, face, mat):
    w, d, wt, ridge, th = spec['width'], spec['depth'], spec['wall_top'], spec['ridge'], spec['thickness']
    hw, hd = w / 2, d / 2
    y0 = -hd if face == 'front' else hd - th
    y1 = y0 + th
    # Closed triangular prism: 6 vertices, 2 end triangles + 3 quads
    verts = [
        (-hw, y0, wt), (hw, y0, wt), (0, y0, ridge),
        (-hw, y1, wt), (hw, y1, wt), (0, y1, ridge)
    ]
    faces = [
        (0, 1, 2),      # front triangle
        (5, 4, 3),      # rear triangle (reversed for outward normal)
        (0, 3, 4, 1),   # bottom quad
        (0, 2, 5, 3),   # left slope quad
        (1, 4, 5, 2)    # right slope quad
    ]
    gable = C.mesh(f"{spec['id']}_gable_{face}", verts, faces, mat)
    _tag(gable, spec, 'gable', face)
    for op in spec['openings']:
        if op['face'] != face or op['bottom'] < wt:
            continue
        cx, cz, ow, oh = op['center'], op['bottom'], op['width'], op['height']
        cutter = C.box(f"cut_g_{op['id']}", Vector((cx, y0 + th / 2, cz + oh / 2)), (ow, th + .4, oh), mat)
        _apply_bool(gable, cutter)
    return gable


def _build_roof(spec, mat, roof_mat):
    w, d, wt, ridge = spec['width'], spec['depth'], spec['wall_top'], spec['ridge']
    hw, hd = w / 2, d / 2
    os_, og = spec['overhang_side'], spec['overhang_gable']
    pitch = (ridge - wt) / hw
    edge = hw + os_
    eave_z = ridge - pitch * edge
    slope_len = math.sqrt(edge ** 2 + (ridge - eave_z) ** 2)
    angle = math.atan2(ridge - eave_z, edge)
    roof_depth = d + 2 * og

    for side in ('right', 'left'):
        sign = 1 if side == 'right' else -1
        # Plate: true slope from ridge (x=0,z=ridge) to eave (x=sign*edge, z=eave_z)
        mid_x = sign * edge / 2
        mid_z = (ridge + eave_z) / 2
        rot_y = angle if side == 'right' else -angle
        plate = C.box(f"{spec['id']}_roof_{side}", Vector((mid_x, 0, mid_z)), (slope_len, roof_depth, .15), roof_mat)
        plate.rotation_euler[1] = rot_y
        _tag(plate, spec, 'roof', side)

        # Tiles: rows span x=0..edge along slope, cols fill full roof depth
        rows, cols = 16, 22
        row_span = edge / rows
        col_span = roof_depth / cols
        for r in range(rows):
            for c in range(cols):
                t = (r + .5) / rows
                u = (c + .5) / cols
                x = sign * edge * t
                z = ridge - pitch * abs(x)
                y = -hd - og + roof_depth * u
                # Tile dimensions proportional to slope span and depth with modest overlap
                tw = slope_len / rows * 1.08
                td = col_span * .98
                tile = C.box(f"{spec['id']}_shingle_{side}_{r}_{c}", Vector((x, y, z + .11)), (tw, td, .04), roof_mat, bevel=0)
                tile.rotation_euler[1] = rot_y
                _tag(tile, spec, 'roof', side)

    # Ridge beam full depth
    C.beam(f"{spec['id']}_ridge", Vector((0, -hd - og, ridge)), Vector((0, hd + og, ridge)), .2, .2, mat)
    # Tag ridge and verges
    ridge_obj = bpy.data.objects.get(f"{spec['id']}_ridge")
    if ridge_obj:
        _tag(ridge_obj, spec, 'roof', None)

    # Gable verges at FRONT/REAR Y±(depth/2+gableoverhang)
    for s in (1, -1):
        y_v = s * (hd + og)
        for side in (-1, 1):
            verge = C.beam(f"{spec['id']}_verge_{s}_{side}", (0, y_v, ridge), (side * edge, y_v, eave_z), .15, .15, mat)
            _tag(verge, spec, 'roof', 'front' if s == -1 else 'rear')


def _build_opening(spec, op, mats):
    face, cx, cz, ow, oh = op['face'], op['center'], op['bottom'], op['width'], op['height']
    kind = op['kind']
    hw, hd = spec['width'] / 2, spec['depth'] / 2
    n = _face_normal(face)
    if face in ('front', 'rear'):
        y = -hd if face == 'front' else hd
        frame_l = C.box(f"{spec['id']}_{op['id']}_frame_l", Vector((cx - ow / 2 - .05, y, cz + oh / 2)), (.1, .1, oh), mats['oak'])
        frame_r = C.box(f"{spec['id']}_{op['id']}_frame_r", Vector((cx + ow / 2 + .05, y, cz + oh / 2)), (.1, .1, oh), mats['oak'])
        frame_t = C.box(f"{spec['id']}_{op['id']}_frame_t", Vector((cx, y, cz + oh + .05)), (ow + .2, .1, .1), mats['oak'])
        # Bottom sill for windows/vents, not doors
        if kind in ('window', 'vent'):
            frame_b = C.box(f"{spec['id']}_{op['id']}_frame_b", Vector((cx, y, cz - .05)), (ow + .2, .1, .1), mats['oak'])
            _tag(frame_b, spec, 'shell', face)
    else:
        x = hw if face == 'right' else -hw
        frame_l = C.box(f"{spec['id']}_{op['id']}_frame_l", Vector((x, cx - ow / 2 - .05, cz + oh / 2)), (.1, .1, oh), mats['oak'])
        frame_r = C.box(f"{spec['id']}_{op['id']}_frame_r", Vector((x, cx + ow / 2 + .05, cz + oh / 2)), (.1, .1, oh), mats['oak'])
        frame_t = C.box(f"{spec['id']}_{op['id']}_frame_t", Vector((x, cx, cz + oh + .05)), (.1, ow + .2, .1), mats['oak'])
        if kind in ('window', 'vent'):
            frame_b = C.box(f"{spec['id']}_{op['id']}_frame_b", Vector((x, cx, cz - .05)), (.1, ow + .2, .1), mats['oak'])
            _tag(frame_b, spec, 'shell', face)

    for f in (frame_l, frame_r, frame_t):
        _tag(f, spec, 'shell', face)

    if kind in ('door', 'double_door', 'loft_door'):
        leaves = 2 if kind == 'double_door' else 1
        for i in range(leaves):
            lw = ow / leaves
            # Hinge at outer jamb: left leaf hinge at cx - ow/2, right leaf hinge at cx + ow/2
            if leaves == 1:
                hinge_x = cx - ow / 2
                leaf_cx = cx
            else:
                if i == 0:
                    hinge_x = cx - ow / 2
                    leaf_cx = cx - ow / 4
                else:
                    hinge_x = cx + ow / 2
                    leaf_cx = cx + ow / 4
            if face in ('front', 'rear'):
                hinge_loc = Vector((hinge_x, y, cz))
                leaf = C.box(f"{spec['id']}_{op['id']}_leaf{i}", Vector((leaf_cx, y, cz + oh / 2)), (lw - .05, .08, oh - .1), mats['oak'])
            else:
                hinge_loc = Vector((x, hinge_x, cz))
                leaf = C.box(f"{spec['id']}_{op['id']}_leaf{i}", Vector((x, leaf_cx, cz + oh / 2)), (.08, lw - .05, oh - .1), mats['oak'])
            _tag(leaf, spec, 'door', face)
            hinge = bpy.data.objects.new(f"{spec['id']}_{op['id']}_hinge{i}", None)
            C.ASSET.objects.link(hinge)
            hinge.location = hinge_loc
            _tag(hinge, spec, 'door_hinge', face)
            # Update view layer before parenting to get correct world matrix
            bpy.context.view_layer.update()
            leaf.parent = hinge
            leaf.matrix_parent_inverse = hinge.matrix_world.inverted()
            # Doors CLOSED: rotation 0; open_angle is metadata only
            open_ang = -90 if i == 0 else 90
            if kind == 'loft_door':
                open_ang = 0
            hinge.rotation_euler[2] = 0.0
            hinge["open_angle_degrees"] = open_ang
    elif kind in ('window', 'vent'):
        if kind == 'vent':
            # Vent has trim only, no shutters
            pass
        else:
            for i, side in enumerate(('l', 'r')):
                # Shutter centre halfway between hinge and window centre in CLOSED pose
                if side == 'l':
                    hinge_x = cx - ow / 2
                    shutter_cx = (hinge_x + cx) / 2
                else:
                    hinge_x = cx + ow / 2
                    shutter_cx = (hinge_x + cx) / 2
                if face in ('front', 'rear'):
                    sloc = Vector((shutter_cx, y, cz + oh / 2))
                    shutter = C.box(f"{spec['id']}_{op['id']}_shutter{side}", sloc, (ow / 2 - .1, .06, oh - .1), mats['oak'])
                else:
                    sloc = Vector((x, shutter_cx, cz + oh / 2))
                    shutter = C.box(f"{spec['id']}_{op['id']}_shutter{side}", sloc, (.06, ow / 2 - .1, oh - .1), mats['oak'])
                _tag(shutter, spec, 'shutter', face)
                hinge = bpy.data.objects.new(f"{spec['id']}_{op['id']}_sh_hinge{side}", None)
                C.ASSET.objects.link(hinge)
                if face in ('front', 'rear'):
                    hinge.location = Vector((hinge_x, y, cz))
                else:
                    hinge.location = Vector((x, hinge_x, cz))
                _tag(hinge, spec, 'shutter_hinge', face)
                bpy.context.view_layer.update()
                shutter.parent = hinge
                shutter.matrix_parent_inverse = hinge.matrix_world.inverted()
                # Rotate 180 to rest beside wall
                ang = 180 if side == 'l' else -180
                hinge.rotation_euler[2] = math.radians(ang)
                hinge["open_angle_degrees"] = ang


def build_shell(spec, mats):
    w, d, floor, wt, ridge, th = spec['width'], spec['depth'], spec['floor'], spec['wall_top'], spec['ridge'], spec['thickness']
    hw, hd = w / 2, d / 2
    wall_mat = mats[spec.get('wall_material', 'plaster')]

    # Foundation: top EXACT floor, bottom 0
    found = C.box(f"{spec['id']}_foundation", Vector((0, 0, floor / 2)), (w + .4, d + .4, floor), mats['stone'])
    _tag(found, spec, 'foundation')

    # Walls
    for face in ('front', 'rear', 'right', 'left'):
        builder = _build_log_wall if spec.get('wall_style') == 'log' else _build_wall
        builder(spec, face, wall_mat)

    # Gables: only front/rear
    for face in ('front', 'rear'):
        _build_gable(spec, face, mats['oak'] if spec.get('wall_style') == 'log' else wall_mat)

    # Roof
    _build_roof(spec, mats['oak'], mats['roof'])

    # Openings
    for op in spec['openings']:
        _build_opening(spec, op, mats)

    # Ceiling
    if 'ceiling_z' in spec:
        cz = spec['ceiling_z']
        ceil = C.box(f"{spec['id']}_ceiling", Vector((0, 0, cz)), (w - .4, d - .4, .1), mats['oak'])
        _tag(ceil, spec, 'ceiling')
        if 'attic_hatch' in spec:
            ah = spec['attic_hatch']
            hx, hy = ah['center_xy']
            hw_, hd_ = ah['size_xy']
            cutter = C.box("cut_hatch", Vector((hx, hy, cz)), (hw_, hd_, .3), mats['oak'])
            _apply_bool(ceil, cutter)

    # Chimney
    if 'chimney' in spec:
        ch = spec['chimney']
        cx, cy = ch['centre_xy']
        cw, cd = ch['footprint_xy']
        top_z = ch['top_z']
        chim = C.box(f"{spec['id']}_chimney", Vector((cx, cy, (wt - .3 + top_z) / 2)), (cw, cd, top_z - wt + .3), mats['stone'])
        _tag(chim, spec, 'chimney')

    # Timber architecture: corner posts and wall top rails
    post_size = .15
    for px in (-hw + .04, hw - .04):
        for py in (-hd + .04, hd - .04):
            post = C.box(f"{spec['id']}_post_{px}_{py}", Vector((px, py, floor + (wt - floor) / 2)), (post_size, post_size, wt - floor), mats['oak'])
            _tag(post, spec, 'shell', 'front' if py < 0 else 'rear')

    # Wall top rails/verges (skip across openings)
    for face in ('front', 'rear'):
        y = -hd if face == 'front' else hd
        rail = C.box(f"{spec['id']}_toprail_{face}", Vector((0, y, wt - .075)), (w, .18, .15), mats['oak'])
        _tag(rail, spec, 'shell', face)
    for face in ('left', 'right'):
        x = -hw if face == 'left' else hw
        rail = C.box(f"{spec['id']}_toprail_{face}", Vector((x, 0, wt - .075)), (.15, d, .15), mats['oak'])
        _tag(rail, spec, 'shell', face)

    # Low stone courses along wall outside only
    course_h = .3
    for face in ('front', 'rear'):
        y = -hd - .075 if face == 'front' else hd + .075
        course = C.box(f"{spec['id']}_stonecourse_{face}", Vector((0, y, floor + course_h / 2)), (w, .15, course_h), mats['stone'])
        _tag(course, spec, 'shell', face)
        for op in spec['openings']:
            if op['face'] == face and op['kind'] in ('door', 'double_door'):
                cutter = C.box('cut_plinth_entry', (op['center'], y, floor + course_h / 2), (op['width'], .5, course_h + .1), mats['stone'], bevel=0)
                _apply_bool(course, cutter)
    for face in ('left', 'right'):
        x = -hw - .075 if face == 'left' else hw + .075
        course = C.box(f"{spec['id']}_stonecourse_{face}", Vector((x, 0, floor + course_h / 2)), (.15, d, course_h), mats['stone'])
        _tag(course, spec, 'shell', face)

    # Steps aligned to FRONT entry centre
    if spec.get('entrance_style') == 'steps':
        entry = next((op for op in spec['openings'] if op['face'] == 'front' and op['kind'] in ('door', 'double_door')), None)
        ex = entry['center'] if entry else 0
        aw = spec.get('approach_width', 1.2)
        # Two treads at different Y, tops floor/2 and floor
        for i in range(2):
            step_h = floor / 2 * (i + 1)
            step_y = -hd - 1.1 + i * .6
            step = C.box(f"{spec['id']}_step{i}", Vector((ex, step_y, step_h / 2)), (aw, .6, step_h), mats['stone'])
            _tag(step, spec, 'foundation')

    # Ramp: closed wedge, rear edge meets floor at front wall, front edge ground 0
    elif spec.get('entrance_style') == 'ramp':
        entry = next((op for op in spec['openings'] if op['face'] == 'front' and op['kind'] in ('door', 'double_door')), None)
        ex = entry['center'] if entry else 0
        aw = spec.get('approach_width', 1.2)
        ramp_len = aw
        # Wedge: rear at y=-hd, z=floor; front at y=-hd-ramp_len, z=0
        verts = [
            (ex - aw / 2, -hd, 0), (ex + aw / 2, -hd, 0), (ex + aw / 2, -hd, floor), (ex - aw / 2, -hd, floor),
            (ex - aw / 2, -hd - ramp_len, 0), (ex + aw / 2, -hd - ramp_len, 0)
        ]
        faces = [(0, 1, 5, 4), (3, 2, 1, 0), (0, 4, 3), (1, 2, 5), (4, 5, 2, 3)]
        ramp = C.mesh(f"{spec['id']}_ramp", verts, faces, mats['stone'])
        _tag(ramp, spec, 'foundation')

    # Canopy: sloped from z_inner to z_outer
    if 'canopy' in spec:
        cp = spec['canopy']
        cx = (cp['x_start'] + cp['x_end']) / 2
        cy = (cp['y_start'] + cp['y_end']) / 2
        cw = cp['x_end'] - cp['x_start']
        cd = cp['y_end'] - cp['y_start']
        z_in = cp['z_inner']
        z_out = cp['z_outer']
        # Slope from inner (higher) to outer (lower)
        slope_len = math.sqrt(cw ** 2 + (z_in - z_out) ** 2)
        angle = math.atan2(z_in - z_out, cw)
        slab = C.box(f"{spec['id']}_canopy", Vector((cx, cy, (z_in + z_out) / 2)), (slope_len, cd, .1), mats['roof'])
        slab.rotation_euler[1] = angle
        _tag(slab, spec, 'canopy')
        # Posts: top matches local roof height, base ground 0
        for px in (cp['x_start'], cp['x_end']):
            for py in (cp['y_start'], cp['y_end']):
                # Determine z at this y position on the slope
                t = (px - cp['x_start']) / cw
                z_top = z_in + (z_out - z_in) * t
                post = C.box(f"{spec['id']}_canopy_post_{px}_{py}", Vector((px, py, z_top / 2)), (.15, .15, z_top), mats['oak'])
                _tag(post, spec, 'canopy')

    # Entrance canopy: uses given ec z_inner/z_outer, NOT door top
    if 'entrance_canopy' in spec:
        ec = spec['entrance_canopy']
        entry = next((op for op in spec['openings'] if op['face'] == 'front' and op['kind'] in ('door', 'double_door')), None)
        if entry:
            ex = entry['center']
            z_in = ec.get('z_inner', wt)
            z_out = ec.get('z_outer', wt - .5)
            proj = ec['projection']
            # Sloped slab from inner to outer
            slope_len = math.sqrt(proj ** 2 + (z_in - z_out) ** 2)
            angle = math.atan2(z_in - z_out, proj)
            slab = C.box(f"{spec['id']}_entry_canopy", Vector((ex, -hd - proj / 2, (z_in + z_out) / 2)), (ec['width'], slope_len, .1), mats['oak'])
            slab.rotation_euler[0] = angle
            _tag(slab, spec, 'canopy', 'front')
            # Supports/brackets rise to roof, outside entry passage
            for s in (-1, 1):
                bx = ex + s * ec['width'] / 2
                # Post from ground to roof height at that y
                z_top = z_out
                post = C.box(f"{spec['id']}_entry_post_{s}", Vector((bx, -hd - proj, z_top / 2)), (.15, .15, z_top), mats['oak'])
                _tag(post, spec, 'canopy', 'front')
                # Bracket from wall to roof
                bracket = C.beam(f"{spec['id']}_bracket{s}", Vector((bx, -hd, z_in)), Vector((bx, -hd - proj, z_out)), .08, .08, mats['oak'])
                _tag(bracket, spec, 'canopy', 'front')

    # Deselect all
    bpy.ops.object.select_all(action='DESELECT')
