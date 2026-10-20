extends RefCounted
var path=""
var cursor=0
var finished=false
func _init(config: Dictionary):
	var directory="res://build/qa/fireball-trial/sessions"
	DirAccess.make_dir_recursive_absolute(directory)
	path=directory+"/%d-%d" % [int(Time.get_unix_time_from_system()*1000),Time.get_ticks_usec()]
	write_line({"kind":"session","config":config,"created":Time.get_datetime_string_from_system()})
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
func write_line(data: Dictionary):
	var f=FileAccess.open(path+".jsonl",FileAccess.READ_WRITE if FileAccess.file_exists(path+".jsonl") else FileAccess.WRITE)
	if f==null: return
	f.seek_end()
	f.store_line(JSON.stringify(serial(data)))
func flush(b):
	while cursor<b.events.size():
		write_line(b.events[cursor])
		cursor+=1
func finish(b):
	if finished: return
	flush(b)
	var r=b.report()
	r["end_reason"]="completed" if b.result in ["success","failure","config_error"] else "user_end"
	var f=FileAccess.open(path+"-summary.json",FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(serial(r),"\t"))
		f.close()
	var text="时长 %.2f 秒\n释放 %d · 落地 %d · 命中 %d\n接续 %d/%d · 窗口超时 %d\n受击 %d · 伤害 %.1f\n升级 %s\n取消原因 %s\n" % [r.duration,r.released,r.landed,r.hit_shots,r.resumed,r.attempts,r.timeouts,r.hits,r.damage,str(r.upgrades),str(r.cancels)]
	f=FileAccess.open(path+"-summary.txt",FileAccess.WRITE)
	if f: f.store_string(text)
	finished=true
