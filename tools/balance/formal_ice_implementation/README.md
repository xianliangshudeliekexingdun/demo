# 正式冰系实装验证

这套工具调用当前原生Godot与实际`Route.step`，不复制伤害、寒霜或敌人AI模型。批准值来自设计14及`tools/balance/five_schools/ice.json`；运行值唯一归`data/ice_spells_v1.json`、`ice_artifacts_v1.json`及原共享源。设计参数文件仍保留设计阶段状态，不因此否定本轮已取得的实施授权。

以下命令均在`D:/demo`执行，固定原console exe；自动退出，无导出、远端操作或互动常驻。窗口测试等生产素材全部导入并冻结后**串行**执行。

```powershell
python -X utf8 tools/balance/formal_ice_implementation/data_contract.py
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/formal_ice_tests.gd --check-only
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/formal_ice_tests.gd
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/formal_ice_compat_tests.gd
python -X utf8 tools/balance/formal_ice_implementation/source_binding.py before main tests/run_tests.gd
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/run_tests.gd -- --qa-out=res://build/qa/formal-ice-implementation-20261018/main
python -X utf8 tools/balance/formal_ice_implementation/source_binding.py after main tests/run_tests.gd
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/formal_ice_implementation/run.gd -- final ice_first
python -X utf8 tools/balance/formal_ice_implementation/acceptance.py
& ./Godot_v4.7.2-stable_win64_console.exe --path D:/demo --script res://tests/formal_ice_assets_visual.gd
& ./Godot_v4.7.2-stable_win64_console.exe --path D:/demo --script res://tests/formal_ice_vfx_visual.gd
& ./Godot_v4.7.2-stable_win64_console.exe --path D:/demo --script res://tests/formal_ice_visual.gd
```

旧独立火、通用、十术、宝物及45房规则继续保留覆盖，可用各脚本的`--qa-out=res://build/qa/formal-ice-implementation-20261018/<范围>`将本轮结果写入新目录，避免覆盖旧轮证据。`formal_ice_compat_tests`只是旧主suite前五组的快速预检，计数与主suite重叠，不能额外累加作新覆盖。

## 验证分层

- `data_contract.py`逐字段比较批准数值与新运行源，并将旧共享data、火状态／通用／局外核心及两原引擎与任务前SHA比较。这是静态一致性，不证明运行效果。
- `formal_ice_tests.gd`通过实际Route与Spell／Ice／Artifact接口验证十术三级、16宝物、寒霜与免控、死亡父击旧token、区域共享门、实时属性、冻结AI及清理。夹具隔离出生／清场／AI；敌人行为组明确启用生产EnemyCombat。手工指定法术、宝物和沙包不称自然库存。
- `run.gd`使用`scenarios.json`固定I03起手、20261017种子、实际三选一、八方向移动、0.25秒决策与4.5米敌弹感知，只提交移动和真实奖励选择。无生命、位置、伤害、冷却、阶段、掉落或库存覆写。参数记录的是测试策略及观察范围，不是运行平衡值。
- `formal_ice_visual.gd`从真实Main首页通过鼠标选择冰系／起手，并用实际WASD与选卡走45房。它与压力工具的决策／优先策略并非同一个策略，不拿两条路线的差别作某单件宝物或控制的因果结论。测试账户与显示偏好隔离，生产账号仅比较SHA。
- 素材矩阵和特效场景明确标为受控夹具；必须读取实际截图像素，不能只以coverage字段通过代替可见性。素材图鉴只证明控件与资源，受控金色触发不能当作自然抽中。

## 来源与结果

证据集中在`build/qa/formal-ice-implementation-20261018/`。每个正式运行保存输入、种子／策略、来源SHA、规则结果或逐房记录；`source_binding.py`额外追踪脚本中明确声明的`res://`依赖闭包，范围外仍在编辑的QA脚本不会被误当作主suite输入。

首次调试长任务因核心边界修复和旧仅火选卡夹具被停止，其日志／旧结果保留为`debug`，不作为最终源版本证据。压力工具补齐冰职业执行模块绑定后重新运行，不能只后验追加SHA。设计阶段`build/qa/five-schools-design-20261018/`与旧火设计／实装报告均不覆盖。

本轮不以单条自动路线推断玩家胜率、构筑必成、最终强度、正式Boss或完整60房约30分钟。固定策略的清房／路线耗时如实保存，不能代替真人体验与后续平衡。
