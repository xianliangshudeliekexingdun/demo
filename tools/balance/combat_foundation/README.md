# 战斗系统公式讨论工具

在D:/demo执行：

```powershell
python tools/balance/combat_foundation/check.py
```

[parameters.json](parameters.json)只定义讨论场景；基础属性、法术参数、既有上限读取运行源，通用道具数值参考独立预算输入。当前检查暴击率无上限、100%起必暴及60%CDR。结果写入[results.md](../../../build/qa/generic-items-implementation-20261018/formulas/results.md)与[results.json](../../../build/qa/generic-items-implementation-20261018/formulas/results.json)。旧315项报告保留原输入哈希；可用`--parameters`与`--out`留存其他方案。

工具校对乘式、同桶相加、暴击期望、CD与防御上限、护盾分摊、契约顺序、旧乘式中性等价，以及固定沙包的离散命中期望。命中分布为确定性求和，不需要随机种子。源文件绑定哈希，工具不会写入data、scripts、场景或资源，也不启动Godot。

当前游戏已按道具规则接入玩家防御，敌方防御仍未实现。例子里的目标防御、固定蓄能伤害经过防御、静态攻击百分比均是讨论方案。1000／5000生命沙包不是正式怪物或Boss数值。此工具不模拟状态取值时机、触发链、移动、技能命中、P04／P05、AI、回复、控制或60房通关时长；不能把算式通过当成这些机制已实装或已验证。
