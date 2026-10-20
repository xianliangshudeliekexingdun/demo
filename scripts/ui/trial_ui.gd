extends "res://scripts/ui/game_ui.gd"
signal start_requested(count: int,short_run: bool,upgrades: Array)
signal pause_requested
signal resume_requested
signal menu_requested
signal reload_requested(count: int,upgrades: Array)
signal upgrade_chosen(id: String)
const Stats=preload("res://scripts/core/fireball_stats.gd")
var info: Label
var phase_text: Label
var mana_bar: ProgressBar
var chant_bar: ProgressBar
var cooldown_bar: ProgressBar
var window_bar: ProgressBar
var message: Label
var cfg: Dictionary = {}
var count_select: OptionButton
var checks: Array = []
var setup_stats: Label
var setup_owned: Array = []
var notice_until=0.0

func _ready():
	root=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme=Theme.new()
	var font=FontVariation.new()
	font.base_font=FONT
	font.variation_opentype={2003265652:500.0}
	theme.default_font=font
	theme.default_font_size=18
	root.theme=theme
	add_child(root)
	hud=Control.new()
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_art=HUD_ART.new()
	hud_art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(hud_art)
	health_label=label(hud,"",Vector2(112,84),14)
	label(hud,"法力",Vector2(34,120),15)
	mana_bar=bar(Vector2(80,122),Vector2(230,16),Color("69cbdc"))
	phase_text=label(hud,"",Vector2(408,25),23)
	chant_bar=bar(Vector2(410,60),Vector2(350,13),Color("ffc175"))
	label(hud,"闪避",Vector2(409,91),14)
	cooldown_bar=bar(Vector2(456,95),Vector2(145,10),Color("b8e3e5"))
	window_bar=bar(Vector2(620,95),Vector2(140,10),Color("9ff5ee"))
	info=label(hud,"",Vector2(1000,26),16)
	button(hud,"暂停 / 测试设置",Rect2(1020,76,232,42),func(): pause_requested.emit())
	message=label(hud,"",Vector2(430,125),18,Color("ffe0a1"))
	label(hud,"左键按住吟唱 · 松键释放    右键闪避 · 持续按住自动接续",Vector2(28,667),17)
	label(hud,"WASD 移动    Esc 暂停    F11 全屏",Vector2(28,693),14)
	var icon=TextureRect.new()
	var atlas=AtlasTexture.new()
	atlas.atlas=ICONS[0]
	atlas.region=ICON_REGIONS[0]
	icon.texture=atlas
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.position=Vector2(604,620)
	icon.size=Vector2(72,72)
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_child(icon)
	hud.hide()
func bar(pos: Vector2,dimensions: Vector2,color: Color) -> ProgressBar:
	var p=ProgressBar.new()
	p.position=pos
	p.size=dimensions
	p.max_value=1
	p.show_percentage=false
	p.mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("background",box(Color("213940"),5))
	p.add_theme_stylebox_override("fill",box(color,5))
	hud.add_child(p)
	return p
func show_trial_menu(error: String=""):
	hud.hide()
	new_overlay(.48)
	var p=panel(overlay,Rect2(325,100,630,535),Color("213940"))
	label(p,"火球术 · 战斗试验",Vector2(45,30),36)
	label(p,"吟唱与走位，抓住你的施法窗口。",Vector2(46,91),18)
	button(p,"自由测试  ·  敌人数与升级组合",Rect2(45,152,540,62),func(): show_setup(0,[],false),true).disabled=not error.is_empty() and cfg.is_empty()
	button(p,"短流程  ·  三场战斗与两次成长",Rect2(45,233,540,62),func(): start_requested.emit(1,true,[]),true).disabled=not error.is_empty() and cfg.is_empty()
	button(p,"重新读取数值表",Rect2(45,315,260,48),func(): reload_requested.emit(-1,[]))
	button(p,"返回原战斗菜单",Rect2(325,315,260,48),func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	label(p,"参数：data/fireball_trial.csv\n修改后重新加载。试验记录自动保存在 build/qa。",Vector2(46,389),16)
	if not error.is_empty(): label(p,error,Vector2(46,454),14,Color("ffb1a1"))
func show_setup(count: int,ids: Array,can_resume: bool):
	new_overlay(.62)
	var p=panel(overlay,Rect2(358,40,564,640),Color("213940"))
	label(p,"自由测试设置",Vector2(28,20),28)
	label(p,"敌人数",Vector2(28,72),17)
	count_select=OptionButton.new()
	count_select.position=Vector2(140,67)
	count_select.size=Vector2(150,38)
	for i in range(4): count_select.add_item(str(i)+" 只",i)
	count_select.select(count)
	p.add_child(count_select)
	checks.clear()
	setup_owned=ids.duplicate()
	for i in range(6):
		var cb=CheckBox.new()
		cb.text=Stats.NAMES[i]+" · "+(["普通","稀有","传说"][0 if i<3 else (1 if i<5 else 2)])
		cb.position=Vector2(28,125+i*47)
		cb.button_pressed=Stats.IDS[i] in ids
		cb.toggled.connect(func(on):
			if on: setup_owned.append(Stats.IDS[i])
			else: setup_owned.erase(Stats.IDS[i])
			update_setup_stats())
		p.add_child(cb)
		checks.append(cb)
	setup_stats=label(p,"",Vector2(28,421),17)
	update_setup_stats()
	button(p,"按设置重置试验",Rect2(28,494,245,48),func(): start_requested.emit(count_select.selected,false,setup_owned),true)
	button(p,"加载参数并重置",Rect2(290,494,245,48),func(): reload_requested.emit(count_select.selected,setup_owned))
	button(p,"继续当前试验" if can_resume else "返回",Rect2(28,555,245,45),func(): resume_requested.emit() if can_resume else show_trial_menu())
	button(p,"结束并返回",Rect2(290,555,245,45),func(): menu_requested.emit())
func update_setup_stats():
	if cfg.is_empty(): return
	var s=Stats.compute(cfg,setup_owned)
	setup_stats.text="有效吟唱 %.2fs · 消耗 %.1f · 半径 %.2fm\n基础伤害 %.1f · 固定飞行 %.2fs" % [s.chant,s.cost,s.radius,s.damage,cfg["fireball.flight_time"]]
func show_trial_pause(b):
	if not b.short_run:
		show_setup(b.enemy_count,b.owned,true)
		return
	new_overlay(.62)
	var p=panel(overlay,Rect2(425,235,430,250),Color("213940"))
	label(p,"试验已暂停",Vector2(95,30),30)
	button(p,"继续",Rect2(40,103,350,48),func(): resume_requested.emit(),true)
	button(p,"结束并返回",Rect2(40,173,350,42),func(): menu_requested.emit())
func show_choices(b):
	new_overlay(.68)
	label(overlay,"第 %d 场完成 · 选择这次的成长" % b.wave,Vector2(314,159),30)
	if b.choices.is_empty():
		button(overlay,"已取得全部升级，继续",Rect2(420,320,440,70),func(): upgrade_chosen.emit(""),true)
	for i in range(b.choices.size()):
		var id=b.choices[i]
		var x=130+i*345
		var p=panel(overlay,Rect2(x,235,320,290),Color("213940"))
		label(p,Stats.NAMES[Stats.IDS.find(id)],Vector2(25,30),25)
		var tier=Stats.TIERS[Stats.IDS.find(id)]
		label(p,{"common":"普通","rare":"稀有","legendary":"传说"}[tier],Vector2(25,72),14,Color("f1d79a"))
		label(p,Stats.description(id,b.cfg,b.owned),Vector2(25,101),17)
		button(p,"选择",Rect2(25,215,270,50),func(): upgrade_chosen.emit(id),true)
func show_trial_result(b):
	new_overlay(.65)
	var p=panel(overlay,Rect2(360,170,560,360),Color("213940"))
	label(p,"试验完成" if b.result=="success" else ("剩余升级权重为零" if b.result=="config_error" else "再试一次"),Vector2(110,28),30)
	label(p,"释放 %d · 命中 %d · 受击 %d\n接续 %d / %d · 输出伤害 %.1f\n本次记录已保存到 build/qa/fireball-trial/sessions" % [b.summary.released,b.summary.hit_shots,b.summary.hits,b.summary.resumed,b.summary.attempts,b.summary.damage],Vector2(30,94),17)
	button(p,"重新开始",Rect2(30,221,245,54),func(): start_requested.emit(b.enemy_count,b.short_run,[]),true)
	button(p,"返回试验菜单",Rect2(290,221,240,54),func(): menu_requested.emit())
func refresh_trial(b):
	hud_art.ratio=b.player.health/b.cfg["player.health_max"]
	hud_art.selected=1
	hud_art.queue_redraw()
	health_label.text="%.0f / %.0f" % [b.player.health,b.cfg["player.health_max"]]
	mana_bar.value=b.player.mana/b.cfg["mana.max"]
	mana_bar.tooltip_text="法力 %.1f / %.1f" % [b.player.mana,b.cfg["mana.max"]]
	var s=b.stats()
	var names={"idle":"按住左键 · 开始吟唱","chanting":"吟唱中","ready":"就绪 · 松键释放","charging_molten":"火球就绪 · 继续蓄力强化","ready_molten":"熔核就绪 · 松键释放","dodging":"闪避中","resume_window":"接续窗口 · 重新按住左键"}
	phase_text.text=names.get(b.phase,b.phase)
	chant_bar.value=b.extra/s.extra_chant if b.phase in ["charging_molten","ready_molten"] else b.chant/s.chant
	cooldown_bar.value=1-clampf((b.dodge_until-b.elapsed)/b.cfg["dodge.cooldown"],0,1)
	window_bar.value=clampf((b.window_end-b.elapsed)/b.cfg["dodge.resume_window"],0,1) if b.phase=="resume_window" else 0
	info.text=("第 %d / 3 场" % b.wave if b.short_run else "自由测试 · %d 敌人" % b.enemy_count)+"\n法力 %.1f / %.0f" % [b.player.mana,b.cfg["mana.max"]]
	if Time.get_ticks_msec()/1000.0>notice_until: message.text="超出射程 · 落点已限制" if b.range_clamped and b.phase!="idle" else ""
func notify(text: String):
	message.text=text
	notice_until=Time.get_ticks_msec()/1000.0+1.2
