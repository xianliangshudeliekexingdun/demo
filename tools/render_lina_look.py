import bpy
from pathlib import Path
O=Path('D:/demo/build/qa/lina-blender-look-v1')
s=next(s for s in bpy.data.scenes if s.name.startswith('Lina_Appearance_Study'))
bpy.context.window.scene=s
bpy.ops.render.render(write_still=True,scene=s.name)
bpy.ops.wm.save_as_mainfile(filepath=str(O/'lina-look-editable.blend'))
