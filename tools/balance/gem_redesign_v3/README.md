# 新版十核心与属性宝石离线提案

版本：gem-redesign-v3-r3，2026-10-22批准前提案快照。**后续用户已授权且完成十核心／属性石／养成与配套表现实施。此目录保留原阶段离线推导，不作为运行默认值或新实施验证。** 当前规则看[局外养成](../../../docs/游戏设计/局外养成.md)，原生证据看[本轮实施](../../../build/qa/gem-v3-implementation-20261022/validation_summary.json)。本目录仍由`.gdignore`隔离；旧结果保存当时输入与来源哈希，当前重跑会读取更新后的工程来源，不能把旧结果冒充当前实机。

完整提案：[新版魔法宝石十核心与养成提案](../../../docs/游戏设计/未来方案/25-新版魔法宝石十核心与养成提案.md)。用户方向及“不要直接制作”的范围由[历史30](../../../docs/历史决策/归档/30-新版宝石整体规划与十核心提案.md)保存。

## 文件与模型契约

| 子模型 | 可编辑提案 | 核算范围 |
|---|---|---|
| `common_model.py` | `common_parameters.json` | 星裂精确暴击期望、回响命中率、血祭解析自耗、血晶生命／盾池与现有GT04／GT01回流比；无AI／真实命中预测 |
| `fire_ice_lightning_model.py` | `fire_ice_lightning_parameters.json` | 火共享燃烧／消费事件账本、冰显式输入窗口的储伤、雷有限旧导电／网络消费损失；不复现完整战斗 |
| `wind_earth_spirit_model.py` | `wind_earth_spirit_parameters.json` | 真实参数下规定走位／可达接触的输出包络、构装到期替换／成熟、契灵有限寿命和逐动作协同；不估价变宽额外命中 |
| `economy_model.py` | `economy_parameters.json` | 实际清房魔尘／触媒费用、核心确定解锁、属性抽取保底／材料守恒／消费政策；Python RNG非Godot序列 |

`*_proposal.md`是编制提案时的版本化分项说明，`proposal_intro.md`提供总约束和锚点。它们不是当前运行规则；当前正式数值仍从data与core读取。`run_models.py`可一次执行四组隔离模型；各模型支持`--parameters`和`--output`，只允许向本项目build/qa写结果。

## 复现

```powershell
Set-Location D:/demo
python tools/balance/gem_redesign_v3/run_models.py
```

可只运行一组或使用独立候选参数，例如：

```powershell
python tools/balance/gem_redesign_v3/common_model.py --parameters tools/balance/gem_redesign_v3/common_parameters.json --output build/qa/gem-redesign-v3-20261022/common
python tools/balance/gem_redesign_v3/economy_model.py --accounts-per-seed 400 --output build/qa/gem-redesign-v3-20261022/economy
```

结果根目录为`build/qa/gem-redesign-v3-20261022`，每组均包含机器可读结果与可读摘要；参数、模型版本、来源哈希、已知案例／不变量、情境与扫描随结果保存。经济模型采用3个固定seed、每seed400账号；15／30／45／60房收入情境和三种预算政策分别执行。固定玩家策略是模型假设，不是游戏里的自动留款或消费限制。

## 保真与调参的区别

模型错误先修正并加已知案例，再选择数值：火／雷工具补入真实L01未导电加值，岩工具修复初选锚时多计一帧驻留；经济工具分别修正小额收入无法攒第二核心及首个额外核心过度锁住余额的问题。输出中的model_changes／model_corrections记录保真修复，参数扫描另列，不能用调参掩盖模型差异。

早期候选和低收益结果保留于相应结果子目录。正式推荐不等于所有情境强度相同：保留早I07碎冰、频繁F07消费、成熟电网与核心的竞争，以及岩单术长战高于／多术普通低于调参锚点等限制。

经济r3增加累计真实结算清房15／30各12精粹的一次性补给。冻结的r2无补给基线位于结果根的`economy-r2-no-milestones/`；0／12／24补给对照每格同样1200账号。固定手算校准与可编辑候选参数分开，合法调参不应被推荐值的硬编码期望误判。

## 范围限制

这里没有游戏实施、存档迁移、原生规则测试、互动实机、截图、自然整局、性能、导出或最终平衡验收。不可把某个来源的伤害增幅当作整套八槽构筑提升，不可把105魔尘预算结算次数当作真人通关次数／小时数，不可把输入的合法邻敌、命中率和驻阵比例当作实测。

后续同日已获用户制作授权，并完成原生core、迁移、工坊和程序表现；结果见本页顶部实施证据。这里的旧提案结果仍不代表当前实机，实机依用户既有安排统一执行。
