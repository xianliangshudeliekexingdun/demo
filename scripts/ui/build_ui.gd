extends "res://scripts/ui/game_ui.gd"
signal flow_requested(slots: Array)
signal upgrade_chosen(id: String)
signal retry_requested
signal start_requested(count: int,multiplier: float,slots: Array)
signal reload_requested(count: int,multiplier: float,slots: Array)
signal pause_requested
signal resume_requested
signal menu_requested
const Catalog=preload("res://scripts/core/spell_catalog.gd")
const SpellStats=preload("res://scripts/core/spell_stats.gd")
var cfg: Dictionary={}
var presets: Dictionary={}
var wave_count=0
var setup_owned: Array=[]
var preset_name="none"
var upgrade_page=0
var upgrade_checks: Array=[]
var upgrade_notes: Array=[]
var choice_descriptions: Array=[]
var setup_body: Control
var upgrade_select: OptionButton
var preset_select: OptionButton
var build_count_text: Label
var setup_slots: Array=Catalog.IDS.duplicate()
var slot_selects: Array=[]
var count_select: OptionButton
var health_spin: SpinBox
var setup_info: Label
var phase_text: Label
var mana_text: Label
var mana_bar: ProgressBar
var chant_bar: ProgressBar
var cooldown_bar: ProgressBar
var info: Label
var effects_text: Label
var message: Label
var slots_ui: Array=[]
var notice_until=0.0
func _ready():
	root=Control.new()
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme=Theme.new()
	var readable_font=FontVariation.new()
	readable_font.base_font=FONT
	readable_font.variation_opentype={2003265652:500.0}
	theme.default_font=readable_font
	theme.default_font_size=18
	root.theme=theme
	add_child(root)
	hud=Control.new()
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(hud)
	hud_art=HUD_ART.new()
	hud_art.show_selection=false
	hud_art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(hud_art)
	health_label=label(hud,"",Vector2(112,84),14)
	mana_text=label(hud,"",Vector2(32,115),16,Color("a0e7f0"))
	mana_bar=make_bar(Vector2(32,144),Vector2(279,12),Color("69cbdc"))
	phase_text=label(hud,"",Vector2(410,25),22)
	chant_bar=make_bar(Vector2(410,60),Vector2(420,12),Color("ffc175"))
	cooldown_bar=make_bar(Vector2(457,97),Vector2(145,10),Color("b8e3e5"))
	label(hud,"闪避",Vector2(410,89),14)
	effects_text=label(hud,"",Vector2(620,88),15)
	info=label(hud,"",Vector2(996,24),16)
	button(hud,"暂停 / 自由设置",Rect2(1000,80,244,44),func(): pause_requested.emit())
	message=label(hud,"",Vector2(411,123),16,Color("ffe0a1"))
	for i in range(5):
		var p=panel(hud,Rect2(414+i*91,610,84,86),Color("213940"))
		var glyph=label(p,"",Vector2(28,1),22)
		var icon=preload("res://scripts/ui/build_fire_icon.gd").new()
		icon.position=Vector2(25,3)
		icon.size=Vector2(34,34)
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
		var shade=ColorRect.new()
		shade.position=Vector2(4,3)
		shade.size=Vector2(76,34)
		shade.color=Color(0.06,0.1,0.12,.78)
		shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
		p.add_child(shade)
		var timer=label(p,"",Vector2(4,5),19,Color("ffe0a1"))
		timer.size=Vector2(76,26)
		timer.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var l=label(p,"",Vector2(4,38),14)
		l.size=Vector2(76,43)
		l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		slots_ui.append({"panel":p,"label":l,"icon":icon,"glyph":glyph,"shade":shade,"timer":timer})
	label(hud,"左键按住吟唱 · 松键释放\n右键闪避 · 持续按住自动接续",Vector2(26,659),15)
	label(hud,"滚轮 / 1—5 切换法术\nWASD 移动 · Esc 暂停 · F11 全屏",Vector2(949,659),15)
	hud.hide()
func make_bar(pos: Vector2,dimensions: Vector2,color: Color) -> ProgressBar:
	var p=ProgressBar.new()
	p.position=pos
	p.size=dimensions
	p.max_value=1
	p.show_percentage=false
	p.mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("background",box(Color("213940"),4))
	p.add_theme_stylebox_override("fill",box(color,4))
	hud.add_child(p)
	return p
func show_setup(count: int,multiplier: float,order: Array,can_resume: bool,error: String=""):
	if not can_resume: hud.hide()
	new_overlay(.68)
	setup_slots=order.duplicate()
	var p=panel(overlay,Rect2(160,40,960,640),Color("213940"))
	label(p,"五法术构筑试验",Vector2(32,20),32)
	label(p,"阶段B · 五法术构筑    共享法力 / 独立冷却",Vector2(34,69),17,Color("bcd4ce"))
	label(p,"安排五个槽位",Vector2(32,116),23)
	slot_selects.clear()
	for i in range(5):
		label(p,str(i+1),Vector2(37,169+i*52),18)
		var opt=OptionButton.new()
		opt.position=Vector2(71,160+i*52)
		opt.size=Vector2(241,42)
		for id in Catalog.IDS: opt.add_item(Catalog.TITLES[id])
		opt.select(Catalog.IDS.find(setup_slots[i]))
		opt.item_selected.connect(func(index): swap_slot(i,index))
		p.add_child(opt)
		slot_selects.append(opt)
	label(p,"敌人数",Vector2(34,443),17)
	count_select=OptionButton.new()
	count_select.position=Vector2(112,434)
	count_select.size=Vector2(200,40)
	for i in range(7): count_select.add_item(str(i)+" 只")
	count_select.select(count)
	p.add_child(count_select)
	label(p,"生命倍率",Vector2(34,493),17)
	health_spin=SpinBox.new()
	health_spin.position=Vector2(137,482)
	health_spin.size=Vector2(175,40)
	health_spin.min_value=.1
	health_spin.max_value=10
	health_spin.step=.05
	health_spin.value=multiplier
	p.add_child(health_spin)
	setup_body=Control.new()
	setup_body.position=Vector2(362,112)
	setup_body.size=Vector2(560,416)
	setup_body.mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.add_child(setup_body)
	button(p,"法术参数",Rect2(362,111,164,38),func(): show_parameters())
	button(p,"专属升级",Rect2(540,111,164,38),func(): show_upgrades())
	button(p,"无升级",Rect2(718,111,200,38),func(): apply_preset("none"))
	show_parameters()
	var problem=label(p,error,Vector2(33,549),14,Color("ffb1a1"))
	problem.size=Vector2(890,30)
	problem.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(p,"按设置重置",Rect2(32,582,205,44),func(): start_requested.emit(count_select.selected,health_spin.value,setup_slots),true).disabled=cfg.is_empty()
	button(p,"加载参数并重置",Rect2(251,582,205,44),func(): reload_requested.emit(count_select.selected,health_spin.value,setup_slots))
	button(p,"继续当前试验" if can_resume else "返回主菜单",Rect2(470,582,205,44),func():
		if can_resume: resume_requested.emit()
		else: get_tree().change_scene_to_file("res://scenes/main.tscn"))
	button(p,"结束并返回" if can_resume else ("短流程 · %d场成长" % wave_count),Rect2(689,582,235,44),func():
		if can_resume: menu_requested.emit()
		else: flow_requested.emit(setup_slots))
func swap_slot(i: int,index: int):
	var other=setup_slots.find(Catalog.IDS[index])
	var old=setup_slots[i]
	setup_slots[i]=Catalog.IDS[index]
	setup_slots[other]=old
	slot_selects[other].select(Catalog.IDS.find(old))
	update_setup()
func clear_setup_body():
	for child in setup_body.get_children():
		setup_body.remove_child(child)
		child.queue_free()
	setup_info=null
	upgrade_checks.clear()
	upgrade_notes.clear()
func show_parameters():
	clear_setup_body()
	setup_info=label(setup_body,"",Vector2(0,50),17)
	update_setup()
	label(setup_body,"切换取消未释放进度；新星冻结需专属升级。\n自由测试可任意配置；短流程从零升级开始。\n暂停后的配置只有明确重置才生效。",Vector2(0,360),15,Color("bcd4ce"))
func apply_preset(name: String):
	preset_name=name
	setup_owned=Catalog.FUTURE_UPGRADES.duplicate() if name=="all" else ([] if name=="none" else presets[name].duplicate())
	show_upgrades()
func show_upgrades():
	clear_setup_body()
	upgrade_select=OptionButton.new()
	upgrade_select.position=Vector2(0,51)
	upgrade_select.size=Vector2(235,38)
	for id in Catalog.IDS: upgrade_select.add_item(Catalog.TITLES[id])
	upgrade_select.select(upgrade_page)
	upgrade_select.item_selected.connect(func(index):
		upgrade_page=index
		show_upgrades())
	setup_body.add_child(upgrade_select)
	preset_select=OptionButton.new()
	preset_select.position=Vector2(251,51)
	preset_select.size=Vector2(303,38)
	var keys=["none","frequency","control","sustain","all"]
	for name in ["无升级","频繁施法 · 8项","控场爆破 · 8项","持续压制 · 8项","全部30项 · 压力测试"]: preset_select.add_item(name)
	preset_select.select(maxi(0,keys.find(preset_name)))
	preset_select.item_selected.connect(func(index): apply_preset(keys[index]))
	setup_body.add_child(preset_select)
	for i in range(6):
		var id=Catalog.FUTURE_UPGRADES[upgrade_page*6+i]
		var cb=CheckBox.new()
		cb.text=Catalog.upgrade_name(id)+" · "+Catalog.TIER_NAMES[Catalog.tier(id)]
		cb.position=Vector2(0,98+i*47)
		cb.size=Vector2(552,26)
		cb.add_theme_font_size_override("font_size",17)
		cb.button_pressed=id in setup_owned
		cb.toggled.connect(func(on):
			if on and not id in setup_owned: setup_owned.append(id)
			elif not on: setup_owned.erase(id)
			preset_name="custom"
			update_upgrade_notes())
		setup_body.add_child(cb)
		upgrade_checks.append(cb)
		var note=label(setup_body,"",Vector2(30,125+i*47),13,Color("bcd4ce"))
		note.size=Vector2(525,23)
		upgrade_notes.append(note)
	build_count_text=label(setup_body,"",Vector2(0,390),15,Color("ffe0a1"))
	update_upgrade_notes()
func update_upgrade_notes():
	for i in range(upgrade_notes.size()):
		var id=Catalog.FUTURE_UPGRADES[upgrade_page*6+i]
		upgrade_notes[i].text=SpellStats.description(id,cfg,setup_owned) if not cfg.is_empty() else "参数无效"
	build_count_text.text="当前持有 %d 项 · 自由试验预设：%s" % [setup_owned.size(),{"none":"无升级","frequency":"频繁施法","control":"控场爆破","sustain":"持续压制","all":"全部30项","custom":"自定义"}.get(preset_name,"自定义")]
func update_setup():
	if not is_instance_valid(setup_info): return
	if cfg.is_empty():
		setup_info.text="参数尚未有效加载，请检查错误后重载。"
		return
	var text="当前构筑 · %d项专属升级\n\n" % setup_owned.size()
	for id in setup_slots:
		var st=SpellStats.compute(cfg,id,setup_owned)
		text+="%s   %.0f法力 / %.2f秒吟唱 / %s秒冷却\n%s\n" % [Catalog.TITLES[id],st.cost,st.chant,str(st.cooldown),Catalog.ROLES[id]]
	setup_info.text=text
func refresh_build(b):
	hud_art.ratio=b.player.health/b.cfg["player.health_max"]
	hud_art.queue_redraw()
	health_label.text="%.0f / %.0f" % [b.player.health,b.cfg["player.health_max"]]
	var s=b.stats()
	mana_text.text="法力 %.1f / %.0f    本次需要 %.0f" % [b.player.mana,b.cfg["mana.max"],s.cost]
	mana_bar.value=b.player.mana/b.cfg["mana.max"]
	var names={"idle":"按住吟唱","chanting":"吟唱中","ready":"就绪 · 松键释放","charging_molten":"熔核蓄力中 · 可松键普通释放","ready_molten":"熔核就绪 · 松键释放","dodging":"闪避中","resume_window":"接续窗口 · 再次按住"}
	phase_text.text=Catalog.TITLES[b.active_spell()]+" · "+names.get(b.phase,b.phase)
	if b.phase=="idle" and b.cooldown_remaining(b.active_spell())>0:
		phase_text.text="%s · 冷却中 %.1f秒" % [Catalog.TITLES[b.active_spell()],b.cooldown_remaining(b.active_spell())]
	chant_bar.value=b.extra/s.extra_chant if b.phase in ["charging_molten","ready_molten"] else b.chant/s.chant
	cooldown_bar.value=1-clampf((b.dodge_until-b.elapsed)/b.cfg["dodge.cooldown"],0,1)
	effects_text.text=("回春 %.1fs  " % maxf(0,b.healing.until-b.elapsed) if not b.healing.is_empty() else "")+("灯灵 %.1fs" % maxf(0,b.lamp.until-b.elapsed) if not b.lamp.is_empty() else "")
	if b.shield_total()>0: effects_text.text+="  盾 %.0f" % b.shield_total()
	info.text=("第%d / %d场" % [b.wave,b.layout.waves.size()] if b.short_run else "阶段B · 自由测试")+" · %d项升级\n存活 %d / %d    %.0fs" % [b.owned.size(),b.enemies.filter(func(e): return e.health>0).size(),b.enemy_count,b.elapsed]
	for i in range(5):
		var id=b.slots[i]
		var remaining=b.cooldown_remaining(id)
		slots_ui[i].shade.visible=remaining>0
		slots_ui[i].timer.text=("%.1fs" % minf(ceilf(remaining*10)/10,b.cfg[id+".cooldown"])) if remaining>0 else ""
		slots_ui[i].icon.visible=id=="fireball" and remaining==0
		slots_ui[i].glyph.visible=remaining==0
		slots_ui[i].glyph.text={"fireball":"","meteor":"陨","frost":"霜","rejuvenation":"春","lamp":"灵"}[id]
		slots_ui[i].glyph.add_theme_color_override("font_color",Color(Catalog.COLORS[id]))
		var st=box(Color("544662") if i==b.selected else Color("213940"),7)
		st.border_color=Color("f1d79a") if i==b.selected else Color("63817e")
		st.set_border_width_all(2 if i==b.selected else 1)
		slots_ui[i].panel.add_theme_stylebox_override("panel",st)
		slots_ui[i].label.text="%d %s\n%.0f法力" % [i+1,Catalog.TITLES[id],SpellStats.compute(b.cfg,id,b.owned).cost]
		slots_ui[i].label.add_theme_color_override("font_color",Color(Catalog.COLORS[id]) if i==b.selected else Color("d1d9d1"))
	if Time.get_ticks_msec()/1000.0>notice_until: message.text="松开左键后重新按住" if b.left_gate else ("落点超出射程，已限制" if b.range_clamped and b.phase!="idle" else "")
func notify(text: String):
	message.text=text
	notice_until=Time.get_ticks_msec()/1000.0+1.5
func clear_notice():
	message.text=""
	notice_until=0
func show_flow_pause(b):
	new_overlay(.68)
	var p=panel(overlay,Rect2(300,160,680,410),Color("213940"))
	label(p,"第%d场 · 已暂停" % b.wave,Vector2(40,28),30)
	var names=[]
	for id in b.owned: names.append(Catalog.TITLES[Catalog.upgrade_spell(id)]+" · "+Catalog.upgrade_name(id))
	var held=label(p,"",Vector2(40,84),16)
	held.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	held.size=Vector2(600,189)
	held.text="当前成长：\n"+("暂无升级" if names.is_empty() else "   /   ".join(names))
	button(p,"继续当前试验",Rect2(40,288,600,44),func(): resume_requested.emit(),true)
	button(p,"结束并返回",Rect2(40,348,600,42),func(): menu_requested.emit())
func show_build_choices(b):
	new_overlay(.72)
	choice_descriptions.clear()
	label(overlay,"第%d场完成 · 选择这次的成长" % b.wave,Vector2(240,121),30)
	label(overlay,"生命保留，法力恢复；下场开始前松开按键。",Vector2(242,171),17,Color("bcd4ce"))
	for i in range(b.choices.size()):
		var id=b.choices[i]
		var p=panel(overlay,Rect2(128+i*348,235,328,315),Color("213940"))
		label(p,Catalog.TITLES[Catalog.upgrade_spell(id)]+" · "+Catalog.TIER_NAMES[Catalog.tier(id)],Vector2(22,26),18,Color(Catalog.COLORS[Catalog.upgrade_spell(id)]))
		label(p,Catalog.upgrade_name(id),Vector2(22,72),26)
		var description=label(p,"",Vector2(22,128),17)
		description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		description.size=Vector2(284,112)
		description.text=SpellStats.description(id,b.cfg,b.owned).replace("；","\n").replace("，","\n").replace(" · ","\n")
		choice_descriptions.append(description)
		button(p,"选择此升级",Rect2(22,249,284,44),func(): upgrade_chosen.emit(id),true)
	if b.choices.is_empty(): button(overlay,"升级池已耗尽 · 继续",Rect2(400,300,480,60),func(): upgrade_chosen.emit(""),true)
func show_build_result(b):
	new_overlay(.68)
	var p=panel(overlay,Rect2(360,170,560,370),Color("213940"))
	label(p,"试验完成 · 构筑已记录" if b.result=="success" else ("参数错误 · 请重载" if b.result=="config_error" else "莉奈倒下了 · 再试一次"),Vector2(40,30),29)
	label(p,"伤害 %.1f · 治疗 %.1f · 释放 %d\n试验摘要保存到 build/qa/build-trial/sessions" % [b.summary.damage,b.heal_total,b.summary.released],Vector2(40,107),17)
	if b.result=="config_error":
		var error=label(p,b.reward_error,Vector2(40,166),14,Color("ffb1a1"))
		error.size=Vector2(480,43)
		error.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(p,"以相同设置重试",Rect2(40,221,480,48),func(): retry_requested.emit(),true)
	button(p,"返回试验设置",Rect2(40,282,480,44),func(): menu_requested.emit())
