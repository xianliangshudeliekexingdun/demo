extends RefCounted
## Requests only. Account transactions own fees, rolls, locks and equipment.
const T = preload("res://scripts/ui/atelier_theme.gd")
const Icon = preload("res://scripts/ui/gem_icon.gd")
const COLORS = Icon.RARITY_COLORS
const PAGE_SIZE = 6
const EFFECT_HINTS = {
	"inferno":"搭配：焰弹术、焰流旋涡、炽焰法阵。频繁熔核爆弹会打断余烬。",
	"coffin":"搭配：霜弹术、极寒领域、冰封棺；可接其他学派本体，契灵普攻不储伤。",
	"lightning":"搭配：雷矢术、贯雷枪、导电印记。成熟电网与导电消费存在取舍。",
	"wind":"搭配：风刃术、逐风矢、剪风双翼、留风之径；持续移动与施法共同维持。",
	"earth":"岩棱坠击支点可起步；再配地脉石柱、护阵石碑。只有碎岩矢时缺少锚点。",
	"spirit":"契灵召唤或灵刃侍从即可起步；跨族更快。契印灵矢单术没有普攻来源。",
	"fracture":"搭配允许暴击的法术本体；属性优先暴击与暴伤，起步低暴击收益较低。",
	"echo":"搭配贯焰光束、冰锥穿刺、山崩落击；聚风涡或霜环有助于敌人停留。",
	"sacrifice":"用暖焰护持、岩甲术、护主灵支持护盾；需要承担低生命风险。",
	"aegis":"搭配护盾与回盾来源，属性可选生命、护盾、防御；留意实际治疗来源。"
}

static func picture(parent: Node, gem: Dictionary, rect: Rect2):
	var icon=Icon.new()
	icon.set_gem(gem)
	icon.position=rect.position
	icon.size=rect.size
	parent.add_child(icon)
	return icon

static func effect_picture(parent: Node, id: String, rect: Rect2):
	return picture(parent,{"core":id,"rarity":"gold","affixes":[]},rect)

static func build(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	if not state.pending_reforge.is_empty():
		compare(ui)
		return
	if not ui.gem_tool.is_empty():
		match ui.gem_tool:
			"salvage": salvage(ui)
			_: reforge(ui)
		return
	if ui.gem_show_rules:
		rules_page(ui)
		return
	if not ui.gem_results.is_empty():
		results(ui)
		return
	ui.btn(ui.page,"规则与概率",Rect2(826,198,220,46),"gem_rules").add_theme_font_size_override("font_size",20)
	T.label(ui.page,"宝石精粹  %d"%int(state.essence),Rect2(1120,198,424,46),24,T.CYAN)
	equipment(ui,state)
	draw_panel(ui,state)
	inventory(ui,state)
	detail(ui,state)

static func equipment(ui,state: Dictionary) -> void:
	var lib=ui.meta.gems
	var left=T.panel(ui.page,Rect2(54,260,330,580))
	T.label(left,"出发装备",Rect2(18,12,292,38),25,T.GOLD)
	var counts: Dictionary={}
	var first_slot: Dictionary={}
	for index in 4:
		var gem: Dictionary=lib.find(state,str(state.slots[index]))
		var effect: String=str(gem.get("core","")) if str(gem.get("rarity",""))=="gold" else ""
		if effect.is_empty(): continue
		counts[effect]=int(counts.get(effect,0))+1
		if not first_slot.has(effect): first_slot[effect]=index
	for index in 4:
		var id: String=str(state.slots[index])
		var gem: Dictionary=lib.find(state,id)
		var y: float=60+index*84
		T.label(left,"宝石槽 %d"%[index+1],Rect2(18,y,226,24),16,T.MUTED)
		var b=ui.btn(left,lib.title(gem),Rect2(14,y+25,234,50),"gem_select",id)
		b.add_theme_font_size_override("font_size",18)
		b.tooltip_text=lib.affix_text(gem)+("\n"+lib.core_description(str(gem.core)) if not str(gem.get("core","")).is_empty() else "")
		ui.btn(left,"卸下",Rect2(256,y+25,60,50),"gem_equip","%d:"%index,false,ui.meta.is_in_run() or gem.is_empty()).add_theme_font_size_override("font_size",17)
		var effect: String=str(gem.get("core","")) if str(gem.get("rarity",""))=="gold" else ""
		if not effect.is_empty() and int(counts.get(effect,0))>1 and int(first_slot.get(effect,-1))!=index:
			T.label(left,"同名效果重复 · 不生效",Rect2(14,y+76,300,20),15,T.WARN)
	var values: Dictionary=ui.meta.get_preview_stats()
	T.label(left,"出发属性",Rect2(18,410,292,30),20,T.GOLD)
	T.paragraph(left,"生命 %s    护盾 %s\n攻击 %s    防御 %s\n暴击 %s%%  ·  暴伤 %s倍\n冷却 %s%%  ·  移速 +%s%%"%[ui.number(values.health),ui.number(values.shield),ui.number(values.attack),ui.number(values.get("defense",0)),ui.number(float(values.crit_rate)*100),ui.number(values.crit_multiplier),ui.number(float(values.get("cdr",0))*100),ui.number(float(values.get("speed",0))*100)],Rect2(18,448,292,116),18,T.TEXT)

static func draw_panel(ui,state: Dictionary) -> void:
	var lib=ui.meta.gems
	var locked: bool=ui.meta.is_in_run()
	var cost: int=int(lib.rules.draw_cost)
	var draw=T.panel(ui.page,Rect2(408,260,640,104))
	ui.btn(draw,"抽取一次 · %d魔尘"%cost,Rect2(14,12,294,48),"gem_draw","1",true,locked or int(ui.meta.get_state().dust)<cost).add_theme_font_size_override("font_size",21)
	ui.btn(draw,"连续十次 · %d魔尘"%(cost*10),Rect2(322,12,304,48),"gem_draw","10",false,locked or int(ui.meta.get_state().dust)<cost*10).add_theme_font_size_override("font_size",21)
	T.label(draw,"紫色保底 %d 抽内 · 金色保底 %d 抽内" % [maxi(1,int(lib.rules.pity.purple_or_better)-int(state.rare_misses)),maxi(1,int(lib.rules.pity.gold)-int(state.gold_misses))],Rect2(16,66,608,28),18,T.MUTED)

static func inventory(ui,state: Dictionary) -> void:
	var lib=ui.meta.gems
	var locked: bool=ui.meta.is_in_run()
	T.label(ui.page,"宝石背包 · %d枚"%state.inventory.size(),Rect2(408,370,400,34),23)
	var inventory: Array=state.inventory.duplicate(true)
	inventory.reverse()
	ui.gem_page=clampi(ui.gem_page,0,maxi(0,ceili(float(inventory.size())/PAGE_SIZE)-1))
	for row in mini(PAGE_SIZE,inventory.size()-ui.gem_page*PAGE_SIZE):
		var gem: Dictionary=inventory[ui.gem_page*PAGE_SIZE+row]
		var y: float=412+row*58
		var slot: int=state.slots.find(gem.id)
		var text: String=lib.title(gem)+(" · 已锁" if bool(gem.locked) else "")+(" · 槽%d"%(slot+1) if slot>=0 else "")
		var b=ui.btn(ui.page,text,Rect2(462,y,586,50),"gem_select",str(gem.id),ui.selected==str(gem.id))
		b.add_theme_font_size_override("font_size",19)
		b.tooltip_text=lib.affix_text(gem)
		picture(ui.page,gem,Rect2(408,y,48,48))
	if inventory.is_empty(): T.paragraph(ui.page,"背包是空的。\n用魔尘抽取宝石，绿色到金色都会出现。",Rect2(430,454,596,112),22)
	ui.btn(ui.page,"‹",Rect2(408,766,66,48),"gem_page",str(ui.gem_page-1),false,ui.gem_page==0)
	T.label(ui.page,"%d / %d"%[ui.gem_page+1,maxi(1,ceili(float(inventory.size())/PAGE_SIZE))],Rect2(488,766,200,48),20)
	ui.btn(ui.page,"›",Rect2(690,766,66,48),"gem_page",str(ui.gem_page+1),false,(ui.gem_page+1)*PAGE_SIZE>=inventory.size())
	ui.btn(ui.page,"分解闲置绿蓝",Rect2(776,766,272,48),"gem_batch_preview","",false,locked).add_theme_font_size_override("font_size",19)

static func detail(ui,state: Dictionary) -> void:
	var lib=ui.meta.gems
	var gem: Dictionary=lib.find(state,ui.selected)
	var p=T.panel(ui.page,Rect2(1084,260,460,580),true)
	if gem.is_empty():
		T.label(p,"选择一枚宝石",Rect2(22,20,416,42),28)
		T.paragraph(p,"四个槽位不限制品质。\n金色宝石＝一个特殊效果＋三条属性。\n四条属性（含效果）都可被精粹重洗。",Rect2(22,88,416,300),23,T.TEXT)
		return
	picture(p,gem,Rect2(18,16,78,78))
	T.paragraph(p,lib.title(gem),Rect2(108,22,330,72),25,COLORS.get(str(gem.rarity),T.TEXT))
	T.label(p,"%s · #%d"%[lib.rules.rarity_names.get(gem.rarity,gem.rarity),int(gem.serial)],Rect2(22,104,416,28),18,T.MUTED)
	if str(gem.get("core",""))!="":
		T.paragraph(p,lib.core_description(str(gem.core)),Rect2(22,138,416,96),18,T.CYAN)
	T.paragraph(p,lib.affix_text(gem),Rect2(22,240,416,120),21,T.TEXT)
	var duplicates: Dictionary={}
	for id in state.slots:
		var equipped: Dictionary=lib.find(state,str(id))
		var effect: String=str(equipped.get("core","")) if str(equipped.get("rarity",""))=="gold" else ""
		if not effect.is_empty(): duplicates[effect]=int(duplicates.get(effect,0))+1
	var own_effect: String=str(gem.get("core",""))
	if own_effect!="" and int(duplicates.get(own_effect,0))>1:
		T.label(p,"同名效果只生效槽位最靠前的一枚",Rect2(22,364,416,26),17,T.WARN)
	for index in 4:
		var equipped_id: String=str(state.slots[index])
		ui.btn(p,"宝石槽 %d"%[index+1],Rect2(22+index*106,394,100,46),"gem_equip","%d:%s"%[index,gem.id],equipped_id==str(gem.id),ui.meta.is_in_run() or equipped_id==str(gem.id)).add_theme_font_size_override("font_size",17)
	var locked: bool=ui.meta.is_in_run() or bool(gem.locked)
	ui.btn(p,"精粹重洗",Rect2(22,452,416,46),"gem_tool","reforge",true,locked).add_theme_font_size_override("font_size",21)
	ui.btn(p,"分解",Rect2(22,508,198,42),"gem_single_preview","",false,ui.meta.is_in_run() or bool(gem.locked) or str(gem.id) in state.slots).add_theme_font_size_override("font_size",19)
	ui.btn(p,"解锁" if bool(gem.locked) else "锁定",Rect2(236,508,202,42),"gem_lock",str(gem.id),false,ui.meta.is_in_run()).add_theme_font_size_override("font_size",19)

static func reforge(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	var lib=ui.meta.gems
	var gem: Dictionary=lib.find(state,ui.selected)
	var p=T.panel(ui.page,Rect2(104,208,1392,632),true)
	if gem.is_empty():
		T.label(p,"请先选择一枚宝石。",Rect2(32,40,1200,42),26)
		ui.btn(p,"返回宝石",Rect2(1040,560,316,48),"gem_tool","",true)
		return
	var locks: Array=ui.gem_reroll_locks.duplicate()
	var valid: Array=[]
	for lock in locks:
		if lock is String and lock=="core" and str(gem.get("core",""))!="": valid.append(lock)
		elif lock is int and lock>=0 and lock<gem.affixes.size(): valid.append(lock)
	locks=valid
	ui.gem_reroll_locks=locks
	T.label(p,"精粹重洗 · "+lib.title(gem),Rect2(30,14,1000,42),28,T.GOLD)
	T.paragraph(p,"勾选要固定的内容，其余重新随机。每固定一项 +%d 精粹，最多固定 %d 项。\n当前精粹 %d。"%[int(lib.rules.reforge.per_lock),int(lib.rules.reforge.max_locks),int(state.essence)],Rect2(30,66,1328,60),19,T.MUTED)
	var y: float=138
	if str(gem.get("core",""))!="":
		var locked_core: bool="core" in locks
		ui.btn(p,("已固定效果 · "+str(lib.core_rule(str(gem.core)).name)) if locked_core else ("效果 · "+str(lib.core_rule(str(gem.core)).name)),Rect2(30,y,640,48),"gem_reroll_toggle","core",locked_core).add_theme_font_size_override("font_size",19)
		T.paragraph(p,lib.core_description(str(gem.core)),Rect2(690,y,668,48),17,T.CYAN)
		y+=58
	for index in gem.affixes.size():
		var line: Dictionary=gem.affixes[index]
		var locked_line: bool=index in locks
		ui.btn(p,("已固定 · " if locked_line else "固定 · ")+str(lib.rules.affixes[line.stat].label),Rect2(30,y,640,48),"gem_reroll_toggle",str(index),locked_line).add_theme_font_size_override("font_size",19)
		T.label(p,lib.affix_text({"affixes":[line],"rarity":gem.rarity}),Rect2(690,y,668,48),18,T.TEXT)
		y+=58
	var cost: int=lib.reforge_cost(gem,locks)
	var blocked: bool=ui.meta.is_in_run() or bool(gem.locked) or locks.size()>=lib.lockable_count(gem) or int(state.essence)<cost
	T.label(p,"本次费用 %d 精粹"%cost,Rect2(30,556,420,46),23,T.GOLD)
	ui.btn(p,"返回宝石",Rect2(30,606,420,48),"gem_tool","")
	ui.btn(p,"确认重洗",Rect2(472,606,880,48),"gem_reroll","",true,blocked).add_theme_font_size_override("font_size",21)

static func compare(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	var q: Dictionary=state.pending_reforge
	var lib=ui.meta.gems
	var gem: Dictionary=lib.find(state,str(q.gem_id))
	var p=T.panel(ui.page,Rect2(104,208,1392,632),true)
	T.label(p,"选择重洗结果 · "+lib.title(gem),Rect2(30,14,1200,42),28,T.GOLD)
	T.paragraph(p,"已消耗 %d 精粹，剩余 %d。关闭或重启保留当前候选，选择后保存。"%[int(q.cost),int(state.essence)],Rect2(30,64,1328,40),19,T.MUTED)
	for index in 2:
		var card=T.panel(p,Rect2(30+index*680,120,652,400))
		T.label(card,"当前结果" if index==0 else "本次候选",Rect2(24,18,600,40),26,T.GOLD if index==0 else T.CYAN)
		var content: Dictionary=q.old if index==0 else q.candidate
		if not str(content.get("core","")).is_empty():
			T.label(card,str(lib.core_rule(str(content.core)).name),Rect2(24,72,600,38),24,T.TEXT)
			T.paragraph(card,lib.core_description(str(content.core)),Rect2(24,116,600,120),18,T.CYAN)
		T.paragraph(card,lib.affix_text({"affixes":content.get("affixes",[]),"rarity":gem.rarity}),Rect2(24,246,600,140),21,T.TEXT)
		ui.btn(p,"保留当前" if index==0 else "采用新结果",Rect2(30+index*680,546,652,60),"gem_resolve","%d:%s"%[int(q.token),"old" if index==0 else "new"],index==1,ui.meta.is_in_run())

static func salvage(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	var lib=ui.meta.gems
	var eligible: Array=[]
	var gain: int=0
	for id in ui.gem_salvage_ids:
		var gem: Dictionary=lib.find(state,str(id))
		if gem.is_empty() or bool(gem.locked) or id in state.slots: continue
		eligible.append(gem)
		gain+=int(lib.salvage_value(gem))
	var p=T.panel(ui.page,Rect2(104,208,1392,632),true)
	T.label(p,"分解预览",Rect2(30,16,1250,44),30,T.GOLD)
	T.paragraph(p,"本次分解 %d 枚，获得 %d 精粹；当前 %d。\n装备中或锁定的宝石受保护。确认后删除宝石，不返还重洗投入。"%[eligible.size(),gain,int(state.essence)],Rect2(30,76,1328,70),20,T.TEXT)
	var counts: Dictionary={}
	for gem in eligible: counts[str(gem.rarity)]=int(counts.get(str(gem.rarity),0))+1
	var index: int=0
	for rarity in ["green","blue","purple","gold"]:
		T.label(p,"%s  %d枚"%[lib.rules.rarity_names.get(rarity,rarity),int(counts.get(rarity,0))],Rect2(34,168+index*54,1220,42),24)
		index+=1
	if eligible.size()==1: T.label(p,lib.title(eligible[0])+"  #"+str(eligible[0].serial),Rect2(34,420,1260,42),25,T.GOLD)
	elif eligible.is_empty(): T.label(p,"没有符合条件的宝石。",Rect2(34,420,1260,42),25,T.GOLD)
	ui.btn(p,"返回宝石",Rect2(30,546,652,62),"gem_tool","")
	ui.btn(p,"确认分解 · 获得%d精粹"%gain,Rect2(710,546,652,62),"gem_salvage_confirm","",true,eligible.is_empty() or eligible.size()!=ui.gem_salvage_ids.size() or ui.meta.is_in_run())

static func results(ui) -> void:
	var lib=ui.meta.gems
	var panel=T.panel(ui.page,Rect2(104,208,1392,632),true)
	T.label(panel,"宝石已收入背包",Rect2(28,12,900,48),30,T.GOLD)
	for index in ui.gem_results.size():
		var gem: Dictionary=ui.gem_results[index]
		var card=T.panel(panel,Rect2(28+(index%5)*270,80+floori(index/5.0)*220,256,204))
		picture(card,gem,Rect2(14,12,46,46))
		T.paragraph(card,lib.title(gem),Rect2(68,10,174,54),19,COLORS.get(gem.rarity,T.TEXT))
		T.paragraph(card,lib.affix_text(gem),Rect2(14,74,228,100),17,T.TEXT)
		T.label(card,"#%d · %s"%[int(gem.serial),lib.rules.rarity_names.get(gem.rarity,gem.rarity)],Rect2(14,174,228,24),16,COLORS.get(gem.rarity,T.TEXT))
	ui.btn(panel,"查看宝石背包",Rect2(1010,560,354,48),"gem_results_close","",true)

static func rules_page(ui) -> void:
	var lib=ui.meta.gems
	var r: Dictionary=lib.rules
	var panel=T.panel(ui.page,Rect2(168,228,1264,600),true)
	T.label(panel,"宝石规则",Rect2(32,16,480,48),30,T.GOLD)
	var text: String="四个槽位不限制品质，同一枚宝石只能占一个槽。\n金色宝石＝一个特殊效果＋三条属性；三条属性不分主副，全部按档位随机。\n\n品质概率：绿%s%%／蓝%s%%／紫%s%%／金%s%%。\n紫色保底 %d 抽内；金色硬保底 %d 抽内。\n档位Ⅰ／Ⅱ／Ⅲ：%s%%／%s%%／%s%%。\n\n金色宝石可以同时装备多枚；同名效果只让槽位最靠前的一枚生效，其余仍提供属性。\n\n精粹重洗：全洗 %d 精粹，每固定一项 +%d，最多固定 %d 项。\n分解产出：绿%d／蓝%d／紫%d／金%d 精粹。\n累计真实清房达里程可领一次性精粹。"%[
		r.base_weights.green,r.base_weights.blue,r.base_weights.purple,r.gold_weight,
		int(r.pity.purple_or_better),int(r.pity.gold),
		r.tier_weights[0],r.tier_weights[1],r.tier_weights[2],
		int(r.reforge.base),int(r.reforge.per_lock),int(r.reforge.max_locks),
		int(r.salvage_yields.green),int(r.salvage_yields.blue),int(r.salvage_yields.purple),int(r.salvage_yields.gold)]
	T.paragraph(panel,text,Rect2(34,90,1196,440),20,T.TEXT)
	ui.btn(panel,"返回宝石",Rect2(916,546,312,48),"gem_rules_close","",true)
