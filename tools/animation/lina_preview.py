"""Build editable Blender previews and inspect actual skinned geometry."""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector, Quaternion

QA = Path('D:/demo/build/qa/lina-rig')
ART = Path('D:/demo/art/lina')
RIG = 'Lina_Rig'


def assign(rig, action):
    rig.animation_data_create()
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]


def pose_at(rig, action_name, frame):
    assign(rig, bpy.data.actions[action_name])
    bpy.context.scene.frame_set(int(frame), subframe=frame%1)
    return {pb.name:(pb.rotation_quaternion.copy(),pb.location.copy()) for pb in rig.pose.bones}


def combined_attack():
    rig = bpy.data.objects[RIG]
    if bpy.data.actions.get('Lina_Attack_Fireball_R'):
        return bpy.data.actions['Lina_Attack_Fireball_R']
    pieces = [('Lina_Cast_Enter_R',17),('Lina_Cast_Hold_R',12),('Lina_Cast_Release_R',16),('Lina_Cast_Exit_R',14)]
    samples = []
    for name,count in pieces:
        for frame in range(1,count+1):
            samples.append(pose_at(rig,name,frame))
    # Adjacent source clips meet in the same pose. Blend the small export mismatches.
    boundaries = [17,29,45]
    for boundary in boundaries:
        left,right = samples[boundary-1],samples[boundary]
        for offset in range(3):
            blend = (offset+1)/4
            index = boundary+offset
            if index >= len(samples):
                break
            for name in samples[index]:
                q,loc = samples[index][name]
                samples[index][name] = (left[name][0].slerp(q,blend),left[name][1].lerp(loc,blend))
    # The beginning and end are the same relaxed neutral pose for preview looping.
    neutral = pose_at(rig,'Lina_Idle',1)
    for index in range(4):
        blend = index/3
        for name,(q,loc) in list(samples[index].items()):
            samples[index][name] = (neutral[name][0].slerp(q,blend),neutral[name][1].lerp(loc,blend))
    for k in range(4):
        blend = (k+1)/4
        index = len(samples)-4+k
        for name,(q,loc) in list(samples[index].items()):
            samples[index][name] = (q.slerp(neutral[name][0],blend),loc.lerp(neutral[name][1],blend))
    action = bpy.data.actions.new('Lina_Attack_Fireball_R')
    action.use_fake_user = True
    action['source_author'] = 'Quaternius'
    action['source_license'] = 'CC0-1.0'
    action['source_action'] = 'Spell_Simple_Enter + Idle + Shoot + Exit; mirrored'
    action['release_frame'] = 32
    action['preview_only_timing'] = True
    assign(rig,action) if action.slots else setattr(rig.animation_data,'action',action)
    for frame,pose in enumerate(samples,1):
        for name,(q,location) in pose.items():
            if name in ('root','fireball_socket_r'):
                continue
            pb = rig.pose.bones[name]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion, pb.location = q,location
            pb.keyframe_insert('rotation_quaternion',frame=frame,group=name)
            if name == 'pelvis':
                pb.keyframe_insert('location',frame=frame,group=name)
    for name,frame in [('Charge',1),('Ready',17),('Release_R',32),('Recover',46),('End',59)]:
        marker = action.pose_markers.new(name)
        marker.frame = frame
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    action.asset_mark()
    return action


def material(name, color, emission=False):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color,1)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color,1)
    bsdf.inputs['Roughness'].default_value = .78
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*color,1)
        bsdf.inputs['Emission Strength'].default_value = 3
    return mat


def remove_preview_effects():
    """The approved character preview contains skeletal motion only."""
    orb = bpy.data.objects.get('Preview_Fireball_Only')
    if not orb:
        return []
    mesh = orb.data
    action = orb.animation_data.action if orb.animation_data else None
    materials = [slot.material for slot in orb.material_slots if slot.material]
    name = orb.name
    bpy.data.objects.remove(orb,do_unlink=True)
    if action and action.users == 0:
        bpy.data.actions.remove(action)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
    for mat in materials:
        if mat.users == 0:
            bpy.data.materials.remove(mat)
    return [name]


def setup_preview():
    remove_preview_effects()
    existing = bpy.data.scenes.get('Lina_Animation_Preview')
    if existing and existing.camera:
        return existing
    if existing:
        bpy.data.scenes.remove(existing)
    combined_attack()
    scene = bpy.data.scenes.new('Lina_Animation_Preview')
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 12
    scene.render.resolution_x = 1440
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1,151
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    scene.world = bpy.data.worlds.new('Lina_Preview_World')
    scene.world.use_nodes = True
    bg = next(n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Color'].default_value = (.07,.09,.14,1)
    bg.inputs['Strength'].default_value = .35
    rig_source = bpy.data.objects[RIG]
    neutral = bpy.data.actions['Lina_Idle']
    for index,(label,name) in enumerate([('IDLE','Lina_Idle'),('RUN','Lina_Run'),('FIREBALL / RIGHT HAND','Lina_Attack_Fireball_R')]):
        rig = rig_source.copy()
        rig.name = 'Preview_'+label.split(' /')[0]
        scene.collection.objects.link(rig)
        rig.animation_data_clear()
        rig.animation_data_create()
        rig.location = (0,(index-1)*1.12,0)
        rig.rotation_euler.z = math.radians(-12)
        action = bpy.data.actions[name]
        track = rig.animation_data.nla_tracks.new()
        strip = track.strips.new(name,1,action)
        strip.action_slot = action.slots[0]
        strip.repeat = 12
        strip.extrapolation = 'NOTHING'
        rig.hide_render = False
        rig.show_in_front = False
        rig['preview_action'] = name
        for part in range(17):
            obj = bpy.data.objects[f'tripo_part_{part}'].copy()
            obj.name = f'Preview_{index}_part_{part}'
            scene.collection.objects.link(obj)
            obj.parent = rig
            for mod in obj.modifiers:
                if mod.type == 'ARMATURE':
                    mod.object = rig
            obj.hide_render = False
    floor_data = bpy.data.meshes.new('Preview_Floor')
    floor_data.from_pydata([(-2,-3,-.012),(3,-3,-.012),(3,3,-.012),(-2,3,-.012)],[],[(0,1,2,3)])
    floor = bpy.data.objects.new('Preview_Floor',floor_data)
    scene.collection.objects.link(floor)
    floor.data.materials.append(material('Preview_floor_mat',(.065,.075,.10)))
    camera_data = bpy.data.cameras.new('Preview_Camera')
    camera = bpy.data.objects.new('Preview_Camera',camera_data)
    scene.collection.objects.link(camera)
    camera.location = (4,0,1.65)
    camera.rotation_euler = (Vector((0,0,.45))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera_data.type, camera_data.ortho_scale = 'ORTHO',3.48
    scene.camera = camera
    text_mat = material('Preview_labels',(.72,.81,.93),True)
    for index,label in enumerate(['IDLE','RUN','FIREBALL / RIGHT HAND']):
        data = bpy.data.curves.new('Preview_label_'+str(index),'FONT')
        data.body, data.align_x, data.size = label,'CENTER',.064 if index < 2 else .047
        obj = bpy.data.objects.new(data.name,data)
        scene.collection.objects.link(obj)
        obj.location = (.05,(index-1)*1.12,1.13)
        obj.rotation_euler = camera.rotation_euler.copy()
        obj.data.materials.append(text_mat)
    for name,loc,power,size in [('Key',(2,-2,3),170,3),('Fill',(2,2,1.6),110,3),('Rim',(-1,1,2.4),170,2)]:
        data = bpy.data.lights.new('Preview_'+name,'AREA')
        data.energy, data.shape, data.size = power,'DISK',size
        obj = bpy.data.objects.new(data.name,data)
        scene.collection.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = (Vector((0,0,.5))-obj.location).to_track_quat('-Z','Y').to_euler()
    scene['scope'] = 'Blender-only animation preview; no gameplay rules or runtime integration'
    scene['visual_effects'] = False
    bpy.context.window.scene = scene
    return scene


def validate():
    scene = bpy.data.scenes['Scene']
    bpy.context.window.scene = scene
    rig = bpy.data.objects[RIG]
    report = {'weights':{},'actions':{},'notes':['Blender-only validation; user quality review pending.']}
    for i in range(17):
        obj = bpy.data.objects[f'tripo_part_{i}']
        sums = [sum(g.weight for g in v.groups) for v in obj.data.vertices]
        report['weights'][obj.name] = {'vertices':len(sums),'unweighted':sum(s < .999 for s in sums),'max_sum_error':max(abs(s-1) for s in sums)}
    for name in ['Lina_Idle','Lina_Run','Lina_Attack_Fireball_R','Lina_Cast_Hold_R']:
        action = bpy.data.actions[name]
        first,last = action.frame_range
        pose1 = pose_at(rig,name,first)
        pose2 = pose_at(rig,name,last)
        loop_error = max(pose1[n][0].rotation_difference(pose2[n][0]).angle for n in pose1)
        samples = []
        for frame in [first,(first+last)/2,last]:
            pose_at(rig,name,frame)
            dg = bpy.context.evaluated_depsgraph_get()
            z_values = []
            for part in [4,5]:
                obj = bpy.data.objects[f'tripo_part_{part}'].evaluated_get(dg)
                mesh = obj.to_mesh()
                z_values.extend((obj.matrix_world@v.co).z for v in mesh.vertices)
                obj.to_mesh_clear()
            samples.append({'frame':frame,'boot_lowest_z':min(z_values),'right_hand':list(rig.pose.bones['hand_r'].head),'left_hand':list(rig.pose.bones['hand_l'].head)})
        report['actions'][name] = {'frames':list(action.frame_range),'loop_angle_error_degrees':math.degrees(loop_error),'samples':samples}
    (QA/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return report


def render_frames(frames, animated=False):
    scene = bpy.data.scenes['Lina_Animation_Preview']
    bpy.context.window.scene = scene
    paths=[]
    for frame in frames:
        scene.frame_set(frame)
        path = QA/'frames'/f'frame_{(frame-1)//3:04d}.png' if animated else QA/f'preview_{frame:04d}.png'
        path.parent.mkdir(parents=True,exist_ok=True)
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True,scene=scene.name)
        paths.append(str(path))
    return {'frames':paths}
