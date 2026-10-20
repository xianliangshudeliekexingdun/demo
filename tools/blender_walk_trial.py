"""Isolated chibi walk study. Run through Blender MCP; no game asset changes."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector, Matrix

OUT = Path('D:/demo/build/qa/blender-walk-v4')
OUT.mkdir(parents=True, exist_ok=True)
scene = bpy.data.scenes.new('Lina_Walk_Study_v4')
bpy.context.window.scene = scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 480
scene.render.resolution_y = 480
scene.render.resolution_percentage = 100
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 32
scene.render.image_settings.file_format = 'PNG'
sh = scene.display.shading
sh.light = 'STUDIO'
sh.color_type = 'MATERIAL'
sh.show_shadows = True
sh.show_cavity = True
sh.cavity_type = 'BOTH'
sh.background_type = 'WORLD'
scene.world = bpy.data.worlds.new('Walk_Study_World')
scene.world.color = (.055, .075, .10)
COLORS = {'body':(.68,.63,.82,1),'left':(.17,.64,.72,1), 'right':(.92,.48,.25,1),'joint':(.20,.22,.29,1),'face':(.92,.83,.68,1),'eye':(.055,.10,.16,1),'ground':(.16,.20,.25,1)}
mats = {}
for name, color in COLORS.items():
    m = bpy.data.materials.new('Study_'+name)
    m.diffuse_color = color
    mats[name] = m

arm = bpy.data.armatures.new('Study_Skeleton')
rig = bpy.data.objects.new('Walk_Rig', arm)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
rig.show_in_front = True
bpy.ops.object.mode_set(mode='EDIT')
rest = {}
def bone(name, a, b, parent=None):
    eb = arm.edit_bones.new(name)
    eb.head, eb.tail = a, b
    if parent: eb.parent = arm.edit_bones[parent]
    rest[name] = (Vector(a), Vector(b))
bone('pelvis', (0,0,.70), (0,0,.87))
bone('chest', (0,0,.87), (0,0,1.23), 'pelvis')
bone('head', (0,0,1.23), (0,0,1.75), 'chest')
for s, x in [('L',-.14),('R',.14)]:
    bone('thigh.'+s,(x,0,.70),(x,-.035,.40),'pelvis')
    bone('shin.'+s,(x,-.035,.40),(x,0,.10),'thigh.'+s)
    bone('foot.'+s,(x,0,.10),(x,-.20,.10),'shin.'+s)
    bone('upperarm.'+s,(x*2,0,1.16),(x*2.3,0,.94),'chest')
    bone('forearm.'+s,(x*2.3,0,.94),(x*2.5,-.035,.73),'upperarm.'+s)
bpy.ops.object.mode_set(mode='OBJECT')
for pb in rig.pose.bones: pb.rotation_mode = 'QUATERNION'

def ellipsoid(name, location, scale, material, bind=None, direction=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=location)
    ob = bpy.context.object
    ob.name = name
    if direction: ob.rotation_euler = Vector(direction).to_track_quat('Z','Y').to_euler()
    ob.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for p in ob.data.polygons: p.use_smooth = True
    ob.data.materials.append(mats[material])
    if bind:
        vg = ob.vertex_groups.new(name=bind)
        vg.add(list(range(len(ob.data.vertices))),1,'REPLACE')
        mod = ob.modifiers.new('Skeleton','ARMATURE')
        mod.object = rig
    return ob

ellipsoid('Pelvis',(0,0,.75),(.215,.14,.145),'body','pelvis')
ellipsoid('Torso',(0,0,1.02),(.225,.14,.245),'body','chest')
ellipsoid('Head',(0,-.015,1.55),(.335,.285,.335),'face','head')
for x in [-.105,.105]:
    ellipsoid('Eye',(x,-.284,1.58),(.027,.018,.041),'eye','head')
ellipsoid('Nose',(0,-.302,1.49),(.032,.026,.031),'face','head')
for s in ['L','R']:
    c = 'left' if s=='L' else 'right'
    for part in ['thigh','shin','upperarm','forearm']:
        n = part+'.'+s
        a,b = rest[n]
        radius = .079 if part in ['thigh','shin'] else .061
        ellipsoid(n+'_mesh',(a+b)/2,(radius,radius,(b-a).length*.53),c,n,b-a)
        ellipsoid(n+'_joint',a,(radius*.92,)*3,'joint',n)
    x = -.14 if s=='L' else .14
    ellipsoid('Shoe.'+s,(x,-.07,.075),(.09,.16,.075),c,'foot.'+s)
    ellipsoid('Hand.'+s,(x*2.5,-.035,.72),(.073,.062,.08),'face','forearm.'+s)

bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.008))
bpy.context.object.name = 'Study_Ground'
bpy.context.object.data.materials.append(mats['ground'])
camdata = bpy.data.cameras.new('Study_Camera')
cam = bpy.data.objects.new('Study_Camera',camdata)
scene.collection.objects.link(cam)
scene.camera = cam
camdata.type = 'ORTHO'
camdata.ortho_scale = 2.35
cam.location = (3,-6,3.0)
cam.rotation_euler = (Vector((0,0,.92))-cam.location).to_track_quat('-Z','Y').to_euler()

def pose_segment(name,a,b):
    pb = rig.pose.bones[name]
    bpy.context.view_layer.update()
    pb.matrix = Matrix.Translation(a) @ (Vector(b)-Vector(a)).to_track_quat('Y','Z').to_matrix().to_4x4()
    bpy.context.view_layer.update()
    pb.keyframe_insert('location',frame=frame)
    pb.keyframe_insert('rotation_quaternion',frame=frame)
    pb.keyframe_insert('scale',frame=frame)

# One 32-frame cycle, including frame33 closure. Travel equivalent 0.64 units/cycle.
# Stance occupies 60%; matching velocity compensates root travel exactly.
metrics=[]
for frame in range(1,34):
    t=(frame-1)/32
    angle=2*math.pi*t
    pelvis=Vector((.020*math.cos(angle),0,.674-.018*math.cos(2*angle)))
    chest=pelvis+Vector((-.008*math.cos(angle),-.014,.17))
    neck=chest+Vector((-.009*math.cos(angle),-.012,.36))
    pose_segment('pelvis',pelvis,chest)
    pose_segment('chest',chest,neck)
    pose_segment('head',neck,neck+Vector((0,0,.52)))
    row={'frame':frame,'feet':{}}
    for s,sgn,offset in [('L',-1,0),('R',1,.5)]:
        p=(t+offset)%1
        if p<.6:
            y=-.192+.64*p
            z=.10
        else:
            u=(p-.6)/.4
            # Cubic Hermite, same endpoint velocity as stance, with short toe clearance.
            h=3*u*u-2*u*u*u
            y=.192-.384*h+.256*(2*u*u*u-3*u*u+u)
            z=.10+.105*math.sin(math.pi*u)**2
        hip=pelvis+Vector((sgn*.14, .016*sgn*math.sin(angle),0))
        ankle=Vector((sgn*.14,y,z))
        delta=ankle-hip
        d=delta.length
        upper=(rest['thigh.'+s][1]-rest['thigh.'+s][0]).length
        lower=(rest['shin.'+s][1]-rest['shin.'+s][0]).length
        along=(upper*upper-lower*lower+d*d)/(2*d)
        axis=delta.normalized()
        forward=Vector((0,-1,0))
        bend=(forward-axis*forward.dot(axis)).normalized()
        knee=hip+axis*along+bend*math.sqrt(max(0,upper*upper-along*along))
        pose_segment('thigh.'+s,hip,knee)
        pose_segment('shin.'+s,knee,ankle)
        pose_segment('foot.'+s,ankle,ankle+Vector((0,-.20,0)))
        shoulder=neck+Vector((sgn*.28, .022*sgn*math.sin(angle),-.07))
        swing=-sgn*.23*math.cos(angle)
        elbow=shoulder+Vector((sgn*.025,.22*math.sin(swing),-.22*math.cos(swing)))
        hand=elbow+Vector((sgn*.02,.21*math.sin(swing-.16),-.21*math.cos(swing-.16)))
        pose_segment('upperarm.'+s,shoulder,elbow)
        pose_segment('forearm.'+s,elbow,hand)
        row['feet'][s]={'phase':p,'ankle':list(ankle),'stance':p<.6,'reach_margin':upper+lower-d}
    metrics.append(row)

scene.frame_set(1)
bpy.context.view_layer.update()
# Verify evaluated skeleton endpoints, rather than only designed trajectories.
max_error=0
for row in metrics:
    scene.frame_set(row['frame'])
    bpy.context.view_layer.update()
    for s in ['L','R']:
        actual=rig.pose.bones['shin.'+s].tail.copy()
        max_error=max(max_error,(actual-Vector(row['feet'][s]['ankle'])).length)
scene.frame_set(1)
start={p.name:p.matrix.copy() for p in rig.pose.bones}
scene.frame_set(33)
loop_error=max(max(abs(p.matrix[r][c]-start[p.name][r][c]) for r in range(4) for c in range(4)) for p in rig.pose.bones)
report={'blender':bpy.app.version_string,'frames':32,'fps':24,'ankle_error':max_error,'loop_matrix_error':loop_error,'minimum_reach_margin':min(f['reach_margin'] for row in metrics for f in row['feet'].values()),'notes':['In-place walk; compensated travel 0.64 units per cycle.','Flat-foot contact study; heel-toe articulation and clothing not implemented.','Analytic two-bone IK baked onto editable armature action.'],'samples':metrics}
(OUT/'verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
scene.frame_set(1)
scene.render.filepath=str(OUT/'front/frame_')
(OUT/'front').mkdir(exist_ok=True)
# Write only the study scene and dependencies. Preserve user's current unsaved file.
bpy.data.libraries.write(str(OUT/'walk-study.blend'),{scene},fake_user=True)
result={'scene':scene.name,'file':str(OUT/'walk-study.blend'),'ankle_error':max_error,'loop_error':loop_error,'objects':len(scene.objects)}
