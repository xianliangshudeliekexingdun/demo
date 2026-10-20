extends RefCounted
var path=""
var cursor=0
var finished=false
var error=""
func _init(config: Dictionary,metadata: Dictionary={},directory: String="res://build/qa/build-trial/sessions"):
	# Deliberately do not call the fireball constructor: separate session schema/path.
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:
		error="无法创建试验记录目录"
		return
	path=directory+"/%d-%d" % [int(Time.get_unix_time_from_system()*1000),Time.get_ticks_usec()]
	write_line({"kind":"session","schema":"build-trial-2","config":config,"metadata":metadata,"created":Time.get_datetime_string_from_system()})
func write_line(data: Dictionary):
	if path.is_empty(): return
	var f=FileAccess.open(path+".jsonl",FileAccess.READ_WRITE if FileAccess.file_exists(path+".jsonl") else FileAccess.WRITE)
	if f==null:
		error="无法写入试验记录："+path
		return
	f.seek_end()
	f.store_line(JSON.stringify(serial(data)))
	if f.get_error()!=OK: error="试验记录写入失败"
func serial(value):
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var result={}
		for k in value: result[k]=serial(value[k])
		return result
	if value is Array:
		var result=[]
		for v in value: result.append(serial(v))
		return result
	return value
func flush(b):
	while cursor<b.events.size():
		write_line(b.events[cursor])
		cursor+=1
func finish(b):
	if finished: return
	flush(b)
	finished=true
	if path.is_empty(): return
	var r=b.report()
	r["end_reason"]=b.result if b.result in ["failure","success","config_error"] else "user_end"
	var f=FileAccess.open(path+"-summary.json",FileAccess.WRITE)
	if f==null:
		error="无法写入试验摘要"
		return
	f.store_string(JSON.stringify(serial(r),"\t"))
	f.close()
	var content="五法术试验 · 阶段B\n时长 %.2f秒 · 实际伤害 %.1f · 治疗 %.1f\n" % [r.duration,r.damage,r.heal]
	content+="减速 %.2f敌人秒 · 冻结 %.2f敌人秒 · 吸收盾 %.1f · 防致命 %d次\n法力不足 %.2f秒 · 升级 %s\n" % [r.slow_enemy_seconds,r.freeze_enemy_seconds,r.shield_absorbed,r.fatal_protections,r.mana_low_seconds,str(r.upgrades)]
	content+="伤害来源 %s\n成长路径 %s\n" % [str(r.damage_by_kind),str(r.choice_history)]
	for id in b.slots:
		var s=r.by_spell[id]
		content+="%s：开始%d / 释放%d / 取消%d / 冷却拒绝%d · 法力%.1f · 伤害%.1f · 治疗%.1f / 过量%.1f\n" % [id,s.started,s.released,s.cancels,s.cooldown_blocked,s.mana,s.damage,s.heal,s.overheal]
	f=FileAccess.open(path+"-summary.txt",FileAccess.WRITE)
	if f: f.store_string(content)
	else: error="无法写入可读摘要"
