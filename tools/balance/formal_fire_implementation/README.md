# 正式火系实装验证工具

本目录只调用实际 Godot `CourtyardRoute.step`，不复制设计模型或用理论 DPS 代替实机。设计模型快照仍在 `tools/balance/formal_fire/`，不覆盖。

## 运行

```powershell
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/formal_fire_implementation/run.gd -- final fire_first
```

参数为本目录 `scenarios.json`。固定 20261017 seed，F03 起手，8 向移动，0.25 秒决策间隔、4.5 米敌弹观察。只从实际三选一中选择，以火职业宝物和 F11/F07 为偏好，按真实接触取得书、箱子和出口。没有修改血量、位置、伤害、冷却、库存、掉落或阶段。该样本用升级优先的有序选择；原生 Main 脚本使用新学优先，二者是不同预设偏好，不作因果对照。

输出为 `build/qa/formal-fire-implementation-20261018/pressure/final.json`，保存源哈希、实际参数、每房与分段记录、真实奖励列表及燃烧/引爆分量。`source_stable` 必须为 true。该工具不会读写玩家局外存档，也不导出或常驻游戏。

## 证据分层

- `tests/formal_fire_tests.gd`：真实 core API 的确定性夹具；隔离 AI/出生/清场，验证精确边界，不冒称自然库存。
- `tests/route_spell_tests.gd`、`tests/route_artifact_tests.gd`、`tests/generic_items_tests.gd`：正式火系与归档回归、通用道具回归。
- 本目录 runner：一条真实自然 core 路线，固定策略与 seed，不是玩家通关率。
- `tests/formal_fire_visual.gd`：实际 Main、鼠标整卡选择和按住 WASD 行走，隔离测试存档；自动退出。
- `tests/formal_fire_assets_visual.gd`：4 张新图的正式控件矩阵及真实图鉴，矩阵是受控展示。
- `tests/formal_fire_vfx_visual.gd`：明确受控的实际 core 施法/宝物/敌人夹具，经生产 View 读取真实状态；验证燃烧、传播、引爆、复燃、暂停与清理，不冒称自然取得。

## 限制

45 房仍是现有精英混编，未涉及正式 Boss、46—60 房、真人生存率、完整约 30 分钟目标或最终平衡验收。单路线不同奖励或策略不能归因于单件宝物。伤害遥测为实际造成伤害，含过量伤害裁切；不是静止目标理论 DPS。自然样本末箱取得 G04，之后没有战斗，因此它不能证明自然复燃。

第一次压力运行在同刻复燃优先级修正前主动中止，只保留 `pressure-discarded-before-reignite-priority.log`，没有作为最终证据。最终完整运行按修正后固定源重新执行。
