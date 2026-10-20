extends RefCounted
const Fireball=preload("res://scripts/core/fireball_stats.gd")
# Pure attributes from configuration and ownership; fireball reuses the old calculator.
static func compute(c: Dictionary,id: String,owned: Array=[],enhanced: bool=false) -> Dictionary:
	if id=="fireball":
		var s=Fireball.compute(c,owned,enhanced)
		s["range"]=c["fireball.range"]
		s["cooldown"]=c["fireball.cooldown"]
		return s
	var s={"chant":c[id+".chant_time"],"cost":c[id+".mana_cost"],"cooldown":c[id+".cooldown"],"radius":0.0,"range":0.0,"damage":0.0,"extra_chant":1.0,"enhanced":false}
	match id:
		"meteor":
			s.radius=c["meteor.radius"]
			s.range=c["meteor.range"]
			s.damage=c["meteor.damage"]
			s["fall_time"]=c["meteor.fall_time"]
		"frost":
			s.radius=c["frost.radius"]
			s["slow_duration"]=c["frost.slow_duration"]
			s["slow_multiplier"]=c["frost.slow_multiplier"]
		"rejuvenation":
			s["total_heal"]=c["rejuvenation.total_heal"]
			s["duration"]=c["rejuvenation.duration"]
			s["tick_interval"]=c["rejuvenation.tick_interval"]
		"lamp":
			s["duration"]=c["lamp.duration"]
			s["attack_interval"]=c["lamp.attack_interval"]
			s.range=c["lamp.range"]
			s.damage=c["lamp.damage"]
	for upgrade in owned:
		if upgrade not in preload("res://scripts/core/spell_catalog.gd").FUTURE_UPGRADES: continue
		var prefix="build_upgrade."+upgrade+"."
		match upgrade:
			"meteor_quick","heal_quick":
				if (id=="meteor" and upgrade=="meteor_quick") or (id=="rejuvenation" and upgrade=="heal_quick"): s.chant*=c[prefix+"chant_multiplier"]
			"meteor_wide","frost_wide":
				if id==("meteor" if upgrade=="meteor_wide" else "frost"): s.radius+=c[prefix+"radius_bonus"]
			"meteor_efficient","frost_efficient","heal_efficient":
				if id=={"meteor_efficient":"meteor","frost_efficient":"frost","heal_efficient":"rejuvenation"}[upgrade]: s.cost=maxf(0,s.cost-c[prefix+"cost_reduction"])
			"frost_duration":
				if id=="frost": s.slow_duration+=c[prefix+"duration_bonus"]
			"heal_amount":
				if id=="rejuvenation": s.total_heal*=c[prefix+"total_multiplier"]
			"lamp_duration":
				if id=="lamp": s.duration+=c[prefix+"duration_bonus"]
			"lamp_damage":
				if id=="lamp": s.damage*=c[prefix+"damage_multiplier"]
			"lamp_range":
				if id=="lamp": s.range+=c[prefix+"range_bonus"]
	# Snapshot every effect parameter, including those supplied by twin without sync.
	for key in c:
		if key.begins_with("build_upgrade."): s[key]=c[key]
	s["owned"]=owned.duplicate()
	return s
static func description(id: String,c: Dictionary,owned: Array) -> String:
	var catalog=preload("res://scripts/core/spell_catalog.gd")
	if id in Fireball.IDS: return Fireball.description(id,c,owned.filter(func(key): return key!=id)).replace("\n"," · ")
	var spell=catalog.upgrade_spell(id)
	var before=compute(c,spell,owned.filter(func(key): return key!=id))
	var after=compute(c,spell,owned if id in owned else owned+[id])
	var p="build_upgrade."+id+"."
	match id:
		"meteor_quick","heal_quick": return "吟唱 %.2f → %.2f秒" % [before.chant,after.chant]
		"meteor_wide","frost_wide": return "作用半径 %.2f → %.2f米" % [before.radius,after.radius]
		"meteor_efficient","frost_efficient","heal_efficient": return "消耗 %.0f → %.0f法力" % [before.cost,after.cost]
		"meteor_fragments": return "首击后%.2f秒：%d碎星，各%.0f%%伤害，半径%.1f米" % [c[p+"delay"],c[p+"count"],100*c[p+"damage_multiplier"],c[p+"radius"]]
		"meteor_burn": return "一片地表持续%.1f秒，每%.1f秒%.0f伤害" % [c[p+"duration"],c["upgrade.embers.tick_interval"],c[p+"tick_damage"]]
		"meteor_storm": return "%d主击，间隔%.2f秒，各%.0f%%；碎星/地表仅一份" % [c[p+"count"],c[p+"interval"],100*c[p+"damage_multiplier"]]
		"frost_duration": return "减速/侵蚀时长 %.1f → %.1f秒" % [before.slow_duration,after.slow_duration]
		"frost_freeze": return "冻结%.1f秒；同敌%.1f秒保护，解冻继续原攻击" % [c[p+"freeze_duration"],c[p+"freeze_lockout"]]
		"frost_exposure": return "直接火球/陨火伤害×%.2f，不影响燃烧/召唤" % c[p+"damage_multiplier"]
		"frost_field": return "原地领域%.1f秒，每%.2f秒续减速；不续冻结/侵蚀" % [c[p+"duration"],c[p+"refresh_interval"]]
		"heal_amount": return "总治疗 %.0f → %.0f点" % [before.total_heal,after.total_heal]
		"heal_immediate": return "总治疗%.0f%%立即到账，余量持续，总预算不增加" % (100*c[p+"immediate_fraction"])
		"heal_shield": return "溢出×%.2f转盾，上限%.0f，持续%.1f秒" % [c[p+"overheal_multiplier"],c[p+"shield_cap"],c[p+"shield_duration"]]
		"heal_spring": return "回春有效时每场一次：保留%.0f生命，免伤%.1f秒" % [c[p+"retained_health"],c[p+"invulnerable_time"]]
		"lamp_duration": return "灯灵持续 %.1f → %.1f秒" % [before.duration,after.duration]
		"lamp_damage": return "基础攻击 %.1f → %.1f，不乘同步" % [before.damage,after.damage]
		"lamp_range": return "基础索敌 %.1f → %.1f米" % [before.range,after.range]
		"lamp_sync": return "主动火球/陨火释放同步%.0f伤害，间隔%.2f秒" % [c[p+"damage"],c[p+"trigger_interval"]]
		"lamp_guard": return "每%.1f秒加%.0f盾，上限%.0f，持续%.1f秒" % [c[p+"interval"],c[p+"shield_gain"],c[p+"shield_cap"],c[p+"shield_duration"]]
		"lamp_twin": return "第二灯灵仅同步；无需稀有同步，不复制攻击/盾"
	return ""
