# 法术三级定点核算

只用于本地数值调校，目录由`.gdignore`隔离。游戏不读取这里的冻结来源、场景或工具。

唯一运行源是`data/route_spell_growth.json`。`baseline/`保留迁移前法术和32职业定义；`scenarios.json`可修改攻击、目标位置、持续时间、种子、构筑和暴击／冷却边界。

`measure.gd`继承实际Route，隔离敌人AI／出生／清场；不复制伤害公式。目标仍经过真实施法、命中、燃烧、寒霜、窗口、派生和实际回复。每版有120个单术等级／布局场景，36个构筑场景及6个高暴击／高冷却边界，共162。一次一级焰弹的手算案例为100主伤＋8×25燃烧＝300；系数扫描为100×scale＋200，燃烧不缩放。

在D:/demo执行：

```powershell
.\Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/spell_growth/measure.gd -- --out=res://build/qa/spell-growth-implementation-20261020/model-current.json
.\Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/spell_growth/measure.gd -- --baseline --out=res://build/qa/spell-growth-implementation-20261020/model-before.json
.\Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/spell_growth/measure.gd -- --baseline --old-gear --out=res://build/qa/spell-growth-implementation-20261020/model-old-gear.json
.\Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/spell_growth/measure.gd -- --scale=0.9 --out=res://build/qa/spell-growth-implementation-20261020/model-low.json
.\Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/spell_growth/measure.gd -- --scale=1.1 --out=res://build/qa/spell-growth-implementation-20261020/model-high.json
python -X utf8 tools/balance/spell_growth/compare.py
```

可用`--school=fire`或`--school=ice`只跑该系60个单术场景；这时不能与完整162场景混比。`--old-gear`必须搭配`--baseline`，强制授予旧32职业是理论参照，不是实际可取得的装备或验收门槛。

输出包含实际DPS、释放数、真实回盾和护体覆盖率、运行／冻结源哈希、已知案例与有界检查。DPS差异只支持所列目标、种子与构筑；防御、位移、控场、自然奖励选择和玩家存活不在模型覆盖内。F09会把固定敌人推离后续攻击范围。主伤±10%扫描不缩放几何、寒霜、回复、燃烧或新机制的独立系数。三种子范围是观察范围，不宣称统计置信区间。
