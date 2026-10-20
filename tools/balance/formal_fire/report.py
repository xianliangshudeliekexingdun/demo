"""Read-only report and narrow acceptance probes after the bound main run."""
from __future__ import annotations

from copy import deepcopy
import hashlib
import heapq
import math
from pathlib import Path

from io_utils import DEFAULT_OUT, ROOT, hashes, load, read, write
from model import Model


class KillCapture(Model):
    def raw_damage(self, actor, value, source, ident):
        was_alive = self.alive(actor)
        actual = super().raw_damage(actor, value, source, ident)
        if was_alive and not self.alive(actor) and not hasattr(self, "first_kill_at"):
            self.first_kill_at = self.now
        return actual


def advance(model, until):
    while model.queue and model.queue[0][0] <= until+1e-8:
        model.now, _, _, kind, payload = heapq.heappop(model.queue)
        model.dispatch(kind, payload)
    model.now = until


def acceptance(inputs, manifest, rows):
    params, base, _, _ = inputs
    checks, starters = [], []

    def check(label, condition, **details):
        checks.append({"label": label, "pass": bool(condition), **details})

    for ident in ("F01", "F03", "F08"):
        times = []
        for seed in params["seeds"]:
            scene = deepcopy(params["scenarios"][0])
            scene["health"] = 180
            model = KillCapture(*inputs, scene, {"items": [], "crit_rate_override": 0}, [ident], 1, seed, 6)
            model.run()
            kill = getattr(model, "first_kill_at", None)
            times.append(kill)
            check("L1 stationary180 no-crit/no-items/no-synergy within6s", kill is not None and kill <= 6,
                  spell=ident, seed=seed, first_kill_seconds=kill)
        starters.append({"spell": ident, "minimum_seconds": min(times), "maximum_seconds": max(times), "times": times})
    scene = deepcopy(params["scenarios"][0])
    scene["health"] = 180
    model = KillCapture(*inputs, scene, {"items": [], "crit_rate_override": 0}, ["F03"], 1, 20261018, 5)
    model.now = .7
    model.post_hit(0, 1, {"id": "F03", "cast": 1, "natural": True, "scale": 1, "field": 0}, ignite=True)
    expected_first_only = .7+math.ceil((180-100)/(100*params["burn"]["tick_coefficient"]))*params["burn"]["interval"]
    advance(model, expected_first_only)
    check("only guaranteed first rain100 plus selected burn kills at2.7", abs(getattr(model, "first_kill_at", 999)-expected_first_only) < 1e-8 and model.metrics["damage"] == 180,
          damage=model.metrics["damage"], first_kill_seconds=getattr(model, "first_kill_at", None))
    burn_rates = []
    for items in ([], ["P06"]):
        model = Model(*inputs, deepcopy(params["scenarios"][0]), {"items": items, "crit_rate_override": 0}, ["F01"], 1, 20261018, 10)
        model.ignite(0)
        for tick in range(1, 41):
            advance(model, tick*.25)
            model.ignite(0)
        damage = model.by_source["burn"]
        expected_damage = 10/params["burn"]["interval"]*100*params["burn"]["tick_coefficient"]
        check("repeated shared ignition maintains selected single-instance rate", abs(damage-expected_damage) < 1e-6,
              items=items, damage_over10seconds=damage, ticks=model.metrics["burn_ticks"])
        burn_rates.append({"items": items, "damage_over10seconds": damage, "damage_per_second": damage/10})
    g03 = []
    for trigger in ("age_two_seconds", "expiration"):
        profile = {"items": ["G03"], "cdr_override": .6, "g03_trigger": trigger, "crit_rate_override": 0}
        model = Model(*inputs, deepcopy(params["scenarios"][0]), profile, ["F06"], 3, 20261018, 60)
        result = model.run()
        count = result["metrics"].get("g03_bursts", 0)
        check("G03 trigger high-CDR criterion", count > 0 if trigger == "age_two_seconds" else count == 0, trigger=trigger, count=count)
        g03.append({"trigger": trigger, "count": count})
    current = hashes(manifest["source_hashes_before"])
    check("all main-run bound sources still match", current == manifest["source_hashes_before"])
    first = next(r for r in rows if r["group"] == "spell" and r["build"] == "F01" and r["scenario"] == "single_static" and r["profile"] == "ordinary" and r["level"] == 3 and r["horizon"] == 60)
    spread = next(r for r in rows if r["group"] == "spell" and r["build"] == "F11" and r["scenario"] == "spread_six" and r["profile"] == "ordinary" and r["level"] == 3 and r["horizon"] == 60)
    ratio = spread["total"]["mean"]/first["total"]["mean"]
    check("F11 spread-six versus F01 single identity criterion", .8 <= ratio <= 1.2, ratio=ratio, target=[.8, 1.2])
    return {"checks": len(checks), "failures": [x for x in checks if not x["pass"]], "details": checks,
            "starter_cases": starters, "continuous_burn": burn_rates, "g03_comparison": g03, "identity_ratio": ratio,
            "scope": "Narrow candidate mathematical criteria, separate from current native bridge and main matrix; no AI/survival/full route"}


def main():
    inputs = load()
    params, base, _, _ = inputs
    manifest = read(DEFAULT_OUT / "run_manifest.json")
    rows = read(DEFAULT_OUT / "scenario_results.json")["scenarios"]
    rain = read(DEFAULT_OUT / "rain_math.json")
    native_summary = read(DEFAULT_OUT / "baseline_summary.json")
    criteria = acceptance(inputs, manifest, rows)
    write(DEFAULT_OUT / "acceptance_checks.json", criteria)
    if criteria["failures"]:
        raise AssertionError(criteria["failures"])

    def find(group, build, scenario="single_static", profile="ordinary", level=3, horizon=60):
        return next(r for r in rows if r["group"] == group and r["build"] == build and r["scenario"] == scenario and r["profile"] == profile and r["level"] == level and r["horizon"] == horizon)

    def mean(row, category, key):
        return row[category].get(key, {}).get("mean", 0)

    lines = ["# 正式火系候选数值核验", "", "本轮仅设计和持久工具，运行游戏仍未接入F11、共享燃烧与新职业宝物。参数推荐沿用审查稿，不把抽象输出拟合成真人胜率、正式Boss或最终30分钟时长。",
             "", "## 结论与判据", "", "采用每跳25%攻击、G04额外引爆倍率＋2作为本轮主候选。三起手静止180HP、无道具／共鸣／暴击的受控判据通过；F03首落100＋完整燃烧200的完整预算300，只有首落命中时180HP锚点在2.7秒解决。共享燃烧重复刷新没有叠层／延迟首跳，P06不提升维持中的50%攻击／秒伤害率。G03改为满2秒能解决本次孤立高CDR法阵的触发饥饿，仍可能被更早的P04追加替换中断。",
             "", "| 起手L1 | 8固定seed中首次击杀时间范围 | 场景 |", "|---|---:|---|"]
    for row in criteria["starter_cases"]:
        lines.append(f"| {row['spell']} | {row['minimum_seconds']:.2f}～{row['maximum_seconds']:.2f}秒 | 1个静止180HP、半径0.3米、无暴击、首击命中 |")
    lines += ["", "这些是离散模型结果，不用平均伤害取整冒充预计击杀时间。F03‘其余落全空’另以独立手算／事件夹具确认2.7秒；移动、AI、碰撞穿越和受伤均未加入。",
              "", f"F11疏散6目标对同参F01单体的总输出比为{criteria['identity_ratio']:.3f}，进入预定0.8～1.2的初版身份区间；这只验证特定角色目标，不要求所有场景DPS相等，也不证明八槽机会成本已完全合理。B05减速与B09移速的真实价值未折算伤害。整体输出平衡仍待实装后的相同敌群试玩。",
              "", "## 模型修复与数值选择分开", "", "先修复等待就绪后漏吟唱、追加F07误用过去锁点、F01次弹落地才重选三项模型缺陷，并补回归；这些改动没有用提高数值掩盖工具错误。修正前984矩阵已经移入initial-candidate/retired-pre-correction，明确不作当前结论。",
              "修正模型下初版每跳10%／G04＋1的12组、96轨迹与参数原字节保存于initial-candidate。随后独立96组／768轨迹比较每跳10／20／25／30%与G04＋1／＋2：身份比0.456／0.737／0.858／0.968。25%是本次达到身份区间所需的较低候选，G04＋2使引爆构筑的收益更可感知；30%／＋2是更高整体增益备选，未选用。详见identity_sensitivity.md/.json。",
              "", "## 来源与通过范围", "", f"当前真实core：228条隔离输出、{manifest['native_bridge']['checks']}项原生检查、{native_summary['summary_checks']}项后处理检查，均0失败。原生脚本已通过本机Godot4.7.2解析；直接调用现行Route/Spell/Artifact APIs，没有运行完整路线。",
              f"候选抽象：{manifest['seed_and_trial_count']['scenarios']}场景×{manifest['seed_and_trial_count']['seeds_per_scenario']}固定seed＝{manifest['seed_and_trial_count']['trajectories']}条轨迹；{manifest['validation']['checks']}项模型检查0失败（其中4200条为固定seed刷新状态／终止检查）；本报告另{criteria['checks']}项明确判据0失败。两类检查不与旧suite累计。",
              f"矩阵包括{manifest['group_counts']['spell']}个单法术场景、{manifest['group_counts']['build']}个组合场景、{manifest['group_counts']['item']}个职业单件／对照场景；来源运行前后保持，报告时全部{len(manifest['source_hashes_before'])}个绑定来源仍匹配。",
              "", "当前基线见`baseline.md`，包含旧G03＋F06三级在无额外CDR时60秒7次到期触发、总CDR60%时0次。该证据来自真实旧core，不用未来候选替代历史实现。",
              "", "## 火雨：期望与上界分开", "", f"假想半径0.3米目标恰在中心，随机落点在半径1.32米圆盘内等面积分布：命中概率=min(1,((0.85+0.3)/1.32)²)＝{rain['uniform_disk_random_drop_hit_probability']:.6f}。独立{rain['trials']:,}次抽样得到{rain['monte_carlo_observed']:.6f}，绝对误差{rain['absolute_error']:.6f}。此式只计算单落几何，不包含追踪、移动、暴击、燃烧或末段地火。",
              "", "| 等级 | 当前随机各落直伤期望 | 候选固定首100后直伤期望 | 候选落击全命中上界 | 加完整地火后总本体上界 | B03落击直伤期望 |", "|---|---:|---:|---:|---:|---:|"]
    for row in rain["levels"]:
        ground = base["spells"]["F03"]["levels"][row["level"]-1]
        ground_coefficient = ground["ground_coefficient"]*ground["ground_duration"] / base["spells"]["F03"]["ground_interval"]
        lines.append(f"| {row['level']} | {100*row['current_random_expected_direct_coefficient']:.2f}% | {100*row['candidate_expected_direct_coefficient']:.2f}% | {100*row['candidate_all_hit_upper_direct_coefficient']:.0f}% | {100*(row['candidate_all_hit_upper_direct_coefficient']+ground_coefficient):.0f}% | {100*row['with_B03_expected_direct_coefficient']:.2f}% |")
    actual_m01_radius = read(ROOT / params["first_room_geometry_source"])["M01"]["radius"]
    actual_hit = min(1, ((params["geometry"]["rain_impact_radius"]+actual_m01_radius) / (base["spells"]["F03"]["radius"]*params["geometry"]["rain_scatter_fraction"]))**2)
    lines += ["", f"本模型半径0.3米是明确的假想目标，不冒充当前M01。当前M01半径{actual_m01_radius:.2f}米时，同一静止圆盘几何的单落命中概率约{actual_hit:.4%}，说明目标大小会明显改变期望；仍不能据此替代真实追击命中率。候选首落100%是系数，其固定中心不等于必定追中已移动目标。",
              "", "## 三级有限时间输出", "", "下表为60秒、A100、默认5%暴击、无道具、单独持有该术（没有三火）的**总目标DPS均值**。密集／疏散／移动均有6目标，单体只有1目标；不能横跨目标数量比较命中能力。F02增伤需与其他法术组合，F10无缺盾不施放，低DPS不代表其无效。",
              "", "| 法术 | 1静止 | 6密集 | 6疏散 | 6合成移动 |", "|---|---:|---:|---:|---:|"]
    for ident in params["retained_ids"]+list(params["new_spells"]):
        values = [find("spell", ident, scene)["total"]["mean"] / 60 for scene in ("single_static", "dense_six", "spread_six", "mobile_low_coverage")]
        name = params["new_spells"].get(ident, base["spells"].get(ident, {}))["name"]
        name = params["spell_overrides"].get(ident, {}).get("name", name)
        lines.append(f"| {ident} {name} | " + " | ".join(f"{value:.2f}" for value in values)+" |")
    lines += ["", "移动轨迹是合成正弦曲线，不受玩家、击退或减速影响；只能看本模型中的覆盖损失。火弹为落点采样近似，不执行现项目完整扫掠碰撞；无目标时0.05秒复查后完整吟唱，不冒充原生120Hz时序。F05／F06的控场与站位收益不能由本表判死。全部30秒、各级、样本最小／最大／SD／标准误在CSV和JSON中。",
              "", "## 八槽固定组合与分量", "", "固定八进攻：F01／F02／F03／F05／F06／F07／F08／F11，全部三级，1静止目标、60秒。无额外CDR实际包含三火10%；通用施法组含U03／GU05／GU06／GU07／P04／P05共6件；通用＋职业再含G01／P06／G04，合计9件。不是自然九箱保证取得。",
              "", "| 配置 | 本体（含区域） | 共享燃烧 | 引爆 | 职业派生 | 总DPS |", "|---|---:|---:|---:|---:|---:|"]
    labels = {"ordinary": "无额外CDR（总10%）", "high_cdr": "总CDR60%压力", "generic_cast_triggers": "6通用（总16%＋P05事件）", "profession_areas": "3火区职业", "generic_profession": "6通用＋3职业"}
    for profile, label in labels.items():
        row = find("build", "eight_offense", profile=profile)
        values = [mean(row, "by_source", x)/60 for x in ("direct", "burn", "detonation", "profession_proc")]
        lines.append(f"| {label} | "+" | ".join(f"{v:.2f}" for v in values)+f" | {row['total']['mean']/60:.2f} |")
    lines += ["", "固定附伤GT01另在有明确每3秒损失30盾的合成输入中计算；只扣实际拥有的盾，不模拟穿盾生命伤害或存活。因此蓄能结果不能当受压时净生存或‘越挨打越赚’结论。P04／G01不递归，P05按剩余CD动态减半，F06追加会替换旧阵，不能直接把所有倍率相乘当线性提升。",
              "", "## 职业单件探针", "", "以下为三级60秒，单件相对相同法术／同seed对照的平均总伤害变化。对应法术组合在parameters.item_probes明列；不同项的对照不是同一构筑，禁止用这一列给全部宝物排绝对强弱。B05／B09未做DPS等价，B10列实际回盾变化。",
              "", "| 宝物 | 1静止 | 6密集 | 6疏散 | 6合成移动 |", "|---|---:|---:|---:|---:|"]
    item_values = []
    for probe in params["item_probes"]:
        cells = []
        for scene in ("single_static", "dense_six", "spread_six", "mobile_low_coverage"):
            control = find("item", probe["item"], scene, "control")
            item = find("item", probe["item"], scene, "with_item")
            a, b = control["total"]["mean"], item["total"]["mean"]
            if probe["item"] == "B10":
                a, b = mean(control, "metrics", "shield_restored"), mean(item, "metrics", "shield_restored")
            delta = (b/a-1)*100 if a else None
            cells.append(f"{delta:+.1f}%" if delta is not None else "无可比伤害")
            item_values.append({"item": probe["item"], "scenario": scene, "control_mean": a, "with_item_mean": b, "percent_delta": delta,
                                "metric": "actual_shield_restored" if probe["item"] == "B10" else "total_damage"})
        lines.append(f"| {probe['item']} | "+" | ".join(cells)+" |")
    lines += ["", "P06在持续高频刷新下不提高50%攻击／秒的共享燃烧率，收益主要来自低频覆盖、未来库存和引爆。G04的复燃不是立即伤害；若主爆／GT01已杀则不引爆，若引爆已杀则不安排，延迟期间死亡／结束也取消。F11对已经有燃烧的邻敌不占名额，不重复刷新它们。",
              "", "## G03新旧对照", "", "真实旧core高CDR的F06三级60秒到期触发为0；在同类隔离候选、总CDR60%、无P04条件下："]
    for row in criteria["g03_comparison"]:
        lines.append(f"- `{row['trigger']}`：{row['count']}次。")
    lines += ["", "此判据通过只证明触发冲突得到处理，不证明金色宝物的整体强度已经定案。常规矩阵还包含P04提前替换，有效爆发数按实际存续计算。",
              "", "## 局限与最小后续验证", "", "1. 实装后先用同一组前期敌群对照三起手的首击可靠性与受压清敌，再验证F11疏散覆盖是否足以支付八槽机会成本。当前无限HP主目标不转火，会高估持续聚焦、忽略补刀、过量伤害与实际击杀循环。",
              "2. 用同一移动策略对照火区／传播引爆／连射暴击，各取无道具和相同数量宝物；检查F06站位风险、F05末端停留、B05／B09控场、F11挡墙和G03追加替换可读性。",
              "3. 检查目标死亡、换房、清场与暂停时的原生事件权限；此模型只覆盖明确有限窗口／结束取消，不替代未来runtime测试和真实像素查看。",
              "", "不提供Boss生命、胜率、经济收益、触媒成型率或60房约30分钟结论。所有冻结候选参数仍是供审查的第一版，整体强度尚无用户验收。",
              "", "## 复现与文件", "", "见tools/balance/formal_fire/README.md。核心参数、场景、seed、结果源哈希在parameters.json／run_manifest.json；逐场景来源分量在scenario_results.json／scenario_summary.csv。当前实际core结果与假想候选分开存放，不把本次规则检查累计到旧主suite。", ""]
    (DEFAULT_OUT / "report.md").write_text("\n".join(lines), encoding="utf-8")
    write(DEFAULT_OUT / "summary.json", {"main_run": manifest["seed_and_trial_count"], "bound_sources_still_match": True,
                                        "native_checks": manifest["native_bridge"], "baseline_summary_checks": native_summary["summary_checks"],
                                        "model_checks": manifest["validation"], "acceptance_checks": {"checks": criteria["checks"], "failures": len(criteria["failures"])},
                                        "rain_math": rain, "item_probe_deltas": item_values,
                                        "report_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                                        "runtime_baseline_output_sha256": hashlib.sha256((DEFAULT_OUT / "runtime_baseline.json").read_bytes()).hexdigest(),
                                        "main_manifest_sha256": hashlib.sha256((DEFAULT_OUT / "run_manifest.json").read_bytes()).hexdigest(),
                                        "omissions": params["omissions"]})
    print(f"FORMAL_FIRE_REPORT acceptance={criteria['checks']}/0 bound_sources_still_match=True")


if __name__ == "__main__":
    main()
