# 45房原生压力工具

直接运行本工程原 console 引擎和真实 `Route.step`，不复制伤害、敌人AI、掉落或成长模型。策略复用 `tests/route_rebalance_tests.gd`，观察封装只限制敌弹可见距离；所有成长来自实际提供的候选，奖励与门通过真实移动接触。

```powershell
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/route45/run.gd -- accepted-full full
python tools/balance/route45/summarize.py accepted-full
```

`quick` 为普通策略、单种子、三起始法术；`full` 为三个策略×两个固定种子×三个起始法术，另加一条防控优先路径。也可用 `profile:precise`、`profile:ordinary`、`profile:short_view` 分开运行，每份标签不同。`defense` 另补防控优先路径。配置在 `scenarios.json`，只保存实验种子／策略／超时边界，不是游戏默认参数。

报告写入 `build/qa/route45-20261018/<标签>.json`，每条情境完成即保存，死亡、战斗超时、非战斗无进展、总超时均保留。报告绑定真实 core、路线、敌人数据与策略哈希；逐房记录类型、组合、远程数量、活怪／敌弹峰值、战斗和行走总时长、承伤、生命与法术／宝物轨迹，并汇总为1—15、16—30、31—45三段。

精确策略每1/12秒决策、读取30米内敌弹；普通每0.25秒、4.5米；短视每0.4秒、3米。固定120Hz推进，选卡自动瞬间完成，不伪造思考时间。时间用真实核心双时钟交叉核验；可复现自动策略只是压力情境，不能当真人反应、胜率或体验验收。

`baseline15/results.json` 保留扩展前实际跑完的三条普通策略；对应原始两JSON和配置快照也保留在同目录。新工具换房清除移动方向记忆，拾取方向按所选策略频率重算；旧工具延续上一房方向记忆，拾取逐步重算。这些输入轨迹差异可造成前15房时间微差，不能把微差归因于数值变化，也不能把旧报告当扩展后版本。前15配置不变由独立逐字段回归确认。

`tests/route45_tests.gd` 是明确修改敌人生命、阶段或装备以隔离规则边界的专项；与本工具的自然路线、`tests/route45_visual.gd` 的真实 Main／卡牌／WASD 像素证据分开报告。视觉脚本使用独立存档和偏好，自动退出，不启动常驻试玩或导出。

## 有界敏感性实验

```powershell
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/route45/sensitivity.gd
```

`sensitivity.gd` 继承旧 `route_pressure` 的真实 replay runner，以F01、种子20261017、普通策略跑后30房普通怪／精英生命档位的0.9、1.0、1.1三点自洽对照。每点只在`Route.configure`之后、`choose_initial`之前注入派生EnemyCombat runtime，并先用owner房数45验证覆盖；不写回data，不修改出生后敌人／玩家生命或阶段。完整override、全部未完成结果、原源哈希、前15房轨迹相等校验保存为`sensitivity.json`。该实验只观察参数响应，不改变当前游戏候选，也不替代多种子主版本报告。由于移动记忆／拾取采样不同，不拿新45工具的1.0行拼入这组三点。
