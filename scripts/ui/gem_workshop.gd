extends RefCounted
## Read-only UI. Every draw/equipment request is committed by meta progression.
const T = preload("res://scripts/ui/atelier_theme.gd")
const Work = preload("res://scripts/ui/gem_workshop_actions.gd")
const COLORS = {"green": Color("91d4ae"), "blue": Color("89c9f2"), "purple": Color("d1abed"), "gold": Color("edd08b"), "legacy": Color("b7c6ce")}
const PAGE_SIZE = 6

static func build(ui) -> void:
	if not ui.meta.get_state().gem_state.pending_reforge.is_empty():
		Work.compare(ui)
		return
	if not ui.gem_tool.is_empty():
		if ui.gem_tool == "salvage": Work.salvage(ui)
		else: Work.reforge(ui)
		return
	if ui.gem_show_rules:
		rules_page(ui)
		return
	if not ui.gem_results.is_empty():
		results(ui)
		return
	var state: Dictionary = ui.meta.get_state().gem_state
	var lib = ui.meta.gems
	T.label(ui.page, "四槽普通词条同时生效，金色特效由核心槽激活。", Rect2(54, 198, 1040, 38), 21)
	T.label(ui.page, "宝石精粹  %d" % int(state.essence), Rect2(1210,198,334,38), 24, T.CYAN)
	var left = T.panel(ui.page, Rect2(54, 252, 420, 564))
	T.label(left, "本次装备", Rect2(22, 14, 300, 40), 26, T.GOLD)
	for index in 4:
		var gem: Dictionary = lib.find(state, str(state.slots[index]))
		var y: float = 66.0 + index * 82.0
		var title: String = "核心槽" if index == 0 else "副槽 %d" % index
		T.label(left, title, Rect2(18, y, 90, 28), 18, T.GOLD if index == 0 else T.MUTED)
		var select = ui.btn(left, lib.title(gem), Rect2(106, y, 220, 54), "gem_select", str(gem.get("id", "")))
		select.add_theme_font_size_override("font_size", 18)
		select.tooltip_text = lib.title(gem) + "\n" + lib.affix_text(gem)
		ui.btn(left, "卸下", Rect2(334, y, 68, 54), "gem_equip", "%d:" % index, false, gem.is_empty()).add_theme_font_size_override("font_size", 18)
		if not gem.is_empty() and str(gem.rarity) == "gold":
			T.label(left, "特效已激活" if index == 0 else "仅普通词条 · 特效未激活", Rect2(110, y + 54, 290, 24), 15, T.GOLD if index == 0 else T.MUTED)
	var values: Dictionary = ui.meta.get_preview_stats()
	T.label(left, "出发属性", Rect2(22, 414, 360, 30), 20, T.GOLD)
	T.paragraph(left, "生命 %s    护盾 %s    攻击 %s\n防御 %s    暴击 %s%%    暴伤 %s倍\n冷却缩减 %s%%    战斗移速 +%s%%" % [ui.number(values.health), ui.number(values.shield), ui.number(values.attack), ui.number(values.get("defense", 0)), ui.number(float(values.crit_rate)*100.0), ui.number(values.crit_multiplier), ui.number(float(values.get("cdr", 0))*100.0), ui.number(float(values.get("speed", 0))*100.0)], Rect2(22, 450, 382, 100), 18, T.TEXT)
	var draw = T.panel(ui.page, Rect2(498, 252, 512, 128))
	var locked: bool = ui.meta.is_in_run()
	var cost: int = int(lib.rules.draw_cost)
	ui.btn(draw, "抽取一次 · %d魔尘" % cost, Rect2(18, 14, 228, 50), "gem_draw", "1", true, locked or int(ui.meta.get_state().dust) < cost)
	ui.btn(draw, "连续十次 · %d魔尘" % (cost*10), Rect2(260, 14, 234, 50), "gem_draw", "10", false, locked or int(ui.meta.get_state().dust) < cost*10)
	var remaining: int = (int(lib.rules.pity.first_gold) if bool(state.first_gold) else int(lib.rules.pity.gold_hard)) - int(state.gold_misses)
	T.label(draw, "%s至多%d抽 · 下抽金率%s%%" % ["首金" if bool(state.first_gold) else "金色", remaining, ui.number(lib.gold_probability(state)*100.0)], Rect2(18, 70, 476, 26), 18, T.GOLD)
	T.label(draw, "紫或金至多%d抽 · 保底持续保存" % (int(lib.rules.pity.purple_or_better)-int(state.rare_misses)), Rect2(18, 98, 476, 24), 16, T.MUTED)
	T.label(ui.page, "宝石背包  ·  %d枚" % state.inventory.size(), Rect2(498, 392, 250, 36), 24)
	ui.btn(ui.page, "全部", Rect2(770, 392, 108, 38), "gem_filter", "all", ui.gem_filter == "all").add_theme_font_size_override("font_size", 18)
	ui.btn(ui.page, "金色", Rect2(890, 392, 120, 38), "gem_filter", "gold", ui.gem_filter == "gold").add_theme_font_size_override("font_size", 18)
	var inventory: Array = state.inventory.duplicate(true)
	inventory.reverse()
	if ui.gem_filter == "gold": inventory = inventory.filter(func(gem): return gem.rarity == "gold")
	ui.gem_page = clampi(int(ui.gem_page), 0, maxi(0, ceili(float(inventory.size())/PAGE_SIZE)-1))
	for row in mini(PAGE_SIZE, inventory.size() - ui.gem_page*PAGE_SIZE):
		var gem: Dictionary = inventory[ui.gem_page*PAGE_SIZE+row]
		var slot: int = state.slots.find(gem.id)
		var name: String = lib.title(gem) + "  #%d" % int(gem.serial)
		if bool(gem.locked): name += " · 已锁"
		if slot >= 0: name += " · " + ("核心" if slot == 0 else "副%d" % slot)
		var button = ui.btn(ui.page, name, Rect2(498, 442+row*49, 512, 42), "gem_select", str(gem.id), ui.selected == gem.id)
		button.add_theme_font_size_override("font_size", 18)
		button.set_meta("selection_id", gem.id)
		button.tooltip_text = lib.affix_text(gem)
		if ui.selected != gem.id: button.add_theme_color_override("font_color", COLORS[gem.rarity])
	if inventory.is_empty(): T.paragraph(ui.page, "背包还没有宝石。\n完成战斗房获得魔尘，返回这里抽取。", Rect2(516, 468, 460, 100), 21)
	ui.btn(ui.page, "‹", Rect2(498, 750, 66, 44), "gem_page", str(ui.gem_page-1), false, ui.gem_page <= 0)
	T.label(ui.page, "%d / %d" % [ui.gem_page+1, maxi(1, ceili(float(inventory.size())/PAGE_SIZE))], Rect2(586, 750, 330, 44), 20)
	ui.btn(ui.page, "›", Rect2(944, 750, 66, 44), "gem_page", str(ui.gem_page+1), false, (ui.gem_page+1)*PAGE_SIZE >= inventory.size())
	ui.btn(ui.page, "规则与概率", Rect2(498,800,244,40), "gem_rules").add_theme_font_size_override("font_size",18)
	ui.btn(ui.page, "分解闲置绿蓝", Rect2(758,800,252,40), "gem_batch_preview", "", false, locked).add_theme_font_size_override("font_size",18)
	detail(ui, lib.find(state, ui.selected), state)

static func detail(ui, gem: Dictionary, state: Dictionary) -> void:
	var lib = ui.meta.gems
	var right = T.panel(ui.page, Rect2(1034, 252, 512, 588), true)
	if gem.is_empty():
		T.label(right, "选择一枚宝石", Rect2(26, 20, 460, 46), 28)
		if not bool(ui.meta.get_state().free_claimed.gem):
			T.paragraph(right, "原有的首次免费宝石仍可领取一枚。\n领取不消耗抽取次数或首金保障。", Rect2(26, 88, 460, 92), 20)
			for index in 3:
				var id: String = ["MG01", "MG02", "MG03"][index]
				var item: Dictionary = ui.meta.get_item_status("gem", id)
				var text: String = "%s · 免费领取" % str(item.name)
				ui.btn(right, text, Rect2(26, 200+index*66, 460, 50), "gem_starter", id, false, ui.meta.is_in_run())
		else: T.paragraph(right, "在背包中选择宝石查看词条，\n再选择要装入的核心槽或副槽。\n\n所有品质均可放入四个槽位。", Rect2(26, 100, 460, 180), 21)
	else:
		var color: Color = COLORS[gem.rarity]
		ui.equipment_picture(right, str(gem.get("legacy_id", "MG02")), Rect2(20, 16, 76, 76))
		T.paragraph(right, lib.title(gem), Rect2(112, 22, 370, 76), 27, color)
		T.label(right, str(lib.rules.rarity_names[gem.rarity]) + " · #%d" % int(gem.serial), Rect2(28, 98, 450, 30), 18, color)
		T.paragraph(right, lib.affix_text(gem), Rect2(28, 134, 456, 112), 21, T.TEXT)
		var slot: int = state.slots.find(gem.id)
		if str(gem.rarity) == "gold":
			T.label(right, "核心特效 · " + ("已激活" if slot == 0 else "装入核心槽后激活"), Rect2(28, 250, 456, 34), 20, T.GOLD)
			T.paragraph(right, lib.core_description(str(gem.core)), Rect2(28, 292, 456, 145), 18, T.TEXT)
		elif gem.has("legacy_id"):
			T.paragraph(right, "传承宝石保留旧版已获得的属性；\n旧版付费升级已关闭。", Rect2(28, 270, 456, 100), 19)
		else: T.paragraph(right, "普通词条在核心槽和副槽均生效。\n金色宝石才有流派特效。", Rect2(28, 270, 456, 100), 19)
		for index in 4:
			ui.btn(right, "装入核心" if index == 0 else "装入副槽 %d" % index, Rect2(28+(index%2)*236, 438+floori(index/2.0)*56, 220, 48), "gem_equip", "%d:%s" % [index, gem.id], slot == index, ui.meta.is_in_run() or slot == index).add_theme_font_size_override("font_size", 19)
		var entries:Array=[["改良","gem_tool","reforge"],["分解","gem_single_preview",""],["解锁" if bool(gem.locked) else "锁定","gem_lock",str(gem.id)]]
		for index in entries.size():
			var entry:Array=entries[index]
			ui.btn(right,entry[0],Rect2(28+index*156,548,144,40),entry[1],entry[2],false,ui.meta.is_in_run() or (gem.has("legacy_id") and index<2)).add_theme_font_size_override("font_size",18)

static func results(ui) -> void:
	var panel = T.panel(ui.page, Rect2(104, 208, 1392, 616), true)
	T.label(panel, "宝石已收入背包", Rect2(28, 12, 900, 48), 30, T.GOLD)
	for index in ui.gem_results.size():
		var gem: Dictionary = ui.gem_results[index]
		var card = T.panel(panel, Rect2(28+(index%5)*270, 80+floori(index/5.0)*220, 256, 204))
		card.add_theme_stylebox_override("panel", T.box(T.PANEL, COLORS[gem.rarity], 2))
		T.paragraph(card, ui.meta.gems.title(gem), Rect2(14, 10, 228, 54), 21, COLORS[gem.rarity])
		T.paragraph(card, ui.meta.gems.affix_text(gem), Rect2(14, 74, 228, 94), 18, T.TEXT)
		T.label(card, "金色特效 · 核心槽激活" if gem.rarity == "gold" else "#%d · %s" % [int(gem.serial), ui.meta.gems.rules.rarity_names[gem.rarity]], Rect2(14, 172, 228, 24), 16, COLORS[gem.rarity])
	ui.btn(panel, "查看背包", Rect2(1010, 548, 354, 48), "gem_results_close", "", true)

static func rules_page(ui) -> void:
	var panel = T.panel(ui.page, Rect2(168, 228, 1264, 600), true)
	var r:Dictionary=ui.meta.gems.rules
	T.label(panel, "宝石规则", Rect2(32, 16, 480, 48), 30, T.GOLD)
	ui.btn(panel,"抽取与保底",Rect2(620,20,280,44),"gem_rules_section","draw",ui.gem_rules_section=="draw").add_theme_font_size_override("font_size",20)
	ui.btn(panel,"分解与改良",Rect2(924,20,304,44),"gem_rules_section","work",ui.gem_rules_section=="work").add_theme_font_size_override("font_size",20)
	var text:String
	if ui.gem_rules_section=="work":
		text="普通词条分I／II／III档，各品质共用三档数值，抽到概率为%s%%／%s%%／%s%%。\n品质只限制普通词条数量：绿1／蓝2／紫3／金3；金色额外带一个核心。\n分解收益：绿%d／蓝%d／紫%d／金%d宝石精粹；魔尘继续用于抽取。\n普通改良每次：绿%d／蓝%d／紫%d／金%d精粹。金色核心重洗每次%d精粹。\n选择的普通词条会重新随机类型和档位，其余位置不变；不会与另两条类型重复。\n核心重洗从其余七种核心等权随机，不会得到当前核心；不提供指定兑换或目标保底。\n候选不会与旧结果完全相同；可保留旧结果，费用照常消耗。\n生成候选、扣费和随机进度一并保存；关闭或重启后仍是同一候选。\n已装备、锁定和传承宝石不可分解；分解预览确认后整批结算。\n“分解闲置绿蓝”只处理未装备、未锁定的绿色和蓝色，不包含紫色和金色。\n已装备的宝石可改良，改良不改变槽位；锁定宝石须先解锁。\n分解和改良均不推进抽取品质保底，本局出发后不能调整宝石。" % [r.tier_weights[0],r.tier_weights[1],r.tier_weights[2],r.workshop.salvage_yields.green,r.workshop.salvage_yields.blue,r.workshop.salvage_yields.purple,r.workshop.salvage_yields.gold,r.workshop.affix_costs.green,r.workshop.affix_costs.blue,r.workshop.affix_costs.purple,r.workshop.affix_costs.gold,r.workshop.core_cost]
	else:
		var odds:PackedStringArray=[]
		for rarity in ["green","blue","purple","gold"]:odds.append("%s%s%%" % [r.rarity_names[rarity],r.base_weights[rarity]])
		text="每次%d魔尘；连续十次%d魔尘，逐次结算同一组保底。\n基础品质概率：%s。\n普通词条八种等权，同一宝石不重复；金色核心八种等权，允许重复。\n连续%d次未出紫或金，下次必为紫或金；紫和金都会重置这项计数。\n首颗金色最多%d抽；提前获得即完成首金保障，之后使用常规金保底。\n常规金：前%d抽为%s%%；第%d抽起每抽增加%s个百分点；第%d抽100%%。\n先判金色；未出金且小保底到期时给紫色。非金概率按基础权重同比缩减。\n金色重置两项计数，紫色只重置小保底。计数跨单抽、十次、返回和重启保存。\n下一抽金率和剩余保底次数以背包页为准。\n四个槽位均可装所有品质；只有核心槽激活金色特效。\n%d房按已清战斗房结算：前%d房每房%d尘，之后每房%d尘；商店不计。" % [r.draw_cost,int(r.draw_cost)*10,"／".join(odds),int(r.pity.purple_or_better)-1,r.pity.first_gold,int(r.pity.gold_soft_start)-1,r.base_weights.gold,r.pity.gold_soft_start,ui.number(float(r.pity.gold_soft_increment)*100),r.pity.gold_hard,r.route_income.max_room,r.route_income.early_end,r.route_income.early_dust,r.route_income.later_dust]
	T.paragraph(panel,text,Rect2(34,90,1196,430),20,T.TEXT)
	ui.btn(panel, "返回宝石", Rect2(916, 530, 312, 48), "gem_rules_close", "", true)
