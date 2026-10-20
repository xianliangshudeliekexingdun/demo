"""Human-readable tables from immutable design-model outputs, no simulation."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/qa/formal-spell-framework-20261018"


def read(name):
    return json.loads((OUT / name).read_text(encoding="utf-8"))


def pct(value):
    return f"{100 * value:.2f}%"


def main():
    manifest = read("run_manifest.json")
    exact = read("exact_offer_cases.json")
    sweep = read("sweep.json")
    accepted = read("recommended.json")
    validation = read("model_validation.json")
    runtime = read("runtime_fidelity.json")
    labels = {"primary_first": "有主选主", "learn_first": "新学优先", "upgrade_first": "升级优先", "mixed_four_four": "尝试4主＋4任意跨系"}
    levels = {"adaptive:0.28": "一级", "adaptive:0.4": "二级", "adaptive:0.52": "三级"}
    lines = ["# 正式触媒／法术抽样评估", "", "结论：建议采用按当前合法池计算的 `P主=q+(1-q)×强度`，一级／二级／三级强度28%／40%／52%；不采用固定每张40%／50%／60%。这是可进入原型验证的设计值，不是已接入运行规则或最终平衡验收。", "", "法术关系是情境型：本工具只计算取得分布与选择空间，不比较伤害、胜率或法术真实效用。触媒不提供攻击，不改变召唤间隔；没有保底或强制主系卡位。价格与魔尘收益不在模型中，当前45房不产生局外结算。", "", "## 证据与限制", "", f"当前Godot原core只读桥：{runtime['checks']}项、{runtime['failures']}失败；Python独立数学／分布核对：{validation['checks']}项、{validation['failures']}失败。{manifest['sweep_scenarios']}组扫描＋{manifest['recommended_scenarios']}组推荐情境，共{manifest['total_trajectories']}条固定seed轨迹，轨迹不变量违规{len(manifest['trajectory_invariant_failures'])}，运行来源稳定{manifest['source_stable']}。", "", "所有以下60法术初始概率均是“六系各10、全部ID当前合法”的数学锚点，不表示实际开局60项都可出现。轨迹仅覆盖等级／八槽资格：坍岩令已有构造、群灵号令／契约法阵已有召唤等总纲新前置，职业宝物资格、具体法术效用均未模拟。无触媒对照也固定同一主系起手，没有模拟真实随机起手。", "", "`mixed_four_four`只是4主系＋4个任意跨系ID；非主ID在六系时可分属五个学派，不能称为指定双系构筑成型率。百分比是模型中的抽样／预设选择结果，不是真人成型率或通关率，也没有任何完整60房／Boss／30分钟结论。", "", "## 六系10主＋50副的精确三卡分布", "", "| 规则 | 第一张主系 | 一屏至少1主 | 一屏全3主 | 一屏主系均数 | 一屏至少1副 |", "|---|---:|---:|---:|---:|---:|"]
    rules = ["uniform", "old_weight:1.5", "old_weight:1.75", "old_weight:2", "adaptive:0.28", "adaptive:0.4", "adaptive:0.52"]
    for rule in rules:
        row = next(x for x in exact if x["scenario"] == "six_school_fresh" and x["rule"] == rule)
        lines.append(f"| {rule} | {pct(row['first_draw_primary'])} | {pct(row['at_least_one_primary'])} | {pct(row['all_primary'])} | {row['expected_primary_cards']:.3f} | {pct(row['at_least_one_other'])} |")
    lines += ["", "旧权重一栏是把现行逐ID倍率机制推广到10主／50副的反事实比较；实际旧MC01只关联当前十火中的三个ID。不能写成当前游戏已有60法术。自适应数值40%／50%／60%只对应此锚点的第一张；每抽走一张后q重算，整屏概率不是独立二项式。", "", "## 两系／三系的跨系机会", "", "| 已上线系数 | 等级 | 第一张主系 | 一屏全3主 | 一屏至少1副 |", "|---|---|---:|---:|---:|"]
    for schools, scenario in [(2, "two_school_fresh"), (3, "three_school_fresh")]:
        for rule in levels:
            row = next(x for x in exact if x["scenario"] == scenario and x["rule"] == rule)
            lines.append(f"| {schools} | {levels[rule]} | {pct(row['first_draw_primary'])} | {pct(row['all_primary'])} | {pct(row['at_least_one_other'])} |")
    lines += ["", "上线学派少时，本系的自然基数更大，装备后纯系更容易，跨系卡机会随触媒等级下降。这是明确的取舍，不强制补副系卡位。玩家可主动选跨系，但不能承诺指定组合必成。只有一个学派实际可用时，任何概率倾向都不能改善已经100%本系的池；因此解锁触媒不能同时锁住所有其他已上线法术库。", "", "## 合法池边界与被否定方案", "", "| 状态：仅6主＋2副尚可升级 | 第一张主系 | 全3主 | 主系均数 |", "|---|---:|---:|---:|"]
    for rule in ["uniform", "fixed:0.4", "fixed:0.5", "fixed:0.6"] + list(levels):
        row = next(x for x in exact if x["scenario"] == "full_slots_six_primary_two_other_upgrades" and x["rule"] == rule)
        lines.append(f"| {rule} | {pct(row['first_draw_primary'])} | {pct(row['all_primary'])} | {row['expected_primary_cards']:.3f} |")
    lines += ["", "此状态至少出现1张主系是数学必然（副系只有两个合法ID而要抽三张），并非触媒保底。固定40%还会把两系初始无触媒50%的主池概率降到40%；固定60%会把满槽6主2副的75%降到60%。自适应强度保持两池非空时每张条件概率高于合法池均匀基线，且等级单调。", "", "主池只剩1／2个ID时，不放回会限制一屏主系最多1／2张；一池空则回退。仅剩三个合法ID时三张必然全展示，等级不能凭空再改变该屏组成；全满返回空候选。", "", "## 推荐值的23成长轨迹", "", "每行5000次、四个seed批次。前8指前八次法术奖励选择（另有一级起手），不是“已经拿满8槽”；最终指当前36书节点结束。由于满槽后不能换ID，首次满8槽和最终满级时的主／副ID数相同。", "", "| 系数 | 等级 | 预设偏好 | 前8奖励后主／副槽均值 | 最终主／副槽均值 | 最终主槽P05／P50／P95 | 8槽全主比例 | 4主＋4任意跨系比例 |", "|---|---|---|---|---|---|---:|---:|"]
    for row in accepted:
        main = row["final_primary_slots"]
        lines.append(f"| {row['active_schools']} | {levels[row['rule']]} | {labels[row['policy']]} | {row['first_eight_primary_slots']['mean']:.2f}／{row['first_eight_other_slots']['mean']:.2f} | {main['mean']:.2f}／{row['final_other_slots']['mean']:.2f} | {main['p05']}／{main['p50']}／{main['p95']} | {pct(row['all_primary_final_fraction'])} | {pct(row['mixed_four_four_final_fraction'])} |")
    lines += ["", "以上纯系／混搭比例受人为选择规则影响。不是概率保底、实战强度，也不证明角色价值相等。均值的Monte Carlo标准误、观测最小／最大、各seed批次均值、前8奖励中的副系出现频率、首次满槽所需成长数均保留于recommended.json。观测为0的事件不推断其数学概率为0。", "", "## p30／40／50／60／70扫描与简化敏感性", "", "固定p扫描只作对照，不能因某一策略的最终主系较多而忽略其相对均匀基线反向降概率的问题。", "", "| 六系、主系偏好 | 最终主槽均值 | 纯8主比例 |", "|---|---:|---:|"]
    for row in sweep:
        if row["active_schools"] == 6 and row["policy"] == "primary_first" and row["rule"].startswith("fixed:"):
            lines.append(f"| {row['rule']} | {row['final_primary_slots']['mean']:.3f} | {pct(row['all_primary_final_fraction'])} |")
    lines += ["", "简化强度30%／40%／50%在六系初始第一张为41.67%／50%／58.33%，不是40%／50%／60%；与主候选的L1／L3只差1.67个百分点，保留作敏感性，不据小样本尾部波动宣称更优。", "", "## 成长不变量与风险", "", "本模型348000条轨迹均：起手总等级1，每次合法选择增加总等级1，最多八槽三级总等级24，因此23次成长；实际第23个书节点是28房，随后13书节点资格耗尽跳过。204组结果均无非法ID、同屏重复、九槽或四级，首次满槽的ID组成与最终相同。未来法术前置未纳入，故此结论不能代替最终资格可达性工程验证。", "", "| 风险／未知 | 当前证据 | 最小后续验证 |", "|---|---|---|", "| 少学派时纯系过于集中 | 两系三级主系偏好纯8主约84.94%，六系约45.22%；属于版本与偏好条件 | 先以两系原型观察玩家是否感到副系仍值得选，再决定是否保持同强度 |", "| 看到概率就误以为保底 | 六系一级首抽40%，一屏至少1主实际78.62%，仍存在无主屏 | 文案明确抽取倾向，观察玩家能否预测连续未出现，不承诺必成 |", "| 法术前置改变合法池 | 总纲新构造／召唤前置未模拟；10＋50为锚点 | 接入时用真实资格池做同样DP／抽样与逐节点日志 |", "| 指定副学派被稀释 | 模型仅统计任意跨系，不衡量火＋冰等指定双系目标 | 法术／职业宝物定稿后单列指定副系与关键法术可达性 |", "| 实战价值不同 | 本模型没有DPS、站位、召唤、控制或Boss | 在同关卡／资源下进行两系实际构筑试玩，而非用概率当胜率 |", "", "复现见tools/balance/formal_spell_framework/README.md；本轮没有实现新玩法、修改价格或按未来150魔尘虚构收入。"]
    (OUT / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    current_matches = all(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest for path, digest in manifest["source_sha256"].items())
    summary = {"model_version": manifest["model_version"], "recommended_strengths": [0.28, 0.4, 0.52],
               "runtime_fidelity": {"checks": runtime["checks"], "failures": runtime["failures"]},
               "model_validation": {"checks": validation["checks"], "failures": validation["failures"]},
               "scenarios": manifest["sweep_scenarios"] + manifest["recommended_scenarios"],
               "trajectories": manifest["total_trajectories"], "invariant_failures": manifest["trajectory_invariant_failures"],
               "source_stable_at_run": manifest["source_stable"], "bound_sources_still_match": current_matches,
               "prerequisites_modeled": "levels and slots only; construction/summoning requirements explicitly omitted",
               "mixed_metric": "four primary + four arbitrary nonprimary IDs, not a specified secondary-school build",
               "claim_level": "draw/progression design prediction, not implementation, combat win rate or session time"}
    (OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
