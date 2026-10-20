"""Historical reproduction: write migrated drafts only, never current themes.

Generate metric plans and original sections 4.4--4.8 from matched spatial inputs.
"""
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from design_documents import resolve_design_document

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "data/balance_candidates/room_spatial_v1.json"
OUT = ROOT / "build/qa/room-spatial-20261017/selected"
DOC = resolve_design_document(ROOT / "docs/游戏设计/03-首关流程与场景.md")
START, END = "<!-- spatial-review:start -->", "<!-- spatial-review:end -->"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def plan(config, metrics):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.font_manager import FontProperties
    from matplotlib.patches import Rectangle, Circle
    font = FontProperties(fname=str(ROOT / "assets/fonts/NotoSansSC.ttf"))
    plt.rcParams.update({"font.family": font.get_name(), "axes.unicode_minus": False})
    # Register the existing licensed project font, no font install or copy.
    from matplotlib import font_manager
    font_manager.fontManager.addfont(str(ROOT / "assets/fonts/NotoSansSC.ttf"))
    width, depth = metrics["floor"]["width"], metrics["floor"]["depth"]
    entry_depth, combat_depth, portal_depth = [z["depth"] for z in metrics["zones_bottom_to_top"]]
    fig, axes = plt.subplots(1, len(config["layouts"]), figsize=(15.6, 8.7), facecolor="#f8fafc")
    fig.suptitle(f"{width:g}×{depth:g}米 · 三种复用布局", fontsize=21, y=.98, color="#172c3c")
    for ax, (layout_id, layout) in zip(axes, config["layouts"].items()):
        ax.set_aspect("equal")
        ax.set_xlim(-width / 2 - .15, width / 2 + .15)
        ax.set_ylim(-depth / 2 - .15, depth / 2 + .15)
        for z, height, color in [(-depth / 2, entry_depth, "#e7eee6"),
                                  (-combat_depth / 2, combat_depth, "#eef2f5"),
                                  (depth / 2 - portal_depth, portal_depth, "#e2eaf7")]:
            ax.add_patch(Rectangle((-width / 2, z), width, height, facecolor=color, zorder=0))
        central = config["layout_rules"]["central_clear_width"]
        ax.add_patch(Rectangle((-central / 2, -combat_depth / 2), central, combat_depth,
                               fill=False, edgecolor="#90a9b1", linestyle="--", linewidth=1.2, zorder=2))
        ax.text(0, -combat_depth / 2 + .3, f"中轴净宽{central:g}米", ha="center", va="bottom", fontsize=10, color="#52727a")
        for b in layout["blocks"]:
            x, z = b["center"]
            w, d = b["size"]
            ax.add_patch(Rectangle((x - w / 2, z - d / 2), w, d, facecolor="#52697a", edgecolor="#263f50", zorder=4))
        size = config["spikes"]["plate_size"]
        for key, (x, z) in config["spikes"]["plates"].items():
            group = "A" if key in ("SW", "NE") else "B"
            color = "#d9852f" if group == "A" else "#a761a4"
            ax.add_patch(Rectangle((x - size / 2, z - size / 2), size, size,
                                   facecolor=color, edgecolor=color, alpha=.35, zorder=3))
            ax.text(x, z, group, ha="center", va="center", fontsize=12, color="#633d31", zorder=5)
        spawn = config["spawn"]
        for side, x in enumerate(spawn["side_x"]):
            for i, z in enumerate(spawn["anchor_z"]):
                for offset in spawn["slot_offsets_z"]:
                    ax.plot(x, z + offset, "o", markersize=5, markerfacecolor="#26798c", markeredgecolor="white", zorder=5)
                ax.text(x - .48 if x < 0 else x + .48, z, str(side * len(spawn["anchor_z"]) + i + 1),
                        ha="center", va="center", fontsize=9, color="#26798c")
        px, pz = spawn["entry_player_center"]
        ax.add_patch(Circle((px, pz), .3, facecolor="#53805b", edgecolor="white", zorder=5))
        ax.text(px + .65, pz, "玩家入口", va="center", fontsize=11, color="#34523b")
        portal_z = depth / 2 - portal_depth / 2
        ax.add_patch(Circle((0, portal_z), .48, fill=False, edgecolor="#4870a1", linewidth=2))
        ax.text(.8, portal_z, "清场后传送", va="center", fontsize=11, color="#365b89")
        mx, mz = spawn["major_enemy_center"]
        ax.text(mx, mz, "+", ha="center", va="center", fontsize=21, color="#87959f")
        ax.text(mx, mz + .55, "精英／首领起点", ha="center", fontsize=9, color="#77848d")
        ax.add_patch(Rectangle((-width / 2, -depth / 2), width, depth, fill=False,
                               edgecolor="#344957", linewidth=2, zorder=7))
        ax.set_title(layout["name"], fontsize=16, pad=12, color="#243d4d")
        ax.set_xticks([-6, -3, 0, 3, 6])
        ax.set_yticks([-7, -5, 0, 5, 7])
        ax.set_xlabel("x（米）", fontsize=10)
        ax.grid(color="#cbd3da", alpha=.48, linewidth=.45)
        ax.tick_params(labelsize=9)
        for spine in ax.spines.values():
            spine.set_visible(False)
    axes[0].set_ylabel("z（米，向上为推进方向）", fontsize=10)
    fig.text(.5, .073, "深色＝实体掩体　蓝点＝8个边缘出生区的16个候选位　A／B＝交替地刺组", ha="center", fontsize=12, color="#344b59")
    fig.text(.5, .036, "按米制坐标绘制；地刺按逐房配置启用，图中四块不代表同时伸出。此图为配置平面图。", ha="center", fontsize=11, color="#607580")
    fig.subplots_adjust(top=.87, bottom=.16, left=.055, right=.985, wspace=.16)
    path = OUT / "layout_plans.png"
    fig.savefig(path, dpi=140, facecolor=fig.get_facecolor())
    plt.close(fig)
    return path


def main():
    config, result = load(SOURCE), load(OUT / "results.json")
    assert load(OUT / "parameters_used.json") == config, "Stale spatial parameter snapshot"
    for relative, expected in result["input_sha256"].items():
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == expected, f"Stale input: {relative}"
    metrics = load(SOURCE.parent / config["metrics_parameters"])
    ordinary = load(SOURCE.parent / config["ordinary_room_parameters"])
    base = load(SOURCE.parent / config["base_parameters"])
    s, p, r = config["spikes"], config["spawn"], config["layout_rules"]
    plan(config, metrics)
    text = [START, "### 4.4 12×14米布局配置", "",
            "用户已授权按12×14米确定本节布局、地刺与出生规则；以下是助手在该授权内收敛的首版制作配置，尚未接入Godot。唯一调参源为[room_spatial_v1.json](../../data/balance_candidates/room_spatial_v1.json)，本节与图由[生成器](../../tools/balance/first_run/write_spatial_review.py)生成快照，不能把表格作为另一处编辑源。", "",
            "坐标以房间中心为原点，x向右，z朝画面上方传送区；地面x∈[-6,6]、z∈[-7,7]，中部战斗区z∈[-5,5]。障碍只放中部，三个布局共用入口、传送和出生规则。", "",
            "![三种地图的米制平面图](../../build/qa/room-spatial-20261017/selected/layout_plans.png)", "",
            "| 布局 | 实体掩体（中心x,z；宽×深，米） | 走位用途 |", "|---|---|---|"]
    uses = {"open": "两侧各一块，中部大面积绕行；教学、缓和和首领优先",
            "pillars": "四根独立柱，两侧和柱间可穿行，用于追击／远程组合",
            "cover": "左右错列短墙，提供换侧掩护；保留中轴与两条外侧通路"}
    for key, layout in config["layouts"].items():
        blocks = "；".join(f"({b['center'][0]:g},{b['center'][1]:g}) {b['size'][0]:g}×{b['size'][1]:g}" for b in layout["blocks"])
        text.append(f"| {layout['name']} | {blocks} | {uses[key]} |")
    text += ["", f"三个布局中轴净宽{r['central_clear_width']:g}米；掩体至外墙、掩体之间最近实体间隔至少{r['minimum_solid_wall_gap']:g}米。沿用玩家半径{base['player']['radius']:g}米、移速{base['player']['move_speed']:g}米/秒。掩体挡双方移动与直射／直线束，落点与范围伤害可越掩体；不新增可破坏墙、门锁、窄走廊或第四种布局。入口／上方传送区可被敌人追入，仍不是常驻安全区。", "",
             "### 4.5 地刺位置、周期与伤害", "",
             "只摆放当前配置使用的底座；无刺房不放，教学放一块，稀疏放A两块，标准放A／B四块。已摆底座始终可见，收回时可行走；伸出时仍可穿行但会尝试伤害玩家，不形成新的实体障碍。地刺不伤害怪物。", "",
             "| 项目 | 首版配置 |", "|---|---|"]
    plates = "；".join(f"{k}({v[0]:g},{v[1]:g})" for k, v in s["plates"].items())
    text += [f"| 单块与中心坐标 | {s['plate_size']:g}×{s['plate_size']:g}米；{plates} |",
             "| 四种逐房配置 | 无刺；单块教学SW；稀疏组SW＋NE；标准组A=SW＋NE、B=NW＋SE交替 |",
             f"| 时序 | 进房{s['first_warning_after_room_start']:g}秒后首次预警；预警{s['warning']:g}秒→伸出{s['active']:g}秒→收回并休息{s['rest_after_retract']:g}秒 |",
             f"| 标准周期 | 无重型攻击延迟时每{s['warning'] + s['active'] + s['rest_after_retract']:g}秒触发一组，每块在标准配置中每{2 * (s['warning'] + s['active'] + s['rest_after_retract']):g}秒伸出一次；每次最多两块 |",
             "| 单次伤害 | " + "／".join(str(s["damage_by_economy_stage"][stage]) for stage in ("early", "middle", "late")) + "（1—15／16—45／46—60房），先盾后血，不暴击、减速或击退 |",
             f"| 命中限制 | 每组每轮最多一次接触伤害尝试；两块重叠、持续站刺或离开再进都不追加。同享{base['player']['hurt_invulnerability']:g}秒受击保护，保护期首次接触也消耗本轮尝试，不延迟补伤 |",
             "| 关停 | 清场成立、玩家死亡或最终首领核心死亡即取消预警／伤害；不为等第一次地刺而延后清场 |", "",
             f"重型攻击与地刺共用一个主威胁窗口：同一时刻只放行一组重型前摇／主体伤害，已开始的先完成，窗口间至少隔{ordinary['spawn']['minimum_heavy_warning_start_gap']:g}秒，已到期的地刺优先；地刺预警至收回期间不新开重型攻击，下一重型同样等收回后至少该时长。这是首版空间配置在09仅限制起手间隔之上的调度收敛，不更改原攻击伤害／自身冷却。重型包括冲锋兽、术士的大范围落点、精英及首领的大范围／冲锋／直线招式；普攻小弹可继续，既有弹体不抹除，持续弹体不占整个重型窗口。地刺只延后、不补发追赶，休息从实际收回重新计算。实际主体伤害结束点需在接入时绑定，隔离时序夹具不是首领招式时长。", "",
             "预警采用地面边框／填充变化，伸出采用突起形态；出生预警用独立圆形符号，不能只靠红色区分。首版同一组同步亮、同步收，不做每块独立随机周期。", "",
             "### 4.6 怪物出生点与整批预警", "",
             f"玩家固定中心({p['entry_player_center'][0]:g},{p['entry_player_center'][1]:g})。精英／首领首次中心({p['major_enemy_center'][0]:g},{p['major_enemy_center'][1]:g})，开场预警{p['major_initial_preview']:g}秒；其原定初始伴随怪仍在边缘，与主怪同时预警，不新增伴随数量。普通房首批与增援使用既有{ordinary['spawn']['preview_seconds']:g}秒预警。", "",
             "| 出生项 | 首版配置 |", "|---|---|"]
    text += [f"| 区域与候选位 | 左右各4区，共8区；x={'／'.join(f'{v:g}' for v in p['side_x'])}，区中心z={'／'.join(f'{v:g}' for v in p['anchor_z'])}；每区z偏移±{abs(p['slot_offsets_z'][0]):g}，共16候选位 |",
             f"| 距离与空位 | 出生中心距玩家至少{ordinary['spawn']['safe_player_distance']:g}米；同批点间至少{p['minimum_slot_spacing']:g}米；掩体／墙额外净空{p['static_clearance']:g}米，已有敌人额外间隔{p['existing_enemy_clearance']:g}米 |",
             f"| 体积预算 | 普通候选位预留半径{p['normal_footprint_radius']:g}米，精英首领中心预留半径{p['major_footprint_radius']:g}米；这是空间预算，未改怪物属性。接入碰撞形体必须在预算内，超出时重核点位／通路 |",
             f"| 出现后的起手 | 可立刻受到伤害；{p['attack_lock_after_appearance']:g}秒内不开始攻击，之后仍走各自已有前摇；沿用无接触伤害规则 |",
             f"| 动态增援 | 继续沿用09：最多两批、剩余≤{ordinary['spawn']['next_batch_when_alive_at_most']}只且整批可容纳才开始预警；前期／中期／后期在场上限5／6／8。开始预警与正式出现时均检查 |",
             "| 选位 | 带种子、不重复抽取；左右数量尽量平衡，不强制四面包围；必须可达、无实体／敌人体积重叠、不压预警或伸出的地刺 |",
             "| 预警后被玩家靠近 | 撤销整批预警，另选完整安全批次并重新给足预警；标记不追着玩家移动、不瞬间换位出现。若无完整落点则整批排队，不删怪、不偷缩批次 |",
             "| 批次与清场 | 尚有未出批次／排队增援不能算清场；批间不回满护盾、不清冷却或持续效果。已死亡的最终首领核心例外，立即终止召唤与本房 |", "",
             "本次实际坐标替代09旧的‘至多两相邻边’空间候选：采用左右边缘，不强求相邻边。旧normal_rooms_v1.json字节、285只普通敌人、各房组合／批次与触发条件保持不变，不能根据候选位增怪。最终首领仍按原第二阶段规则：旧组清空且18秒已到才出最多2只M01／M02，使用本节边缘位；召唤预警服从实际剩余上限与安全检查，不改变其18秒规则。", "",
             "### 4.7 六十房布局与地刺分布", "",
             f"共{result['room_counts']['spikes']}／60战斗房含地刺，分阶段为{result['room_counts']['spikes_by_economy_stage']['early']}／15、{result['room_counts']['spikes_by_economy_stage']['middle']}／30、{result['room_counts']['spikes_by_economy_stage']['late']}／15；七精英和三首领均可配刺。1—4不放刺，第5房单块教学；16／25新敌教学、31／46数值换档、首领前两房留出无刺缓和。商店不占战斗房且不放刺。", "",
             "| 房号 | 类型 | 布局 | 地刺 |", "|---|---|---|---|"]
    ordinary_ids = {row["room"] for row in ordinary["rooms"]}
    bosses = {row["room"] for row in base["bosses"]}
    names = {"off": "无", "teach": "单块教学", "sparse": "稀疏A", "standard": "标准A／B交替"}
    for row in config["rooms"]:
        kind = "普通" if row["room"] in ordinary_ids else "首领" if row["room"] in bosses else "精英"
        text.append(f"| {row['room']} | {kind} | {config['layouts'][row['layout']]['name']} | {names[row['spikes']]} |")
    minimum = min(min(g["escape_margin_seconds"].values()) for g in result["geometry"])
    text += ["", "### 4.8 空间、时序与承伤检查", "",
             f"[运行器](../../tools/balance/first_run/run_spatial.py)读取同一源，结果归[执行记录](../../build/qa/room-spatial-20261017/selected/results.json)，保留输入哈希、实际参数／情境及CSV。模型按{load(OUT / 'scenarios_used.json')['grid_step']:g}米网格、角色半径＋0.05米余量膨胀矩形，只允许四向路径；角部使用方形膨胀，比真实圆形更保守。", "",
             f"完成3布局×8种地刺掩码（含实际不会同时发生的四块全开压力边界），入口至传送与剩余可行走网格均连通。另检查0.5米普通怪空间预算的静态连通与1米首领中心净空。1米地刺最不利网格脱离路程1米；慢反应夹具用0.7秒反应＋实际移速60%（3米/秒），1.2秒预警余量约{minimum:.3f}秒，达到预设0.15秒下限。24组尺寸／预警对照中，0.8／1.0秒预警或1.5米大板在1.2秒预警时达不到该慢反应余量；因此首版保留小板与1.2秒预警。", "",
             f"出生检查覆盖50普通房首批×16次及3布局增援×200次，共{result['spawn_trials']}次带种子夹具；另每布局250个玩家点位检查空场候选容量。三布局空场最少可用位为" + "／".join(str(v["min_eligible_slots_no_existing"]) for v in result["spawn"]) + "；增援排队次数为" + "／".join(str(v["reinforcement_deferred"]) for v in result["spawn"]) + "。这只是抽样，动态不满足时仍必须排队，不能承诺所有位置都立即刷出。整批容量、剩余数量、玩家占位重校、受击保护、持续／重复接触、清场／死亡终止和重型错峰均有独立边界检查。", "",
             "承伤以相互错开、实际生效的攻击作短窗口账本：两次史莱姆攻击＋一次地刺，基础100盾时前期0、中期前半0、中期后半8、后期26生命损失；后期持U02（125盾）为1生命，再装三级MG02（135盾）为0。该对照不假设必出神器，不含F10回盾或酒馆恢复，更不是60房通关预测。地刺伤害不额外提高已同意怪物攻击。", "",
             "静态连通不含活怪堵路、弹道、落点叠加、真实寻路、自动选敌绕掩体、碰撞扫掠或屏幕可读性；重型攻击时序夹具不含持续普通弹体。上述规则与数值作为白盒实施依据，仍需在实际单房闭环分别检查规则、Godot像素和用户体验。本轮没有修改或启动运行原型。", END]
    section = "\n".join(text) + "\n\n"
    doc = DOC.read_text(encoding="utf-8")
    if START in doc:
        doc = doc[:doc.index(START)] + section + doc[doc.index(END) + len(END):].lstrip("\n")
    else:
        doc = doc.replace("## 5. 时间与交付边界", section + "## 5. 时间与交付边界", 1)
    DOC.write_text(doc, encoding="utf-8")
    print(json.dumps({"document": str(DOC), "figure": str(OUT / 'layout_plans.png'),
                      "checks_passed": result["checks_passed"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
