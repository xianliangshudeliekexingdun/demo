# 四阶段伤害与快慢弹幕核算

设计24的持续调参工具，受`.gdignore`隔离，游戏不加载、不打包。本工具核对数值与发射边界，不模拟完整真人战斗。

- `baseline.json`：本轮修改前六个真实数据源；`baseline_manifest.json`：实施前源码／资源／原引擎哈希。
- `native-baseline.json`：修改前原生core的60房规格及23个20秒单源夹具，保留原始记录。
- `accepted_proposal.json`：本轮选中的提案快照，仅用于`--proposal`复算；**不是运行默认值**。以后调参直接改data，再执行默认的current核算。
- `parameters.json`：参考生命／防御情境、容量持续时间、反应假设、容量和伤害敏感性幅度与检查阈值。
- `measure.gd`：读取真实core，导出规格及实际发弹时间／数量；不运行场景或自然路线，不读写正式账号。
- `check_plan.py`：与冻结基线比较，核对原生规格／周期／完整弹组、伤害承受次数、反应几何和整轮预约容量。
- `audit.py`：核对批准的文件变化、资源／关卡／法术与原引擎保持、显式依赖和本轮文档引用。

在`D:/demo`执行：

~~~powershell
& ./Godot_v4.7.2-stable_win64_console.exe --headless --path D:/demo --script res://tools/balance/enemy_pressure/measure.gd -- --out=res://build/qa/enemy-pressure-20261020/native-current.json
python -X utf8 tools/balance/enemy_pressure/check_plan.py --native build/qa/enemy-pressure-20261020/native-current.json --out build/qa/enemy-pressure-20261020/model-current.json
python -X utf8 tools/balance/enemy_pressure/audit.py
~~~

只重算设计快照：`python -X utf8 tools/balance/enemy_pressure/check_plan.py --proposal --out build/qa/enemy-pressure-20261020/model-proposal.json`。改情境可传`--config 文件路径`；修改运行数据后应重新捕获native-current，避免拿旧捕获误作新版本验证。

模型合同：普通／精英基伤选择后乘room damage一次，身体以新基值乘body倍率一次；Boss逐招基伤另乘专用房间倍率。每次攻击的所有子轮在预警前整份预约，释放时将预约转为在场弹；到达寿命或射程后释放名额。容量事件包含起手错峰、完整动作与0.25秒重试；没有随机采样，所以无随机种子和统计胜率。

模型校正记录：早期实现曾将前三房M02的未缩放生命除以0.8，令未出场的M05参考生命误算140；原生对照显示正确为112。先修正模型的教学例外并加入固定回归，再比较参数。运行参数没有为这个模型错误作补偿。

结果：`build/qa/enemy-pressure-20261020/model-current.json`保存基线与当前表、121个真实批次／合法极端容量情境及敏感性。当前规格／单源周期／整弹组原生对照和其它检查共8236项、0失败。容量保守峰值18／80／188／318，对应预算64／128／208／320；最拥挤的双环＋四慢扇极端组合约11.9%的申请会按规则重试。

同一59房20秒原生静止单源夹具：M02发射21→35颗，M05为54→162，M06为68→136，M07为36→88。夹具给玩家足够生命以记录完整时序，这些是实际发射数量，不是自然清房、真实命中率或正常承伤。缺口环弹第一轮朝玩家开口，增加总弹数也不等于自动增加同样比例的命中。

局限：容量模型故意忽略击杀／掩体／命中、保留最长合法存续时间；参考构筑只有明确给定的生命／护盾／防御，不纳入回盾、控制或自然奖励。不推算总路线时长、胜率、帧率或交叉弹幕后处处安全。按用户要求，本轮未实机、截图、自然通关、性能或导出。
