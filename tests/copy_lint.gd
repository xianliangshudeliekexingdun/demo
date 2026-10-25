extends SceneTree
## Player-facing copy check for the surfaces rewritten in R1: source literals of
## the menu, HUD, shop, stat tiles and workshop, plus the rendered preparation
## and settings pages. No gameplay, screenshot or pixel evidence.
const UI=preload("res://scripts/ui/atelier_ui.gd")
const Meta=preload("res://scripts/core/meta_progression.gd")
const Controller=preload("res://scripts/main.gd")
const OUTPUT="res://build/qa/copy-r1-20261025"
const FILES=[
	"res://scripts/ui/atelier_ui.gd",
	"res://scripts/ui/first_room_ui.gd",
	"res://scripts/ui/route_shop_ui.gd",
	"res://scripts/ui/loadout_summary.gd",
	"res://scripts/ui/gem_workshop.gd",
]
const FORBIDDEN=["书奖","空跳数","下跳","返还单体","历史职业宝物","无法术条件","全系列","清房","起手","存活敌人","不是必出","不保证必出","实际概率"]
var checks:int=0
var failures:Array=[]
var literals:int=0

func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1
	if not ok:
		failures.append(label)
		push_error("COPY: "+label)

func _cjk(ch:String)->bool:
	if ch.is_empty():return false
	var code=ch.unicode_at(0)
	return (code>=0x4E00 and code<=0x9FFF) or (code>=0x3400 and code<=0x4DBF)
func _digit(ch:String)->bool:
	return not ch.is_empty() and ch.unicode_at(0)>=48 and ch.unicode_at(0)<=57

func inspect(text:String,where:String,strict_terms:bool=true):
	if text.strip_edges().is_empty():return
	if strict_terms:
		for word in FORBIDDEN:
			check(not text.contains(word),"%s 出现禁词「%s」：%s" % [where,word,text.left(36)])
	for zero in ["0 米","0米","0 名","0名","0 敌","0敌","0 点","0点"]:
		if text.contains(zero):
			check(false,"%s 出现零值句「%s」：%s" % [where,zero,text.left(36)])
			break
	var length=text.length()
	var spacing_reported=false
	for i in length:
		var ch=text[i]
		if spacing_reported:break
		if ch=="%" and i+1<length and _cjk(text[i+1]):
			check(false,"%s 百分号后缺空格：%s" % [where,text.left(36)])
			spacing_reported=true
		elif (ch=="米" or ch=="秒" or ch=="级" or ch=="层" or ch=="名" or ch=="点" or ch=="倍") and i>0 and _digit(text[i-1]):
			check(false,"%s 数字与单位间缺空格：%s" % [where,text.left(36)])
			spacing_reported=true
	for i in length:
		if text[i]=="→":
			var before=text[i-1] if i>0 else ""
			var after=text[i+1] if i+1<length else ""
			if before!=" " or after!=" ":
				check(false,"%s 箭头两侧需空格：%s" % [where,text.left(36)])
				break

func scan_source(path:String):
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null:
		check(false,"无法读取 "+path)
		return
	var text=file.get_as_text()
	var regex=RegEx.new()
	regex.compile("\"(?:[^\"\\\\]|\\\\.)*\"")
	for line in text.split("\n"):
		var trimmed=line.strip_edges()
		if trimmed.begins_with("#"):continue
		for hit in regex.search_all(line):
			var value=hit.get_string()
			value=value.substr(1,value.length()-2).replace("\\n","\n").replace("\\t","\t")
			if value.begins_with("res://") or value.begins_with("user://"):continue
			literals+=1
			inspect(value,path.get_file())

func collect(page:Control,where:String)->void:
	for node in page.find_children("*","Label",true,false):
		inspect(node.text,where)
		inspect(str(node.tooltip_text),where+"·悬停")
	for node in page.find_children("*","Button",true,false):
		inspect(node.text,where)
		inspect(str(node.tooltip_text),where+"·悬停")

func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Meta.TEST_SAVE_ROOT))
	for path in FILES:scan_source(path)
	var account_path=Meta.TEST_SAVE_ROOT+"copy_lint_%d.json"%Time.get_ticks_usec()
	var account=Meta.new(account_path)
	check(account.load_state().ok,"isolated account loads")
	var controller=Controller.new()
	controller.save_path=account_path
	controller.preferences_path=OUTPUT+"/temporary-display.cfg"
	controller.meta=account
	var ui=UI.new()
	root.add_child(ui)
	controller.ui=ui
	ui.requested.connect(controller.handle_request)
	for next in ["prepare","settings","catalyst"]:
		controller.screen=next
		controller.refresh()
		collect(ui.page,next)
	ui.free()
	controller.free()
	if FileAccess.file_exists(account_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(account_path))
	var report={"checks":checks,"failures":failures.size(),"literals":literals,"details":failures,"scope":"Source literals of menu/HUD/shop/stat/workshop plus rendered preparation, settings and catalyst pages. Copy only; no gameplay, screenshot or pixel evidence."}
	FileAccess.open(OUTPUT+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COPY LINT checks=%d literals=%d failures=%d"%[checks,literals,failures.size()])
	quit(0 if failures.is_empty() else 1)
