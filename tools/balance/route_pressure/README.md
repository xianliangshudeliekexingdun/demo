# 前期路线压力调参工具

> 本目录保留前15房历史工具、当时的默认情境与结果说明。当前45房压力检查使用[新工具](../route45/README.md)；本脚本的真实replay实现也被新敏感性实验以显式45房配置复用。下列默认命令和6—8分钟目标按原15房范围阅读，不作为当前45房验收。

本工具直接运行真实 Godot 核心，不另写伤害、AI、寻路或掉落近似模型。运行参数唯一来自 `data/route_enemy_runtime.json`；本目录 `scenarios.json` 只配置测试种子、选卡策略、移动决策频率和敌弹可见距离，不作为游戏默认值。

在 `D:/demo` 的 PowerShell 中运行：

```powershell
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/route_pressure/run.gd -- selected full
```

`quick` 运行三个开局的单种子低频决策策略；`full` 运行三种策略、三个固定种子、三个开局，再补一条防御控制优先路径。也可用 `profile:precise`、`profile:ordinary`、`profile:short_view` 分开执行，输出标签应各不相同。报告写入 `build/qa/route-pressure-20261017/<标签>.json`。

第三个用户参数 `baseline` 可将本轮保存在 `build/qa/route-pressure-20261017/baseline_enemy_runtime.json` 的旧敌人数值注入显式配置，再跑当前核心，例如 `-- baseline-canonical quick baseline`。配置发生在任何敌人出生前，不写回游戏数据；这样比较双方都经过同一拾取／计时实现。没有该参数时始终读取游戏唯一当前数据。

本轮接受的B版28情境分别保存在 `selected-ordinary.json`、`selected-precise.json`、`selected-short.json`；同核心基线为 `baseline-canonical.json`。运行下列命令可从原始报告重新生成前后表、分布、档位CSV及手算锚点，不修改游戏参数：

```powershell
python tools/balance/route_pressure/summarize.py
```

生成结果为[压力评审快照](../../../build/qa/route-pressure-20261017/pressure_review.md)、[机器可读摘要](../../../build/qa/route-pressure-20261017/pressure_summary.json)及[普通怪档位CSV](../../../build/qa/route-pressure-20261017/ordinary_stats.csv)。

## 模型合同

- 原项目 console exe，固定 120Hz 真正 `Route.step`；只提交八方向移动、实际提供的法术和神器选择。测试不修改生命、敌人血量、法术等级或阶段来凑通关。
- 准确策略沿用 `tests/route_rebalance_tests.gd` 的只读移动规划。低频策略每 0.25 秒决定一次，只读取 4.5 米内敌弹；短视策略每 0.4 秒决定一次，只读取 3 米内敌弹。地面锁圈、冲锋线和角色位置仍可读。这些是可复现的压力情境，不能代表真人反应时间分布或通关率。
- 清场后真正走向地面奖励，进入原核心选卡门槛后才合法选择；选完真正走门。自动选择不累计虚构的选卡停留时间。
- `combat_seconds` 为执行战斗阶段的固定步总量；`active_seconds` 同时含实际清场后走位、拾取与走门。字段由工具独立计步，可交叉检查游戏新旧时间定义。
- 按房记录战斗秒数、承伤、剩余生命／盾及实际构筑；按敌人记录首次看到出生至真正死亡的时间。该生存时间含接敌移动，不是固定站桩单体输出结论。
- 记录敌人实际起手事件及逐怪起手时刻；档位表直接读取 `type_spec(type,room)`，包含生命、移动／弹速、攻击周期、完整预警和碰撞半径。表中一级焰弹命中次数与理论耗时只作无遮挡、满命中、无暴击的手算锚点，不代表后期真实构筑。

## 证据边界

目标是前15房常规构筑约6—8分钟有效游玩，作为本轮试作目标。检查保留前三房教学，后段普通怪的耐久、接近速度、弹速和起手频率共同增加；生命压力、精英耗时及构筑差异分别观察。自动策略能避开攻击，只说明这条核心输入路径有解，不等于画面可读性、真人难度或体验已经认可。

快速报告用于有界参数比较；确定候选后，应在同一核心版本执行多种子完整报告。不能将已变更核心之前的报告冒充当前版本结果，或只看成功样本而省略死亡、超时与阶段卡住的记录。

本轮B版普通策略9条中位6:18，4条快于6分钟；短视策略最低剩162.8生命。防御／控制优先单独一条约10:55，仍明显偏慢；所有精英本体出生至击败最长50.23秒，最后整房更久包括普通护卫。保留这些偏离，先交用户复试，不继续加厚来强追所有样本的时长。
