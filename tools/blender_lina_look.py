"""Static Lina appearance study; local geometry only, isolated from game assets."""
import bpy, math
from mathutils import Vector
from pathlib import Path
O=Path('D:/demo/build/qa/lina-blender-look-v1');O.mkdir(parents=True,exist_ok=True)
s=bpy.data.scenes.new('Lina_Appearance_Study');bpy.context.window.scene=s
s.render.engine='BLENDER_WORKBENCH'
s.render.resolution_x=768;s.render.resolution_y=768;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.film_transparent=True
s.display.shading.light='STUDIO';s.display.shading.color_type='MATERIAL'
s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.cavity_type='BOTH'
s.display.shading.show_object_outline=True;s.display.shading.object_outline_color=(.07,.035,.09)
s.display.shading.studio_light='paint.sl'
s.view_settings.view_transform='Standard'
colors={'purple':(.17,.095,.25,1),'hat':(.22,.135,.29,1),'lining':(.28,.17,.36,1),'gold':(.68,.47,.21,1),'cream':(.9,.82,.65,1),'lace':(.99,.93,.78,1),'skin':(1,.73,.58,1),'hair':(.86,.82,.94,1),'hairshade':(.64,.60,.76,1),'brown':(.23,.135,.105,1),'band':(.38,.24,.18,1),'dark':(.055,.026,.07,1),'white':(.99,.98,1,1),'blue':(.025,.37,.85,1),'cyan':(.03,.81,1,1),'blush':(.94,.40,.40,1)}
m={}
for k,c in colors.items():
 a=bpy.data.materials.new('LinaStudy_'+k);a.diffuse_color=c;m[k]=a
def finish(o,name,mat,smooth=True):
 o.name=name;o.data.materials.append(m[mat])
 if smooth and o.type=='MESH':
  for p in o.data.polygons:p.use_smooth=True
 return o
def ball(name,pos,scale,mat):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=20,location=pos)
 o=bpy.context.object;o.scale=scale;return finish(o,name,mat)
def mesh(name,verts,faces,mat,smooth=True):
 d=bpy.data.meshes.new(name);d.from_pydata(verts,[],faces);d.update();o=bpy.data.objects.new(name,d);s.collection.objects.link(o);return finish(o,name,mat,smooth)
def tube(name,pts,r,mat):
 d=bpy.data.curves.new(name,'CURVE');d.dimensions='3D';d.bevel_depth=r;d.bevel_resolution=3
 sp=d.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for p,co in zip(sp.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(name,d);s.collection.objects.link(o);o.data.materials.append(m[mat]);return o
def rings(name,rows,mat,n=64,pleat=0):
 v=[]
 for x,y,z,rx,ry in rows:
  for j in range(n):
   a=2*math.pi*j/n;f=1+pleat*math.cos(10*a);v.append((x+rx*math.cos(a)*f,y+ry*math.sin(a)*f,z))
 faces=[tuple(range(n-1,-1,-1))]
 for k in range(len(rows)-1):
  for j in range(n):faces.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
 faces.append(tuple((len(rows)-1)*n+j for j in range(n)))
 return mesh(name,v,faces,mat)

# Boots, stocking legs and cream dress.
for x in [-.17,.17]:
 ball('Stocking',(x,0,.42),(.095,.095,.29),'dark')
 ball('Boot',(x,-.07,.15),(.125,.19,.15),'brown')
 rings('Boot_cuff',[(x,0,.18,.105,.10),(x,0,.35,.10,.095)],'brown',32)
 tube('Boot_gold_trim',[(x-.095,-.03,.34),(x,-.10,.30),(x+.095,-.03,.34)],.013,'gold')
 for z in [.20,.25]:tube('Boot_laces',[(x-.04,-.105,z),(x+.04,-.105,z+.025)],.008,'gold')
rings('Dress',[(0,0,.59,.40,.26),(0,0,.64,.385,.25),(0,0,.88,.27,.19),(0,0,1.13,.20,.14)],'cream',64,.04)
rings('Lace_hem',[(0,0,.565,.41,.267),(0,0,.61,.405,.265)],'lace',64,.045)
for j in range(32):
 a=j*math.tau/32;ball('Hem_scallop',(.40*math.cos(a),.26*math.sin(a),.574),(.028,.025,.024),'lace')
for sign in [-1,1]:
 tube('Dress_seam',[(sign*.14,-.15,1.04),(sign*.20,-.195,.84),(sign*.30,-.23,.64)],.009,'gold')
ball('Neck',(0,0,1.23),(.095,.09,.14),'skin')
# Back cape, open at the front.
v=[];n=48
for z,rx,ry in [(1.22,.22,.17),(1.08,.33,.23),(.78,.39,.29),(.51,.43,.32)]:
 for j in range(n):
  a=-.25+(math.pi+.50)*j/(n-1);v.append((rx*math.cos(a),ry*math.sin(a),z+.035*math.cos(a*4)))
f=[]
for k in range(3):
 for j in range(n-1):f.append((k*n+j,k*n+j+1,(k+1)*n+j+1,(k+1)*n+j))
cape=mesh('Purple_cape',v,f,'purple');sol=cape.modifiers.new('Cloth_thickness','SOLIDIFY');sol.thickness=.018
tube('Cape_hem',v[-n:],.015,'gold')
for j in [0,n-1]:tube('Cape_edge',[v[k*n+j] for k in range(4)],.013,'gold')
for sign in [-1,1]:
 ball('Shoulder_mantle',(sign*.17,0,1.18),(.22,.19,.105),'purple')
 tube('Mantle_trim',[(sign*.02,-.185,1.19),(sign*.20,-.185,1.12),(sign*.34,-.05,1.13)],.014,'gold')
ball('Brooch_gold',(0,-.204,1.15),(.068,.025,.069),'gold')
ball('Brooch_crystal',(0,-.231,1.15),(.032,.015,.043),'cyan')
for sign in [-1,1]:tube('Collar_ribbon',[(sign*.025,-.20,1.13),(sign*.06,-.21,1.0)],.013,'gold')
# Sleeves and hands: right hand raised to grasp the staff.
for sign in [-1,1]:
 arm=ball('Sleeve',(sign*.30,-.015,1.00),(.12,.115,.19),'cream');arm.rotation_euler[1]=sign*.42
 hand=(sign*.40,-.08,.88) if sign<0 else (.43,-.13,1.08)
 ball('Hand',hand,(.066,.06,.079),'skin')
 if sign>0:tube('Raised_forearm',[(.32,-.04,.92),hand],.063,'cream')
# Large face and layered hair silhouette.
body_objects=set(s.objects)
ball('Back_hair',(0,.035,1.57),(.365,.265,.41),'hairshade')
ball('Face',(0,-.09,1.54),(.313,.255,.295),'skin')
for sign in [-1,1]:
 ball('Ear',(sign*.305,-.07,1.48),(.054,.04,.075),'skin')
 for j in range(4):
  x=sign*(.22+j*.027);y=.045+j*.035
  rings('Back_hair_lock',[(x,y,1.67,.115,.10),(x+sign*.035,y,1.36,.105,.09),(x+sign*.065,y-.02,1.13,.10,.07),(x+sign*.14,y-.04,.96,.015,.015)],'hair',24)
# Anime eye layers on the face, no external textures.
for x in [-.122,.122]:
 ball('Eye_outline',(x,-.320,1.57),(.084,.020,.106),'dark')
 ball('Eye_white',(x,-.335,1.561),(.073,.018,.093),'white')
 ball('Iris',(x+.008,-.352,1.558),(.049,.012,.079),'blue')
 ball('Iris_light',(x+.01,-.362,1.537),(.035,.006,.045),'cyan')
 ball('Pupil',(x+.008,-.369,1.57),(.021,.005,.047),'dark')
 ball('Eye_glint',(x-.009,-.376,1.602),(.018,.005,.025),'white')
 ball('Small_glint',(x+.033,-.373,1.532),(.008,.004,.011),'white')
 ball('Cheek',(x*1.48,-.303,1.461),(.038,.008,.014),'blush')
 tube('Upper_lash',[(x-.073,-.343,1.61),(x,-.352,1.657),(x+.075,-.337,1.625)],.012,'dark')
tube('Mouth',[(-.024,-.342,1.425),(0,-.347,1.418),(.022,-.342,1.426)],.006,'brown')
# Sweeping tapered fringe, ending above eyes to preserve expression.
for x,z in [(-.25,1.57),(-.17,1.65),(-.065,1.67),(.045,1.66),(.16,1.69),(.26,1.53)]:
 rings('Fringe',[(x*.65,-.20,1.86,.105,.095),(x,-.28,1.76,.085,.06),(x-.04,-.337,z,.010,.010)],'hair',24)
# Wide brim with asymmetric lifted edge, bent crown, band and buckle.
head_objects=set(s.objects)-body_objects
v=[];n=96
for r in [.30,.56,.76]:
 for j in range(n):
  a=j*math.tau/n;v.append((r*math.cos(a),r*.70*math.sin(a),1.94+.105*math.cos(a)+.035*math.sin(2*a)))
f=[]
for k in range(2):
 for j in range(n):f.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
brim=mesh('Wide_witch_hat_brim',v,f,'hat');sol=brim.modifiers.new('Brim_thickness','SOLIDIFY');sol.thickness=.028
tube('Brim_piping',v[-n:]+[v[-n]],.012,'purple')
rings('Bent_hat_crown',[(0,0,1.94,.36,.28),(-.015,.02,2.15,.28,.22),(-.08,.03,2.40,.19,.15),(-.18,.02,2.59,.095,.08),(-.32,0,2.49,.066,.055),(-.48,-.015,2.43,.02,.018)],'hat')
rings('Hat_leather_band',[(0,-.002,1.97,.363,.285),(-.012,.01,2.095,.311,.248)],'band')
tube('Buckle',[(.045,-.277,2.005),(.19,-.258,2.025),(.18,-.235,2.13),(.038,-.253,2.11),(.045,-.277,2.005)],.015,'gold')
tube('Buckle_pin',[(.045,-.28,2.06),(.13,-.27,2.07)],.007,'gold')
# Lantern hangs from crooked hat tip.
tube('Lantern_hook',[(-.48,-.015,2.43),(-.50,-.015,2.35),(-.51,-.015,2.30)],.015,'gold')
for z,r in [(2.28,.085),(2.11,.072)]:rings('Lantern_cap',[(-.51,-.015,z-.025,r,.065),(-.51,-.015,z+.025,r*.6,.042)],'gold',16)
ball('Lantern_glow',(-.51,-.015,2.19),(.050,.044,.095),'cyan')
for x in [-.567,-.453]:tube('Lantern_frame',[(x,-.05,2.12),(x,-.05,2.27)],.009,'gold')
# Crooked wooden staff and faceted cyan crystal.
hat_objects=set(s.objects)-body_objects-head_objects
tube('Staff',[(.33,-.11,.43),(.46,-.12,1.04),(.62,-.10,1.66)],.033,'brown')
tube('Crystal_fork',[(.60,-.10,1.58),(.72,-.10,1.67),(.72,-.10,1.83)],.027,'gold')
tube('Crystal_fork',[(.61,-.10,1.59),(.55,-.10,1.71),(.59,-.10,1.78)],.024,'brown')
rings('Staff_crystal',[(.65,-.10,1.68,.005,.005),(.66,-.10,1.79,.092,.065),(.71,-.10,1.97,.005,.005)],'cyan',5)
for p in bpy.context.scene.objects:
 if p.name.startswith('Staff_crystal'):
  for face in p.data.polygons:face.use_smooth=False
def group(name,objects,pivot,scale,location):
 e=bpy.data.objects.new(name,None);s.collection.objects.link(e);e.location=pivot
 bpy.context.view_layer.update()
 for o in objects:
  world=o.matrix_world.copy();o.parent=e;o.matrix_world=world
 e.scale=scale;e.location=location
group('Body_proportions',body_objects,(0,0,0),(1,1,.85),(0,0,0))
group('Head_proportions',head_objects,(0,0,1.54),(1.15,1.10,1.10),(0,0,1.38))
group('Hat_proportions',hat_objects,(0,0,1.94),(1.08,1.08,1),(0,0,1.86))
for o in head_objects|hat_objects:
 if o.type=='MESH' and any(k in o.name for k in ['Fringe','hair_lock','Bent_hat_crown']):
  sub=o.modifiers.new('Soft_silhouette','SUBSURF');sub.levels=2;sub.render_levels=2
camd=bpy.data.cameras.new('LinaLook_Camera');cam=bpy.data.objects.new('LinaLook_Camera',camd);s.collection.objects.link(cam);s.camera=cam
camd.type='ORTHO';camd.ortho_scale=3.1;cam.location=(2.6,-8,3.1);cam.rotation_euler=(Vector((0,0,1.32))-cam.location).to_track_quat('-Z','Y').to_euler()
s.render.filepath=str(O/'lina-front.png')
bpy.data.libraries.write(str(O/'scene-library.blend'),{s},fake_user=True)
result={'scene':s.name,'objects':len(s.objects),'library':str(O/'scene-library.blend')}
