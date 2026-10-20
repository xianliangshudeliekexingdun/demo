extends RefCounted
const IDS = ["fireball", "meteor", "frost", "rejuvenation", "lamp"]
const TITLES = {"fireball":"火球术", "meteor":"陨火术", "frost":"冰霜新星", "rejuvenation":"回春术", "lamp":"召唤灯灵"}
const COLORS = {"fireball":"ffc175", "meteor":"ff9963", "frost":"94dbff", "rejuvenation":"a4dfaa", "lamp":"d5b7ff"}
const ROLES = {"fireball":"常规输出 · 预判落点", "meteor":"群体爆发 · 长吟唱", "frost":"自身控场 · 追击减速", "rejuvenation":"自身治疗 · 持续恢复", "lamp":"持续辅助 · 跟随攻击"}
const FUTURE_UPGRADES = ["quick_chant","efficient_cast","wide_blast","embers","echo","molten","meteor_quick","meteor_wide","meteor_efficient","meteor_fragments","meteor_burn","meteor_storm","frost_wide","frost_duration","frost_efficient","frost_freeze","frost_exposure","frost_field","heal_amount","heal_quick","heal_efficient","heal_immediate","heal_shield","heal_spring","lamp_duration","lamp_damage","lamp_range","lamp_sync","lamp_guard","lamp_twin"]
const UPGRADE_NAMES=["熟练吟唱","节能施法","扩散火焰","余烬之地","二重爆破","熔核火球","稳定吟唱","广域冲击","法力凝聚","碎星迸裂","炽热地表","天火降临","扩散寒气","寒意延续","节能凝霜","深度冻结","寒霜侵蚀","永冬领域","充沛生命","轻声祈愿","循环生息","即刻复苏","生命余裕","不息之春","长明灯芯","明亮火光","灵性追随","同步施法","守护微光","双生灯灵"]
const TIERS=["common","common","common","rare","rare","legendary"]
const TIER_NAMES={"common":"普通","rare":"稀有","legendary":"传说"}
static func upgrade_spell(id: String) -> String: return IDS[FUTURE_UPGRADES.find(id)/6] if id in FUTURE_UPGRADES else ""
static func upgrade_name(id: String) -> String: return UPGRADE_NAMES[FUTURE_UPGRADES.find(id)] if id in FUTURE_UPGRADES else ""
static func tier(id: String) -> String: return TIERS[FUTURE_UPGRADES.find(id)%6]
static func valid_upgrades(ids: Array) -> bool:
	var seen=[]
	for id in ids:
		if id not in FUTURE_UPGRADES or id in seen: return false
		seen.append(id)
	return true
static func valid_loadout(slots: Array) -> bool:
	if slots.size()!=5: return false
	var seen=[]
	for id in slots:
		if id not in IDS or id in seen: return false
		seen.append(id)
	return true
static func targeted(id: String) -> bool: return id in ["fireball","meteor"]
