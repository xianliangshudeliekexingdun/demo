"""Developer-only: capture original Lua behavior. Never part of runtime/export."""
from pathlib import Path
import json
from lupa.lua54 import LuaRuntime

source = Path('D:/taptap/scripts')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().script_path = (source / '?.lua').as_posix()
lua.execute('package.path = script_path .. ";" .. package.path')
capture = lua.eval('''function(ability, moving)
 local Lab,Move,Growth=require('DodgeLab'),require('PlayerMovement'),require('Growth')
 local lab,p=Lab.Create('courtyard'),Move.Create(5)
 lab.logging=false
 local g=Growth.Create(); g.abilities[ability]=true; Lab.AttachGrowth(lab,g)
 local frames={}
 for frame=1,1200 do
   local dx,dz=0,0
   if moving then
     local phase=math.floor((frame-1)/180)%4
     dx=phase==0 and 1 or (phase==2 and -1 or 0)
     dz=phase==1 and -1 or (phase==3 and 1 or 0)
   end
   local oldX,oldZ=p.x,p.z
   if lab.result=='playing' then Move.Update(p,dx,dz,1/120,5.225,-9.6,9.6) end
   Lab.Update(lab,p,1/120,oldX,oldZ)
   if frame%30==0 then
     local row={frame=frame,x=p.x,z=p.z,health=p.health,result=lab.result,target=lab.targetId or 0,
       shots=lab.shots,hits=lab.hits,attack_hits=lab.attackHits,kills=lab.kills,damage=lab.damageDealt,enemies={}}
     for _,e in ipairs(lab.enemies) do table.insert(row.enemies,{x=e.x,z=e.z,health=e.health,state=e.state}) end
     table.insert(frames,row)
   end
 end
 return frames
end''')

def native(v):
    if not hasattr(v, 'items'): return v
    values = dict(v.items())
    if values and all(isinstance(k, int) for k in values):
        return [native(values[i]) for i in range(1, len(values)+1)]
    return {k:native(x) for k,x in values.items()}

rows=[]
for ability in ['fireball','lightning','orbit']:
    for moving in [False,True]:
        rows.append(dict(ability=ability,moving=moving,frames=native(capture(ability,moving))))
Path(__file__).with_name('fixtures').joinpath('lua_baseline.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
print('Captured 6 Lua scenarios, 240 checkpoints at 1/120 s')
