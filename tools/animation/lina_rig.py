"""Local Blender rig/retarget tool for the user supplied Lina model.

Run in the connected Blender session after importing UAL1_Standard.glb.
The original model is backed up separately before this script is used.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ART = Path('D:/demo/art/lina')
QA = Path('D:/demo/build/qa/lina-rig')
RIG_NAME = 'Lina_Rig'
MODEL_NAMES = [f'tripo_part_{i}' for i in range(17)]


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x-a)/(b-a)))
    return t*t*(3-2*t)


def make_rig():
    if bpy.data.objects.get(RIG_NAME):
        return bpy.data.objects[RIG_NAME]
    bpy.context.window.scene = bpy.data.scenes['Scene']
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    data = bpy.data.armatures.new('Lina_Humanoid')
    rig = bpy.data.objects.new(RIG_NAME, data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    rig.show_in_front = True
    data.display_type = 'OCTAHEDRAL'
    bpy.ops.object.mode_set(mode='EDIT')
    bones = data.edit_bones

    def bone(name, head, tail, parent=None, deform=True):
        b = bones.new(name)
        b.head, b.tail = head, tail
        if parent:
            b.parent = bones[parent]
        b.use_deform = deform
        direction = Vector(tail)-Vector(head)
        b.align_roll(Vector((1,0,0)) if abs(direction.normalized().x) < .85 else Vector((0,0,1)))
        return b

    bone('root', (0,0,0), (0,0,.10), deform=False)
    bone('pelvis', (.018,0,.438), (.02,0,.485), 'root')
    bone('spine_01', (.02,0,.485), (.023,0,.535), 'pelvis')
    bone('spine_02', (.023,0,.535), (.025,0,.582), 'spine_01')
    bone('spine_03', (.025,0,.582), (.028,0,.625), 'spine_02')
    bone('neck_01', (.028,0,.625), (.028,0,.655), 'spine_03')
    bone('Head', (.028,0,.655), (.02,0,.80), 'neck_01')
    for suffix, side in [('l',1), ('r',-1)]:
        bone('clavicle_'+suffix, (.025,side*.024,.601), (.025,side*.083,.591), 'spine_03')
        bone('upperarm_'+suffix, (.025,side*.083,.591), (.039,side*.157,.474), 'clavicle_'+suffix)
        bone('lowerarm_'+suffix, (.039,side*.157,.474), (.045,side*.215,.397), 'upperarm_'+suffix)
        bone('hand_'+suffix, (.045,side*.215,.397), (.047,side*.246,.373), 'lowerarm_'+suffix)
        bone('thigh_'+suffix, (.023,side*.069,.455), (.033,side*.079,.268), 'pelvis')
        bone('calf_'+suffix, (.033,side*.079,.268), (.015,side*.083,.100), 'thigh_'+suffix)
        bone('foot_'+suffix, (.015,side*.083,.100), (.082,side*.083,.034), 'calf_'+suffix)
        bone('ball_'+suffix, (.082,side*.083,.034), (.11,side*.083,.030), 'foot_'+suffix)
        bone('hair_'+suffix, (-.018,side*.102,.664), (-.025,side*.146,.48), 'Head')
        bone('hair_tip_'+suffix, (-.025,side*.146,.48), (-.032,side*.158,.34), 'hair_'+suffix)
        bone('skirt_'+suffix, (.02,side*.07,.443), (.025,side*.14,.285), 'pelvis')
    bone('hair_back', (-.065,0,.67), (-.11,0,.47), 'Head')
    bone('hair_back_tip', (-.11,0,.47), (-.10,0,.33), 'hair_back')
    bone('skirt_front', (.05,0,.443), (.105,0,.285), 'pelvis')
    bone('skirt_back', (-.015,0,.443), (-.06,0,.285), 'pelvis')
    bone('hat_tip', (-.02,0,.815), (-.025,.13,.935), 'Head')
    bone('fireball_socket_r', (.058,-.236,.388), (.10,-.236,.388), 'hand_r', False)
    bpy.ops.object.mode_set(mode='OBJECT')
    for group_name, names in {
        'Body': ['root','pelvis','spine_01','spine_02','spine_03','neck_01','Head'],
        'Arms': [n for n in data.bones.keys() if any(k in n for k in ['clavicle','upperarm','lowerarm','hand_'])],
        'Legs': [n for n in data.bones.keys() if any(k in n for k in ['thigh','calf','foot_','ball_']) and 'socket' not in n],
        'Hair and Cloth': [n for n in data.bones.keys() if n.startswith(('hair','skirt','hat'))],
        'Sockets': ['fireball_socket_r'],
    }.items():
        collection = data.collections.new(group_name)
        for name in names:
            collection.assign(data.bones[name])
    rig['source_model'] = 'User supplied Tripo model in Blender, 2026-10-16'
    rig['forward_axis'] = '+X; character right is -Y; Z up'
    rig['animation_source'] = 'Quaternius Universal Animation Library 1 Standard, CC0'
    rig['fireball_socket'] = 'fireball_socket_r'
    rig['status'] = 'Blender preview; not approved for runtime replacement'
    return rig


def weights_for_part(part, p):
    x,y,z = p
    side = 'l' if y >= 0 else 'r'
    if part in (2,7):
        return {'Head':1}
    if part == 13:
        w = .65*smooth(.82,.95,z)*smooth(.03,.18,y)
        return {'Head':1-w, 'hat_tip':w}
    if part == 0:
        # The face and hair share a mesh. Keep the face/skull rigid; only lower strands bend.
        if z >= .645:
            return {'Head':1}
        w = 1-smooth(.43,.645,z)
        if x < -.055 and abs(y) < .09:
            root, tip = 'hair_back', 'hair_back_tip'
        else:
            root, tip = 'hair_'+side, 'hair_tip_'+side
        tip_w = 1-smooth(.37,.52,z)
        return {'Head':1-w, root:w*(1-tip_w), tip:w*tip_w}
    if part in (10,11):
        return {'hand_r' if part == 10 else 'hand_l':1}
    if part in (6,8):
        suffix = 'r' if part == 6 else 'l'
        t = smooth(.440,.510,z)
        return {'upperarm_'+suffix:t, 'lowerarm_'+suffix:1-t}
    if part in (4,5):
        suffix = 'l' if part == 4 else 'r'
        toe = .22*smooth(.075,.11,x)*(1-smooth(.045,.075,z))
        shin = .3*smooth(.105,.14,z)
        return {'foot_'+suffix:1-toe-shin, 'ball_'+suffix:toe, 'calf_'+suffix:shin}
    if part in (14,15):
        suffix = 'l' if part == 14 else 'r'
        # Generated thigh meshes extend above the hip. Those hidden upper flaps
        # must remain at the pelvis, otherwise they emerge through the dress waist.
        hip = smooth(.29,.345,z)
        thigh = smooth(.236,.302,z)*(1-hip)
        return {'pelvis':hip,'thigh_'+suffix:thigh,'calf_'+suffix:(1-hip)-thigh}
    if part == 9:
        return {'pelvis':1}
    if part == 12:
        return {'spine_03':1}
    if part == 16:
        return {'neck_01':1}
    if part == 3:
        # Cape follows the chest and collar; avoid arm weights tearing the neckline.
        upper = smooth(.49,.61,z)
        return {'spine_02':1-upper,'spine_03':upper}
    if part == 1:
        if z < .45:
            cloth = 1-smooth(.32,.45,z)
            radial = Vector((x-.023,y))
            a, b = abs(radial.x), abs(radial.y)
            denom = a+b+1e-8
            nx = 'skirt_front' if radial.x >= 0 else 'skirt_back'
            ny = 'skirt_l' if radial.y >= 0 else 'skirt_r'
            return {'pelvis':1-cloth,nx:cloth*a/denom,ny:cloth*b/denom}
        levels = [('pelvis',.455),('spine_01',.495),('spine_02',.55),('spine_03',.60)]
        if z >= levels[-1][1]:
            return {levels[-1][0]:1}
        for (lo, za),(hi,zb) in zip(levels,levels[1:]):
            if z <= zb:
                t = smooth(za,zb,z)
                return {lo:1-t,hi:t}
    raise ValueError(f'No weight rule for part {part}')


def bind(rig):
    report = []
    for i,name in enumerate(MODEL_NAMES):
        obj = bpy.data.objects[name]
        if obj.get('lina_bound'):
            continue
        if obj.vertex_groups:
            raise RuntimeError(f'Unexpected existing vertex groups on {name}; inspect before overwriting')
        world = obj.matrix_world.copy()
        obj.parent = rig
        obj.matrix_world = world
        buckets = {}
        for vertex in obj.data.vertices:
            weights = {k:v for k,v in weights_for_part(i,world@vertex.co).items() if v > 1e-7}
            total = sum(weights.values())
            for key, value in weights.items():
                group = obj.vertex_groups.get(key) or obj.vertex_groups.new(name=key)
                group.add([vertex.index],value/total,'REPLACE')
        mod = obj.modifiers.get('Lina Skin') or obj.modifiers.new('Lina Skin', 'ARMATURE')
        mod.object = rig
        mod.use_deform_preserve_volume = True
        obj['lina_bound'] = True
        report.append({'object':name,'vertices':len(obj.data.vertices),'groups':len(obj.vertex_groups)})
    return report


def assign_source(source, action_name):
    action = bpy.data.actions[action_name]
    source.animation_data.action = action
    source.animation_data.action_slot = action.slots[0]
    # glTF imports all actions as NLA strips. Disable those during explicit sampling.
    for track in source.animation_data.nla_tracks:
        track.mute = True
    return action


def bake_actions(rig):
    source = bpy.data.objects['UAL_Source_Rig']
    source.animation_data_create()
    source.hide_set(False)
    scene = bpy.context.scene
    source_fps = float(source.get('import_fps',scene.render.fps))
    source['import_fps'] = source_fps
    scene.render.fps = 30
    conversion = Matrix.Rotation(math.pi/2,3,'Z')
    mirror = Matrix.Diagonal(Vector((-1,1,1)))
    assign_source(source,'Idle_Loop')
    scene.frame_set(0)
    arm_names = {n for n in source.pose.bones.keys() if any(k in n for k in ['upperarm','lowerarm','hand_'])}
    idle_refs = {b.name:b.matrix.to_3x3().normalized().copy() for b in source.pose.bones}
    run_refs = {b.name:(idle_refs[b.name] if b.name in arm_names else b.bone.matrix_local.to_3x3().normalized()) for b in source.pose.bones}
    target_rest = {b.name:b.matrix_local.to_3x3().normalized() for b in rig.data.bones}
    target_local = {b.name:(target_rest[b.parent.name].inverted()@target_rest[b.name] if b.parent else target_rest[b.name]) for b in rig.data.bones}
    hip_idle = source.pose.bones['pelvis'].head.copy()
    hip_rest = source.data.bones['pelvis'].head_local.copy()
    scale = (.455-.034)/(.9321-.0152)
    identity = Quaternion()
    main_bones = [b for b in rig.data.bones if b.name in source.data.bones and b.name != 'root']
    rig.animation_data_create()

    def sample_pose(src_frame, mirrored=False, running=False):
        scene.frame_set(math.floor(src_frame),subframe=src_frame%1)
        refs = run_refs if running else idle_refs
        rotations = {'root':target_rest['root']}
        for b in main_bones:
            source_name = b.name
            if mirrored and source_name.endswith(('_l','_r')):
                source_name = source_name[:-1]+('r' if source_name[-1]=='l' else 'l')
            delta = source.pose.bones[source_name].matrix.to_3x3().normalized()@refs[source_name].inverted()
            if mirrored:
                delta = mirror@delta@mirror
            delta = conversion@delta@conversion.inverted()
            if b.name in ('Head','neck_01'):
                delta = identity.slerp(delta.to_quaternion(),.65).to_matrix()
            rotations[b.name] = delta@target_rest[b.name]
        actual_rotations = {'root':target_rest['root']}
        for b in main_bones:
            parent = rotations[b.parent.name]
            basis = target_local[b.name].inverted()@parent.inverted()@rotations[b.name]
            q = basis.to_quaternion().normalized()
            if running and b.name.startswith('thigh_'):
                # The adult source lifts knees into this character's short dress.
                # Retain its timing and support changes, reduce the hip excursion.
                amount = min(.60,.68/max(q.angle,1e-8))
                q = identity.slerp(q,amount)
            elif running and b.name.startswith('calf_'):
                q = identity.slerp(q,.80)
            elif running and b.name.startswith('upperarm_'):
                q = identity.slerp(q,.60)
            elif running and b.name.startswith('lowerarm_'):
                q = identity.slerp(q,.75)
            elif running and b.name.startswith(('foot_','ball_')):
                # Preserve the source foot orientation after shortening the stride.
                basis = target_local[b.name].inverted()@actual_rotations[b.parent.name].inverted()@rotations[b.name]
                q = basis.to_quaternion().normalized()
            pb = rig.pose.bones[b.name]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q
            pb.location = (0,0,0)
            actual_rotations[b.name] = actual_rotations[b.parent.name]@target_local[b.name]@q.to_matrix()
        hip_delta = source.pose.bones['pelvis'].head-(hip_rest if running else hip_idle)
        if mirrored:
            hip_delta = mirror@hip_delta
        # Root remains stationary. Preserve only the template's small hip motion.
        rig.pose.bones['pelvis'].location = target_rest['pelvis'].inverted()@(conversion@hip_delta*scale)

    definitions = [
        ('Lina_Idle','Idle_Loop',False,True),
        ('Lina_Run','Jog_Fwd_Loop',False,True),
        ('Lina_Cast_Enter_R','Spell_Simple_Enter',True,False),
        ('Lina_Cast_Hold_R','Spell_Simple_Idle_Loop',True,True),
        ('Lina_Cast_Release_R','Spell_Simple_Shoot',True,False),
        ('Lina_Cast_Exit_R','Spell_Simple_Exit',True,False),
    ]
    result = []
    for target_name,source_name,mirrored,loop in definitions:
        if bpy.data.actions.get(target_name):
            raise RuntimeError(f'{target_name} already exists; do not replace edited actions automatically')
        src_action = assign_source(source,source_name)
        start,end = src_action.frame_range
        frames = max(1,round((end-start)*30/source_fps))
        action = bpy.data.actions.new(target_name)
        action.use_fake_user = True
        action['source_action'] = source_name
        action['source_author'] = 'Quaternius'
        action['source_license'] = 'CC0-1.0'
        action['mirrored_for_right_hand'] = mirrored
        action['loop'] = loop
        rig.animation_data.action = action
        for pb in rig.pose.bones:
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = identity
            pb.location = (0,0,0)
        for frame in range(frames+1):
            sample_pose(start+(end-start)*frame/frames,mirrored,target_name == 'Lina_Run')
            phase = 2*math.pi*frame/frames
            # Secondary chains are actual deform bones; the face and brim stay rigid.
            for pb in rig.pose.bones:
                if pb.name.startswith('hair'):
                    amount = .026 if target_name == 'Lina_Run' else .008
                    pb.rotation_quaternion = Quaternion((0,1,0),amount*math.sin(phase*2-.8))
                elif pb.name.startswith('skirt'):
                    amount = .10 if target_name == 'Lina_Run' else .014
                    offset = 0 if pb.name.endswith('l') else math.pi
                    pb.rotation_quaternion = Quaternion((1,0,0),amount*math.sin(phase+offset))
                elif pb.name == 'hat_tip':
                    pb.rotation_quaternion = Quaternion((1,0,0),(.025 if target_name == 'Lina_Run' else .008)*math.sin(phase-.7))
            if target_name == 'Lina_Run':
                # Open the skirt around the lifted knee instead of allowing the leg through it.
                thigh_angles = {s:rig.pose.bones['thigh_'+s].rotation_quaternion.to_euler('XYZ').x for s in ('l','r')}
                front = max(0.0,*thigh_angles.values())
                back = max(0.0,*[-v for v in thigh_angles.values()])
                for n,angle in [('skirt_front',front*.95),('skirt_back',-back*.75),('skirt_l',max(0,thigh_angles['l'])*.9),('skirt_r',max(0,thigh_angles['r'])*.9)]:
                    rig.pose.bones[n].rotation_quaternion = Quaternion((1,0,0),angle)
            # Match actual boot soles, preserving the source's short airborne phase.
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            sole = float('inf')
            for boot_name in ('tripo_part_4','tripo_part_5'):
                boot = bpy.data.objects[boot_name].evaluated_get(dg)
                mesh = boot.to_mesh()
                sole = min(sole,min((boot.matrix_world@v.co).z for v in mesh.vertices))
                boot.to_mesh_clear()
            desired_height = 0.0
            if target_name == 'Lina_Run':
                desired_height = min(.018,max(0.0,min(source.pose.bones['ball_l'].head.z,source.pose.bones['ball_r'].head.z)-.0152)*scale*.15)
            rig.pose.bones['pelvis'].location += target_rest['pelvis'].inverted()@Vector((0,0,desired_height-sole))
            for pb in rig.pose.bones:
                if pb.name in ('root','fireball_socket_r'):
                    continue
                pb.keyframe_insert('rotation_quaternion',frame=frame+1,group=pb.name)
            rig.pose.bones['pelvis'].keyframe_insert('location',frame=frame+1,group='pelvis')
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        if loop and len(curve.keyframe_points)>1:
                            curve.keyframe_points[-1].co.y = curve.keyframe_points[0].co.y
                        for key in curve.keyframe_points:
                            key.interpolation = 'LINEAR'
        action.asset_mark()
        result.append({'action':target_name,'source':source_name,'frames':frames+1,'seconds':frames/30,'loop':loop,'right_hand_mirror':mirrored})
    source.hide_set(True)
    return result


def main():
    ART.mkdir(parents=True,exist_ok=True)
    QA.mkdir(parents=True,exist_ok=True)
    rig = make_rig()
    bindings = bind(rig)
    actions = bake_actions(rig)
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 76
    rig.animation_data.action = bpy.data.actions['Lina_Idle']
    rig.animation_data.action_slot = rig.animation_data.action.slots[0]
    bpy.context.scene.frame_set(1)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    # Keep external template meshes out of all production views and renders.
    for name in ('Mannequin','棱角球','UAL_Source_Rig'):
        obj = bpy.data.objects.get(name)
        if obj:
            obj.hide_set(True)
            obj.hide_render = True
    report = {'rig':rig.name,'bones':len(rig.data.bones),'bindings':bindings,'actions':actions,'runtime_integrated':False}
    (QA/'binding_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/'lina_rigged_20261016.blend'),compress=True)
    return report


if __name__ == '__main__':
    result = main()
