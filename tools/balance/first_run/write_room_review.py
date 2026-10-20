"""Historical reproduction: write migrated drafts only, never current themes.

Render original authored room tables and pacing figures from verified inputs.
"""
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from design_documents import resolve_design_document

ROOT=Path(__file__).resolve().parents[3]
SOURCE=ROOT/"data/balance_candidates/normal_rooms_v1.json"
REPORT=ROOT/"build/qa/normal-rooms-20261017/selected/results.json"
DOC=resolve_design_document(ROOT/"docs/游戏设计/09-普通房配置与难度节奏.md")
FIGURE=REPORT.parent/"pacing.png"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def table(headers, rows):
    return "\n".join(["| "+" | ".join(headers)+" |","|"+"|".join("---" for _ in headers)+"|"]+["| "+" | ".join(map(str,r))+" |" for r in rows])


result=load(REPORT)
config=load(SOURCE)
assert result["parameters"]==config
for key,entry in result["input_hashes"].items():
    assert hashlib.sha256(Path(entry["path"]).read_bytes()).hexdigest()==entry["sha256"],f"Stale {key}"
base=load(SOURCE.parent/config["base_parameters"])
economy=load(SOURCE.parent/config["economy_parameters"])
budgets={r["room"]:r for r in result["room_budgets"]}
room_map={r["room"]:r for r in config["rooms"]}
special={r["room"]:r for r in base["elites"]+base["bosses"]}
spawn=config["spawn"]
names={"M01":"史","M02":"花","M03":"冲","M04":"术"}
case_names={"burst":"连发爆破／一级生机","spirit":"精灵协同／一级生机","area":"阵地覆盖／一级生机","weak_no_shop":"辅助偏多、低命中／不购买／无宝石","optimized_gem3":"集中输出、高命中／三级强攻"}


def pack_text(pack):
    return "＋".join(f"{names[k]}{n}" for k,n in pack.items())


def draw():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.font_manager import FontProperties
    font=FontProperties(fname=str(ROOT/"assets/fonts/NotoSansSC.ttf"))
    plt.rcParams["font.family"]=font.get_name()
    from matplotlib import font_manager
    font_manager.fontManager.addfont(str(ROOT/"assets/fonts/NotoSansSC.ttf"))
    plt.rcParams["axes.unicode_minus"]=False
    fig,axes=plt.subplots(2,1,figsize=(15,6.8),sharex=True,gridspec_kw={"height_ratios":[1.2,1]})
    for ax in axes:
        for low,high,color in ((.5,15.5,"#eef5fc"),(15.5,45.5,"#f5f2fb"),(45.5,60.5,"#fff2e6")):
            ax.axvspan(low,high,color=color,zorder=0)
        ax.grid(axis="y",color="#d9dee5",linewidth=.6)
        ax.spines[["top","right"]].set_visible(False)
        ax.set_xlim(.5,60.5)
        for boss in base["bosses"]:
            ax.axvline(boss["room"],color="#b93d3d",alpha=.55,linestyle=":",linewidth=1)
        ax.axvline(31,color="#697382",alpha=.45,linestyle="--",linewidth=.7)
    xs=list(range(1,61))
    ys=[budgets[r]["total"] if r in budgets else float("nan") for r in xs]
    peaks=[budgets[r]["peak_upper_bound"] if r in budgets else float("nan") for r in xs]
    axes[0].plot(xs,ys,"o-",color="#24588c",markersize=3.8,linewidth=1.3,label="普通房总敌人数")
    axes[0].plot(xs,peaks,"s--",color="#c66d17",markersize=3,linewidth=1,label="分批规则下在场数上界")
    axes[0].scatter([e["room"] for e in base["elites"]],[13]*len(base["elites"]),marker="^",s=40,color="#7952a1",label="精英节点")
    axes[0].scatter([b["room"] for b in base["bosses"]],[13]*len(base["bosses"]),marker="D",s=35,color="#b93d3d",label="首领节点")
    axes[0].scatter([r+.45 for r in base["recovery"]["shop_after"]],[.35]*len(base["recovery"]["shop_after"]),marker="s",s=32,color="#27846b",label="商店（清房后）")
    axes[0].set_ylim(0,14.3)
    axes[0].set_yticks([0,2,4,6,8,10,12])
    axes[0].set_ylabel("只")
    axes[0].set_title("60房节奏：普通房数量与预算；特殊房只标节点",loc="left",fontsize=16,pad=14)
    axes[0].legend(loc="upper left",ncol=3,fontsize=8,frameon=False)
    axes[1].plot(xs,[budgets[r]["total_health"]/1000 if r in budgets else float("nan") for r in xs],"o-",color="#24588c",markersize=3.7,linewidth=1.3,label="普通房敌人生命合计")
    axes[1].set_ylim(0,11.5)
    axes[1].set_ylabel("千生命")
    axes[1].set_xlabel("战斗房号（5个商店另插入，不占房号）")
    axes[1].set_xticks([1,5,10,15,20,25,30,35,40,45,50,55,60])
    axes[1].annotate("第31房：按已定数值换生命档\n先降组合复杂度",xy=(31,budgets[31]["total_health"]/1000),xytext=(23,5.5),arrowprops={"arrowstyle":"->","color":"#697382"},fontsize=9,color="#424c58")
    axes[1].annotate("56房普通峰值：12只 / 在场≤8\n58—59房减压后进最终首领",xy=(56,budgets[56]["total_health"]/1000),xytext=(38,9.6),arrowprops={"arrowstyle":"->","color":"#697382"},fontsize=9,color="#424c58")
    fig.text(.07,.015,"预算是数量与生命代理；出生位置、攻击叠加及实际走位尚未验证。图中不含精英、首领或其召唤物生命。",fontsize=9,color="#59636e")
    fig.tight_layout(rect=[0,.04,1,1])
    fig.savefig(FIGURE,dpi=140,facecolor="white")
    plt.close(fig)


draw()
out=[]
def write(value=""):
    out.append(value)


write("# 五十个普通房与六十房难度节奏 · 数量与节奏制作基线")
write()
write(f"日期：2026-10-17。用户已同意本页普通房数量、组合与批次节奏先按此版推进；15／45／60首领、7精英、5商店及既定怪物／数值／奖励不变。唯一普通房调参源为[data房间表](../../data/balance_candidates/normal_rooms_v1.json)，版本 `{config['version']}`，原字节与candidate命名保留，当前游戏未加载。地图现按[03第4节](03-首关流程与场景.md#4-横屏地图需求)的12×14米配置推进：具体掩体、地刺、候选位和整批重校由新空间源接管；本页旧空间字段保留为历史候选，旧输出模型不含实体掩体和地刺。")
write()
write("## 1. 递进方法与阶段范围")
write()
write("普通房按‘单独教学→组合发展→密度高潮→减压’推进。1—3房只练移动与自动攻击；4房花妖、16房冲锋兽、25房术士分别单独出现。之后增加组合与分批总量，首领前回落，31／46房进入已确认生命档时先用简单组合承接。难度通过同时在场压力和不同角色的配合递进，清场时长允许随构筑增强缩短。")
write()
ranges=[(1,3,"仅史莱姆"),(4,14,"史莱姆＋花妖；4房单独教学"),(16,24,"加入冲锋兽；16房单独教学"),(25,29,"加入术士；25房单独教学"),(31,44,"围绕已见四类重组"),(46,50,"后期生命档，先复习组合"),(52,56,"提高增援总量，56普通峰值"),(58,59,"最终首领前连续回落")]
stage_rows=[]
for low,high,note in ranges:
    relevant=[r for n,r in budgets.items() if low<=n<=high]
    totals=[r["total"] for r in relevant if r["room"] not in result["scenarios"]["tutorial_rooms"]]
    stage_rows.append((f"{low}—{high}",f"{min(totals)}—{max(totals)}" if min(totals)!=max(totals) else str(totals[0]),max(r["alive_cap"] for r in relevant),note))
write(table(["普通房区间","全房总数（教学房另列）","普通房在场硬上限","设计重点"],stage_rows))
write()
write(f"本表区间内剔除精英和首领。4／16／25房各单独1只新怪；每普通房至多{spawn['max_normal_chargers_per_room']}只冲锋兽、{spawn['max_normal_casters_per_room']}只术士，最多{spawn['max_normal_shooters_alive']}只花妖。当前50个普通房共{sum(r['total'] for r in budgets.values())}只，精英、首领和伴随／召唤物不计入此数。")
write()
write("![普通房数量与生命预算节奏](../../build/qa/normal-rooms-20261017/selected/pacing.png)")
write()
write("图中上界不是要求玩家必须同时面对该数量；清得快时实际并发更低。生命总量是预算代理，不等于实际难度或战斗时间；本图不把首领生命混进普通房曲线。")
write()
write("## 2. 出怪与房间结算")
write()
write(f"- 每房一至两批。第一批先展示{spawn['preview_seconds']:g}秒出生预警，再激活；不是无提示在脚边生效。")
write(f"- 还有下一批时，在场敌人≤{spawn['next_batch_when_alive_at_most']}且余量容得下整批，才开始下一批{spawn['preview_seconds']:g}秒预警；随后激活。不按固定倒计时不断堆怪。")
write("- 一个批次预警期间不重复申请同一批；所有配置批次都已经出完且场上清空，才算整房胜利。即使暂时没有活怪但还有预警／待出批次，仍在同一场战斗。")
write("- 两批之间不补血／盾、不发奖励、不重置法术CD、序列次数、源泉计时、精灵或区域。暖焰护持在房内缺盾时仍可正常施放，包括等待下一批的间隙；完整清房才执行原补盾、法术和神器奖励。")
write(f"- 普通房中，冲锋兽和术士的重型预警起手至少相隔{spawn['minimum_heavy_warning_start_gap']:g}秒；不缩短怪物各自已定的预警或攻击周期。此错峰是待实现规则，本轮输出模型不模拟敌人AI。")
write()
write("## 3. 出生区域与场景复用")
write()
write(f"历史空间候选（实际配置已由03替代）：每种布局先预留{spawn['edge_anchor_count']}个可达边缘点，单批从至多{spawn['at_most_active_edge_sides']}个相邻侧区出生，保留对侧走位空间。候选点距玩家至少{spawn['safe_player_distance']:g}米、同批点间至少{spawn['minimum_spawn_spacing']:g}米；点位都须在可走连通区域，射手不可藏在不可接近的墙后。")
write()
write("预警出现后点位固定。激活前玩家走得过近就延后／换安全点，并在新位置重新给足出生预警；不能把预警追着玩家移动或直接换位置生效。无安全位置时先排队，不能把待出敌人丢掉后误判清房。本页原计算只含数量和节奏；实际坐标、墙体与绕行宽度及新隔离空间核对见03，Godot白盒仍待制作验证。")
write()
write("初稿列出开阔、错列柱、双短墙与宽通道三类布局意图，未制作具体地图。用户随后要求先对齐需求，已确认地刺是多数战斗房的常规威胁，也可与精英／首领组合；此前不加地刺的助手建议作废。以下旧布局名称只保留为组合表标签，实际相同ID对应03最新三模板；空间规则以新源为准，不代表Godot场景或独立资产已获批准。")
write()
write("## 4. 逐房表")
write()
write("史＝M01跃袭史莱姆，花＝M02孢弹花妖，冲＝M03岩甲冲锋兽，术＝M04刻印术士。A／B为同一房的批次，不增加房号或奖励次数。‘在场≤’是该配置按剩余两只触发得到的数量上界，仍受阶段硬上限限制。精英／首领沿用04，不套用普通房的数量上限。")
write()
for low,high in ((1,15),(16,30),(31,45),(46,60)):
    write(f"### {low}—{high}房")
    write()
    data=[]
    for room in range(low,high+1):
        if room in room_map:
            row,budget=room_map[room],budgets[room]
            packs="；".join(f"{'AB'[i]}：{pack_text(pack)}" for i,pack in enumerate(row["packs"]))
            note=row["beat"]+("；之后商店" if room in base["recovery"]["shop_after"] else "")
            data.append((room,packs,budget["total"],budget["peak_upper_bound"],config["layouts"][row["layout"]],note))
        else:
            entry=special[room]
            companions="＋"+"、".join(base["normal_types"][k]["name"] for k in entry.get("adds",[])) if entry.get("adds") else ""
            if room==60 and companions:
                companions="；二阶段有限召唤"+companions[1:]
            data.append((room,entry["name"]+companions,"按04","按04","按04","最终结算" if room==60 else "首领" if room in [b["room"] for b in base["bosses"]] else "精英"))
    write(table(["房","组合与批次","全房总数","在场≤","布局","用途／节点"],data))
    write()
write("## 5. 峰值与回落的具体含义")
write()
write("- 8房教会分批，9房再把已知两类同时放出；11房双射手练习后才进入12房花妖精英。")
write("- 16／25房分别孤立冲锋和落印；28房第一次把四类放进同一房，但分批到来；20／29房为相应精英前回落。")
write("- 31房怪物生命已按原表上升，用5只基础组合承接；37与41—42形成中期普通房峰值，38、40及43—44形成局部缓和。")
write("- 46房同样先复习基础组合；52—56总量9→9→10→11→12，分批与在场上限共同限制压力。54后最后补给不改原位置。")
write("- 56普通峰值后进入57精英，再用58／59的7→6只降压；这两房不额外回血，生命消耗与54后最后补给的意义保留。")
write()
write("## 6. 输出／增援模型检查")
write()
write(f"隔离模型 `{result['model_version']}` 复用既有神器战斗模型，新增有限批次调度；没有改基础或神器的伤害公式。{len(result['checks'])}项检查通过，包括60房覆盖、引入顺序、数量／角色上限、首领前减压、两批未出完不得结算、无批间补盾、冷却保留、精灵持续、待出批期间暖焰护持，以及零预警单批与原模型逐字段一致。")
write()
write(f"5组输入×50房×{result['scenarios']['trials']}次，共{sum(r['trials'] for r in result['rows']):,}次单房输出模拟，另{len(result['sweeps'])}组增援参数对照、共{sum(r['trials'] for r in result['sweeps']):,}次；基础种子{result['scenarios']['seed']}。每个试验先按07有限池及购买策略取得实际库存，只使用进入该房之前的神器，不能提前拿本房奖励。普通三路线带一级生机，低命中不购买且无宝石，集中输出带三级强攻；法术仍用既有固定路径，不把它说成已经联合模拟随机触媒。")
write()
time_rows=[]
for case in result["scenarios"]["cases"]:
    bounds=[]
    for stage in economy["stages"]:
        times=[r["time"]["median"] for r in result["rows"] if r["case"]==case and stage["from"]<=r["room"]<=stage["to"] and r["status"]!="tutorial"]
        bounds.append(f"{min(times):.1f}—{max(times):.1f}")
    time_rows.append((case_names[case],*bounds))
write(table(["条件输入","前期各房中位秒范围","中期各房中位秒范围","后期各房中位秒范围"],time_rows))
write()
below=sum(r["status"]=="below" for r in result["rows"])
above=sum(r["status"]=="above" for r in result["rows"])
write(f"教学单怪房从上表剔除。{sum(r['timeouts'] for r in result['rows'])}次超出90秒；同屏数量都在上限内。预设速度观察带中，{below}组中位低于下沿、{above}组高于上沿，未宣称全部时长目标通过。强构筑普通房偏快是实际观察项，不能据此跳过出招可读性验证；本轮未用全面加血、固定等待或临时加伤害掩盖。")
write()
write("预警0.5／1.2秒、剩余0／3只触发与本版0.8秒／2只分别对照；硬上限会限制提前增援，所以触发阈值和实际并发不能混为一谈。候选主要让清怪慢时延迟下一批，保持快速构筑可以更快推进。具体差异与每房P10／P90、样本库存、实际峰值记录在结果和CSV。")
write()
write("## 7. 未验收范围与最小实测")
write()
write("本页原模型没有位置、寻路、怪物攻击AI或碰撞。旧相邻边候选由03的左右边缘实际配置替代；新隔离空间与错峰核对也不能证明真实攻击全部可躲。已有火区和追加伤害沿旧模型锁定目标组，新出生敌人不自动加入旧组，分批对区域构筑的估计偏保守；最多两个邻居只是密度假设，不是实际AOE上限。")
write()
write("单房从技能就绪开始，未决定跨房CD的运行规则；同房批间CD和持续效果确实保留。没有整局承伤、操作耗时、休息、开门或随机触媒联合模拟，不能把本表耗时相加宣称真实局时长或通关率。旧scenarios.json里的1／10／20等房间敌人数只是历史测试夹具，新的实际普通房配置唯一归本房间表。")
write()
write("接入后先测1／4／8／16／25／28／31／46／56／59：看单怪教学是否来得及读、待出批时会不会误清场、满场火效下出生预警是否看得见、慢构筑会不会被增援压死、56高峰是否仍有普通移动可达的安全路线，再确认其他布局。数量、技能／怪物规则、画面与体验分别验收。当前未创建Godot关卡、运行游戏、执行Godot规则／画面测试或导出。")
write()
write("[数据与工具复现](../../tools/balance/first_run/README.md)、[本版结果及输入哈希](../../build/qa/normal-rooms-20261017/selected/results.json)、[逐房耗时CSV](../../build/qa/normal-rooms-20261017/selected/rooms.csv)。")
write()
DOC.write_text("\n".join(out),encoding="utf-8")
print(f"generated {DOC} and {FIGURE}")
