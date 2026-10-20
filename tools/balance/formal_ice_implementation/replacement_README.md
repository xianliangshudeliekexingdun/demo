# 满槽替换验证

本轮使用实际Route与真实Main，不复制战斗／奖励模型。输出固定在`build/qa/spell-replacement-20261018/`，旧冰目录保持原版证据。规则夹具、只读卡面夹具、自然路线分开报告。

在`D:/demo`用原console执行，窗口脚本串行、自动退出，不启动交付常驻游戏：

```powershell
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/spell_replacement_tests.gd --check-only
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/spell_replacement_tests.gd
python -X utf8 tools/balance/formal_ice_implementation/replacement_source_binding.py before main tests/run_tests.gd
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/run_tests.gd -- --qa-out=res://build/qa/spell-replacement-20261018/main
python -X utf8 tools/balance/formal_ice_implementation/replacement_source_binding.py after main tests/run_tests.gd
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/formal_ice_tests.gd -- --qa-out=res://build/qa/spell-replacement-20261018/ice
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/formal_fire_tests.gd -- --qa-out=res://build/qa/spell-replacement-20261018/fire
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tests/route45_tests.gd -- --qa-out=res://build/qa/spell-replacement-20261018
& ./Godot_v4.7.2-stable_win64_console.exe --path D:/demo --script res://tests/spell_replacement_cards_visual.gd
& ./Godot_v4.7.2-stable_win64_console.exe --path D:/demo --script res://tests/spell_replacement_visual.gd
$nativeExit = $LASTEXITCODE
Set-Content -LiteralPath build/qa/spell-replacement-20261018/visual_exit_code.txt -Value $nativeExit
python -X utf8 tools/balance/formal_ice_implementation/replacement_acceptance.py
```

`spell_replacement_tests.gd`指定库存／奖励，仅测试实际core事务和状态；物理书组明确用受控击杀清房，再通过实际步进走到书。`cards_visual`把只读snapshot送生产UI，逐一检查16张冰职业卡与三起手，不创建自然库存。`spell_replacement_visual`从真实主页点选冰系／I03；测试账户与偏好独立，用鼠键走完45房，不改生命、位置、伤害、冷却、奖励和库存；一次确认与一次取消后放弃均从真实奖励进入。

所有输入、SHA与逐房／操作记录在JSON；156项自然窗口闭包含Main、冰职业模块、新renderer和shader。`replacement_acceptance.py`只读已有记录，精确核45次实体奖励（36书9箱）、44门户、源字节和原生退出码，不能代替游戏运行。不得将各组重叠检查数累计，亦不从单条策略推断真人胜率或最终30分钟平衡。
