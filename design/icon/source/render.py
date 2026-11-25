"""Run under Blender. The orthographic camera spans 10.24 units, or 1024 pixels."""
import argparse
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector
from math import sin, cos, pi

cli = argparse.ArgumentParser()
cli.add_argument("round", type=int, choices=[1, 2, 3])
cli.add_argument("names", nargs="*", default=["undertone", "reed", "cadence", "dovetail"])
cli.add_argument("--templates", action="store_true", help="Render a monochrome menu bar silhouette")
cli.add_argument("--brass-pass", type=int, choices=range(1, 7), default=6)
args = cli.parse_args(sys.argv[sys.argv.index("--") + 1:])
stage = args.round
root = Path(__file__).resolve().parents[1]
out = root / "studies" / f"round-{stage}"
out.mkdir(parents=True, exist_ok=True)

def material(name, color, metal, rough):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    shader = m.node_tree.nodes.get("Principled BSDF")
    for k, v in [("Base Color", (*color, 1)), ("Metallic", metal), ("Roughness", rough)]:
        shader.inputs[k].default_value = v
    return m

def brushed(mat, direction, low, high):
    """Vary the width of the reflection along microscopic machining lines."""
    nt=mat.node_tree
    tex=nt.nodes.new("ShaderNodeTexCoord")
    scale=nt.nodes.new("ShaderNodeVectorMath")
    scale.operation="MULTIPLY"
    scale.inputs[1].default_value=direction
    nt.links.new(tex.outputs["Generated"],scale.inputs[0])
    noise=nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value=1
    noise.inputs["Detail"].default_value=1.5
    nt.links.new(scale.outputs[0],noise.inputs["Vector"])
    ramp=nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["To Min"].default_value=low
    ramp.inputs["To Max"].default_value=high
    nt.links.new(noise.outputs["Fac"],ramp.inputs["Value"])
    nt.links.new(ramp.outputs[0],nt.nodes.get("Principled BSDF").inputs["Roughness"])

def mesh(name, verts, faces, mat, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(mat)
    for poly in data.polygons:
        poly.use_smooth = smooth
    return obj

def bridge(name, rings, mat, cap=True):
    n = len(rings[0])
    faces = [(k*n+i, k*n+(i+1)%n, (k+1)*n+(i+1)%n, (k+1)*n+i)
             for k in range(len(rings)-1) for i in range(n)]
    if cap:
        faces.extend([tuple(reversed(range(n))), tuple(range((len(rings)-1)*n,len(rings)*n))])
    return mesh(name, [v for row in rings for v in row], faces, mat)

def tile():
    mat = material("Fine charcoal ceramic", (.016,.017,.019), .3, .48)
    if stage >= 2:
        mat = material("Honed basalt", (.012,.013,.016), .10, .60)
        mat.node_tree.nodes.get("Principled BSDF").inputs["Specular IOR Level"].default_value=.23
    n = 512
    rim = []
    # A lower shoulder and a wide, shallow crown blend into the level face.
    for radius, z in [(3.99,-.26),(4.065,-.229),(4.105,-.18),(4.12,-.116),
                      (4.118,-.084),(4.108,-.059),(4.090,-.039),(4.065,-.023),
                      (4.029,-.011),(3.974,-.003),(3.90,0),(3.78,0)]:
        row = []
        for i in range(n):
            a = 2*pi*i/n
            x,y = cos(a),sin(a)
            r = radius / (abs(x)**4.65 + abs(y)**4.65)**(1/4.65)
            row.append((r*x,r*y,z))
        rim.append(row)
    bridge("Continuous ceramic housing", rim, mat)

def area(name, pos, strength, width, height, color=(1,1,1), target=(0,0,0)):
    data = bpy.data.lights.new(name,"AREA")
    data.shape = "RECTANGLE"
    data.size = width
    data.size_y = height
    data.energy = strength
    data.color = color
    ob = bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(ob)
    ob.location = pos
    ob.rotation_euler = (Vector(target)-ob.location).to_track_quat("-Z","Y").to_euler()

def studio():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 80 if stage==3 else 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = 1024
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "16"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("Studio ambient")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value=(.28,.30,.32,1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value=.36
    sc.world = world
    bpy.ops.object.camera_add(location=(0,0,15))
    cam = bpy.context.object
    cam.rotation_euler = (0,0,0)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 10.24
    sc.camera = cam
    area("Upper left silk",(-4,5,7),690,6,4,(1,.965,.91))
    area("Right strip",(4.7,1.7,4),345,1.6,5,(.89,.94,1))
    area("Low softbox",(-2,-4,4),120,4,1.5)
    tile()
    return sc

def pose(obj, degrees, scale=1, x=0, y=0):
    obj.rotation_euler.z = math.radians(degrees)
    obj.location = (x,y,0)
    obj.scale = (scale,scale,scale)
    return obj

def undertone():
    mat = material("Warm bone porcelain",(.79,.72,.60),.21,.265)
    if stage==3:
        mat=material("Pale celadon porcelain",(.64,.75,.69),.17,.235)
    # Cross-sections move from the underside over the rolled lip into the well.
    profile=[(.02,.035,0),(.72,.04,0),(.91,.14,0),(.983,.37,0),(1,.54,.01),
             (.967,.72,.06),(.89,.93,.17),(.77,1.10,.32),(.65,1.19,.47),
             (.55,1.22,.60),(.48,1.20,.68),(.428,1.13,.71),(.39,1.00,.71),
             (.35,.79,.68),(.306,.53,.59),(.24,.32,.43),(.15,.23,.29),(.01,.21,.23)]
    if stage >= 2:
        profile = [(.47,.035,.48),(.74,.04,.06),(.93,.14,0),(.995,.38,0),
                   (1,.59,.02),(.962,.78,.06),(.875,1.00,.18),(.77,1.17,.32),
                   (.689,1.24,.44),(.632,1.247,.50),(.60,1.20,.52),
                   (.577,1.07,.53),(.55,.80,.53),(.50,.43,.51),(.47,.035,.48)]
    rings=[]
    for r,z,offset in profile:
        row=[]
        for i in range(128):
            a=2*pi*i/128
            if stage==3:
                # Flatten the foot and turn the crest obliquely across the bore.
                f=min(1,offset/.52)
                ca,sa=cos(a),sin(a)
                x=(1.85*r*math.copysign(abs(ca)**.86,ca)*(1+.10*sa))
                y=(2.33*r*math.copysign(abs(sa)**.79,sa)+offset*.68)
                turn=-.51*f
                row.append((x*cos(turn)-y*sin(turn)+.18*f,
                            x*sin(turn)+y*cos(turn),
                            z*(1+.48*ca-.13*sa)+.015))
                continue
            row.append((1.74*r*cos(a)*(1+.27*sin(a)), 2.46*r*sin(a)+offset,
                        z+.24*r*sin(a)))
        rings.append(row)
    obj=bridge("Porcelain resonator",rings,mat,cap=stage==1)
    sub=obj.modifiers.new("Slip-cast transitions","SUBSURF")
    sub.levels=sub.render_levels=2
    pose(obj,-53 if stage==3 else -32, [1,1.07,1.11][stage-1],x=-.09 if stage==2 else 0,y=.06 if stage==2 else 0)

def pale_brass(*, satin=False):
    mat = material("Brushed pale brass", (.74,.52,.30), .86, .34)
    low, high = (.365, .395) if satin else (.28, .48)
    brushed(mat, (620,7,410), low, high)
    return mat

def reed():
    mat=material("Satin champagne bronze",(.68,.39,.16),.83,.29)
    if stage==3:
        mat=pale_brass()
    rings=[]
    for j in range(121):
        t=j/120
        y=(t-.5)*4.58
        angle=math.radians(-65+169*t)
        width=1.02*(1-.09*cos(pi*2*t))
        if min(t,1-t)<.045:
            u=1-min(t,1-t)/.045
            width-=.20*(1-math.sqrt(max(0,1-u*u)))
        if stage >= 2:
            angle=math.radians(-12+171*t)
            width *= 1.25
        thick=.12 if stage==1 else .16
        if stage==3:
            t_eased=t*t*(3-2*t)
            angle=math.radians(-13+178*(.52*t+.48*t_eased))
            thick=.32 if args.templates else .235
        row=[]
        for i in range(64):
            a=2*pi*i/64
            u=math.copysign(abs(cos(a))**.30,cos(a))*width
            v=math.copysign(abs(sin(a))**.44,sin(a))*thick
            row.append((u*cos(angle)-v*sin(angle),y,(1.46 if stage==3 else 1.075)+u*sin(angle)+v*cos(angle)))
        rings.append(row)
    obj=bridge("Turned bronze reed",rings,mat)
    pose(obj,[-27,-35,-42][stage-1],1 if stage==1 else 1.12)

def cadence():
    mat=material("Smoked titanium",(.36,.40,.43),.79,.32)
    if stage==3:
        mat=material("Vapour-honed aluminium",(.54,.61,.61),.82,.33)
        brushed(mat,(240,240,120),.29,.39)
    n=360
    rings=[]
    def facepoint(r,a,back=False):
        p=6*(a+.75*r)
        # A short downstroke and a long upslope within each radial lobe.
        wave=(sin(p)+.35*sin(2*p)+.11*sin(3*p))/1.22
        if stage >= 2:
            p=4*(a+.62*r)
            wave=(sin(p)+.39*sin(2*p)+.12*sin(3*p))/1.23
        rr=r*(2.24+(.16 if stage==1 else .36)*r**1.7*wave)
        h=.22+.55*(1-r*r)+(.37*wave+.28)*sin(r*pi*.66)**1.15
        return (rr*cos(a),rr*sin(a),.075 if back else h)
    rings.append([facepoint(.988,2*pi*i/n,True) for i in range(n)])
    for j in range(75):
        r=1-(.999 if stage==1 else .745)*j/74
        rings.append([facepoint(r,2*pi*i/n) for i in range(n)])
    if stage >= 2:
        rings.append([facepoint(.249,2*pi*i/n,True) for i in range(n)])
        rings.append(rings[0])
    if stage==3:
        # Rounded profile at both ends of the stamping. The central bore has
        # the same four-fold symmetry as the skirt, with a smaller amplitude.
        def surface(r,a,dz):
            phase=4*(a+.65*r)
            w=(sin(phase)+.29*sin(2*phase)+.07*sin(3*phase))/1.12
            rad=r*(2.22+(.14+.24*r*r)*w)
            z=.31+.35*(1-r*r)+(.34*w+.25)*r**.82
            return (rad*cos(a),rad*sin(a),z+dz)
        path=[(.980,-.17),(.994,-.12),(1,-.075),(1,-.043),(.996,-.016)]
        path += [(.988-(.988-.356)*j/72,0) for j in range(73)]
        path += [(.348,-.008),(.341,-.023),(.337,-.047),(.337,-.081),(.341,-.14)]
        rings=[[surface(r,2*pi*i/n,dz) for i in range(n)] for r,dz in path]
        rings.append([(x,y,.067) for x,y,z in rings[-1]])
        rings.append([(x,y,.067) for x,y,z in rings[0]])
        rings.append(rings[0])
    obj=bridge("Pressed titanium cadence",rings,mat,cap=stage==1)
    return pose(obj,12,1 if stage==1 else 1.10)

def dovetail():
    mat=material("Pale nickel",(.64,.66,.63),.72,.285)
    curve=bpy.data.curves.new("Offset link outline","CURVE")
    curve.dimensions="2D"
    curve.fill_mode="BOTH"
    curve.extrude=.15
    curve.bevel_depth=.065
    curve.bevel_resolution=5
    # A union outline and two opposite-winding counters form a single casting.
    paths=[
      [(-2.15,-1.73),(.40,-1.73),(.40,-.83),(2.15,-.83),(2.15,1.73),(-.40,1.73),(-.40,.83),(-2.15,.83)],
      [(-1.61,-1.19),(-1.61,.29),(-.14,.29),(-.14,-1.19)],
      [(.14,-.29),(.14,1.19),(1.61,1.19),(1.61,-.29)]
    ]
    if stage >= 2:
        # The outside arc is tangent to the two straight edges at either end.
        cx,cy,r=.82,.46,1.39
        outer_arc=[(cx+r*cos(-pi/2+pi*i/120),cy+r*sin(-pi/2+pi*i/120)) for i in range(121)]
        right_eye=[(cx+.75*cos(-2*pi*i/128),cy+.75*sin(-2*pi*i/128)) for i in range(128)]
        paths=[[(-2.22,-1.78),(.04,-1.78),(.04,cy-r),*outer_arc,(-.62,cy+r),
                (-.62,.74),(-2.22,.74)],
               [(-1.67,-1.19),(-1.67,.15),(-.42,.15),(-.42,-1.19)],right_eye]
    if stage==3:
        mat=material("Bead-blasted pewter",(.72,.71,.65),.63,.35)
        brushed(mat,(6,650,240),.29,.42)
        # A continuous tangent replaces the square overlap at the shoulders.
        def bezier(start,ctrl1,ctrl2,end,count=24):
            return [tuple((1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t*t*c+t**3*d
                          for a,b,c,d in zip(start,ctrl1,ctrl2,end))
                    for t in [i/count for i in range(1,count+1)]]
        def arc(cx,cy,r,a0,a1,count):
            return [(cx+r*cos(a0+(a1-a0)*i/count),cy+r*sin(a0+(a1-a0)*i/count))
                    for i in range(1,count+1)]
        outer=[(-2.25,-1.13),(-.96,-1.13)]
        outer += bezier(outer[-1],(-.49,-1.13),(-.56,-.77),(-.14,-.77))
        outer += bezier(outer[-1],(.22,-.77),(.51,-1.25),(1,-1.25))
        outer += arc(1,0,1.25,-pi/2,pi/2,96)
        outer += bezier(outer[-1],(.51,1.25),(.22,.77),(-.14,.77))
        outer += bezier(outer[-1],(-.56,.77),(-.49,1.13),(-.96,1.13))
        outer += [(-2.25,1.13)]
        # Small radii on the four corners of the squared eye.
        left=[(-1.89,-.57),(-.80,-.57)]
        left+=arc(-.80,-.50,.07,-pi/2,0,8)+arc(-.80,.50,.07,0,pi/2,8)
        left+=arc(-1.82,.50,.07,pi/2,pi,8)+arc(-1.82,-.50,.07,pi,3*pi/2,8)
        right=[(1+.69*cos(-2*pi*i/128),.69*sin(-2*pi*i/128)) for i in range(128)]
        paths=[outer,list(reversed(left)),right]
        curve.bevel_depth=.045
    for points in paths:
        spline=curve.splines.new("POLY")
        spline.points.add(len(points)-1)
        for p,coord in zip(spline.points,points):
            p.co=(*coord,0,1)
        spline.use_cyclic_u=True
    obj=bpy.data.objects.new("Cast double counter",curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.rotation_euler=(math.radians(13),math.radians(-14),math.radians(3))
    obj.location.z=1.03
    if stage>=2:
        obj.rotation_euler=(math.radians(9),0,0)
        obj.scale=(1.13,1.13,1.13)
        obj.location.z=.57
    if stage==3:
        obj.rotation_euler=(math.radians(10),math.radians(-5),math.radians(32))
        obj.location.z=.64
        obj.scale=(1.23,1.23,1.23)

def cadence_brass():
    if args.brass_pass == 1:
        obj = cadence()
        obj.data.materials[0] = pale_brass()
        return obj

    # A revolved section rolls continuously from the top into each sidewall.
    # Contour and relief are independent: a smaller scallop can carry a full fold.
    inner, outer = .83, 2.33
    outer_roll, inner_roll = .085, .12
    if args.brass_pass >= 3:
        inner_roll = .085
    if args.brass_pass >= 4:
        inner_roll = .14
    section = []
    for j in range(25):
        angle = j*pi/48
        section.append((outer-outer_roll+outer_roll*cos(angle),
                        outer_roll*(sin(angle)-1)))
    top_start, top_end = outer-outer_roll, inner+inner_roll
    section.extend((top_start+(top_end-top_start)*j/112, 0) for j in range(1,113))
    for j in range(1,25):
        angle = j*pi/48
        section.append((inner+inner_roll-inner_roll*sin(angle),
                        inner_roll*(cos(angle)-1)))

    base_height = .025 if args.brass_pass >= 3 else .061
    count = 512
    def ring(radius, drop, bottom=False):
        t = (radius-inner)/(outer-inner)
        row = []
        for i in range(count):
            a = 2*pi*i/count
            if args.brass_pass == 2:
                phase = 4*(a + .72*t - .02)
                wave = (sin(phase) + .12*sin(2*phase))/1.03
                contour = (.030 + .135*t*t) * wave
                height = (.37 + .10*(1-t) + .115*sin(pi*t)
                          + .22*(.53 + .47*t)*wave + drop)
            elif args.brass_pass == 3:
                phase = 4*(a + .23 + .47*t)
                wave = (sin(phase) + .25*sin(2*phase) + .035*sin(3*phase))/1.09
                contour = (.040 + .166*t*t) * (sin(phase) + .13*sin(2*phase))
                height = (.415 + .20*(1-t*t) + .285*(.54+.46*t)*wave + drop)
            elif args.brass_pass == 4:
                phase = 4*(a + .14 + .59*t)
                wave = (sin(phase) + .34*sin(2*phase) + .10*sin(3*phase))/1.12
                contour = (.029 + .219*t*t) * (sin(phase) + .14*sin(2*phase))
                # Ease the relief into the lip; a slight inward dish leads into the bore.
                depth = .31*(.39 + .61*t**.84)
                height = (.445 + .18*(1-t*t) - .13*(1-t)**3
                          + depth*wave + drop)
            else:
                # Let the ridges subside at the mouth; their light then travels
                # around the band before the face rolls down into the opening.
                phase = 4*(a + .07 + .78*t)
                wave = (sin(phase) + .18*sin(2*phase))/1.05
                contour = (.03+.208*t*t)*(sin(phase)+.16*sin(2*phase))
                blend = t*t*(3-2*t)
                height = (.425 + .16*(1-t*t) - .10*(1-t)**4
                          + .274*(.12+.88*blend)*wave + drop)
            rr = radius + contour
            row.append((rr*cos(a), rr*sin(a), base_height if bottom else height))
        return row

    rings = [ring(r,dz) for r,dz in section]
    rings.extend([ring(inner,0,True),ring(outer,0,True)])
    # Close the underside with shared indices so the outer roll has no seam.
    verts = [v for row in rings for v in row]
    faces = []
    for j in range(len(rings)):
        j1 = (j+1) % len(rings)
        for i in range(count):
            i1 = (i+1) % count
            faces.append((j*count+i, j*count+i1, j1*count+i1, j1*count+i))
    obj = mesh("Pressed brass cadence",verts,faces,pale_brass(satin=args.brass_pass == 6))
    return pose(obj,12,1.10)

builders={"cadence-brass":cadence_brass,"undertone":undertone,"reed":reed,"cadence":cadence,"dovetail":dovetail}
for name in args.names:
    folder = out
    if name == "cadence-brass":
        folder = root / "studies" / "cadence-brass" / f"pass-{args.brass_pass}"
        folder.mkdir(parents=True, exist_ok=True)
    scene = studio()
    if name == "cadence-brass" and args.brass_pass >= 3:
        scene.cycles.samples = 192
        scene.cycles.adaptive_threshold = .012
    builders[name]()
    if args.templates:
        bpy.data.objects["Continuous ceramic housing"].hide_render=True
        black=bpy.data.materials.new("Template ink")
        black.use_nodes=True
        tree=black.node_tree
        ink=tree.nodes.new("ShaderNodeEmission")
        ink.inputs["Color"].default_value=(0,0,0,1)
        tree.links.new(ink.outputs[0],tree.nodes.get("Material Output").inputs["Surface"])
        scene.view_layers[0].material_override=black
        scene.camera.data.ortho_scale=6.35
        scene.render.resolution_x=scene.render.resolution_y=576
        scene.cycles.samples=12
        scene.render.filepath=str(folder / f"{name}-ink.png")
    else:
        scene.render.filepath = str(folder / f"{name}-plate.png")
    bpy.ops.render.render(write_still=True)
