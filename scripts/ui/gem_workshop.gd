extends RefCounted
## Requests only. Account transactions own fees, rolls, unlocks and equipment.
const T = preload("res://scripts/ui/atelier_theme.gd")
const Work = preload("res://scripts/ui/gem_workshop_actions.gd")
const Icon = preload("res://scripts/ui/gem_icon.gd")
const COLORS = Icon.RARITY_COLORS
const PAGE_SIZE = 6
const CORE_HINTS = {
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

static func core_picture(parent: Node, id: String, rect: Rect2):
	return picture(parent,{"core":id,"rarity":"gold"},rect)

static func build(ui) -> void:
	var state: Dictionary=ui.meta.get_state().gem_state
	if not state.pending_reforge.is_empty():
		Work.compare(ui)
		return
	if not ui.gem_tool.is_empty():
		match ui.gem_tool:
			"salvage": Work.salvage(ui)
			"retype": Work.retype(ui)
			_: Work.reforge(ui)
		return
	if ui.gem_show_rules:
		rules_page(ui)
		return
	if not ui.gem_results.is_empty():
		results(ui)
		return
	for index in 3:
		var id: String=["cores","attributes","craft"][index]
		ui.btn(ui.page,["核心目录","属性宝石","制作与起始石"][index],Rect2(54+index*250,198,234,46),"gem_tab",id,ui.gem_tab==id).add_theme_font_size_override("font_size",21)
	ui.btn(ui.page,"规则与概率",Rect2(826,198,220,46),"gem_rules").add_theme_font_size_override("font_size",20)
	T.label(ui.page,"宝石精粹  %d" % int(state.essence),Rect2(1120,198,424,46),24,T.CYAN)
	equipment(ui,state)
	match ui.gem_tab:
		"cores": cores(ui,state)
		"craft": Work.craft(ui)
		_: attributes(ui,state)

static func equipment(ui,state: Dictionary) -> void:
	var lib=ui.meta.gems
	var left=T.panel(ui.page,Rect2(54,260,330,580))
	T.label(left,"出发装备",Rect2(18,12,292,38),25,T.GOLD)
	for index in 4:
		var gem: Dictionary=lib.find(state,str(state.slots[index]))
		var y: float=60+index*84
		T.label(left,"核心" if index==0 else "属性槽 %d"%index,Rect2(18,y,226,24),16,T.GOLD if index==0 else T.MUTED)
		var b=ui.btn(left,lib.title(gem),Rect2(14,y+25,234,50),"gem_select",str(gem.get("id","")))
		b.add_theme_font_size_override("font_size",18)
		b.tooltip_text=lib.affix_text(gem)+("\n"+lib.core_description(str(gem.core)) if not str(gem.get("core","")).is_empty() else "")
		ui.btn(left,"卸下",Rect2(256,y+25,60,50),"gem_equip","%d:"%index,false,ui.meta.is_in_run() or gem.is_empty()).add_theme_font_size_override("font_size",17)
	var values: Dictionary=ui.meta.get_preview_stats()
	T.label(left,"出发属性",Rect2(18,410,292,30),20,T.GOLD)
	T.paragraph(left,"生命 %s    护盾 %s\n攻击 %s    防御 %s\n暴击 %s%%  ·  暴伤 %s倍\n冷却 %s%%  ·  移速 +%s%%"%[ui.number(values.health),ui.number(values.shield),ui.number(values.attack),ui.number(values.get("defense",0)),ui.number(float(values.crit_rate)*100),ui.number(values.crit_multiplier),ui.number(float(values.get("cdr",0))*100),ui.number(float(values.get("speed",0))*100)],Rect2(18,448,292,116),18,T.TEXT)

static func cores(ui,state: Dictionary) -> void:
	var lib=ui.meta.gems
	var selected: String=ui.selected.trim_prefix("core:")
	if selected not in Icon.CORE_IDS: selected=str(lib.core_id(state)) if not str(lib.core_id(state)).is_empty() else Icon.CORE_IDS[0]
	for index in Icon.CORE_IDS.size():
		var id: String=Icon.CORE_IDS[index]
		var owned: bool=id in state.get("unlocked_cores",[])
		var equipped: bool=str(state.slots[0])=="core:"+id
		var rect=Rect2(408+(index%2)*330,260+floori(index/2.0)*116,310,104)
		var b=ui.btn(ui.page,"%s\n%s"%[lib.core_rule(id).name,"已装备" if equipped else ("已解锁" if owned else "未解锁")],rect,"gem_select","core:"+id,selected==id)
		b.set_meta("core_id",id)
		b.set_meta("selection_id","core:"+id)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size",20)
		for key in ["normal","hover","pressed","disabled"]:
			var style=b.get_theme_stylebox(key).duplicate()
			style.content_margin_left=82
			style.content_margin_right=8
			b.add_theme_stylebox_override(key,style)
		core_picture(b,id,Rect2(8,20,64,64))
	var right=T.panel(ui.page,Rect2(1084,260,460,580),true)
	core_picture(right,selected,Rect2(16,16,82,82))
	T.label(right,str(lib.core_rule(selected).name),Rect2(110,20,328,42),28,Icon.tint_for(selected))
	T.label(right,"固定机制 · 无随机词条 · 无等级",Rect2(110,65,328,28),17,T.MUTED)
	T.paragraph(right,lib.core_description(selected),Rect2(22,116,416,224),19,T.TEXT)
	T.paragraph(right,CORE_HINTS.get(selected,""),Rect2(22,346,416,76),18,T.CYAN)
	var owned: bool=selected in state.get("unlocked_cores",[])
	var equipped: bool=str(state.slots[0])=="core:"+selected
	var free: bool=not bool(state.get("core_claimed",false))
	var credit: bool=int(state.get("core_choice_credits",0))>0
	var cost: int=int(lib.rules.core_unlock_cost)
	T.paragraph(right,"核心永久解锁，局外免费更换。\n%s · 自选权益%d次\n出发后装备锁定。"%["首次免费尚未领取" if free else "首次免费已领取",int(state.get("core_choice_credits",0))],Rect2(22,424,416,72),18,T.MUTED)
	var caption: String="已装备" if equipped else ("装备核心" if owned else ("首次免费解锁" if free else ("使用自选权益解锁" if credit else "解锁核心 · %d魔尘"%cost)))
	ui.btn(right,caption,Rect2(22,510,416,52),"gem_core_equip" if owned else "gem_core_unlock",selected,true,equipped or ui.meta.is_in_run() or (not owned and not free and not credit and int(ui.meta.get_state().dust)<cost)).add_theme_font_size_override("font_size",21)

static func attributes(ui,state: Dictionary) -> void:
	var lib=ui.meta.gems
	var locked: bool=ui.meta.is_in_run()
	var cost: int=int(lib.rules.draw_cost)
	var draw=T.panel(ui.page,Rect2(408,260,640,104))
	ui.btn(draw,"抽取一次 · %d魔尘"%cost,Rect2(14,12,294,48),"gem_draw","1",true,locked or int(ui.meta.get_state().dust)<cost).add_theme_font_size_override("font_size",21)
	ui.btn(draw,"连续十次 · %d魔尘"%(cost*10),Rect2(322,12,304,48),"gem_draw","10",false,locked or int(ui.meta.get_state().dust)<cost*10).add_theme_font_size_override("font_size",21)
	T.label(draw,"紫色至多%d抽 · 核心不进入随机池"%maxi(1,int(lib.rules.pity.purple_or_better)-int(state.rare_misses)),Rect2(16,66,608,28),18,T.MUTED)
	T.label(ui.page,"属性背包 · %d枚"%state.inventory.size(),Rect2(408,370,400,34),23)
	var inventory: Array=state.inventory.duplicate(true)
	inventory.reverse()
	ui.gem_page=clampi(ui.gem_page,0,maxi(0,ceili(float(inventory.size())/PAGE_SIZE)-1))
	for row in mini(PAGE_SIZE,inventory.size()-ui.gem_page*PAGE_SIZE):
		var gem: Dictionary=inventory[ui.gem_page*PAGE_SIZE+row]
		var y: float=412+row*58
		var slot: int=state.slots.find(gem.id)
		var text: String=lib.title(gem)+( " · 已锁" if bool(gem.locked) else "")+(" · 槽%d"%slot if slot>0 else "")
		var b=ui.btn(ui.page,text,Rect2(462,y,586,50),"gem_select",str(gem.id),ui.selected==str(gem.id))
		b.add_theme_font_size_override("font_size",19)
		b.set_meta("selection_id",str(gem.id))
		b.tooltip_text=lib.affix_text(gem)
		picture(ui.page,gem,Rect2(408,y,48,48))
	if inventory.is_empty(): T.paragraph(ui.page,"先到“制作与起始石”自选三枚绿石，\n也可用魔尘抽取属性宝石。",Rect2(430,454,596,112),22)
	ui.btn(ui.page,"‹",Rect2(408,766,66,48),"gem_page",str(ui.gem_page-1),false,ui.gem_page==0)
	T.label(ui.page,"%d / %d"%[ui.gem_page+1,maxi(1,ceili(float(inventory.size())/PAGE_SIZE))],Rect2(488,766,200,48),20)
	ui.btn(ui.page,"›",Rect2(690,766,66,48),"gem_page",str(ui.gem_page+1),false,(ui.gem_page+1)*PAGE_SIZE>=inventory.size())
	ui.btn(ui.page,"分解闲置绿蓝",Rect2(776,766,272,48),"gem_batch_preview","",false,locked).add_theme_font_size_override("font_size",19)
	detail(ui,lib.find(state,ui.selected),state)

static func detail(ui,gem: Dictionary,state: Dictionary) -> void:
	var lib=ui.meta.gems
	var p=T.panel(ui.page,Rect2(1084,260,460,580),true)
	if gem.is_empty() or str(gem.get("rarity",""))=="gold":
		T.label(p,"选择一枚属性石",Rect2(22,20,416,42),28)
		T.paragraph(p,"绿：一条主属性\n蓝：一主一副\n紫：一主两副\n\n每行分Ⅰ／Ⅱ／Ⅲ档。\n同颗属性类型不重复。\n\n起始石与定向制作可自选主类型。",Rect2(22,88,416,320),23,T.TEXT)
		return
	picture(p,gem,Rect2(18,16,78,78))
	T.paragraph(p,lib.title(gem),Rect2(108,22,330,72),26,COLORS.get(str(gem.rarity),T.TEXT))
	T.label(p,"%s · #%d"%[lib.rules.rarity_names.get(gem.rarity,gem.rarity),int(gem.serial)],Rect2(22,104,416,30),18,T.MUTED)
	T.paragraph(p,lib.affix_text(gem),Rect2(22,148,416,148),22,T.TEXT)
	var legacy: bool=gem.has("legacy_id") or str(gem.rarity)=="legacy"
	var transition: bool=str(gem.rarity)=="transition"
	T.paragraph(p,"旧属性与档位原值保留，可在培养页预览转换。" if transition else ("传承属性原值保留。" if legacy else "主属性决定方向，副属性支持搭配。升品保留原行与档位。"),Rect2(22,304,416,64),18,T.MUTED)
	for index in 3:
		var slot: int=index+1
		ui.btn(p,"属性槽 %d"%slot,Rect2(22+index*140,382,132,48),"gem_equip","%d:%s"%[slot,gem.id],str(state.slots[slot])==str(gem.id),ui.meta.is_in_run() or str(state.slots[slot])==str(gem.id)).add_theme_font_size_override("font_size",18)
	ui.btn(p,"培养／转换" if transition else "培养",Rect2(22,454,416,48),"gem_tool","reforge",true,ui.meta.is_in_run() or legacy).add_theme_font_size_override("font_size",21)
	ui.btn(p,"分解",Rect2(22,518,198,44),"gem_single_preview","",false,ui.meta.is_in_run() or legacy or bool(gem.locked) or str(gem.id) in state.slots).add_theme_font_size_override("font_size",20)
	ui.btn(p,"解锁" if bool(gem.locked) else "锁定",Rect2(236,518,202,44),"gem_lock",str(gem.id),false,ui.meta.is_in_run()).add_theme_font_size_override("font_size",20)

static func results(ui) -> void:
	var panel=T.panel(ui.page,Rect2(104,208,1392,632),true)
	T.label(panel,"属性宝石已收入背包",Rect2(28,12,900,48),30,T.GOLD)
	for index in ui.gem_results.size():
		var gem: Dictionary=ui.gem_results[index]
		var card=T.panel(panel,Rect2(28+(index%5)*270,80+floori(index/5.0)*220,256,204))
		picture(card,gem,Rect2(14,12,46,46))
		T.paragraph(card,ui.meta.gems.title(gem),Rect2(68,10,174,54),20,COLORS.get(gem.rarity,T.TEXT))
		T.paragraph(card,ui.meta.gems.affix_text(gem),Rect2(14,74,228,100),18,T.TEXT)
		T.label(card,"#%d · %s"%[int(gem.serial),ui.meta.gems.rules.rarity_names.get(gem.rarity,gem.rarity)],Rect2(14,174,228,24),16,COLORS.get(gem.rarity,T.TEXT))
	ui.btn(panel,"查看属性背包",Rect2(1010,560,354,48),"gem_results_close","",true)

static func rules_page(ui) -> void:
	var panel=T.panel(ui.page,Rect2(168,228,1264,600),true)
	var r: Dictionary=ui.meta.gems.rules
	T.label(panel,"宝石规则",Rect2(32,16,480,48),30,T.GOLD)
	ui.btn(panel,"获取与保障",Rect2(620,20,280,44),"gem_rules_section","draw",ui.gem_rules_section=="draw").add_theme_font_size_override("font_size",20)
	ui.btn(panel,"制作与培养",Rect2(924,20,304,44),"gem_rules_section","work",ui.gem_rules_section=="work").add_theme_font_size_override("font_size",20)
	var text: String
	if ui.gem_rules_section=="work":
		var w: Dictionary=r.workshop
		text="品质决定行数：绿一主、蓝一主一副、紫一主两副。核心独立解锁，没有等级与随机词条。\n制作绿／蓝／紫：%d／%d／%d精粹，自选主类型，所有行初始Ⅰ档。\n绿升蓝／蓝升紫：%d／%d，100%%成功，保留原行与档位；新副属性Ⅰ档。\n主属性提Ⅱ／Ⅲ：%d／%d；副属性提Ⅱ／Ⅲ：%d／%d，100%%成功。\n副类型随机重铸%d精粹，旧新二选一；定向重塑%d精粹，确定得到合法类型，两者均保档。\n随机重铸生成候选即扣费，保留旧结果也消耗；关闭重启仍是同一候选。\n分解绿／蓝／紫获得%d／%d／%d精粹，不额外返还培养投入。\n装备中或锁定的石不能分解；锁定后不能培养。\n旧过渡石保留原数值，可先预览再自愿转换；传承石保持原规则。\n所有工坊操作不推进抽取保底，出发后本局不可调整。"%[w.craft_costs.green,w.craft_costs.blue,w.craft_costs.purple,w.upgrade_costs.green,w.upgrade_costs.blue,w.main_tier_costs[0],w.main_tier_costs[1],w.side_tier_costs[0],w.side_tier_costs[1],w.random_retype_cost,w.direct_retype_cost,w.salvage_yields.green,w.salvage_yields.blue,w.salvage_yields.purple]
	else:
		var odds: PackedStringArray=[]
		for rarity in ["green","blue","purple"]: odds.append("%s%s%%"%[r.rarity_names[rarity],r.base_weights[rarity]])
		text="核心首枚免费自选，其余各%d魔尘定向解锁；已有核心局外免费更换，核心不进随机池。\n起始属性石可自选三枚绿Ⅰ主属性，允许相同类型。\n属性石每抽%d魔尘，十连%d；单抽与十连执行相同序列，不额外赠抽。\n基础概率：%s；连续%d抽无紫，下抽必紫，提前出紫立即重置。\n各行档位Ⅰ／Ⅱ／Ⅲ：%s%%／%s%%／%s%%；八种主属性等权，副类型排除主及同颗其他副属性。\n品质保底与随机进度跨关闭、重启保存；制作／升品不推进抽取保底。\n累计真实结算清房达到里程可领一次性精粹，领取情况见制作页。\n%d房清房结算：前%d房每房%d尘，之后每房%d尘；商店不计房。\n金币只用于本局，不能兑换魔尘或精粹。"%[r.core_unlock_cost,r.draw_cost,int(r.draw_cost)*10,"／".join(odds),int(r.pity.purple_or_better)-1,r.tier_weights[0],r.tier_weights[1],r.tier_weights[2],r.route_income.max_room,r.route_income.early_end,r.route_income.early_dust,r.route_income.later_dust]
	T.paragraph(panel,text,Rect2(34,90,1196,430),20,T.TEXT)
	ui.btn(panel,"返回宝石",Rect2(916,530,312,48),"gem_rules_close","",true)
