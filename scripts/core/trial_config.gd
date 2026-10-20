extends RefCounted
const PATH = "res://data/fireball_trial.csv"
const RULES = {
	"player.health_max": ["int", 1, 10000],
	"player.move_speed": ["float", 0.1, 20],
	"player.casting_move_multiplier": ["float", 0, 1],
	"player.radius": ["float", 0.05, 2],
	"mana.max": ["float", 1, 10000],
	"mana.regen_delay": ["float", 0, 10],
	"mana.regen_rate": ["float", 0, 1000],
	"fireball.mana_cost": ["float", 0, 1000],
	"fireball.chant_time": ["float", 0.05, 10],
	"fireball.flight_time": ["float", 0.05, 5],
	"fireball.damage": ["float", 0, 10000],
	"fireball.explosion_radius": ["float", 0.1, 8],
	"fireball.range": ["float", 0.5, 20],
	"fireball.arc_height": ["float", 0, 5],
	"dodge.distance": ["float", 0.1, 8],
	"dodge.duration": ["float", 0.05, 1],
	"dodge.invulnerable_time": ["float", 0, 1],
	"dodge.cooldown": ["float", 0.05, 10],
	"dodge.resume_window": ["float", 0.05, 2],
	"enemy.health": ["float", 1, 10000],
	"enemy.radius": ["float", 0.05, 2],
	"enemy.chase_speed": ["float", 0.1, 15],
	"enemy.attack_trigger_distance": ["float", 0.2, 8],
	"enemy.windup_time": ["float", 0.05, 5],
	"enemy.lunge_distance": ["float", 0.1, 8],
	"enemy.lunge_time": ["float", 0.05, 2],
	"enemy.recover_time": ["float", 0.05, 5],
	"enemy.attack_radius": ["float", 0.05, 3],
	"enemy.damage": ["float", 0, 10000],
	"upgrade.quick_chant.multiplier": ["float", 0.1, 1],
	"upgrade.efficient_cast.cost_reduction": ["float", 0, 1000],
	"upgrade.wide_blast.radius_bonus": ["float", 0, 5],
	"upgrade.embers.duration": ["float", 0.1, 20],
	"upgrade.embers.tick_interval": ["float", 0.05, 5],
	"upgrade.embers.tick_damage": ["float", 0, 10000],
	"upgrade.embers.radius_multiplier": ["float", 0.1, 2],
	"upgrade.echo.delay": ["float", 0.05, 5],
	"upgrade.echo.damage_multiplier": ["float", 0, 3],
	"upgrade.echo.radius_multiplier": ["float", 0.1, 2],
	"upgrade.molten.extra_chant": ["float", 0.05, 5],
	"upgrade.molten.extra_cost": ["float", 0, 1000],
	"upgrade.molten.damage_multiplier": ["float", 1, 10],
	"upgrade.molten.radius_multiplier": ["float", 1, 3],
	"choice.common_weight": ["float", 0, 1000],
	"choice.rare_weight": ["float", 0, 1000],
	"choice.legendary_weight": ["float", 0, 1000],
	"choice.count": ["int", 1, 6],
	"trial.wave_1_count": ["int", 1, 3],
	"trial.wave_2_count": ["int", 1, 3],
	"trial.wave_3_count": ["int", 1, 3],
	"trial.wave_health_multiplier": ["float", 0.1, 5],
	"trial.between_wave_heal": ["float", 0, 10000],
	"trial.between_wave_mana_fraction": ["float", 0, 1],
	"trial.seed": ["int", 0, 2147483647],
	"trial.spawn_left_x": ["float", -8, 8],
	"trial.spawn_center_x": ["float", -8, 8],
	"trial.spawn_right_x": ["float", -8, 8],
	"trial.spawn_z": ["float", -4, 4],
}
var values: Dictionary = {}
var error = ""

func load_table(path: String = PATH) -> bool:
	error = ""
	var f = FileAccess.open(path,FileAccess.READ)
	if f == null: return fail("无法读取数值表："+path)
	var header = f.get_csv_line()
	if not header.is_empty(): header[0]=header[0].trim_prefix("\ufeff")
	if header != PackedStringArray(["key","value","type","unit","min","max","note"]): return fail("CSV列名不正确")
	var candidate = {}
	var line = 1
	while not f.eof_reached():
		var row = f.get_csv_line()
		line += 1
		if row.size()==1 and row[0].strip_edges().is_empty(): continue
		if row.size()!=7: return fail("第%d行需要7列" % line)
		var key = row[0].strip_edges()
		if not RULES.has(key) or candidate.has(key): return fail("第%d行未知或重复键：%s" % [line,key])
		var rule = RULES[key]
		if row[2]!=rule[0] or not row[1].is_valid_float(): return fail("第%d行类型错误：%s" % [line,key])
		var v = float(row[1])
		if not is_finite(v) or v<float(rule[1]) or v>float(rule[2]) or (rule[0]=="int" and v!=floor(v)): return fail("第%d行越界/非有限/非整数：%s" % [line,key])
		candidate[key] = int(v) if rule[0]=="int" else v
	for key in RULES:
		if not candidate.has(key): return fail("缺少参数："+key)
	if candidate["dodge.invulnerable_time"]>candidate["dodge.duration"] or candidate["dodge.duration"]>candidate["dodge.cooldown"]: return fail("dodge：免伤≤时长≤冷却")
	if candidate["upgrade.embers.tick_interval"]>candidate["upgrade.embers.duration"]: return fail("余烬间隔必须≤持续时间")
	if candidate["upgrade.efficient_cast.cost_reduction"]>candidate["fireball.mana_cost"]: return fail("节能减耗超过基础消耗")
	if candidate["fireball.mana_cost"]+candidate["upgrade.molten.extra_cost"]>candidate["mana.max"]: return fail("强化法力消耗超过法力上限")
	if candidate["choice.common_weight"]+candidate["choice.rare_weight"]+candidate["choice.legendary_weight"]<=0: return fail("choice：总有效权重必须大于零")
	for side in ["left","center","right"]:
		var x = candidate["trial.spawn_"+side+"_x"]
		var z = candidate["trial.spawn_z"]
		if absf(x)+candidate["enemy.radius"]>10 or absf(z)+candidate["enemy.radius"]>5.625 or Vector2(x,z).length()<=candidate["enemy.attack_radius"]+candidate["player.radius"]: return fail("出生位置越界或缺少预警安全距离："+side)
	values = candidate
	return true

func fail(message: String) -> bool:
	error = message
	return false
