import bpy
import math
import buildings_common as C


def _tag(obj, spec, item_id):
    obj["building_id"] = spec["id"]
    obj["part_role"] = "furniture"
    obj["item_id"] = item_id


def _parent_local(child, parent):
    child.parent = parent
    child.matrix_parent_inverse.identity()


def _new_root(name, spec, x, y, z=None):
    root = bpy.data.objects.new(name, None)
    C.ASSET.objects.link(root)
    if z is None:
        z = spec["floor"]
    root.location = (x, y, z)
    _tag(root, spec, name)
    return root


def _chest(spec, mats, x, y, w=1.0, d=0.6, h=0.6, item="chest"):
    root = _new_root(item, spec, x, y)
    t = 0.06
    # Bottom
    bottom = C.box(item + "_bottom", (0, 0, t / 2), (w, d, t), mats["oak"], bevel=0.01)
    _tag(bottom, spec, item)
    _parent_local(bottom, root)
    # Walls
    wall_h = h - t
    # Front wall (-Y)
    front = C.box(item + "_wall_front", (0, -d / 2 + t / 2, t + wall_h / 2), (w, t, wall_h), mats["oak"], bevel=0.01)
    _tag(front, spec, item)
    _parent_local(front, root)
    # Back wall (+Y)
    back = C.box(item + "_wall_back", (0, d / 2 - t / 2, t + wall_h / 2), (w, t, wall_h), mats["oak"], bevel=0.01)
    _tag(back, spec, item)
    _parent_local(back, root)
    # Left wall (-X)
    left = C.box(item + "_wall_left", (-w / 2 + t / 2, 0, t + wall_h / 2), (t, d - 2 * t, wall_h), mats["oak"], bevel=0.01)
    _tag(left, spec, item)
    _parent_local(left, root)
    # Right wall (+X)
    right = C.box(item + "_wall_right", (w / 2 - t / 2, 0, t + wall_h / 2), (t, d - 2 * t, wall_h), mats["oak"], bevel=0.01)
    _tag(right, spec, item)
    _parent_local(right, root)

    # Hinge at back edge (+Y), top height
    hinge = bpy.data.objects.new(item + "_hinge", None)
    C.ASSET.objects.link(hinge)
    hinge.location = (0, d / 2 - t / 2, h)
    hinge["open_angle_degrees"] = -100.0
    _tag(hinge, spec, item + "_hinge")
    hinge["part_role"] = "chest_hinge"
    hinge["hinge_axis"] = "X"
    _parent_local(hinge, root)

    # Lid: local to hinge, extends forward (-Y) from hinge
    lid = C.box(item + "_lid", (0, -d / 2 + t / 2, 0.03), (w, d, 0.06), mats["oak"], bevel=0.01)
    _tag(lid, spec, item)
    _parent_local(lid, hinge)

    # Lock plate on front wall, upper part
    lock = C.box(item + "_lock", (0, -d / 2 - 0.01, h * 0.7), (0.12, 0.04, 0.16), mats["iron"], bevel=0.0)
    _tag(lock, spec, item)
    _parent_local(lock, root)


def _table(spec, mats, x, y, w, d, h, item="table"):
    root = _new_root(item, spec, x, y)
    top = C.box(item + "_top", (0, 0, h), (w, d, 0.06), mats["oak"], bevel=0.02)
    _tag(top, spec, item)
    _parent_local(top, root)
    lx, ly = w / 2 - 0.08, d / 2 - 0.08
    for i, (sx, sy) in enumerate([(-lx, -ly), (lx, -ly), (-lx, ly), (lx, ly)]):
        leg = C.box(item + "_leg%d" % i, (sx, sy, h / 2), (0.08, 0.08, h), mats["oak"], bevel=0.01)
        _tag(leg, spec, item)
        _parent_local(leg, root)


def _chair(spec, mats, x, y, face_y, item="chair"):
    root = _new_root(item, spec, x, y)
    seat = C.box(item + "_seat", (0, 0, 0.45), (0.42, 0.42, 0.06), mats["oak"], bevel=0.01)
    _tag(seat, spec, item)
    _parent_local(seat, root)
    # Chair facing +Y means back is at -Y
    back_y = -0.2 if face_y > 0 else 0.2
    back = C.box(item + "_back", (0, back_y, 0.75), (0.42, 0.06, 0.6), mats["oak"], bevel=0.01)
    _tag(back, spec, item)
    _parent_local(back, root)
    for i, (sx, sy) in enumerate([(-0.18, -0.18), (0.18, -0.18), (-0.18, 0.18), (0.18, 0.18)]):
        leg = C.box(item + "_leg%d" % i, (sx, sy, 0.225), (0.06, 0.06, 0.45), mats["oak"], bevel=0.0)
        _tag(leg, spec, item)
        _parent_local(leg, root)


def _bed(spec, mats, x, y, w, l, item="bed"):
    root = _new_root(item, spec, x, y)
    # Frame legs
    leg_h = 0.35
    for i, (sx, sy) in enumerate([(-w / 2 + 0.05, -l / 2 + 0.05), (w / 2 - 0.05, -l / 2 + 0.05), (-w / 2 + 0.05, l / 2 - 0.05), (w / 2 - 0.05, l / 2 - 0.05)]):
        leg = C.box(item + "_leg%d" % i, (sx, sy, leg_h / 2), (0.1, 0.1, leg_h), mats["oak"], bevel=0.0)
        _tag(leg, spec, item)
        _parent_local(leg, root)
    # Side rails
    rail_z = leg_h + 0.03
    for sx in (-w / 2 + 0.05, w / 2 - 0.05):
        rail = C.box(item + "_rail", (sx, 0, rail_z), (0.1, l - 0.1, 0.06), mats["oak"], bevel=0.0)
        _tag(rail, spec, item)
        _parent_local(rail, root)
    # Headboard
    head = C.box(item + "_headboard", (0, l / 2 - 0.05, leg_h + 0.3), (w, 0.1, 0.6), mats["oak"], bevel=0.02)
    _tag(head, spec, item)
    _parent_local(head, root)
    # Footboard
    foot = C.box(item + "_footboard", (0, -l / 2 + 0.05, leg_h + 0.15), (w, 0.1, 0.3), mats["oak"], bevel=0.02)
    _tag(foot, spec, item)
    _parent_local(foot, root)
    # Mattress
    matt = C.box(item + "_mattress", (0, 0, leg_h + 0.1), (w - 0.2, l - 0.2, 0.2), mats["cloth"], bevel=0.03)
    _tag(matt, spec, item)
    _parent_local(matt, root)
    # Pillow
    pillow = C.box(item + "_pillow", (0, l / 2 - 0.35, leg_h + 0.25), (w - 0.4, 0.4, 0.12), mats["cloth"], bevel=0.04)
    _tag(pillow, spec, item)
    _parent_local(pillow, root)


def _hearth(spec, mats, x, y, item="hearth"):
    root = _new_root(item, spec, x, y)
    base = C.box(item + "_base", (0, 0, 0.15), (1.35, 0.95, 0.3), mats["stone"], bevel=0.02)
    _tag(base, spec, item)
    _parent_local(base, root)
    for sx in (-0.6, 0.6):
        pier = C.box(item + "_pier", (sx, 0.35, 0.9), (0.18, 0.25, 1.2), mats["stone"], bevel=0.01)
        _tag(pier, spec, item)
        _parent_local(pier, root)
    # Hood: tapered box (wider at bottom)
    hood = C.mesh(item + "_hood",
        [(-.7,-.4,1.5),(.7,-.4,1.5),(.7,.5,1.5),(-.7,.5,1.5),
         (-.325,-.375,2.1),(.325,-.375,2.1),(.325,.375,2.1),(-.325,.375,2.1)],
        [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)], mats["stone"])
    _tag(hood, spec, item)
    _parent_local(hood, root)
    flue = C.box(item + "_flue", (0, 0, 2.5), (.65, .75, .8), mats["stone"], bevel=0.0)
    _tag(flue, spec, item)
    _parent_local(flue, root)
    back = C.box(item + '_back', (0,.42,.9), (1.2,.12,1.2), mats['stone'])
    _tag(back,spec,item)
    _parent_local(back,root)
    log = C.box(item + "_log", (0, -0.15, 0.32), (0.7, 0.16, 0.16), mats["oak"], bevel=0.04)
    _tag(log, spec, item)
    _parent_local(log, root)
    _vessel(spec,mats,item+'_pot',x+.35,y-.2,spec['floor']+.3,.15,.2)


def _bench(spec, mats, x, y, w, d, h, item="bench"):
    root = _new_root(item, spec, x, y)
    top = C.box(item + "_top", (0, 0, h), (w, d, 0.06), mats["oak"], bevel=0.02)
    _tag(top, spec, item)
    _parent_local(top, root)
    for sx in (-w / 2 + 0.08, w / 2 - 0.08):
        leg = C.box(item + "_leg", (sx, 0, h / 2), (0.08, d - 0.1, h), mats["oak"], bevel=0.0)
        _tag(leg, spec, item)
        _parent_local(leg, root)


def _ladder(spec, mats, x, fy, ty, ztop, w, item="ladder"):
    floor = spec["floor"]
    root = _new_root(item, spec, x, 0, floor)
    dy = ty - fy
    # Local rise is ztop - floor (ztop is absolute world height)
    local_ztop = ztop - floor
    length = math.sqrt(dy * dy + local_ztop * local_ztop)
    ang = math.atan2(local_ztop, dy)
    for sx in (-w / 2, w / 2):
        rail = C.box(item + "_rail", (sx, (fy + ty) / 2, local_ztop / 2), (0.06, length, 0.06), mats["oak"], bevel=0.0)
        rail.rotation_euler = (ang, 0, 0)
        _tag(rail, spec, item)
        _parent_local(rail, root)
    steps = max(5, round(length / .3))
    for i in range(steps):
        t = (i + 1) / (steps + 1)
        sy = fy + dy * t
        sz = local_ztop * t
        rung = C.box(item + "_rung%d" % i, (0, sy, sz), (w, 0.05, 0.05), mats["oak"], bevel=0.0)
        _tag(rung, spec, item)
        _parent_local(rung, root)


def _barrel(spec, mats, x, y, r, h, item="barrel"):
    root = _new_root(item, spec, x, y)
    n = 14
    # Create low-poly barrel with belly
    verts = []
    rings = [(0.0, r * 0.9), (h * 0.25, r * 1.05), (h * 0.5, r * 1.1), (h * 0.75, r * 1.05), (h, r * 0.9)]
    for z, rr in rings:
        for i in range(n):
            a = 2 * math.pi * i / n
            verts.append((rr * math.cos(a), rr * math.sin(a), z))
    faces = []
    for ring_i in range(len(rings) - 1):
        base_idx = ring_i * n
        next_idx = (ring_i + 1) * n
        for i in range(n):
            j = (i + 1) % n
            faces.append((base_idx + i, base_idx + j, next_idx + j, next_idx + i))
    faces.extend([tuple(reversed(range(n))), tuple(range((len(rings)-1)*n, len(rings)*n))])
    body = C.mesh(item + "_body", verts, faces, mats["oak"])
    _tag(body, spec, item)
    _parent_local(body, root)
    # Metal rings (narrow bands)
    for z in (h * 0.25, h * 0.75):
        ring_r = r * 1.06
        ring_verts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            ring_verts.append((ring_r * math.cos(a), ring_r * math.sin(a), z - 0.02))
            ring_verts.append((ring_r * math.cos(a), ring_r * math.sin(a), z + 0.02))
        ring_faces = []
        for i in range(n):
            j = (i + 1) % n
            ring_faces.append((i * 2, i * 2 + 1, j * 2 + 1, j * 2))
        band = C.mesh(item + "_band%d" % int(z / h * 10), ring_verts, ring_faces, mats["iron"])
        _tag(band, spec, item)
        _parent_local(band, root)


def _shelf(spec, mats, x, y, w, d, levels, item="shelf"):
    root = _new_root(item, spec, x, y)
    shelf_h = 2.25
    for sx in (-w / 2, w / 2):
        post = C.box(item + "_post", (sx, 0, shelf_h / 2), (0.08, d, shelf_h), mats["oak"], bevel=0.0)
        _tag(post, spec, item)
        _parent_local(post, root)
    for i in range(levels):
        z = 0.5 + i * 0.7
        plank = C.box(item + "_plank%d" % i, (0, 0, z), (w, d, 0.05), mats["oak"], bevel=0.0)
        _tag(plank, spec, item)
        _parent_local(plank, root)


def _crate(spec, mats, x, y, s, item="crate", z_offset=0):
    c = C.box(item, (x, y, spec["floor"] + s / 2 + z_offset), (s, s, s), mats["oak"], bevel=0.01)
    _tag(c, spec, item)


def _vessel(spec, mats, item, x, y, bottom, radius, height):
    # Closed base + outer/inner rings form an actual open container.
    n = 16
    rings = [(radius*.7,0),(radius,height),(radius*.82,height),(radius*.55,.025)]
    verts = [(r*math.cos(i*2*math.pi/n),r*math.sin(i*2*math.pi/n),z) for r,z in rings for i in range(n)]
    faces = []
    for k in range(3):
        for i in range(n):
            j=(i+1)%n
            faces.append((k*n+i,k*n+j,(k+1)*n+j,(k+1)*n+i))
    faces += [tuple(reversed(range(n))),tuple(range(3*n,4*n))]
    obj=C.mesh(item,verts,faces,mats['iron'])
    obj.location=(x,y,bottom)
    _tag(obj,spec,item)


def build_furniture(spec, mats):
    fid = spec["id"]
    if fid == "H01":
        _hearth(spec, mats, -1.6, 2.65)
        _bed(spec, mats, 1.55, 2.25, 1.2, 2.1)
        _chest(spec, mats, 2.05, 0.65)
        _table(spec, mats, 1.55, -2.1, 1.4, 0.85, 0.78)
        _chair(spec, mats, 1.55, -3.0, 1, "chair1")
        _chair(spec, mats, 1.55, -1.15, -1, "chair2")
        _vessel(spec,mats,'bowl',1.3,-2.1,spec['floor']+.81,.14,.07)
        _vessel(spec,mats,'cup',1.8,-2.1,spec['floor']+.81,.055,.12)
        _bench(spec, mats, -2.25, 1.05, 1.05, 0.55, 0.85, "prep_bench")
        pegs = C.box("coatpegs", (-2.7, -2.7, spec["floor"] + 1.6), (0.4, 0.08, 0.5), mats["oak"], bevel=0.0)
        _tag(pegs, spec, "coatpegs")
        # Bucket moved next to coat pegs
        _vessel(spec,mats,'bucket',-2.4,-3.3,spec['floor'],.18,.35)
        _ladder(spec, mats, -2.1, -1.05, 0.35, 2.95, 0.6, "attic_ladder")
    elif fid == "W01":
        # workbench left wall
        root = _new_root("workbench", spec, -2.55, -1.8)
        top = C.box("workbench_top", (0, 0, 0.85), (1.0, 2.6, 0.08), mats["oak"], bevel=0.02)
        _tag(top, spec, "workbench")
        _parent_local(top, root)
        for i, (sx, sy) in enumerate([(-0.4, -1.1), (0.4, -1.1), (-0.4, 1.1), (0.4, 1.1)]):
            leg = C.box("workbench_leg%d" % i, (sx, sy, 0.425), (0.1, 0.1, 0.85), mats["oak"], bevel=0.0)
            _tag(leg, spec, "workbench")
            _parent_local(leg, root)
        vise = C.box("vise", (-0.3, -1.0, 0.92), (0.15, 0.2, 0.15), mats["iron"], bevel=0.0)
        _tag(vise, spec, "workbench")
        _parent_local(vise, root)
        mallet = C.box("mallet", (0.3, 0.8, 0.92), (0.1, 0.4, 0.06), mats["oak"], bevel=0.0)
        _tag(mallet, spec, "workbench")
        _parent_local(mallet, root)
        # pegboard
        peg = C.box("pegboard", (-3.2, 1.1, spec["floor"] + 1.6), (0.05, 1.7, 1.2), mats["oak"], bevel=0.0)
        _tag(peg, spec, "pegboard")
        for i in range(3):
            tool = C.box("tool%d" % i, (-3.15, .5 + i * 0.6, spec["floor"] + 1.7), (0.05, 0.3, 0.08), mats["iron"], bevel=0.0)
            _tag(tool, spec, "pegboard")
        # spare boards
        for i in range(4):
            b = C.box("board%d" % i, (-2.45, 2.7, spec["floor"] + 0.06 * (i + 1)), (0.9, 0.12, 0.05), mats["oak"], bevel=0.0)
            _tag(b, spec, "boards")
        # shelves right rear
        _shelf(spec, mats, 2.65, 2.5, 1.2, 0.5, 3, "shelves")
        # Stacked crates: upper on top of lower
        _crate(spec, mats, 2.5, 2.4, 0.4, "crate1")
        _crate(spec, mats, 2.5, 2.4, 0.35, "crate2", z_offset=0.4)
        # chest
        _chest(spec, mats, 1.9, 3.5)
        # stool
        stool = C.box("stool", (-1.8, -0.9, spec["floor"] + 0.4), (0.35, 0.35, 0.8), mats["oak"], bevel=0.02)
        _tag(stool, spec, "stool")
        # assembly table right middle
        _table(spec, mats, 2.15, -0.5, 1.15, 2.2, 0.8, "assembly_table")
        # sawhorses under canopy: legs from ground (z=0) up
        for sy in (-0.6, 0.6):
            for sx in (-.42,.42):
                sh = C.beam('sawhorse_leg',(4.45+sx,sy,0),(4.45+sx*.25,sy,.8),.09,.09,mats['oak'])
                _tag(sh,spec,'sawhorses')
        plank = C.box("canopy_plank", (4.45, 0, 0.82), (1.2, 1.6, 0.05), mats["oak"], bevel=0.0)
        _tag(plank, spec, "sawhorses")
        # attic ladder left rear
        _ladder(spec, mats, -2.6, -0.25, 1.35, 3.03, 0.6, "attic_ladder")
    elif fid == "B01":
        # grain bins
        for i, gy in enumerate((-3.6, -1.8)):
            root = _new_root("grainbin%d" % i, spec, -2.6, gy)
            body = C.box("grainbin%d_body" % i, (0, 0, 0.4), (1.35, 1.45, 0.8), mats["oak"], bevel=0.02)
            _tag(body, spec, "grainbin%d" % i)
            _parent_local(body, root)
            grain = C.box("grainbin%d_grain" % i, (0, 0, 0.78), (1.2, 1.3, 0.06), mats["straw"], bevel=0.0)
            _tag(grain, spec, "grainbin%d" % i)
            _parent_local(grain, root)
        # barrels
        _barrel(spec, mats, -2.4, 3.4, 0.35, 0.85, "barrel1")
        _barrel(spec, mats, -3.15, 2.5, 0.35, 0.85, "barrel2")
        # sacks
        for i, (sx, sy) in enumerate([(-1.6, 3.6), (-1.2, 3.9)]):
            sack = C.box("sack%d" % i, (sx, sy, spec["floor"] + 0.25), (0.4, 0.4, 0.5), mats["straw"], bevel=0.1)
            _tag(sack, spec, "sacks")
        # shelves right
        _shelf(spec, mats, 2.9, -1.5, 1.3, 0.5, 2, "shelves")
        # stacked crates: upper on top of lower
        _crate(spec, mats, 2.8, 2.8, 0.5, "crate1")
        _crate(spec, mats, 2.8, 2.8, 0.4, "crate2", z_offset=0.5)
        # hayloft structure: root at world origin, absolute heights
        root = bpy.data.objects.new("hayloft", None)
        C.ASSET.objects.link(root)
        root.location = (0, 0, 0)
        _tag(root, spec, "hayloft")
        # Deck top at 3.38, so center at 3.38 - 0.08 = 3.3
        deck = C.box("hayloft_deck", (0, 2.875, 3.3), (7.5, 3.75, 0.16), mats["oak"], bevel=0.0)
        _tag(deck, spec, "hayloft")
        _parent_local(deck, root)
        for sx in (-2.9, 2.9):
            for sy in (1.2,4.5):
                post = C.box("hayloft_post", (sx, sy, 1.65), (0.15, 0.15, 3.3), mats["oak"], bevel=0.0)
                _tag(post, spec, "hayloft")
                _parent_local(post, root)
        beam = C.box("hayloft_beam", (0, 2.875, 3.3), (7.5, 0.15, 0.15), mats["oak"], bevel=0.0)
        _tag(beam, spec, "hayloft")
        _parent_local(beam, root)
        # Rail: posts + horizontal rails with gap at ladder (x=-2.2)
        # Front rail at y=1.0, deck top 3.38, rail height 0.7 -> center z = 3.38 + 0.35 = 3.73
        # Gap from x=-2.9 to x=-1.5 (ladder area)
        # Left segment: x from -2.9 to -1.5, center x = -2.2, width = 1.4
        rail_left = C.box("hayloft_rail_left", (-3.25, 1.0, 4.08), (1.0, 0.08, 0.09), mats["oak"], bevel=0.0)
        _tag(rail_left, spec, "hayloft")
        _parent_local(rail_left, root)
        # Right segment: x from -1.5 to 2.9, center x = 0.7, width = 4.4
        rail_right = C.box("hayloft_rail_right", (1.05, 1.0, 4.08), (5.4, 0.08, 0.09), mats["oak"], bevel=0.0)
        _tag(rail_right, spec, "hayloft")
        _parent_local(rail_right, root)
        # Rail posts
        for rx in (-3.7, -2.75, -1.65, 1.05, 3.7):
            rpost = C.box("hayloft_rail_post", (rx, 1.0, 3.73), (0.08, 0.08, 0.7), mats["oak"], bevel=0.0)
            _tag(rpost, spec, "hayloft")
            _parent_local(rpost, root)
        # Hay bales on loft: deck top 3.38, bale center at 3.63 (0.25 half-height)
        for i, (hx, hy) in enumerate([(0.5, 3.2), (1.5, 3.6), (-0.8, 3.9)]):
            bale = C.box("haybale%d" % i, (hx, hy, 3.63), (0.7, 0.5, 0.5), mats["straw"], bevel=0.1)
            _tag(bale, spec, "hayloft")
            _parent_local(bale, root)
        # crates below rear, keep x0 clear
        _crate(spec, mats, -2.8, 4.2, 0.5, "crate3")
        _crate(spec, mats, 2.6, 4.3, 0.45, "crate4")
        # ladder to loft: ztop=3.3 is absolute world height
        _ladder(spec, mats, -2.2, -0.35, 1.02, 3.38, 0.6, "loft_ladder")
