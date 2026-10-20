# 非Boss难度方案核算

本目录保留最初设计审查快照；parameters.json中的`proposal_not_approved_not_loaded_by_game`是原阶段标识。用户随后已批准并授权实施，当前参数归[data/route_nonboss_runtime.json](../../../data/route_nonboss_runtime.json)及逐房路线data，游戏不读取本目录。`.gdignore`隔离全部快照、baseline与工具。方案正文见[设计21](../../../docs/游戏设计/历史方案/21-非Boss四阶段与弹幕碰撞方案.md)。

~~~powershell
python -X utf8 tools/balance/nonboss_difficulty/check_plan.py
~~~

可用`--parameters`选择另一份完整方案，`--out`选择结果目录；不修改运行data、存档或正式资源。默认输出到`build/qa/nonboss-difficulty-design-20261020/results.json`。实施后重算请加`--out build/qa/nonboss-implementation-20261020/offline-replay`以保留最初报告。默认从baseline/读取实施前六份原生源的冻结字节，避免将生命补偿重复套用到已改的现行data；可用`--baseline-dir`显式选择另一基准根目录。

模型只核算56个非Boss房的数量／分批／角色上限、以实施前真实敌人继承档位为锚点的生命工作量、静态出生位置、单弹源间隙，以及所提身体接触时钟。接触情境把同一套120Hz固定步分发到30／60／120／144显示帧率，包含持续重叠、轮换敌人、冻结与冲锋；伤害是无防御／装备的边界算例。

生命因素0.6／0.7／0.8三点比较只支持“增量配套降低群怪单体生命”的预算选择。生命总和不等于清场时长或难度；单源间隙不等于多源混编始终可躲。没有复制完整战斗、玩家自动施法、AI、寻路、构筑、奖励、Boss或整体弹幕系统，不报告胜率、自然通关或约30分钟已通过。

用户要求后续统一实机测试，本工具不启动Godot。来源哈希、全部断言、边界与模型遗漏随结果保存。逐房组合由parameters.json维护；设计文档中的表格为其审查快照，运行默认值仍只归data。
