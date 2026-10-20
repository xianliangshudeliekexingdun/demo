extends RefCounted
const Base=preload("res://scripts/core/trial_config.gd")
const Schema=preload("res://scripts/core/build_schema.gd")
const Catalog=preload("res://scripts/core/spell_catalog.gd")
var values: Dictionary={}
var layout: Dictionary={}
var presets: Dictionary={}
var config_hash=""
var error=""
func fail(message: String) -> bool:
	error=message
	return false
func load_all(base_path: String=Base.PATH,path: String="res://data/build_trial.csv",wave_path: String="res://data/build_trial_waves.json",preset_path: String="res://data/build_trial_presets.json") -> bool:
	error=""
	var base=Base.new()
	if not base.load_table(base_path): return fail(base_path+": "+base.error)
	var f=FileAccess.open(path,FileAccess.READ)
	if f==null: return fail(path+": 无法读取")
	var header=f.get_csv_line()
	if not header.is_empty(): header[0]=header[0].trim_prefix("\ufeff")
	if header!=PackedStringArray(["key","value","type","unit","min","max","note"]): return fail(path+": CSV列名错误")
	var candidate={}
	var line=1
	while not f.eof_reached():
		var row=f.get_csv_line()
		line+=1
		if row.size()==1 and row[0].strip_edges().is_empty(): continue
		if row.size()!=7: return fail(path+": 第%d行需要7列" % line)
		var key=row[0].strip_edges()
		if not Schema.RULES.has(key) or candidate.has(key): return fail(path+": 未知/重复键 "+key)
		var rule=Schema.RULES[key]
		if row[2]!=rule[0] or not row[1].is_valid_float(): return fail(path+": 类型错误 "+key)
		var v=float(row[1])
		if not is_finite(v) or v<rule[1] or v>rule[2] or (rule[0]=="int" and v!=floor(v)): return fail(path+": 越界/非有限/非整数 "+key)
		candidate[key]=int(v) if rule[0]=="int" else v
	for key in Schema.RULES:
		if not candidate.has(key): return fail(path+": 缺少键 "+key)
	for key in base.values:
		if key.begins_with("choice.") or key.begins_with("trial."): continue
		if candidate.has(key): return fail(path+": 重复继承键 "+key)
		candidate[key]=base.values[key]
	for id in Catalog.IDS:
		if candidate[id+".mana_cost"]>candidate["mana.max"]: return fail(path+": 消耗超过法力上限 "+id)
	var ticks=candidate["rejuvenation.duration"]/candidate["rejuvenation.tick_interval"]
	if ticks<1 or absf(ticks-roundf(ticks))>0.000001: return fail(path+": rejuvenation.duration必须为tick_interval正整数倍")
	if candidate["build_upgrade.frost_freeze.freeze_lockout"]<candidate["build_upgrade.frost_freeze.freeze_duration"]: return fail(path+": 冻结保护间隔必须不短于冻结时间")
	if candidate["build_upgrade.heal_spring.retained_health"]>candidate["player.health_max"]: return fail(path+": 防致命保留生命超过生命上限")
	var waves=JSON.parse_string(FileAccess.get_file_as_string(wave_path))
	if not waves is Dictionary: return fail(wave_path+": 无效JSON对象")
	if not validate_layout(waves,candidate): return fail(wave_path+": "+error)
	var future=JSON.parse_string(FileAccess.get_file_as_string(preset_path))
	if not future is Dictionary or future.size()!=3: return fail(preset_path+": 需要三组预设")
	for name in ["frequency","control","sustain"]:
		if not future.has(name) or not future[name] is Array or future[name].size()!=8: return fail(preset_path+": 每预设需要8项 "+name)
		var seen=[]
		for id in future[name]:
			if id not in Catalog.FUTURE_UPGRADES or id in seen: return fail(preset_path+": 未知/重复升级 "+str(id))
			seen.append(id)
	values=candidate
	layout=waves
	presets=future
	config_hash=(JSON.stringify(values)+JSON.stringify(layout)+JSON.stringify(presets)).sha256_text()
	return true
func validate_layout(w: Dictionary,c: Dictionary) -> bool:
	if not w.has_all(["free_default_count","free_default_health_multiplier","free_positions","waves"]): return fail("缺少出生/波次键")
	if not number(w.free_default_count,0,6,true) or not number(w.free_default_health_multiplier,.1,10): return fail("自由默认人数/生命倍率错误")
	if not w.free_positions is Dictionary or not w.waves is Array or w.waves.is_empty() or w.waves.size()>31: return fail("出生列表或波次无效")
	for count in range(7):
		if not w.free_positions.has(str(count)) or not positions(w.free_positions[str(count)],count,c): return fail("自由出生无效 %d" % count)
	for wave in w.waves:
		if not wave is Dictionary or not wave.has_all(["count","health_multiplier","positions"]): return fail("波次缺键")
		if not number(wave.count,1,6,true) or not number(wave.health_multiplier,.1,10): return fail("波次人数/生命倍率错误")
		if not positions(wave.positions,int(wave.count),c): return fail("波次出生位置错误")
	return true
func positions(points,count: int,c: Dictionary) -> bool:
	if not points is Array or points.size()!=count: return false
	var seen=[]
	for point in points:
		if not point is Array or point.size()!=2 or not number(point[0],-10,10) or not number(point[1],-5.625,5.625): return false
		var p=Vector2(point[0],point[1])
		if absf(p.x)+c["enemy.radius"]>10 or absf(p.y)+c["enemy.radius"]>5.625 or p.length()<=c["player.radius"]+c["enemy.attack_radius"]: return false
		for old in seen:
			if p.distance_to(old)<=2*c["enemy.radius"]: return false
		seen.append(p)
	return true
func number(v,lo: float,hi: float,integer: bool=false) -> bool:
	return (v is float or v is int) and is_finite(float(v)) and v>=lo and v<=hi and (not integer or v==floor(v))
