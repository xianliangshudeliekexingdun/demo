import bpy
from pathlib import Path
from mathutils import Vector
out=Path('D:/demo/build/qa/blender-walk-v4')
scene=next(s for s in bpy.data.scenes if s.name.startswith('Lina_Walk_Study_v4'))
bpy.context.window.scene=scene
for view,position in [('front',(3,-6,3)),('side',(6,0,2.1))]:
    (out/view).mkdir(exist_ok=True)
    scene.camera.location=position
    scene.camera.rotation_euler=(Vector((0,0,.92))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(out/view/'frame_')
    bpy.ops.render.render(animation=True,scene=scene.name)
scene.camera.location=(3,-6,3)
scene.camera.rotation_euler=(Vector((0,0,.92))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'walk-study-editable.blend'))
(out/'render-complete.txt').write_text('front and side: 32 frames each',encoding='utf-8')
