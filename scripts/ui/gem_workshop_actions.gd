extends RefCounted
## Read-only previews; account transactions commit all fees and candidates.
const T = preload("res://scripts/ui/atelier_theme.gd")
const Icon = preload("res://scripts/ui/gem_icon.gd")

static func shell(ui,title: String,subtitle: String):
	var panel=T.panel(ui.page,Rect2(104,208,1392,632),true)
	T.label(panel,title,Rect2(30,16,1250,44),30,T.GOLD)
	T.paragraph(panel,subtitle,Rect2(30,76,1328,70),20,T.TEXT)
	return panel

static func _picture(parent,gem: Dictionary,rect: Rect2):
	var icon=Icon.new()
	icon.set_gem(gem)
	icon.position=rect.position
	icon.size=rect.size
	parent.add_child(icon)
	return icon

static func craft(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	var lib=ui.meta.gems
	var p=T.panel(ui.page,Rect2(408,260,1136,580),true)
	T.label(p,"选择主属性",Rect2(24,14,1060,42),28,T.GOLD)
	var stats: Array=lib.rules.affixes.keys()
	if ui.gem_main_stat not in stats: ui.gem_main_stat=str(stats[0])
	for index in stats.size():
		var stat: String=str(stats[index])
		var b=ui.btn(p,str(lib.rules.affixes[stat].label),Rect2(24+(index%4)*276,74+floori(index/4.0)*62,260,50),"gem_main_stat",stat,ui.gem_main_stat==stat)
		b.add_theme_font_size_override("font_size",20)
	for index in 3:
		var rarity: String=["green","blue","purple"][index]
		ui.btn(p,"%s · %d精粹"%[lib.rules.rarity_names[rarity],lib.rules.workshop.craft_costs[rarity]],Rect2(24+index*364,214,344,50),"gem_craft_rarity",rarity,ui.gem_craft_rarity==rarity).add_theme_font_size_override("font_size",21)
	var preview: Dictionary={"rarity":ui.gem_craft_rarity,"affixes":[{"stat":ui.gem_main_stat,"role":"main","tier":1,"value":lib.rules.affixes[ui.gem_main_stat].main_tiers[0]}]}
	_picture(p,preview,Rect2(24,294,84,84))
	T.label(p,lib.affix_text(preview),Rect2(128,292,960,40),25,T.TEXT)
	T.paragraph(p,"制作结果：主属性Ⅰ档，新增副属性随机且为Ⅰ档，不与主属性或另一副属性重复。\n费用与结果提交后保存；制作不推进抽取保底。",Rect2(128,344,960,70),20,T.MUTED)
	var free_left: int=maxi(0,int(lib.rules.starter_attribute_count)-int(state.get("starter_attributes_claimed",0)))
	var cost: int=int(lib.rules.workshop.craft_costs[ui.gem_craft_rarity])
	ui.btn(p,"免费领取所选主属性绿Ⅰ · 剩%d枚"%free_left,Rect2(24,430,660,52),"gem_attribute_starter",ui.gem_main_stat,true,free_left<=0 or ui.meta.is_in_run()).add_theme_font_size_override("font_size",22)
	ui.btn(p,"制作%s · %d精粹"%[lib.rules.rarity_names[ui.gem_craft_rarity],cost],Rect2(704,430,408,52),"gem_craft",ui.gem_craft_rarity+":"+ui.gem_main_stat,false,ui.meta.is_in_run() or int(state.essence)<cost).add_theme_font_size_override("font_size",22)
	var milestones: PackedStringArray=[]
	for milestone in lib.rules.milestone_essence:
		var threshold: int=int(milestone.cleared)
		milestones.append("%d房＋%d精粹：%s"%[threshold,int(milestone.essence),"已领取" if threshold in state.get("milestone_claimed",[]) else "待达成"])
	T.paragraph(p,"累计结算清房 %d · %s\n里程精粹在真实结算时自动发放，重复结算不重领。"%[int(state.get("cumulative_cleared",0))," ／ ".join(milestones)],Rect2(24,504,1088,62),18,T.MUTED)

static func reforge(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	var lib=ui.meta.gems
	var gem: Dictionary=lib.find(state,ui.selected)
	var p=shell(ui,"属性培养 · "+lib.title(gem),"宝石精粹 %d · 升品保留原行与档位；提档确定成功。副类型可随机重铸或定向重塑，均保留原档。\n锁定后不能培养，出发后本局无法调整。"%int(state.essence))
	if gem.is_empty() or str(gem.get("rarity","")) in ["gold","legacy"] or gem.has("legacy_id"):
		T.label(p,"请选择一枚属性宝石。",Rect2(32,164,1220,48),24)
	elif str(gem.rarity)=="transition":
		conversion(ui,p,gem,state)
	else:
		var blocked: bool=ui.meta.is_in_run() or bool(gem.locked)
		var w: Dictionary=lib.rules.workshop
		for index in gem.affixes.size():
			var line: Dictionary=gem.affixes[index]
			var y: float=164+index*100
			var tier: int=int(line.get("tier",1))
			var tier_costs: Array=w.main_tier_costs if index==0 else w.side_tier_costs
			var tier_cost: int=int(tier_costs[mini(tier-1,1)])
			T.label(p,lib.affix_text({"affixes":[line]}),Rect2(30,y,470,48),24,T.TEXT)
			ui.btn(p,"已达Ⅲ档" if tier>=3 else "提至%s · %d精粹"%[["Ⅰ","Ⅱ","Ⅲ"][tier],tier_cost],Rect2(516,y,244,48),"gem_raise",str(index),false,blocked or tier>=3 or int(state.essence)<tier_cost).add_theme_font_size_override("font_size",20)
			if index>0:
				ui.btn(p,"随机重铸 · %d"%int(w.random_retype_cost),Rect2(778,y,268,48),"gem_reforge",str(index),false,blocked or int(state.essence)<int(w.random_retype_cost)).add_theme_font_size_override("font_size",20)
				ui.btn(p,"定向重塑 · %d"%int(w.direct_retype_cost),Rect2(1064,y,292,48),"gem_retype_open",str(index),false,blocked or int(state.essence)<int(w.direct_retype_cost)).add_theme_font_size_override("font_size",20)
			else: T.label(p,"主属性类型固定；换方向可制作新石",Rect2(778,y,578,48),19,T.MUTED)
		if str(gem.rarity) in ["green","blue"]:
			var cost: int=int(w.upgrade_costs[gem.rarity])
			var next: String="blue" if gem.rarity=="green" else "purple"
			T.paragraph(p,"升品新增一条随机副属性Ⅰ档；已有类型、档位和装备位置保持。",Rect2(32,482,840,54),21,T.MUTED)
			ui.btn(p,"升为%s · %d精粹"%[lib.rules.rarity_names[next],cost],Rect2(920,478,436,52),"gem_upgrade","",true,blocked or int(state.essence)<cost).add_theme_font_size_override("font_size",22)
		else: T.label(p,"紫色已达最高品质，仍可培养每行档位与副类型。",Rect2(32,488,1260,42),21,T.MUTED)
		if bool(gem.locked): T.label(p,"此石已锁定，请先返回解锁。",Rect2(32,552,850,42),20,T.CYAN)
	ui.btn(p,"返回宝石",Rect2(1040,560,316,48),"gem_tool","",true)

static func conversion(ui,p,gem: Dictionary,state: Dictionary) -> void:
	var lib=ui.meta.gems
	T.paragraph(p,"过渡属性原值保留。选择已有一行作新主属性，该行数值翻倍，其他行及档位保持。\n免费、自愿转换；先核对完整前后结果，再确认。",Rect2(32,156,1260,64),21,T.TEXT)
	var stats: Array=[]
	for line in gem.affixes: stats.append(str(line.stat))
	if ui.gem_main_stat not in stats: ui.gem_main_stat=str(stats[0])
	for index in stats.size():
		ui.btn(p,"主属性："+str(lib.rules.affixes[stats[index]].label),Rect2(32+index*440,242,420,50),"gem_main_stat",stats[index],ui.gem_main_stat==stats[index]).add_theme_font_size_override("font_size",22)
	var converted: Dictionary=lib.converted(gem,ui.gem_main_stat)
	T.paragraph(p,"原属性\n"+lib.affix_text(gem),Rect2(32,326,620,160),23,T.TEXT)
	T.paragraph(p,"转换后\n"+lib.affix_text(converted),Rect2(710,326,620,160),23,T.CYAN)
	ui.btn(p,"确认免费转换",Rect2(32,546,640,56),"gem_convert",ui.gem_main_stat,true,ui.meta.is_in_run() or bool(gem.locked) or converted.is_empty())

static func retype(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	var lib=ui.meta.gems
	var gem: Dictionary=lib.find(state,ui.selected)
	var cost: int=int(lib.rules.workshop.direct_retype_cost)
	var p=shell(ui,"定向重塑副属性","指定合法副类型，保持原档位，确定成功。费用%d精粹；确认前不扣材料。"%cost)
	if gem.is_empty() or ui.gem_line_index<=0 or ui.gem_line_index>=gem.affixes.size():
		ui.btn(p,"返回培养",Rect2(1040,560,316,48),"gem_tool","reforge",true)
		return
	var line: Dictionary=gem.affixes[ui.gem_line_index]
	var excluded: Array=[]
	for other in gem.affixes: excluded.append(str(other.stat))
	var stats: Array=lib.rules.affixes.keys()
	var legal: Array=stats.filter(func(stat): return str(stat) not in excluded)
	if ui.gem_retype_stat not in legal: ui.gem_retype_stat=str(legal[0])
	for index in stats.size():
		var stat: String=str(stats[index])
		ui.btn(p,str(lib.rules.affixes[stat].label),Rect2(30+(index%4)*340,176+floori(index/4.0)*78,320,56),"gem_retype_stat",stat,ui.gem_retype_stat==stat,stat not in legal).add_theme_font_size_override("font_size",22)
	var next: Dictionary={"stat":ui.gem_retype_stat,"tier":line.tier,"role":"side","value":lib.rules.affixes[ui.gem_retype_stat].tiers[int(line.tier)-1]}
	T.paragraph(p,"原属性\n"+lib.affix_text({"affixes":[line]}),Rect2(32,366,620,120),26,T.TEXT)
	T.paragraph(p,"确定结果\n"+lib.affix_text({"affixes":[next]}),Rect2(710,366,620,120),26,T.CYAN)
	ui.btn(p,"返回培养",Rect2(30,546,652,56),"gem_tool","reforge")
	ui.btn(p,"确认重塑 · %d精粹"%cost,Rect2(710,546,652,56),"gem_retype",str(ui.gem_line_index)+":"+ui.gem_retype_stat,true,ui.meta.is_in_run() or bool(gem.locked) or int(state.essence)<cost)

static func compare(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	var q: Dictionary=state.pending_reforge
	var lib=ui.meta.gems
	var gem: Dictionary=lib.find(state,str(q.gem_id))
	var p=shell(ui,"选择重铸结果 · "+lib.title(gem),"已消耗%d精粹，剩余%d。关闭或重启保留当前候选，选择后保存。\n原结果也可保留，费用照常消耗；旧版待选结果保留原费用与分支。"%[int(q.cost),int(state.essence)])
	for index in 2:
		var card=T.panel(p,Rect2(30+index*680,166,652,330))
		T.label(card,"原有结果" if index==0 else "本次候选",Rect2(24,20,600,42),27,T.GOLD if index==0 else T.CYAN)
		var value: Variant=q.old if index==0 else q.candidate
		if q.mode=="core":
			var old_pending: bool=not lib.is_modern(state)
			var spec: Dictionary=lib.rules.legacy_cores.get(str(value),{}) if old_pending else lib.core_rule(str(value))
			T.label(card,str(spec.get("name",value)),Rect2(24,88,600,42),29,T.TEXT)
			T.paragraph(card,lib.legacy_core_description(str(value)) if old_pending else lib.core_description(str(value)),Rect2(24,148,600,160),22,T.TEXT)
		else:
			T.paragraph(card,lib.affix_text({"affixes":[value]}),Rect2(24,104,600,120),30,T.TEXT)
			T.label(card,"仅替换第%d行"%(int(q.index)+1),Rect2(24,250,600,36),20)
		ui.btn(p,"保留原结果" if index==0 else "采用新结果",Rect2(30+index*680,546,652,62),"gem_resolve","%d:%s"%[int(q.token),"old" if index==0 else "new"],index==1,ui.meta.is_in_run())

static func salvage(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	var lib=ui.meta.gems
	var eligible: Array=[]
	var gain: int=0
	for id in ui.gem_salvage_ids:
		var gem: Dictionary=lib.find(state,str(id))
		if gem.is_empty() or gem.has("legacy_id") or bool(gem.locked) or id in state.slots: continue
		eligible.append(gem)
		gain+=int(lib.salvage_value(gem))
	var p=shell(ui,"分解预览","本次分解%d枚，获得%d精粹；当前%d。\n装备中、锁定及传承石受保护。确认后删除宝石，不返还额外培养投入，不改变抽取保底。"%[eligible.size(),gain,int(state.essence)])
	var counts: Dictionary={"green":0,"blue":0,"purple":0,"transition":0}
	for gem in eligible: counts[str(gem.rarity)]=int(counts.get(str(gem.rarity),0))+1
	var index: int=0
	for rarity in counts:
		T.label(p,"%s  %d枚"%[lib.rules.rarity_names.get(rarity,rarity),counts[rarity]],Rect2(34,168+index*54,1220,42),24)
		index+=1
	if eligible.size()==1: T.label(p,lib.title(eligible[0])+"  #"+str(eligible[0].serial),Rect2(34,414,1260,42),25,T.GOLD)
	elif eligible.is_empty(): T.label(p,"没有符合条件的闲置属性石。",Rect2(34,414,1260,42),25,T.GOLD)
	ui.btn(p,"返回宝石",Rect2(30,546,652,62),"gem_tool","")
	ui.btn(p,"确认分解 · 获得%d精粹"%gain,Rect2(710,546,652,62),"gem_salvage_confirm","",true,eligible.is_empty() or eligible.size()!=ui.gem_salvage_ids.size() or ui.meta.is_in_run())
