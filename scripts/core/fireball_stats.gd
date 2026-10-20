extends RefCounted
const IDS = ["quick_chant","efficient_cast","wide_blast","embers","echo","molten"]
const NAMES = ["熟练吟唱","节能施法","扩散火焰","余烬之地","二重爆破","熔核火球"]
const TIERS = ["common","common","common","rare","rare","legendary"]
static func compute(c: Dictionary, owned: Array, enhanced: bool = false) -> Dictionary:
	var rate = c["upgrade.quick_chant.multiplier"] if "quick_chant" in owned else 1.0
	var cost = maxf(0,c["fireball.mana_cost"]-(c["upgrade.efficient_cast.cost_reduction"] if "efficient_cast" in owned else 0.0))
	var radius = c["fireball.explosion_radius"]+(c["upgrade.wide_blast.radius_bonus"] if "wide_blast" in owned else 0.0)
	var damage = c["fireball.damage"]
	if enhanced and "molten" in owned:
		cost += c["upgrade.molten.extra_cost"]
		radius *= c["upgrade.molten.radius_multiplier"]
		damage *= c["upgrade.molten.damage_multiplier"]
	return {"chant":c["fireball.chant_time"]*rate,"extra_chant":c["upgrade.molten.extra_chant"]*rate,"cost":cost,"radius":radius,"damage":damage,"enhanced":enhanced and "molten" in owned,"embers":"embers" in owned,"echo":"echo" in owned}

static func description(id: String,c: Dictionary,owned: Array) -> String:
	var before = compute(c,owned)
	var after = compute(c,owned+[id])
	match id:
		"quick_chant": return "吟唱 %.2f → %.2f 秒\n附加蓄力也同步缩短" % [before.chant,after.chant]
		"efficient_cast": return "消耗 %.1f → %.1f 法力\n更持续地施法" % [before.cost,after.cost]
		"wide_blast": return "半径 %.2f → %.2f 米\n提高落点容错" % [before.radius,after.radius]
		"embers": return "落地留下 %.1f 秒余烬\n每 %.1f 秒造成 %.1f 伤害" % [c["upgrade.embers.duration"],c["upgrade.embers.tick_interval"],c["upgrade.embers.tick_damage"]]
		"echo": return "%.2f 秒后追加一次爆炸\n伤害 %.0f%% · 半径 %.0f%%" % [c["upgrade.echo.delay"],100*c["upgrade.echo.damage_multiplier"],100*c["upgrade.echo.radius_multiplier"]]
		"molten": return "继续按住 %.2f 秒强化\n额外 %.1f 法力 · 伤害 %.0f%%" % [after.extra_chant,c["upgrade.molten.extra_cost"],100*c["upgrade.molten.damage_multiplier"]]
	return ""
