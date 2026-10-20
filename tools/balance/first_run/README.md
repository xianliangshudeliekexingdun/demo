# 首关候选数值计算工具

用途：给自动八槽首关设计伤害、冷却、生命、成长和普通房配置候选，不连接或修改Godot。计算使用Python 3标准库，节奏图生成另用本机Matplotlib与既有字体；本轮未安装依赖。工具目录和候选data子目录均用.gdignore隔离；当前游戏未接入这些参数。

唯一调参来源为[候选JSON](../../../data/balance_candidates/first_run_v1.json)，假设与固定选择路径为[scenarios.json](scenarios.json)。[模型](model.py)负责事件与公式，[运行器](run.py)负责加载、已知例检查、批量情境和报告，[评审生成器](write_review.py)从同一数据与结果生成[数值评审快照](../../../docs/游戏设计/历史方案/05-首版数值与验证.md)。不在脚本保存另一套运行默认参数。

在D:/demo执行：

```powershell
python tools/balance/first_run/run.py
python tools/balance/first_run/write_review.py
```

默认结果在[当前报告](../../../build/qa/first-run-balance-20261017/selected/results.json)。`parameters_used.json`、`scenarios_used.json`保留每次实际输入；CSV含DPS、TTK中位／P10／P90、均值标准误与超时数。固定种子＝基础种子＋情境名UTF-8的CRC32＋试验序号。主要情境64次，参数扫描16或32次。计数与生存账本是确定性输入，不把情境占比当真实玩家概率。

单独对照参数（不覆盖候选源文件或当前报告）：

```powershell
python tools/balance/first_run/run.py --set player.shield=120 --out build/qa/first-run-balance-20261017/shield120
python tools/balance/first_run/run.py --set bosses.2.health=45000 --out build/qa/first-run-balance-20261017/boss45000
```

`--config`、`--scenarios`可读取另一份明确输入；`--trials`至少2；`--no-sweep`跳过网格。候选源发生变化后先重跑再生成文档，生成器核对源文件SHA256及完整参数内容，拒绝拿旧结果更新新参数文档。结果目录中的参数是证据快照，不是另一处编辑源。

## 模型合同

- 独立前摇，成功释放启动该技能CD；命中后伤害先盾后血，最后取整伤害。伤害事件分别抽命中与暴击，同步事件用稳定插入顺序。
- 自然施放计一次；多弹／多跳／精灵攻击不增施放数。序列附加不改本体CD、也不递归触发事件神器；源泉减当前剩余CD，保留前摇与精灵间隔。
- 伤害属性在释放时快照；F06不放大自身伤害快照。法阵替换使旧区域失效；同源区域跳频受限。
- 精灵首次等完整射击间隔，持续结束且CD就绪才重新前摇。最终首领50%血进入阶段转换，有限召唤最多2只，旧组清空且召唤CD结束才重召；核心始终可伤，核心死亡不要求再清小怪。
- 目标组是主目标及最多两个可能邻居，表示密度基准，并非游戏AOE／贯穿上限。火雨、火区、直射命中与站阵率是输入假设。F07分别判中心／外围，回归固定外围325＋75＝400。
- 每个遭遇从技能就绪开始，不决定未来游戏的跨房冷却规则；无真实位置、寻路、碰撞、弹速、障碍遮挡或怪物攻击AI。
- 基础TTK没有神器、宝石；额外精灵与攻击属性另做对照。序列／源泉／护盾加成的压力输入不代表已定全部神器数值，未覆盖金色全部组合。
- 生存账本按固定有效受击数／伤害计算，酒馆先加上限再按新上限恢复，生命上限增加本身不另回血，死后不结算恢复。F10对照用固定房时长，分散与1.5秒集中受击分别计算；这不是整局实时战斗或通关率预测。
- 属性神器对照明确在6／12／21后选生命／护盾／攻击各一件，数量占原节点选择；不声明真实必出、不加入新道具ID或默认额外赠送。

## 检查与证据

运行前执行固定手算、合法选择前缀、护盾溢出、满盾取消、精灵寿命、源泉剩余CD、旧计时事件、法阵替换、同源跳频、有限召唤与酒馆顺序检查；手算用明确测试夹具，不把夹具值当运行默认。每次战斗同时检查生命／护盾范围、最多两个召唤物、自然施放计数和事件终止。

`within/below/above`表示相对设计目标，未达项仍写入结果供评审。模型检查或核心开局比／持续承伤压力边界失败返回非零；不能以退出码0声明所有目标已达到。当前仍保留4个房间耗时观察项，详见数值评审。

模型1.0的[最初基线](../../../build/qa/first-run-balance-20261017/baseline/results.json)包含旧余震处理，仅保留历史；应与[1.2重跑基线](../../../build/qa/first-run-balance-20261017/baseline_replayed/results.json)比较。后者的输入刻意保留用户追加酒馆成长前的恢复规则，不可当现行规则。

这些检查证明计算模型与声明规则的一致性。没有将它与当前旧五法术游戏逐帧对齐；接入新规则后，需用运行事件验证中间值、输出与用户体验，发现差距先修模型／接入错误，再调数值。

## 火系十八件与通用三件

用户已同意基础数值与[神器源](../../../data/balance_candidates/fire_artifacts_v1.json)的21件效果先按本版推进。三个通用幅度用base_ref读取基础表已有80／25／15，不另复制默认值；resolve_catalog只解析到基础参数中的数字，不执行内容，源文件保留candidate命名和字节。

[artifacts.py](artifacts.py)基于基础模型派生事件，所有效果携带自然／精灵／序列／余响／神器来源，阻止追加递归；B05、B09按法术附带状态处理。基础1.3只加无副作用钩子，旧115组无神器指标／生存输出保持一致。神器模型1.1另验证首落伤害、三级回盾压力、协同三级贯穿与替换法阵取消终焰。

```powershell
python tools/balance/first_run/run_artifacts.py
python tools/balance/first_run/write_artifact_review.py
```

可用`--catalog`指定明确参数源，`--trials`调整样本数、`--no-sweep`跳过网格、`--out`另存对照。主要情境每组64次，扫值16次；结果在[神器报告](../../../build/qa/fire-artifacts-20261017/selected/results.json)，保留源哈希、解析前后目录、输入假设和CSV。范围的几何收益、目标留在火雨落点的概率、双区域重合比例由[artifact_scenarios.json](artifact_scenarios.json)显式定义，不伪装成实机命中率。

[write_artifact_review.py](write_artifact_review.py)核对基础／神器源SHA256后生成02数值区与06计算评审；不能用旧结果覆盖新参数。scope表示本轮配套归档：P04／P05仍是通用机制，不将归档字段当作仅火系可获取条件，实际资格按required_spell／requirement定义。新增属性三件为额外条目，共21件，仍不增加奖励机会。

完整条目见[神器](../../../docs/游戏设计/历史方案/02-火系神器.md)，对照方法、九件路线、415项检查、60组情境、34组扫描与未覆盖范围见[计算评审](../../../docs/游戏设计/历史方案/06-神器数值与验证.md)。未模拟真实掉落、购买力、移动／遮挡、全组合最优或所有未来变化；已列参数的内部事件检查不等于Godot实现或体验验收。

## 金币、商店与有限池投放

[经济源](../../../data/balance_candidates/run_economy_v1.json)拥有固定收入、价格、阶段品质权重、节点候选保证和购买额度；用户已同意先按07推进，数值源与既有结果字节不变，只更新确认状态，不扩大为实机验收。[economy.py](economy.py)复用基础源的精英／首领／商店节点、model.py的清房后法术路径，以及artifacts.py的资格判断，不另建一份神器效果。情境[经济假设](economy_scenarios.json)只保存种子、样本数、行为偏好、目标和扫描方案。

```powershell
python tools/balance/first_run/run_economy.py
python tools/balance/first_run/write_economy_review.py
```

默认[结果](../../../build/qa/run-economy-20261017/selected/results.json)记录参数／代码哈希、已执行输入、178项检查、14组共56,000次条件整局、18组扫描共18,000次、128个实际库存接回战斗的输出抽样；CSV给出中位／P10／P90，JSON另有标准误、各店购买力、实际候选品质与两半独立种子。轨迹另存sample_campaigns.json。不是通关率或实际玩家购买比例。

普通随机位先过滤持有／法术资格／零权重品质，再按仍有条目的品质归一权重、品质内均匀取项；同屏不放回。保证占第一个位置，指定品质空缺则取当前合法正权重池最高品质；不足三件如实展示，全部空缺跳过。实际展示统计包含保证与池缩减，不当成表面权重。

同一店商品只生成一次、购买次数累计；purchase的purchased_count参数用于复开边界检查。整局按每节点一次前进，不能用该模拟声称未来游戏UI已防止重进获利。清房金币单次入账、初始余额＋收入－消费＝余额；未消费金币和最后一店之后收入只归结算记录，当前不接局外经济。

单参数对照可使用`--set PATH=JSON`，不覆盖源文件，例如：

```powershell
python tools/balance/first_run/run_economy.py --set prices.gold=280 --out build/qa/run-economy-20261017/gold280
python tools/balance/first_run/run_economy.py --without-guarantees --trials 2000 --no-sweep --no-combat --out build/qa/run-economy-20261017/without-guarantees
```

`--config`／`--scenarios`接受明确输入，`--no-combat`只算经济；价格为正整数、收入为非负整数，每阶段权重合计100。当前不支持非零击杀／表现／回售／空箱收入；模型拒绝这些未实现的收入路线。默认输出之外的比较不得拿来覆盖当前快照。

[write_economy_review.py](write_economy_review.py)核对当前经济、基础、神器、三份情境及经济／战斗代码哈希，再生成[07评审](../../../docs/游戏设计/历史方案/07-金币商店与品质.md)。生成还读取已保存的unlimited-replayed与without-guarantees比较，后者不是默认源。较高收入不限购买初试经同模型重跑，不能把整套方案差异全归因于单个限制。模型只有假设偏好，没有估算最优购买；真实走位、整局承伤与体验仍待接入后验证。

## 局外触媒与魔力宝石

[局外源](../../../data/balance_candidates/meta_growth_v1.json)单独拥有魔尘收益、解锁／升级费用、触媒关联与权重、宝石总加成；用户已同意按08推进，原字节和candidate命名保留。[meta.py](meta.py)读取经济阶段与基础首领节点，不复制地图进度定义；等级0为未解锁，初始各免费选一件，角色只应用已装备一颗宝石。升级和换装只能在局外，开局快照不能被后续状态改写。

```powershell
python tools/balance/first_run/run_meta.py
python tools/balance/first_run/write_meta_review.py
```

[执行报告](../../../build/qa/meta-growth-20261017/selected/results.json)含61项手算／概率／上限／购买／快照／重复结算检查、24组各2000次的法术抽取整局、8组权重与成本扫描、四种进度路径×三种花费策略账本、9种宝石等级的派生属性与简化受击锚点。CSV在同目录choices.csv。`--config`、`--scenarios`、`--trials`、`--out`可另存明确对照，基础／经济／神器来源均通过配置文件引用，原源不变。

[meta_scenarios.json](meta_scenarios.json)保存选择策略、进度情境、目标和扫值。当前加权抽法术的基础等权是设计假设；同屏不放回、八槽／三级过滤优先；开局选择沿既有路径，不计算触媒对开局三个候选的作用。精确枚举与每组第一轮抽取误差在四个标准误内，报告前后两半独立种子。‘追关联’优先学到三种关联，‘沿原路线’按原固定选择偏好补缺，均不是最优输出或玩家分布。

Profile仅为局外规则与账本计算，不读写用户真实游戏存档。JSON往返、免费领取、余额／等级、重领奖励和强退规则可检查；Godot磁盘写入、异常存档、UI、完整新法术路径与神器经济联合分布均未实现／验证，不能据此宣称存档或通关体验已通过。

[write_meta_review.py](write_meta_review.py)核对十项输入哈希后生成[08局外基线](../../../docs/游戏设计/历史方案/08-局外成长触媒与宝石.md)。当前一级／三级完整池关联展示目标和首次升级／完整培养材料目标通过；最大攻击宝石只加开局攻击，不抬高回盾。成本扫描是快速验证版节奏的取舍，完成全培养后只保留剩余魔尘，不推导新价格或无限属性。

## 普通房数量与动态增援

[普通房源](../../../data/balance_candidates/normal_rooms_v1.json)拥有50个普通房的敌人组合、批次、预警、触发阈值、在场上限与布局意图；用户已同意数量／组合／批次节奏，原字节保留。四个既有源分别提供基础、神器、经济和局外数值，不复制敌人血量、特殊房或奖励。实际普通房只读本源；旧scenarios.json中的1／10／20房等敌人数仍是历史基准夹具。[room_scenarios.json](room_scenarios.json)只拥有五种构筑输入、速度观察带、种子与扫描。最新地图配置归03第4节与room_spatial_v1.json，旧空间候选由其接管；本页旧输出模型没有实体掩体、地刺或位置AI。

```powershell
python tools/balance/first_run/run_rooms.py
python tools/balance/first_run/write_room_review.py
```

[rooms.py](rooms.py)派生神器模型，房内从出生预警推进到动态添加下一批；在场剩余两只且整批放得下才预警，所有批次已出完并清空才胜利。批间保留冷却、计数、精灵和区域，缺盾时F10在待出批间隙也可施放。无目标时不循环微秒轮询，激活新敌时唤醒就绪法术；精灵只召一次并持续攻击。已有区域仍按旧抽象模型锁定目标组，新出生敌人不会加入旧组，这是对区域路线偏保守的限制。

[run_rooms.py](run_rooms.py)核对50普通／7精英／3首领覆盖、教学、预算／上限、两批手算计时、批间护盾不回满／F10可回盾、精灵时钟延续及零预警单批与既有模型等价。每次进入房间只接收更早房间的箱子和实际购买库存，不提前应用本房奖励。单场从满生命／盾、技能就绪开始，不推定跨房冷却或整局承伤。

当前[执行结果](../../../build/qa/normal-rooms-20261017/selected/results.json)为270项检查、5种输入×50房×32次共8,000次主抽样，另72组×16次共1,152次扫描；主抽样无90秒超时，在场数未越过上限。预设观察带有75组中位低于下沿、0组高于上沿、160组在范围内、15组教学例外；检查通过不代表全部时长目标达到。每房中位／P10／P90、实际在场峰值和空场等待归同目录rooms.csv／JSON。

`--config`、`--scenarios`、`--out`可指定明确输入和输出，`--no-sweep`可省扫描；计算量由情境中的trials／sweep_trials管理。扫描比较0.5／1.2秒预警及剩余0／3只触发，保留硬上限；不是实际玩家出怪偏好或通关率。模型不含位置、寻路、敌人攻击、遮挡与安全路线，也未联合随机触媒法术路径；安全距离与重型错峰的实际配置现归新空间源，旧相邻边候选由左右边缘替代；都未接入游戏。

[write_room_review.py](write_room_review.py)核对15项输入／代码哈希后生成[09逐房提案](../../../docs/游戏设计/历史方案/09-普通房配置与难度节奏.md)和[节奏图](../../../build/qa/normal-rooms-20261017/selected/pacing.png)。图只展示普通房总数、并发上界与血量预算，特殊房仅标节点；血量合计不等于实机难度。本轮未创建Godot关卡或运行游戏，后续接入后需另验规则、空间、画面和体验。

## 历史18×9尺寸核算

[map_metrics_v1.json](../../../data/balance_candidates/map_metrics_v1.json)拥有首版地面尺寸、格距、拟定投影／HUD占位和过房默认项。[check_map_metrics.py](check_map_metrics.py)读取基础源的移速／半径、project.godot的画布及既有角色绘制调用，不复制这些参数；执行 `python tools/balance/first_run/check_map_metrics.py` 即可重算[结果](../../../build/qa/map-metrics-20261017/results.json)。结果含6项输入哈希和16×8／18×9／20×10三个直接几何对照，没有随机或动态战斗。18×9的手算锚点为(18−0.6)/5＝3.48秒、(9−0.6)/5＝1.68秒。

18×9已因缺少整房向上推进构图而撤回，[旧示意图](../../../build/qa/map-metrics-20261017/room_size.png)与核算原样保留，不再是当前推荐。旧检查器只覆盖空矩形通行时间与角色绘制矩形是否落在拟定HUD之间，没有真实画面或空间安全验证。

## 整房构图与当前尺寸核算

当前[map_metrics_v2.json](../../../data/balance_candidates/map_metrics_v2.json)按下方进入／中部战斗／清场后上方传送组织12×14米整房，三带深度2／10／2米。[check_room_composition.py](check_room_composition.py)读取既有基础、画布和脚底锚点，以拟定新投影／角色显示比例核对地面、人物、墙、传送四框，并检查分区覆盖、HUD占位、传送状态及终点结算，不改旧源。

执行 `python tools/balance/first_run/check_room_composition.py` 复现[结果](../../../build/qa/room-composition-20261017/results.json)，内含10项参数／代码／概念图／提示词哈希；以旧检查器复现v1结果，通过矩形包含边界与独立手算锚点(12−0.6)/5＝2.28秒、(14−0.6)/5＝2.68秒。旧人物矩形169.6像素是历史输入，新96像素是候选呈现值，角色碰撞、移速不变。

[03第4.3节](../../../docs/游戏设计/历史方案/03-首关流程与场景.md#43-首版尺寸建议与默认项)先展示内置image_gen的[整房概念图](../../../docs/游戏设计/参考图/06-整房构图-v2.png)，再给出尺寸；概念图不是精确量尺或运行资源。几何核算只检查声明矩形，不验证真实Godot、法杖／头顶条／首领／特效、出生点、障碍／地刺布局或敌人AI；三带连通、初始安全不代表永久无敌，终点仍最终结算。后续接入另做白盒、像素和用户体验验收。

## 12×14米地图布局、地刺与出生配置

[room_spatial_v1.json](../../../data/balance_candidates/room_spatial_v1.json)是本轮唯一空间调参源：三模板掩体坐标、固定刺板／分组／时序／伤害与主威胁窗口、8区16位／体积预算／整批重校和60房映射。尺寸、人物、普通房批次／上限、阶段和属性对照分别引用已同意源，不复制其默认值；旧普通房数量与组合不变。spatial_scenarios.json只放网格精度、反应／有效移动夹具、种子、抽样数、扫值和重型时长夹具。

```powershell
python tools/balance/first_run/run_spatial.py
python tools/balance/first_run/write_spatial_review.py
```

[spatial.py](spatial.py)负责保守方形膨胀／四向网格、整批选位与激活重校、地刺与重型独占窗口、每轮一次接触伤害；[run_spatial.py](run_spatial.py)做手算夹具、24个静态掩码、24组预警／尺寸扫值、800次普通房首批与600次增援夹具、750个空场容量点位、受击／清场／死亡边界和既有盾成长对照。当前1538项断言包含大量同规则重复情境，不是1538个独立设计结论；扫值明确保留不满足反应余量的对照。

默认[结果](../../../build/qa/room-spatial-20261017/selected/results.json)保存10项源／情境／代码哈希与参数快照，同目录sweeps.csv和spawn_trials.csv保留逐项输入。可用--config／--scenarios／--out另存明确对照，不覆盖默认源。[生成器](write_spatial_review.py)核对全部哈希后更新03第4.4—4.8节与[米制图](../../../build/qa/room-spatial-20261017/selected/layout_plans.png)，只针对默认结果生成当前文档；绘图使用已安装Matplotlib及项目现有Noto字体。原整房概念图和尺寸源保持不变。

网格方形膨胀在角部比圆形碰撞更保守，四向路径不切角；静态安全网格不等于真实敌人不堵路。出生抽样不是全部位置的数学证明，无法安全放整批时必须排队／重新完整预警。重型夹具时长不是实际首领招式时长，普攻弹体可继续存在。短窗口承伤不含F10、回复与整局随机路径，不是胜率模拟。未修改、解析或启动Godot；实际碰撞／寻路、自动选敌、合并弹道预警与画面留到白盒接入后分别验收。
