extends CanvasLayer
signal requested(action: String, payload: String)
const T=preload("res://scripts/ui/atelier_theme.gd")
const TitleStage=preload("res://scripts/presentation/title_stage.gd")
const Art=preload("res://scripts/ui/atelier_art.gd")
const ArtifactIcon=preload("res://scripts/ui/artifact_icon.gd")
const EquipmentIcon=preload("res://scripts/ui/equipment_icon.gd")
const GemIcon=preload("res://scripts/ui/gem_icon.gd")
const GemWorkshop=preload("res://scripts/ui/gem_workshop.gd")
const RouteCatalog=preload("res://scripts/core/courtyard_route_catalog.gd")
const PREVIEWS=["opening","hud","reward","chest","shop","pause","result"]
const SCHOOLS=["fire","ice","lightning","wind","earth","spirit"]
const SPELL_FILTERS=["all","fire","ice","lightning","wind","earth","spirit"]
var root:Control
var page:Control
var screen="home"
var codex_tab="spells"
var meta
var catalog
var selected=""
var opening_spell="F01"
var route_school="fire"
var showcase
var title_stage
var detail_label:Label
var _rendered_screen=""
var _restore_focus=""
var _restore_id=""
var _list_scroll=0
var _artifact_scope="all"
var _spell_scope="all"
var preferences:Dictionary={}
var gem_results:Array=[]
var gem_show_rules=false
var gem_rules_section="draw"
var gem_filter="all"
var gem_page=0
var gem_tool=""
var gem_salvage_ids:Array=[]
var gem_tab="cores"
var gem_main_stat="attack"
var gem_craft_rarity="green"
var gem_line_index=1
var gem_retype_stat="shield"
var gem_reroll_locks:Array=[]

func _ready():
	root=Control.new()
	root.size=Vector2(1600,900)
	root.theme=T.make_theme()
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(root)

func emit(action:String,payload:String=""): requested.emit(action,payload)
func art(parent:Node,motif:String,rect:Rect2,tint:Color=T.GOLD,variant:int=0):
	var a=Art.new()
	a.motif=motif
	a.tint=tint
	a.variant=variant
	a.position=rect.position
	a.size=rect.size
	parent.add_child(a)
	return a
func btn(parent:Node,text:String,rect:Rect2,action:String,payload:String="",primary:bool=false,disabled:bool=false):
	var button=T.button(parent,text,rect,func(): emit(action,payload),primary,disabled)
	button.set_meta("ui_action",action)
	button.set_meta("ui_payload",payload)
	return button

func artifact_picture(parent:Node,id:String,rarity:String,rect:Rect2):
	var icon=ArtifactIcon.new()
	icon.set_item(id,rarity)
	icon.position=rect.position
	icon.size=rect.size
	parent.add_child(icon)
	return icon

func equipment_picture(parent:Node,id:String,rect:Rect2):
	var icon: Control
	if id.begins_with("core:") or id.begins_with("stat:"):
		icon=GemIcon.new()
		icon.item_id=id
		icon.rarity="gold" if id.begins_with("core:") else "green"
	elif id in T.Icon.PROCEDURAL_CATALYSTS:
		icon=T.Icon.new()
		icon.spell_id=id
		icon.tint=catalog.school_color(T.Icon.CATALYST_SCHOOLS[id])
	else:
		icon=EquipmentIcon.new()
		icon.set_item(id)
	icon.position=rect.position
	icon.size=rect.size
	parent.add_child(icon)
	return icon

func render(next:String,progress,content,picked:String="",message:String="",spell_id:String="F01"):
	_restore_focus=""
	_restore_id=""
	_list_scroll=0
	if is_instance_valid(page) and next==_rendered_screen:
		var focused=root.get_viewport().gui_get_focus_owner()
		if focused is Button:
			_restore_focus=focused.text
			_restore_id=str(focused.get_meta("selection_id",""))
		var old_list=page.get_node_or_null("CatalogList")
		if old_list!=null: _list_scroll=old_list.scroll_vertical
	_rendered_screen=next
	screen=next
	meta=progress
	catalog=content
	selected=picked
	opening_spell=spell_id
	detail_label=null
	if is_instance_valid(page):
		root.remove_child(page)
		page.queue_free()
	page=Control.new()
	page.size=root.size
	page.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(page)
	if screen=="home":
		home()
	else:
		if is_instance_valid(title_stage): title_stage.visible=false
		art(page,"background",Rect2(0,0,1600,900))
		header()
		match screen:
			"catalyst": equipment()
			"gem": GemWorkshop.build(self)
			"codex": codex()
			"prepare": prepare()
			"spells","artifacts": grimoire()
			"settings": settings()
			_: preview()
		footer()
	if not message.is_empty():
		if screen=="home":
			var note=T.panel(page,Rect2(340,754,920,44))
			var note_text=T.label(note,message,Rect2(16,0,888,44),18,T.WARN)
			note_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		else:
			var p=T.panel(page,Rect2(624,122,920,52))
			T.label(p,message,Rect2(20,0,880,52),20,T.GOLD)
	call_deferred("focus_first")
func focus_first():
	var buttons=page.find_children("*","Button",true,false)
	if not _restore_focus.is_empty():
		for b in buttons:
			if not b.disabled and b.text==_restore_focus and str(b.get_meta("selection_id",""))==_restore_id:
				b.grab_focus()
				return
	for b in buttons:
		if not b.disabled:
			b.grab_focus()
			return
func header():
	btn(page,"‹  返回",Rect2(48,30,128,48),"back")
	T.label(page,"莉奈大冒险  /  地下城",Rect2(204,30,600,48),22,T.GOLD)
	var wallet=T.panel(page,Rect2(1288,30,256,48))
	art(wallet,"gem",Rect2(10,4,40,40),T.CYAN)
	T.label(wallet,"魔尘   %s"%meta.get_state().get("dust",0),Rect2(62,0,182,48),21)
	var names={"catalyst":"法术触媒","gem":"魔法宝石","codex":"图鉴","prepare":"出发准备","spells":"法术藏书","artifacts":"宝物图鉴","settings":"设置"}
	T.label(page,"界面预览" if screen in PREVIEWS else names.get(screen,"地下城"),Rect2(52,108,550,68),40)
	bar(page,Rect2(54,181,64,2),T.GOLD)
	bar(page,Rect2(118,181,1426,1),Color(T.GOLD,.22))
	if screen in PREVIEWS: T.label(page,"界面预览 · 不进行战斗、购买或发放收益",Rect2(54,194,1400,34),20,T.MUTED)
func footer():
	T.label(page,"莉奈大冒险",Rect2(52,851,240,34),18,T.GOLD)
	T.label(page,"Tab 切换  ·  Enter 确认  ·  Esc 返回  ·  F11 全屏",Rect2(886,851,664,34),18,T.MUTED)
func add_showcase(rect:Rect2):
	showcase=load("res://scenes/ui/lina_showcase.tscn").instantiate()
	showcase.position=rect.position
	showcase.size=rect.size
	page.add_child(showcase)
	# Keyboard alternatives to the portrait's drag interaction.
	btn(page,"‹",Rect2(rect.position.x+80,rect.end.y-12,52,48),"rotate","-15")
	btn(page,"›",Rect2(rect.end.x-132,rect.end.y-12,52,48),"rotate","15")

func ensure_stage():
	if is_instance_valid(title_stage): return
	title_stage=TitleStage.new()
	title_stage.size=Vector2(1600,900)
	root.add_child(title_stage)
	root.move_child(title_stage,0)

func scrim(rect:Rect2,horizontal:bool,peak:float):
	var grad=Gradient.new()
	grad.offsets=PackedFloat32Array([0.0,0.55,1.0])
	grad.colors=[Color(0.02,0.022,0.03,peak),Color(0.02,0.022,0.03,peak*0.35),Color(0.02,0.022,0.03,0.0)]
	var tex=GradientTexture2D.new()
	tex.gradient=grad
	tex.width=64
	tex.height=64
	if horizontal:
		tex.fill_from=Vector2(0,0.5)
		tex.fill_to=Vector2(1,0.5)
	else:
		tex.fill_from=Vector2(0.5,1)
		tex.fill_to=Vector2(0.5,0)
	var node=TextureRect.new()
	node.texture=tex
	node.position=rect.position
	node.size=rect.size
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode=TextureRect.STRETCH_SCALE
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	page.add_child(node)
	return node

func title_tab(parent:Node,text:String,rect:Rect2,action:String,payload:String=""):
	var b=Button.new()
	b.text=text
	b.position=rect.position
	b.size=rect.size
	b.focus_mode=Control.FOCUS_ALL
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size",22)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		b.add_theme_color_override(state,T.TEXT)
	b.add_theme_stylebox_override("normal",T.box(Color(0,0,0,0),Color(0,0,0,0)))
	b.add_theme_stylebox_override("hover",T.box(Color(T.GOLD,.16),Color(0,0,0,0)))
	b.add_theme_stylebox_override("pressed",T.box(Color(T.GOLD,.26),Color(0,0,0,0)))
	b.add_theme_stylebox_override("focus",T.box(Color(0,0,0,0),T.CYAN,2))
	b.pressed.connect(func(): emit(action,payload))
	b.set_meta("ui_action",action)
	b.set_meta("ui_payload",payload)
	parent.add_child(b)
	return b

func route_room_count()->int:
	var route_catalog=RouteCatalog.new()
	var loaded:Dictionary=route_catalog.load_catalog()
	return route_catalog.get_active_room_count() if loaded.ok else 60

func home():
	ensure_stage()
	if is_instance_valid(title_stage): title_stage.visible=true
	scrim(Rect2(0,0,1020,900),true,0.88)
	scrim(Rect2(0,640,1600,260),false,0.90)

	T.label(page,"莉奈大冒险",Rect2(94,80,760,116),78,T.TEXT)
	T.label(page,"第 01 站 · 地下城",Rect2(100,200,560,40),24,T.GOLD)
	bar(page,Rect2(102,252,96,2),T.GOLD)
	T.paragraph(page,"提灯亮着，台阶一路往下，看不到尽头。\n这一趟，就从这里开始。",Rect2(100,280,540,86),23,T.MUTED)

	T.label(page,"%d 房 · 四首领 · 约 30 分钟"%route_room_count(),Rect2(100,374,440,30),19,Color("c3b7a2"))

	var wallet_bg=Panel.new()
	wallet_bg.position=Vector2(1190,38)
	wallet_bg.size=Vector2(226,40)
	wallet_bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	wallet_bg.add_theme_stylebox_override("panel",T.box(Color(0.035,0.030,0.026,0.55),Color(0,0,0,0),0,20))
	page.add_child(wallet_bg)
	var wallet=T.label(page,"魔尘  %s"%meta.get_state().get("dust",0),Rect2(1198,38,210,40),19,T.GOLD)
	wallet.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT

	bar(page,Rect2(0,806,1600,1),Color(T.GOLD,.28))
	var bar_bg=ColorRect.new()
	bar_bg.color=Color(0.024,0.026,0.034,0.74)
	bar_bg.position=Vector2(0,807)
	bar_bg.size=Vector2(1600,93)
	bar_bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	page.add_child(bar_bg)
	var entries=[["出发","prepare"],["图鉴","codex"],["设置","settings"],["退出",""]]
	var start_x:=(1600.0-(4.0*220.0+3.0*24.0))*0.5
	for i in range(entries.size()):
		var entry=entries[i]
		title_tab(page,str(entry[0]),Rect2(start_x+float(i)*244.0,824,220,58),"quit" if str(entry[1]).is_empty() else "navigate",str(entry[1]))

func equipment():
	var kind="catalyst" if screen in ["catalyst","codex"] else "gem"
	var items=meta.get_items(kind)
	if selected.is_empty() and not items.is_empty(): selected=str(items[0].id)
	T.paragraph(page,"调谐六系触媒，提高偏好学派的出现倾向；起手学派可独立选择。" if kind=="catalyst" else "镶入一枚宝石，让下一次出发更有把握。",Rect2(54,198,1400,40),21)
	if screen=="codex":
		T.label(page,"本次装备   "+equipped_name(kind),Rect2(54,256,620,50),20,T.GOLD)
	else:
		btn(page,"法术触媒",Rect2(54,256,180,50),"navigate","catalyst",screen=="catalyst")
		btn(page,"魔法宝石",Rect2(250,256,180,50),"navigate","gem",screen=="gem")
		T.label(page,"本次装备   "+equipped_name(kind),Rect2(462,256,500,50),20,T.GOLD)
	if kind=="catalyst":
		_catalyst_cards(items)
	else:
		var accent:Array=[Color("90cfb2"),T.CYAN,Color("f0af7b")]
		var compact=items.size()>2
		var card_w=276.0 if compact else 400.0
		var card_h=422.0 if compact else 440.0
		var gap=24.0 if compact else 40.0
		var total_w=items.size()*card_w+maxf(0.0,float(items.size()-1))*gap
		var start_x=54.0+maxf(0.0,(876.0-total_w)*0.5)
		for i in range(items.size()):
			var item=items[i]
			var s=meta.get_item_status(kind,str(item.id))
			var p=T.panel(page,Rect2(start_x+i*(card_w+gap),330,card_w,card_h))
			if selected==str(item.id): p.add_theme_stylebox_override("panel",T.box(Color("28334a"),T.GOLD,2))
			var seal_size=176.0 if compact else 200.0
			var pic_size=156.0 if compact else 180.0
			var seal_y=18.0 if compact else 16.0
			var seal_x=(card_w-seal_size)*0.5
			art(p,"seal",Rect2(seal_x,seal_y,seal_size,seal_size),Color(accent[i],.4),i)
			equipment_picture(p,str(item.id),Rect2(seal_x+(seal_size-pic_size)*0.5,seal_y+8,pic_size,pic_size))
			var label_x=22.0 if compact else 24.0
			var label_w=card_w-label_x*2
			var name_y=190.0 if compact else 220.0
			T.label(p,str(item.name),Rect2(label_x,name_y,label_w,48),26 if compact else 28)
			T.label(p,"未解锁" if int(s.level)==0 else "等级 %d / 3%s"%[s.level," · 已装备" if s.equipped else ""],Rect2(label_x,name_y+54,label_w,32),19,T.GOLD if s.equipped else T.MUTED)
			var subtitle={"health":"提高生命上限","shield":"提高护盾上限","attack":"提高攻击力"}.get(item.get("stat",""),"")
			T.label(p,subtitle,Rect2(label_x,name_y+99,label_w,32),18,T.MUTED)
			var value="属性 +"+number(s.effect_value)
			T.label(p,"未生效" if int(s.level)==0 else value,Rect2(label_x,name_y+135,label_w,30),20,accent[i])
			var button_y=name_y+(180.0 if compact else 168.0)
			btn(p,"查看与培养",Rect2(label_x,button_y,label_w,46),"select",str(item.id),selected==str(item.id)).set_meta("selection_id",str(item.id))
	if items.is_empty(): return
	var chosen=items[0]
	for item in items:
		if str(item.id)==selected: chosen=item
	var status=meta.get_item_status(kind,str(chosen.id))
	var d=T.panel(page,Rect2(990,256,556,558),true)
	T.label(d,str(chosen.name),Rect2(30,22,492,54),32)
	T.label(d,"培养与装备",Rect2(32,80,492,30),19,T.GOLD)
	var text=""
	if kind=="catalyst":
		text=catalog.catalyst_description(str(chosen.get("school","fire")),chosen.get("related_spells",[]).size(),meta.get_catalog().get("spell_sampling",{}))
	else: text="每次出发时，按当前装备等级\n增强一种基础属性。\n\n一局内无法更换宝石。"
	T.paragraph(d,text,Rect2(32,126,492,210),19,T.MUTED)
	var effects:Array=status.get("effect_by_level",[]) if kind=="catalyst" else chosen.flat_by_level
	for i in range(effects.size()):
		var col=T.panel(d,Rect2(32+i*166,348,156,70))
		T.label(col,"%d级"%(i+1),Rect2(14,6,130,26),17,T.GOLD if int(status.level)==i+1 else T.MUTED)
		T.label(col,("优先＋"+catalog._percent(effects[i])) if kind=="catalyst" else "+"+number(effects[i]),Rect2(14,30,130,32),22,T.TEXT)
		if kind=="catalyst": col.tooltip_text=catalog.catalyst_reference_text(meta.get_catalog().get("spell_sampling",{}),i+1)
	if int(status.level)==0:
		btn(d,"免费领取并装备" if status.free else "解锁 · %s 魔尘"%status.cost,Rect2(32,470,492,58),"unlock",str(chosen.id),true,not status.can_unlock)
	else:
		btn(d,"卸下" if status.equipped else "装备",Rect2(32,470,154,58),"equip","" if status.equipped else str(chosen.id))
		btn(d,"已达满级" if int(status.level)>=3 else "升级 · %s 魔尘"%status.cost,Rect2(202,470,322,58),"upgrade",str(chosen.id),true,not status.can_upgrade)
	var blocked=str(status.get("blocked_reason",""))
	if blocked.is_empty() and int(status.level)<3 and not (status.can_unlock if int(status.level)==0 else status.can_upgrade): blocked="魔尘不足，还需要 %s 魔尘"%number(maxf(0,float(status.cost)-float(meta.get_state().get("dust",0))))
	T.label(d,blocked if not blocked.is_empty() else "选择后自动保存",Rect2(32,432,492,28),17,T.GOLD if not blocked.is_empty() else T.MUTED)
	T.label(page,"账号首选一件免费 · 装备一件触媒 · 最高三级",Rect2(56,816,850,38),19,T.MUTED)

static func catalyst_card_rect(index:int)->Rect2:
	return Rect2(54+(index%3)*300,330+(index/3)*234,276,216)

func _catalyst_cards(items:Array):
	for i in items.size():
		var item:Dictionary=items[i]
		var status:Dictionary=meta.get_item_status("catalyst",str(item.id))
		var tint:Color=catalog.school_color(str(item.school))
		var panel=T.panel(page,catalyst_card_rect(i))
		panel.set_meta("catalyst_id",str(item.id))
		if selected==str(item.id): panel.add_theme_stylebox_override("panel",T.box(Color("28334a"),T.GOLD,2))
		art(panel,"seal",Rect2(8,5,90,90),Color(tint,.27),i)
		equipment_picture(panel,str(item.id),Rect2(18,15,70,70))
		T.label(panel,str(item.name),Rect2(102,20,158,38),22)
		T.label(panel,"未解锁" if int(status.level)==0 else "等级 %d / 3%s"%[status.level," · 已装" if status.equipped else ""],Rect2(102,60,158,28),17,T.GOLD if status.equipped else T.MUTED)
		var effect="未生效" if int(status.level)==0 else "本系优先＋"+catalog._percent(status.effect_value)
		T.label(panel,effect,Rect2(18,103,240,34),22,tint)
		var inspect=btn(panel,"查看与培养",Rect2(16,158,244,44),"select",str(item.id),selected==str(item.id))
		inspect.set_meta("selection_id",str(item.id))
		inspect.tooltip_text=catalog.catalyst_reference_text(meta.get_catalog().get("spell_sampling",{}),maxi(1,int(status.level)))


func stats(parent:Node,rect:Rect2):
	var values=meta.get_preview_stats()
	var keys=["health","shield","attack"]
	var names=["生命上限","护盾上限","攻击力"]
	for i in range(3):
		var x=rect.position.x+i*rect.size.x/3
		T.label(parent,names[i],Rect2(x,rect.position.y,180,32),19,T.MUTED)
		T.label(parent,number(values.get(keys[i],0)),Rect2(x,rect.position.y+40,180,60),38)
func number(value)->String:
	return str(int(value)) if is_equal_approx(float(value),roundf(float(value))) else String.num(float(value),2)
func equipped_name(kind:String)->String:
	if kind=="gem":
		var state:Dictionary=meta.get_state().gem_state
		var count=0
		for id in state.slots:
			if not str(id).is_empty(): count+=1
		return "%s · %d/4"%[meta.gems.title(meta.gems.find(state,str(state.slots[0]))),count]
	for item in meta.get_items(kind):
		if meta.get_item_status(kind,str(item.id)).equipped: return str(item.name)
	return "未装备"

func equipped_id(kind:String)->String:
	if kind=="gem":
		var state:Dictionary=meta.get_state().gem_state
		var gem:Dictionary=meta.gems.find(state,str(state.slots[0]))
		return "core:"+str(gem.get("core","")) if not gem.is_empty() and not str(gem.get("core","")).is_empty() else ""
	for item in meta.get_items(kind):
		if meta.get_item_status(kind,str(item.id)).equipped:return str(item.id)
	return ""
func prepare():
	var route_catalog=RouteCatalog.new()
	var route_loaded:Dictionary=route_catalog.load_catalog()
	var route_count:int=route_catalog.get_active_room_count() if route_loaded.ok else 0
	var income:Dictionary=meta.gems.rules.route_income
	var early_rooms:int=mini(route_count,int(income.early_end))
	var completion_dust:int=early_rooms*int(income.early_dust)+(route_count-early_rooms)*int(income.later_dust)
	art(page,"seal",Rect2(38,238,650,516),Color(T.CYAN,.45))
	add_showcase(Rect2(80,200,598,532))
	T.label(page,"莉奈",Rect2(172,770,138,44),32)
	T.label(page,"见习魔法师",Rect2(282,775,300,36),21,T.GOLD)
	var p=T.panel(page,Rect2(736,224,808,514))
	T.label(p,"本局学派",Rect2(32,20,180,42),25,T.GOLD)
	for index in SCHOOLS.size():
		var school=SCHOOLS[index]
		var school_button=btn(p,catalog.school_name(school)+"试炼",Rect2(230+(index%3)*182,20+(index/3)*54,172,44),"route_school",school,route_school==school)
		school_button.set_meta("route_school",school)
		school_button.tooltip_text="决定%d房路线的起始三选一；火、冰、雷、风、岩、灵契可混学。起手不要求同系触媒；装备触媒提高对应学派出现倾向，不保证必出。"%route_count
	var catalyst=T.panel(p,Rect2(30,130,748,84))
	equipment_picture(catalyst,equipped_id("catalyst"),Rect2(6,4,76,76))
	T.label(catalyst,"法术触媒",Rect2(94,7,230,28),18,T.MUTED)
	T.label(catalyst,equipped_name("catalyst"),Rect2(94,37,440,34),24)
	btn(catalyst,"更换",Rect2(584,16,140,52),"open_codex","gear")
	var gem=T.panel(p,Rect2(30,224,748,84))
	equipment_picture(gem,equipped_id("gem"),Rect2(6,4,76,76))
	T.label(gem,"魔法宝石 · 1核心＋3属性槽",Rect2(94,7,450,28),18,T.MUTED)
	T.label(gem,equipped_name("gem"),Rect2(94,37,472,34),22)
	btn(gem,"更换",Rect2(584,16,140,52),"navigate","gem")
	bar(p,Rect2(32,326,744,1),Color(T.GOLD,.3))
	stats(p,Rect2(32,344,744,96))
	T.paragraph(p,"选择学派决定起手，六系可混学。\n装备触媒提高对应学派出现倾向，不保证必出。",Rect2(32,456,744,48),18,T.MUTED)
	T.label(page,"%d房路线 · %s起手／六系混搭 · 清房结算魔尘，通关%d尘"%[route_count,catalog.school_name(route_school),completion_dust],Rect2(738,747,806,30),18,T.GOLD)
	btn(page,"查看界面预览",Rect2(736,788,174,48),"navigate","opening")
	var legacy_room_button=btn(page,"进入首房试玩    ›",Rect2(928,788,270,48),"start_room")
	legacy_room_button.tooltip_text="独立首房保留旧版战斗规则；新宝石完整词条与核心效果请在%d房路线测试。"%route_count
	btn(page,"进入%d房路线    ›"%route_count,Rect2(1216,788,328,48),"start_route","",true,not route_loaded.ok)

func spell_text(id:String,level:int=1)->String:
	var d:Dictionary=catalog.describe_spell(id,level)
	return "等级 %d  ·  %s\n\n%s\n\n%s\n\n%s\n\n%s"%[level,str(d.get("role","")),str(d.get("summary","")),str(d.get("description","")),"\n".join(d.get("stats",[])),str(d.get("boundary",""))]
func artifact_text(id:String)->String:
	var d:Dictionary=catalog.describe_artifact(id)
	return str(d.get("rarity_name",""))+" · "+str(d.get("scope_name","宝物"))+"\n\n"+str(d.get("description",""))+"\n\n"+str(d.get("requirement",""))
func choice_text(id:String)->String:
	var d:Dictionary=catalog.describe_spell(id,1)
	var stats:Array=d.get("stats",[])
	return str(d.get("summary",""))+"\n\n"+(str(stats[0]) if not stats.is_empty() else str(d.get("role","")))
func codex():
	var tabs=[["spells","法术",catalog.spells().size()],["artifacts","宝物",catalog.artifacts().size()],["gear","装备",0]]
	for i in range(tabs.size()):
		var tab=tabs[i]
		var titled=str(tab[1])
		if int(tab[2])>0: titled="%s  %d"%[titled,int(tab[2])]
		var tab_button=btn(page,titled,Rect2(748.0+float(i)*196.0,116,184,50),"codex_tab",str(tab[0]),str(tab[0])==codex_tab)
		tab_button.add_theme_font_size_override("font_size",21)
		tab_button.alignment=HORIZONTAL_ALIGNMENT_CENTER
		tab_button.set_meta("codex_tab",str(tab[0]))
	if codex_tab=="gear":
		equipment()
		var shop=btn(page,"进入宝石工坊  ›",Rect2(1340,116,204,50),"navigate","gem")
		shop.add_theme_font_size_override("font_size",19)
	else:
		grimoire()

func grimoire():
	var is_spell=codex_tab=="spells" if screen=="codex" else screen=="spells"
	var items:Array=catalog.spells() if is_spell else catalog.artifacts()
	var all_items:Array=items.duplicate()
	if is_spell and _spell_scope!="all":
		items=items.filter(func(item):return str(item.get("school","fire"))==_spell_scope)
	elif not is_spell and _artifact_scope!="all":
		items=items.filter(func(item):return bool(item.get("values",{}).get("boss_only",false)) if _artifact_scope=="boss" else not bool(item.get("values",{}).get("boss_only",false)))
	var selected_exists=false
	for item in items:
		if str(item.id)==selected:selected_exists=true
	if not selected_exists:selected=""
	if selected.is_empty() and not items.is_empty(): selected=str(items[0].id)
	T.label(page,"%d种法术 · 六系自由混搭，重复选择升至三级"%all_items.size() if is_spell else "通用宝物强化属性与循环 · 首领庭印提供通关成长 · 均不占法术槽",Rect2(54,198,1400,40),21,T.MUTED)
	T.panel(page,Rect2(54,254,478,542))
	var counts={"all":all_items.size(),"generic":0,"boss":0,"fire":0,"ice":0,"lightning":0,"wind":0,"earth":0,"spirit":0}
	for item in all_items:
		var scope=str(item.get("school","fire")) if is_spell else ("boss" if bool(item.get("values",{}).get("boss_only",false)) else "generic")
		counts[scope]=int(counts.get(scope,0))+1
	var scopes=SPELL_FILTERS if is_spell else ["all","generic","boss"]
	var names=["全部","火系","冰系","雷系","风系","岩系","灵契"] if is_spell else ["全部","通用","庭印"]
	if is_spell:
		for i in scopes.size():
			var filter_button=T.button(page,"%s %d"%[names[i],counts[scopes[i]]],Rect2(66+(i%4)*113,266+(i/4)*52,106,44),func():_filter_spells(str(scopes[i])),_spell_scope==scopes[i])
			filter_button.set_meta("spell_school",scopes[i])
	else:
		for i in scopes.size():
			var filter_button=T.button(page,"%s %d"%[names[i],counts[scopes[i]]],Rect2(66+i*113,266,108,38),func():_filter_artifacts(str(scopes[i])),_artifact_scope==scopes[i])
			filter_button.set_meta("artifact_scope",scopes[i])
	var scroll=ScrollContainer.new()
	scroll.name="CatalogList"
	scroll.follow_focus=true
	scroll.position=Vector2(66,370 if is_spell else 314)
	scroll.size=Vector2(454,414 if is_spell else 470)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var list=VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	scroll.add_child(list)
	for item in items:
		var b=T.button(list,"%s　%s"%[str(item.id),str(item.name)],Rect2(0,0,434,62),func(): emit("select",str(item.id)),str(item.id)==selected)
		b.custom_minimum_size=Vector2(430,62)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		for state in ["normal","hover","pressed","disabled"]:
			var padded=b.get_theme_stylebox(state).duplicate()
			padded.content_margin_left=72
			b.add_theme_stylebox_override(state,padded)
		b.add_theme_font_size_override("font_size",21)
		if is_spell: T.icon(b,str(item.id),Rect2(8,7,48,48),Color("25314a") if str(item.id)==selected else catalog.school_color(str(item.get("school","fire"))))
		else: artifact_picture(b,str(item.id),str(item.rarity),Rect2(8,7,48,48))
		b.set_meta("selection_id",str(item.id))
	scroll.set_deferred("scroll_vertical",_list_scroll)
	if items.is_empty(): return
	var chosen=items[0]
	for item in items:
		if str(item.id)==selected: chosen=item
	var p=T.panel(page,Rect2(562,254,982,542),true)
	if is_spell: T.icon(p,str(chosen.id),Rect2(32,24,118,118),catalog.school_color(str(chosen.get("school","fire"))))
	else: artifact_picture(p,str(chosen.id),str(chosen.rarity),Rect2(32,24,118,118))
	T.label(p,str(chosen.name),Rect2(178,36,742,56),36)
	T.label(p,catalog.school_name(str(chosen.get("school","fire")))+" · "+str(chosen.get("role","法术")) if is_spell else str(chosen.rarity_name)+" · "+str(chosen.get("scope_name","宝物"))+" · "+str(chosen.get("school_name","")),Rect2(180,96,742,32),20,T.GOLD)
	bar(p,Rect2(34,159,910,1),Color(T.GOLD,.3))
	var detail_scroll=ScrollContainer.new()
	detail_scroll.position=Vector2(36,184)
	detail_scroll.size=Vector2(910,250 if is_spell else 310)
	detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.focus_mode=Control.FOCUS_ALL
	detail_scroll.tooltip_text="法术与宝物详情；上下方向键或滚轮查看"
	p.add_child(detail_scroll)
	detail_label=T.paragraph(detail_scroll,spell_text(str(chosen.id),1) if is_spell else artifact_text(str(chosen.id)),Rect2(0,0,882,220),21,T.TEXT)
	detail_label.clip_text=false
	detail_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail_label.custom_minimum_size=Vector2(882,0)
	if is_spell:
		T.label(p,"查看等级效果",Rect2(36,466,250,44),18,T.MUTED)
		for i in range(3): btn(p,["一级","二级","三级"][i],Rect2(334+i*198,462,184,50),"detail_level",str(i+1))

func _filter_artifacts(scope:String):
	_artifact_scope=scope
	selected=""
	_rendered_screen=""
	render(screen,meta,catalog)

func _filter_spells(scope:String):
	_spell_scope=scope
	selected=""
	_rendered_screen=""
	render(screen,meta,catalog)

func settings():
	T.label(page,"调整显示与战斗信息，设置会在本机保存。",Rect2(54,198,1400,40),21,T.MUTED)
	var p=T.panel(page,Rect2(54,256,934,550))
	T.label(p,"画面显示",Rect2(32,22,830,44),28,T.GOLD)
	T.label(p,"显示模式",Rect2(32,90,390,50),23)
	btn(p,"切换全屏 / 窗口",Rect2(472,88,430,54),"fullscreen")
	T.label(p,"帧率限制",Rect2(32,164,390,50),23)
	btn(p,"%d 帧 / 秒 · 点击切换"%Engine.max_fps,Rect2(472,162,430,54),"fps")
	bar(p,Rect2(32,242,870,1),Color(T.GOLD,.3))
	T.label(p,"战斗信息与动态效果",Rect2(32,260,830,44),27,T.GOLD)
	var keys=["view_hints","damage_numbers","reduced_motion"]
	var titles=["操作与流程提示","伤害数字","减少动态效果"]
	for i in range(keys.size()):
		var enabled=preferences.get(keys[i])==true
		T.label(p,titles[i],Rect2(32,326+i*67,390,48),23)
		btn(p,"已开启" if enabled else "已关闭",Rect2(654,324+i*67,248,48),"toggle_preference",keys[i],enabled).tooltip_text=titles[i]+"：点击切换"
	var controls=T.panel(page,Rect2(1020,256,524,550))
	T.label(controls,"操作速查",Rect2(32,24,460,44),28,T.GOLD)
	var commands=[["移动","WASD / 方向键"],["施法","自动吟唱与施放"],["暂停 / 返回","Esc"],["切换全屏","F11"],["切换焦点","Tab"],["确认选择","Enter"]]
	for i in range(commands.size()):
		T.label(controls,commands[i][0],Rect2(32,94+i*52,194,42),20,T.MUTED)
		T.label(controls,commands[i][1],Rect2(222,94+i*52,278,42),20)
	bar(controls,Rect2(32,428,460,1),Color(T.GOLD,.3))
	T.paragraph(controls,"莉奈播放已有骨骼待机动作。\n拖动旋转，双击模型复位。",Rect2(32,454,460,68),20,T.MUTED)

func preview_navigation():
	var labels=["开局","局内","法术奖励","宝物箱","商店","暂停","结算"]
	for i in range(PREVIEWS.size()): btn(page,labels[i],Rect2(54+i*215,752,199,50),"navigate",PREVIEWS[i],screen==PREVIEWS[i])
func preview():
	match screen:
		"opening","reward": spell_choices()
		"chest","shop": artifact_choices()
		"hud","pause": hud_preview()
		"result": result_preview()
	preview_navigation()
func spell_choices():
	T.label(page,"选择起始法术" if screen=="opening" else "选择一份新的魔法",Rect2(54,242,1300,52),32)
	var reward_examples={"fire":["F01","F11","F10"],"ice":["I01","I07","I09"],"lightning":["L03","L08","L09"],"wind":["W02","W08","W09"],"earth":["R03","R07","R09"],"spirit":["S01","S04","S09"]}
	var ids=catalog.starter_ids(route_school) if screen=="opening" else reward_examples.get(route_school,reward_examples.fire)
	for i in range(3):
		var p=T.panel(page,Rect2(54+i*502,316,478,404),true)
		art(p,"seal",Rect2(14,2,146,146),Color(T.GOLD,.35))
		T.icon(p,ids[i],Rect2(32,20,110,110),catalog.school_color(route_school))
		T.label(p,catalog.spell_name(str(ids[i])),Rect2(164,28,280,50),30)
		T.label(p,"起始法术 · 一级" if screen=="opening" else "新法术 · 一级",Rect2(166,88,280,32),19,T.GOLD)
		var info:Dictionary=catalog.describe_spell(ids[i],1)
		bar(p,Rect2(30,149,418,1),Color(T.GOLD,.3))
		T.label(p,str(info.role),Rect2(30,166,418,32),20,T.GOLD)
		T.paragraph(p,str(info.summary),Rect2(30,212,418,84),20,T.TEXT)
		T.label(p,str(info.stats[0]) if not info.stats.is_empty() else str(info.role),Rect2(30,300,418,32),18,T.MUTED)
		btn(p,"选用并预览",Rect2(30,344,418,48),"choose_preview",ids[i],true)
func artifact_choices():
	if screen=="shop":
		shop_preview()
		return
	var items=catalog.artifacts()
	T.label(page,"遗迹商店" if screen=="shop" else "开启宝物箱",Rect2(54,242,1300,52),32)
	for i in range(mini(3,items.size())):
		var item=items[i]
		var p=T.panel(page,Rect2(54+i*502,316,478,404))
		art(p,"seal",Rect2(12,10,138,138),Color(Color(item.color),.25))
		artifact_picture(p,str(item.id),str(item.rarity),Rect2(28,26,106,106))
		T.label(p,str(item.name),Rect2(150,37,298,48),28)
		T.label(p,"样例展品 · 不计入持有",Rect2(150,92,300,32),18,T.MUTED)
		T.label(p,str(item.rarity_name)+"宝物",Rect2(30,148,418,32),19,T.MUTED)
		T.paragraph(p,str(item.description),Rect2(30,194,418,126),20)
		btn(p,"查看图鉴",Rect2(30,344,418,48),"artifact_detail",str(item.id))
func shop_preview():
	var economy:Dictionary=catalog.economy_summary()
	T.label(page,"遗迹商店",Rect2(54,242,950,52),32)
	T.label(page,"本局金币   —   /   商品样例",Rect2(1110,246,430,42),20,T.GOLD)
	var items=catalog.artifacts()
	for i in range(mini(3,items.size())):
		var item=items[i]
		var p=T.panel(page,Rect2(54+i*344,316,326,404))
		artifact_picture(p,str(item.id),str(item.rarity),Rect2(18,22,86,86))
		T.label(p,str(item.name),Rect2(114,25,196,46),25)
		T.label(p,str(item.rarity_name)+"宝物",Rect2(114,75,196,32),19,T.MUTED)
		var description=str(item.description)
		if description.length()>52: description=description.left(51)+"…"
		T.paragraph(p,description,Rect2(24,136,278,110),19)
		T.label(p,"价格   %s 金币"%number(item.price),Rect2(24,290,278,32),23,T.GOLD)
		btn(p,"查看商品",Rect2(24,344,278,48),"artifact_detail",str(item.id))
	var supply=T.panel(page,Rect2(1100,316,444,404),true)
	T.label(supply,"酒馆补给",Rect2(28,22,388,48),30)
	T.paragraph(supply,str(economy.shop_supply_text),Rect2(28,98,388,110),21,T.TEXT)
	T.paragraph(supply,str(economy.shop_rule_text),Rect2(28,224,388,94),19,T.MUTED)
	btn(supply,"预览补给说明",Rect2(28,344,388,48),"supply_preview")
func bar(parent:Node,rect:Rect2,color:Color):
	var c=ColorRect.new()
	c.position=rect.position
	c.size=rect.size
	c.color=color
	c.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
func hud_preview():
	var p=T.panel(page,Rect2(54,246,1490,474))
	T.label(p,"遗迹庭院 · 首房",Rect2(30,18,800,42),28,T.GOLD)
	var values=meta.get_run_snapshot().get("player",meta.get_preview_stats())
	T.label(p,"生命  %s / %s"%[number(values.get("health",0)),number(values.get("health",0))],Rect2(30,82,430,32),21)
	bar(p,Rect2(30,126,360,13),Color("d8637c"))
	T.label(p,"护盾  %s / %s"%[number(values.get("shield",0)),number(values.get("shield",0))],Rect2(30,153,430,32),21)
	bar(p,Rect2(30,197,360,10),T.CYAN)
	art(p,"seal",Rect2(792,44,350,280),Color(T.CYAN,.45))
	T.label(p,"局内界面预览",Rect2(566,100,650,52),30,T.GOLD)
	T.label(p,"真实战斗请从准备页进入首房",Rect2(566,162,800,38),22,T.MUTED)
	for i in range(8):
		var slot=T.panel(p,Rect2(265+i*120,352,104,100))
		if i==0:
			T.icon(slot,opening_spell,Rect2(20,5,64,64),catalog.school_color(str(catalog.describe_spell(opening_spell).get("school","fire"))))
			T.label(slot,"等级 1",Rect2(20,70,80,24),15,T.GOLD)
		else: T.label(slot,"空槽",Rect2(25,31,70,34),18,T.MUTED)
	T.label(p,"示例法术：%s · 此处不推进吟唱或冷却"%catalog.spell_name(opening_spell),Rect2(30,274,1300,35),20,T.MUTED)
	if screen=="pause":
		var dim=ColorRect.new()
		dim.color=Color(.025,.04,.065,.88)
		dim.position=Vector2(54,246)
		dim.size=Vector2(1490,474)
		page.add_child(dim)
		var modal=T.panel(page,Rect2(500,298,600,358))
		T.label(modal,"休息片刻",Rect2(42,24,516,62),40)
		T.label(modal,"这是暂停界面预览。",Rect2(44,102,512,40),22,T.MUTED)
		btn(modal,"继续预览",Rect2(42,186,516,58),"navigate","hud",true)
		btn(modal,"返回准备",Rect2(42,264,516,52),"navigate","prepare")
func result_preview():
	var p=T.panel(page,Rect2(270,246,1060,474),true)
	T.label(p,"旅途的回响",Rect2(44,24,970,68),42)
	T.paragraph(p,"真实试炼将在这里结算清房与魔尘。\n当前为界面预览，余额保持不变。",Rect2(44,122,970,88),23,T.MUTED)
	bar(p,Rect2(44,232,970,1),Color(T.GOLD,.3))
	T.label(p,"本局魔尘     —",Rect2(44,262,700,44),27)
	T.label(p,"已有魔尘     %s"%meta.get_state().get("dust",0),Rect2(44,320,700,44),27,T.GOLD)
	btn(p,"返回藏书室",Rect2(700,388,314,58),"navigate","home",true)
