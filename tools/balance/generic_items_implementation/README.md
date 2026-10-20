# 通用道具真实 core 专项

此工具运行当前真实 `Route.step`，不复制伤害公式、不填充库存、不修改生命／敌人／位置／掉落。种子、成长和移动策略固定，所有道具必须从实际缓存候选领取。`generic_first` 优先新增通用机制；`legacy_first` 在同一当前池中使用旧偏好，后者不是旧 21 件版本的直接复刻。暂停与选卡不走战斗时间。

运行：

~~~powershell
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/generic_items_implementation/run.gd -- selected paired
~~~

输出在 `build/qa/generic-items-implementation-20261018/pressure/`，保存来源哈希、配置、逐房时间／承伤／弹幕峰值、实际候选与持有轨迹。两条选择策略只有一个固定种子，不估计真人胜率；未测试 46—60 房、正式 Boss 或最终约 30 分钟。保留死亡／超时结果，不以自动补血让样本完成。

规则夹具单独在 `tests/generic_items_tests.gd`；原生 Main 点击／WASD 和正式素材像素在 `tests/generic_items_visual.gd`。受控规则或素材矩阵不冒充自然库存。

`tests/generic_items_assets_visual.gd` 单独核对 19 张正式图标、40／24／16 图鉴筛选与真实详情点击。完整自然 Main 完成后发现暂停属性第 3 行被裁切；修正仅涉及暂停布局，因此最终暂停由 `tests/generic_items_pause_visual.gd` 做短实际 Main 开局／暂停专项，不重复完整 45 房。两份视觉报告各自保存实际来源哈希，不把修正前整局截图当作最终暂停布局。

