"""Render the imported model's parts for anatomical inspection; never edit source meshes."""
import bpy
from mathutils import Vector, Matrix
from pathlib import Path


def render_atlas():
    scene = bpy.data.scenes.new('Lina_Part_Inspection')
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 8
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1600
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.world = bpy.data.worlds.new('Lina_Atlas_World')
    scene.world.color = (0.25, 0.25, 0.25)
    scene.view_settings.view_transform = 'Standard'
    for i in range(17):
        original = bpy.data.objects[f'tripo_part_{i}']
        copy = original.copy()
        scene.collection.objects.link(copy)
        copy.parent = None
        copy.matrix_world = original.matrix_world.copy()
        shift = Vector((0, (i % 4 - 1.5) * .62, (4 - i // 4) * 1.10))
        copy.location += shift
        text = bpy.data.curves.new(f'part_label_{i}', 'FONT')
        text.body = f'part {i}'
        text.align_x = 'CENTER'
        text.size = .065
        obj = bpy.data.objects.new(text.name, text)
        scene.collection.objects.link(obj)
        obj.location = (.3, shift.y, shift.z - .06)
        obj.rotation_euler = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0))).to_euler()
    camera_data = bpy.data.cameras.new('Lina_Atlas_Camera')
    camera = bpy.data.objects.new(camera_data.name, camera_data)
    scene.collection.objects.link(camera)
    camera.location = (7, 0, 2.65)
    camera.rotation_euler = (Vector((0, 0, 2.65)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = 5.8
    scene.camera = camera
    for name, loc, power, size in [('Key', (4, -2, 5), 500, 5), ('Fill', (3, 3, 2), 300, 4)]:
        light_data = bpy.data.lights.new('Atlas_' + name, 'AREA')
        light_data.energy = power
        light_data.shape = 'DISK'
        light_data.size = size
        light = bpy.data.objects.new(light_data.name, light_data)
        scene.collection.objects.link(light)
        light.location = loc
        light.rotation_euler = (Vector((0, 0, 2.7)) - light.location).to_track_quat('-Z', 'Y').to_euler()
    out = Path('D:/demo/build/qa/lina-rig/part_atlas.png')
    out.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True, scene=scene.name)
    return {'atlas': str(out), 'scene': scene.name}


result = render_atlas()
