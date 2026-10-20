"""Historical reproduction: write migrated drafts only, never current themes.

Generate the economy proposal snapshot from original inputs and executed results.
"""
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from design_documents import resolve_design_document

ROOT = Path(__file__).resolve().parents[3]
REPORTS = ROOT / "build/qa/run-economy-20261017"
SOURCE = ROOT / "data/balance_candidates/run_economy_v1.json"
DEST = resolve_design_document(ROOT / "docs/游戏设计/07-金币商店与品质.md")


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def table(headers, rows):
    return "\n".join(["| " + " | ".join(headers) + " |", "|" + "|".join("---" for _ in headers) + "|"] + ["| " + " | ".join(map(str, row)) + " |" for row in rows])


def number(n):
    return f"{n:g}"


def pct(n):
    return f"{n * 100:.1f}%"


def span(d):
    return f"{number(d['median'])}（{number(d['p10'])}—{number(d['p90'])}）"


result = read(REPORTS / "selected/results.json")
config = read(SOURCE)
assert result["parameters"] == result["source_parameters"] == config
for name, entry in result["input_hashes"].items():
    assert hashlib.sha256(Path(entry["path"]).read_bytes()).hexdigest() == entry["sha256"], f"Stale {name}"
baseline = read(REPORTS / "unlimited-replayed/results.json")
unguaranteed = read(REPORTS / "without-guarantees/results.json")
assert baseline["model_version"] == unguaranteed["model_version"] == result["model_version"]
base = read(SOURCE.parent / config["base_parameters"])
catalog = read(SOURCE.parent / config["artifact_catalog"])
scenario = result["assumptions"]
names = {"burst":"连发爆破", "spirit":"精灵协同", "area":"阵地覆盖", "weak":"辅助偏多／低命中", "optimized":"集中输出／高命中"}
policies = {"balanced":"按路线偏好购买", "save_gold":"前店买蓝、中期存首金", "cheapest":"优先最低价", "no_shop":"只领箱子、不购买"}
rarities = {"blue":"蓝色", "purple":"紫色", "gold":"金色"}
normal = [r for r in result["rows"] if r["path"] in scenario["ordinary_paths"] and r["policy"] == "balanced"]
all_balanced = [r for r in result["rows"] if r["policy"] == "balanced"]
out = []


def write(value=""):
    out.append(value)


write("# 金币、商店与神器品质 · 首版制作基线")
write()
write(f"日期：2026-10-17。用户已同意21件神器及本页金币、商店与品质方案先按此版推进；数字、规则与计算证据保持上一版，源文件保留candidate命名及原字节。参数 `{config['version']}`，模型 `{result['model_version']}`。唯一经济调参源为[data经济表](../../data/balance_candidates/run_economy_v1.json)，本页由同源数据与匹配哈希的执行结果生成；当前游戏没有接入，数值同意不等于实机体验认可。")
write()
write("## 1. 范围与购买节奏")
write()
write(f"沿用[六十房节点](03-首关流程与场景.md)和[已同意神器](02-火系神器.md)：7精英、15／45首领共9个免费神器箱，9／24／33／42／54房后5家酒馆。每店展示至多{config['offers']['shop_slots']}件神器，**本店最多买{config['shop']['max_purchases_per_visit']}件**，因此整局最多9箱＋5购买＝14件。只卖当前有用且未持有的神器，不另卖法术、局外宝石或恢复服务。")
write()
write("目标是先买一件蓝色改善前期，中期在立即补强和存钱等金色之间取舍，最后一店补关键缺件。首版减少经营操作：固定商品、统一价格，购买次数归整家店，退出重进不能再买一件。")
write()
write("## 2. 金币从哪里来")
write()
write(f"开局{config['currency']['initial']}金币。存活并完成房间后自动入账一次，精英奖金与普通清房收入相加；敌人个数、召唤次数和战斗耗时不改变收入。")
write()
write(table(["阶段","普通房","精英总收入","计算"], [(f"{s['name']} {s['from']}—{s['to']}",s["clear_gold"],s["clear_gold"]+s["elite_bonus"],f"清房{s['clear_gold']}＋精英加奖{s['elite_bonus']}") for s in config["stages"]]))
write()
write(table(["特殊节点","金币","其他奖励"], [(f"{room}房首领",next(s["clear_gold"] for s in config["stages"] if s["from"]<=int(room)<=s["to"])+bonus,f"含额外首领奖{bonus}；另有神器箱及原战后回血") for room,bonus in config["income"]["boss_bonus"].items()] + [("60房最终首领","直接最终结算","不再发无后续用途的局内金币／神器箱／法术")]))
write()
write("首版不设击杀金币、连胜、满血／无伤奖金或广告收入；盾受损、生命受损均不扣清房收入。这样生命压力与金币购买力可分别调节，受伤较多的玩家仍可获得同样的补强预算。参考拆解案中的旧奖励只是来源信息，没有自动沿用为本版要求。")
write()
write(table(["商店：哪房后","距上一店新增金币","累计取得（尚未扣购买）"], [(r["shop_after"],r["increment_since_previous_shop"],r["cumulative_earned"]) for r in result["income_ledger"]]))
write()
last_budget = result["income_ledger"][-1]["cumulative_earned"]
write(f"最后商店之前可支配的总收入为{last_budget}；1—59房总收入{result['total_run_income']}。最后商店后的{result['total_run_income']-last_budget}只计入本局结算记录，不能反算成购买力。金币只在本局使用，结束后清空；暂不兑换触媒、宝石等局外资源。结算展示取得、消费、剩余三项，不额外增加计分公式。")
write()
write("## 3. 商店商品与价格")
write()
write(table(["品质","已同意条目数","统一价格","商品范围"],[(rarities[t],sum(i["rarity"]==t for i in catalog["items"].values()),config["prices"][t],"十法术各一件专属＋生命琥珀／护壁晶核" if t=="blue" else "五件配套＋增幅棱晶" if t=="purple" else "炎冠圣契／赤灵王印／焚界之核") for t in rarities]))
write()
write(f"- 五店价格相同，不随房号涨价；商品显示名称、品质、效果与价格。{config['offers']['shop_slots']}件是陈列数，只能买其中{config['shop']['max_purchases_per_visit']}件，也可以不买。")
write("- 清房应有的法术选择先完成，才确定本次神器资格；不增加法术奖励次数。酒馆首次进入先领免费成长与回血，再查看并购买固定商品。")
write(f"- 沿用已同意的每店免费生命上限＋{base['recovery']['shop_max_health_gain']}、按新上限回复{pct(base['recovery']['shop_fraction'])}；不消耗金币，也不占本店神器购买次数。当店买生命琥珀不追补已结算的免费回血。")
write("- 三件通用神器与其余条目同池抽取，不保证每家店另送或必卖一件通用神器；每件本局最多持有一件。")
write("- 本店不刷新、不补货、不回售。离开后商品不保留到下一店；再次打开本店仍是相同库存、同一购买额度。下一家店重新抽取，先前未购买的条目仍可能出现。")
write()
first, second, third = result["income_ledger"][:3]
blue, purple, gold = (config["prices"][t] for t in rarities)
at_second = second["cumulative_earned"] - blue
at_third_saved = third["cumulative_earned"] - blue
write(f"购买例：9后有{first['cumulative_earned']}，买{blue}蓝装余{first['cumulative_earned']-blue}。24后进店有{at_second}；若买{purple}紫装，33后只有{at_third_saved-purple}。若24店存钱，33后有{at_third_saved}，遇到合用金色就能付{gold}。金色并非按时必在店里出现，因此盲目一直等金色会损失购买机会。")
write()
write("## 4. 阶段品质权重与节点保证")
write()
write("箱子和商店共用下表，适用于**一个普通随机候选位的基础品质权重**。它不是整箱品质概率，也不是玩家最后持有比例；节点保证和剩余池会改变实际展示率。")
write()
write(table(["阶段","蓝色","紫色","金色"],[(f"{s['from']}—{s['to']}房",*[f"{number(s['rarity_weights'][t])}%" for t in rarities]) for s in config["stages"]]))
write()
write(table(["节点","候选保证","边界"],[("9后第一商店","至少1件蓝色","确保初次到店有买得起的选择"),("15房首领箱","至少1件紫色","保证提供，不自动额外赠送"),("45房首领箱","至少1件金色","仍须满足法术资格且未持有；不保证指定金色")]))
write()
write("保证占用第一个候选位，其他位置正常抽取。若指定品质已无合资格、未持有条目，首位改取当前正权重池中最高品质；整池不足时只展示实际数量，全部耗尽明确跳过，不偷偷重复赠送或兑换金币。玩家仍能从箱子中选其他品质。")
write()
write("抽取顺序：先排除未满足法术条件和已持有的条目 → 排除该阶段零权重品质 → 执行首位保证 → 余位按仍有候选的品质重新归一权重 → 该品质内等概率选一件 → 同一屏不放回，再生成下一位。箱子选1件后才记为持有，其余候选下次仍可出现；商店未购买项也不算持有。")
write()
write("数学锚点：在蓝／紫数量足够、金色尚有可抽条目且没有首位保证时，中期三个普通候选里至少出现一金的概率是1−0.9³＝27.1%，不是10%。如果尚无合资格金色或已经全部持有，金色展示率为0，权重分给剩余品质；前期金色基础权重为0，缺池也不会提前解锁。")
write()
write("当前只有21件、每条路线未必符合全部条目。以按路线偏好购买的模拟为例，实际晚期候选统计如下，包含保证、持有过滤与少于三候选的情况；高品质已拿到后，后面的箱子可能主要提供补缺蓝装。")
write()
late_rows = []
for row in normal:
    for entry in row["effective_slot_probabilities"]:
        if entry["stage"] == "late":
            late_rows.append((names[row["path"]],"箱子" if entry["source"]=="chest" else "商店",*[pct(entry["probabilities"][t]) for t in rarities]))
write(table(["路线","晚期实际候选位","蓝","紫","金"],late_rows))
write()
write("这些是特定固定法术路径／选择偏好的条件结果，不能作为面向所有玩家的统一实际掉率。没有靠补同名物品维持名义概率。")
write()
write("## 5. 模型验证与方案取舍")
write()
write(f"保留[独立工具](../../tools/balance/first_run/README.md)。{len(result['checks'])}项模型检查通过，含手算账本、品质归一、三候选27.1%对照、资格、池不足、零权重、购买额度与重开、余额非负和守恒；{len(result['targets'])}项经济目标均在预设范围。")
write()
write(f"5条固定合法法术路径，三普通路线各4种购买策略、另2条边界路线只比较常规购买，共{len(result['rows'])}组、每组{scenario['trials']}次，合计{sum(r['trials'] for r in result['rows']):,}次条件整局；扫描另{len(result['sweeps'])}组、每组{scenario['sweep_trials']}次。种子{scenario['seed']}＋路线CRC32＋试验编号；同一路线不同策略用同批种子，另报告前后半批独立种子结果。假设抵达全部节点，不是预测通关概率。")
write()
write(table(["普通路线","购买件数：中位（P10—P90）","最终持有","金色件数","空神器箱局比例","结算剩金中位"],[(names[r["path"]],span(r["purchases"]),span(r["owned"]),span(r["gold_owned"]),pct(r["empty_chest_campaign_rate"]),number(r["leftover"]["median"])) for r in normal]))
write()
write("四种策略是明确输入的行为假设：")
write()
for key, description in scenario["policy_descriptions"].items():
    write(f"- {policies[key]}：{description}。")
write()
write(table(["路线","存首金时购买中位","不购买最终持有","实际取舍"],[(names[path],number(next(r["purchases"]["median"] for r in result["rows"] if r["path"]==path and r["policy"]=="save_gold")),number(next(r["owned"]["median"] for r in result["rows"] if r["path"]==path and r["policy"]=="no_shop")),"等待核心可能少买1—2件；最低价买法会留下更多无用途余额") for path in scenario["ordinary_paths"]]))
write()
write("路线偏好是情境顺序，不是效用数值、最优构筑或真实玩家选择。金色也不一定比关键紫色更合用；看见金色不等于必选，因此没有把‘未持有金色’误判为‘从未提供金色’。三件通用的实际获取率另留在结果中，不将其当默认赠送。")
write()
write(table(["相同模型的比较","连发爆破","精灵协同","阵地覆盖"],[("不限制多买：遇到空箱的局比例",*[pct(next(r["empty_chest_campaign_rate"] for r in baseline["rows"] if r["path"]==p and r["policy"]=="balanced")) for p in scenario["ordinary_paths"]]),("本版最多买1件：空箱的局比例",*[pct(r["empty_chest_campaign_rate"]) for r in normal]),("取消首店蓝色保证：首店无可负担商品",*[pct(1-next(r["visits"][0]["affordable_rate"] for r in unguaranteed["rows"] if r["path"]==p and r["policy"]=="balanced")) for p in scenario["ordinary_paths"]])]))
write()
write("不限制多买的对照同时使用较高初试收入，只用于比较整套初试与收敛方案，不能把差异全归因于购买上限。比较结果解释为何保留单店购买额度与第一店蓝色保证；基础生命、法术和21件神器数值均未改变。")
write()
thin_rate = next(r["thin_offer_campaign_rate"] for r in normal if r["path"] == "burst")
write(f"边界：连发路线约{thin_rate*100:.2f}%的模拟会遇到少于三候选，通常发生在57房只剩两件可选；本版没有出现空箱。若以后要求全程严格三选一，需要扩充合资格条目，或减少可购买次数，不能靠重复神器凑数。首版沿用‘最多三选一、池不足按实际展示’。")
write()
write("收入降低20%或价格提高20%的扫描中，三普通路线购买中位由5降至4；提高收入或降价并不突破单店额度，主要改变高品质购买能力／余钱。中期金权重5%与20%的对照没有改变最终金色中位2件，但出现时机及选择组合会变化；45房保证与仅有三件金色限制了只看最终数量的解释力。")
write()
write("## 6. 邻近战斗检查与证据限制")
write()
write(f"把模拟实际获得的库存接回已校验的神器事件模型，按均匀间隔选取每组{scenario['combat_probes_per_route']}条整局结果，执行{sum(r['n'] for r in result['combat_probes'])}个最终首领输出抽样；没有用预先指定的九件理想库存替代掉落结果。")
write()
write(table(["路线","正常购买最终首领秒：中位（P10—P90）","只拿箱子中位秒"],[(names[path],f"{r['ttk']['median']:.1f}（{r['ttk']['p10']:.1f}—{r['ttk']['p90']:.1f}）", f"{next(p['ttk']['median'] for p in result['combat_probes'] if p['path']==path and p['policy']=='no_shop'):.1f}" if path in scenario["ordinary_paths"] else "未在本轮抽样") for path in names for r in result["combat_probes"] if r["path"]==path and r["policy"]=="balanced"]))
write()
write("集中输出路线约15秒，是需要观察的强度上界信号；本页没有擅自削弱已同意神器或抬高首领生命。接入后要核对最终首领二阶段是否有足够展示时间。抽样只验证库存与输出的衔接，没有真实位置、寻路、避险或整局生命损耗，也不证明高存钱策略更容易通关。")
write()
write("试玩观察：初店是否清楚只有一次购买；33店预算不足时是否愿意存钱；拿金色前后是否改变选择；57箱不足三选一是否可接受；未花金币与最后商店后收入是否让玩家困惑。数值、经济模型、Godot规则实现、画面和体验分别验收。")
write()
write("[本版结果与输入哈希](../../build/qa/run-economy-20261017/selected/results.json)、[逐策略统计CSV](../../build/qa/run-economy-20261017/selected/summary.csv)、[固定种子整局轨迹](../../build/qa/run-economy-20261017/selected/sample_campaigns.json)、[较高收入不限购买对照](../../build/qa/run-economy-20261017/unlimited-replayed/results.json)、[取消节点保证对照](../../build/qa/run-economy-20261017/without-guarantees/results.json)。本轮只保存设计参数、工具与文档；未修改现有运行文件、未启动游戏或进行Godot规则／画面验收、导出或上传。")
write()
DEST.write_text("\n".join(out), encoding="utf-8")
print(f"generated {DEST}")
