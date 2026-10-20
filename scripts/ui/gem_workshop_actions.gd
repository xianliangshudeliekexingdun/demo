extends RefCounted
## Read-only previews; the account commits all costs, candidates and decisions.
const T = preload("res://scripts/ui/atelier_theme.gd")

static func shell(ui, title: String, subtitle: String):
	var panel = T.panel(ui.page, Rect2(104,208,1392,632), true)
	T.label(panel,title,Rect2(30,16,1250,44),30,T.GOLD)
	T.paragraph(panel,subtitle,Rect2(30,76,1328,70),20,T.TEXT)
	return panel

static func reforge(ui) -> void:
	var state:Dictionary=ui.meta.get_state().gem_state
	var lib=ui.meta.gems
	var gem:Dictionary=lib.find(state,ui.selected)
	var p=shell(ui,"宝石改良 · "+lib.title(gem),"宝石精粹 %d  ·  选择一条重新随机类型与档位，其他词条和核心不变。\n候选生成即扣费，随后可选旧、新结果；保留旧结果也会消耗精粹。" % int(state.essence))
	if gem.is_empty() or gem.has("legacy_id"):
		T.label(p,"请选择一枚抽取获得的宝石。",Rect2(32,164,1220,48),24)
	else:
		var cost:int=int(lib.rules.workshop.affix_costs[gem.rarity])
		var blocked:bool=ui.meta.is_in_run() or bool(gem.locked)
		for index in gem.affixes.size():
			var line:Dictionary={"affixes":[gem.affixes[index]]}
			T.label(p,lib.affix_text(line),Rect2(36,164+index*68,830,48),24,T.TEXT)
			ui.btn(p,"改良此条 · %d精粹" % cost,Rect2(980,164+index*68,376,48),"gem_reforge",str(index),false,blocked or int(state.essence)<cost)
		if gem.rarity=="gold":
			T.label(p,"核心 · "+str(lib.core_rule(str(gem.core)).name),Rect2(36,376,830,36),24,T.GOLD)
			T.paragraph(p,lib.core_description(str(gem.core)),Rect2(36,422,860,124),20,T.TEXT)
			ui.btn(p,"重洗核心 · %d精粹" % int(lib.rules.workshop.core_cost),Rect2(980,386,376,54),"gem_reforge","core",false,blocked or int(state.essence)<int(lib.rules.workshop.core_cost))
			T.paragraph(p,"其余七种核心等权随机。\n三条普通词条保持不变。",Rect2(988,458,360,78),19)
		if bool(gem.locked):T.label(p,"此宝石已锁定，解锁后可改良。",Rect2(36,552,850,42),20,T.CYAN)
	ui.btn(p,"返回宝石",Rect2(1040,560,316,48),"gem_tool","",true)

static func compare(ui) -> void:
	var state:Dictionary=ui.meta.get_state().gem_state
	var q:Dictionary=state.pending_reforge
	var lib=ui.meta.gems
	var gem:Dictionary=lib.find(state,str(q.gem_id))
	var p=shell(ui,"选择改良结果 · "+lib.title(gem),"已消耗%d宝石精粹，剩余%d。选择后保存；离开或重启会保留这次候选。\n只有所选位置改变，其他词条和装备关系保持不变。" % [int(q.cost),int(state.essence)])
	for index in 2:
		var card=T.panel(p,Rect2(30+index*680,166,652,330))
		T.label(card,"原有结果" if index==0 else "本次候选",Rect2(24,20,600,42),27,T.GOLD if index==0 else T.CYAN)
		var value:Variant=q.old if index==0 else q.candidate
		if q.mode=="core":
			T.label(card,str(lib.core_rule(str(value)).name),Rect2(24,88,600,42),29,T.TEXT)
			T.paragraph(card,lib.core_description(str(value)),Rect2(24,148,600,160),22,T.TEXT)
		else:
			T.paragraph(card,lib.affix_text({"affixes":[value]}),Rect2(24,104,600,100),30,T.TEXT)
			T.label(card,"仅替换第%d条普通词条" % (int(q.index)+1),Rect2(24,250,600,36),20)
		ui.btn(p,"保留原结果" if index==0 else "采用新结果",Rect2(30+index*680,530,652,62),"gem_resolve","%d:%s" % [int(q.token),"old" if index==0 else "new"],index==1,ui.meta.is_in_run())

static func salvage(ui) -> void:
	var state:Dictionary=ui.meta.get_state().gem_state
	var lib=ui.meta.gems
	var eligible:Array=[]
	var gain:int=0
	for id in ui.gem_salvage_ids:
		var gem:Dictionary=lib.find(state,str(id))
		if gem.is_empty() or gem.has("legacy_id") or bool(gem.locked) or id in state.slots:continue
		eligible.append(gem)
		gain+=int(lib.rules.workshop.salvage_yields[gem.rarity])
	var p=shell(ui,"分解预览","当前宝石精粹 %d  ·  本次分解%d枚，获得%d精粹。\n已装备、已锁定和传承宝石受保护；分解后宝石消失，抽取保底保持原进度。" % [int(state.essence),eligible.size(),gain])
	var counts:Dictionary={"green":0,"blue":0,"purple":0,"gold":0}
	for gem in eligible:counts[gem.rarity]+=1
	for index in 4:
		var rarity:String=["green","blue","purple","gold"][index]
		T.label(p,"%s宝石  %d枚   × %d精粹" % [lib.rules.rarity_names[rarity],counts[rarity],int(lib.rules.workshop.salvage_yields[rarity])],Rect2(34,168+index*54,1220,42),24)
	if eligible.size()==1:
		T.label(p,"本次分解：%s  #%d" % [lib.title(eligible[0]),int(eligible[0].serial)],Rect2(34,408,1260,42),25,T.GOLD)
	elif eligible.is_empty():T.label(p,"没有符合条件的闲置宝石。",Rect2(34,408,1260,42),25,T.GOLD)
	if int(counts.gold)>0:T.label(p,"包含金色核心，请核对后再确认。",Rect2(34,464,1260,38),22,T.GOLD)
	ui.btn(p,"返回宝石",Rect2(30,548,652,62),"gem_tool","")
	ui.btn(p,"确认分解 · 获得%d精粹" % gain,Rect2(710,548,652,62),"gem_salvage_confirm","",true,eligible.is_empty() or eligible.size()!=ui.gem_salvage_ids.size() or ui.meta.is_in_run())
