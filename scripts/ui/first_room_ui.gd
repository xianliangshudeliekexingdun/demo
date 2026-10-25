extends CanvasLayer
signal requested(action:String,payload:Variant)
const T=preload("res://scripts/ui/atelier_theme.gd")
const LINA_PORTRAIT=preload("res://assets/ui/lina_portrait_3d.png")
const Catalog=preload("res://scripts/ui/grimoire_catalog.gd")
const ArtifactIcon=preload("res://scripts/ui/artifact_icon.gd")
const ChoiceCard=preload("res://scripts/ui/choice_card.gd")
const RoomProgress=preload("res://scripts/ui/room_progress.gd")
const SLOT_TEXTURE=preload("res://assets/ui/frames_v1/spell_slot.tres")
const ShopUI=preload("res://scripts/ui/route_shop_ui.gd")
const BossBar=preload("res://scripts/ui/route_boss_bar.gd")
const GemIcon=preload("res://scripts/ui/gem_icon.gd")
var _boss_bar:Control
var _shop_ui:Control
var root:Control
var modal:Control
var health_label:Label
var shield_label:Label
var health_bar:ProgressBar
var shield_bar:ProgressBar
var objective:Label
var detail:Label
var timer_label:Label
var currency_label:Label
var enemies_label:Label
var route_title_backdrop:Panel
var route_progress:Control
var room_index_label:Label
var artifact_bar:Panel
var _artifact_signature=""
var slots:Array=[]
var spell_labels:Array=[]
var cooldown_labels:Array=[]
var slot_bars:Array=[]
var slot_icons:Array=[]
var hint_nodes:Array=[]
var preferences:Dictionary={}
var last_modal=""
var _finished=false
var _choice_buttons:Array=[]
var _choice_cards:Array=[]
var _choice_active=false
var _choice_keyboard=false
var _vitals:Panel
var _generic_status:Label
var _display_catalog:Dictionary={}
var _attribute_summary=""
var _gem_status:Label
var _gem_icon:Control
const GemNames=preload("res://scripts/core/magic_gems.gd")
var _gem_names=GemNames.new()
var _choice_room_revision:int=-1
var _reward_skip_button:Button
var _replacement_pending:Dictionary={}
var _replacement_buttons:Array=[]
var _replacement_active:bool=false
var _replacement_keyboard:bool=false
var _replacement_focus_index:int=0
var _replacement_last_request:int=-1
var _replacement_target:Label
var _replacement_selected_index:int=-1
var _replacement_confirm:Button

func _ready():
	layer=20
	_display_catalog=Catalog.load_catalog()
	root=Control.new()
	root.size=Vector2(1600,900)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.theme=T.make_theme()
	add_child(root)
	_build_hud()
func emit(action:String,payload:Variant=""):requested.emit(action,payload)
func btn(parent:Node,text:String,rect:Rect2,action:String,payload:Variant="",primary:bool=false,disabled:bool=false):
	return T.button(parent,text,rect,func():emit(action,payload),primary,disabled)
func set_visual_options(options:Dictionary):
	preferences=options.duplicate(true)
	for node in hint_nodes:node.visible=bool(preferences.get("view_hints",true))
	if bool(preferences.get("reduced_motion",false)):
		for card in _choice_cards:
			if not card.reveal_complete:card.reveal_immediately()
func make_bar(parent:Node,rect:Rect2,color:Color)->ProgressBar:
	var b=ProgressBar.new()
	b.position=rect.position
	b.min_value=0
	b.max_value=1
	b.step=.001
	b.show_percentage=false
	b.add_theme_font_size_override("font_size",1)
	b.mouse_filter=Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("background",T.box(Color("151b2a"),Color("535870"),1,3))
	b.add_theme_stylebox_override("fill",T.box(color,color.lightened(.15),1,3))
	parent.add_child(b)
	b.size=rect.size
	return b
func _build_hud():
	var vitals=T.panel(root,Rect2(32,22,430,78))
	_vitals=vitals
	_vitals.name="PlayerAttributes"
	_vitals.mouse_filter=Control.MOUSE_FILTER_PASS
	var portrait_frame=T.panel(vitals,Rect2(8,9,60,60))
	portrait_frame.name="LinaPortraitFrame"
	portrait_frame.add_theme_stylebox_override("panel",T.box(Color("111a2b"),T.GOLD.darkened(.12),1,6))
	portrait_frame.clip_contents=true
	var portrait=TextureRect.new()
	portrait.name="LinaPortrait"
	portrait.texture=LINA_PORTRAIT
	portrait.position=Vector2(1,1)
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(portrait)
	# Assign after expand mode: the default texture minimum would retain 512px.
	portrait.size=Vector2(58,58)
	health_label=T.label(vitals,"",Rect2(82,2,318,26),17)
	health_bar=make_bar(vitals,Rect2(82,31,316,10),Color("dc6178"))
	shield_bar=make_bar(vitals,Rect2(82,48,316,7),Color("6acbe0"))
	shield_label=T.label(vitals,"",Rect2(82,54,316,22),14,T.CYAN)
	route_title_backdrop=T.panel(root,Rect2(594,16,412,82))
	route_title_backdrop.add_theme_stylebox_override("panel",T.box(Color(0.035,0.055,0.09,0.92),Color(0.38,0.5,0.64,0.28),1,6))
	route_title_backdrop.visible=false
	room_index_label=T.label(route_title_backdrop,"",Rect2(18,4,376,25),16,T.MUTED)
	room_index_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	route_progress=RoomProgress.new()
	route_progress.name="RoomProgress"
	route_progress.position=Vector2(31,32)
	route_title_backdrop.add_child(route_progress)
	objective=T.label(root,"",Rect2(558,23,484,34),24,T.TEXT)
	objective.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	enemies_label=T.label(root,"",Rect2(558,62,484,28),17,T.MUTED)
	enemies_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var counters=T.panel(root,Rect2(1208,22,248,78))
	currency_label=T.label(counters,"",Rect2(16,4,220,36),20,T.GOLD)
	timer_label=T.label(counters,"",Rect2(16,43,220,28),17,T.MUTED)
	timer_label.mouse_filter=Control.MOUSE_FILTER_PASS
	_gem_icon=GemIcon.new()
	_gem_icon.position=Vector2(36,105)
	_gem_icon.size=Vector2(30,30)
	_gem_icon.rarity="gold"
	root.add_child(_gem_icon)
	_gem_status=T.paragraph(root,"",Rect2(74,106,420,58),17,T.CYAN)
	_gem_status.mouse_filter=Control.MOUSE_FILTER_PASS
	_boss_bar=BossBar.new()
	_boss_bar.position=Vector2(510,108)
	root.add_child(_boss_bar)
	btn(root,"暂停",Rect2(1472,29,96,60),"room_pause")
	var hint=T.paragraph(root,"WASD / 方向键移动\n移动中自动吟唱\nEsc 暂停 · F11 全屏",Rect2(38,757,290,94),18,T.MUTED)
	hint_nodes.append(hint)
	detail=T.paragraph(root,"",Rect2(1280,770,282,76),18,T.CYAN)
	T.label(root,"法 术 构 筑",Rect2(432,771,740,24),15,T.GOLD)
	for i in range(8):
		var slot=T.panel(root,Rect2(432+i*94,804,84,78))
		slot.name="SpellSlot%d"%(i+1)
		slot.mouse_filter=Control.MOUSE_FILTER_PASS
		slot.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
		var socket=TextureRect.new()
		socket.name="SpellSlotBackground"
		socket.texture=SLOT_TEXTURE
		socket.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		socket.stretch_mode=TextureRect.STRETCH_SCALE
		socket.mouse_filter=Control.MOUSE_FILTER_IGNORE
		socket.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		slot.add_child(socket)
		socket.size=slot.size
		slots.append(slot)
		var icon=T.icon(slot,"empty",Rect2(17,8,50,43),T.LINE)
		slot_icons.append(icon)
		spell_labels.append(T.label(slot,"◇",Rect2(6,49,72,22),14,T.MUTED))
		spell_labels[i].horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		cooldown_labels.append(T.label(slot,"",Rect2(45,5,28,20),13,T.GOLD))
		cooldown_labels[i].add_theme_stylebox_override("normal",T.box(Color(.035,.05,.08,.94),Color.TRANSPARENT,0,2))
		cooldown_labels[i].horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		cooldown_labels[i].visible=false
		slot_bars.append(make_bar(slot,Rect2(10,69,64,3),T.GOLD))
	artifact_bar=T.panel(root,Rect2(432,711,742,48))
	artifact_bar.name="RunArtifacts"
	artifact_bar.visible=false
	_generic_status=T.label(root,"",Rect2(432,682,742,24),15,T.CYAN)
	_generic_status.name="GenericItemStatus"
func gem_status_text(s:Dictionary) -> String:
	var gems:Dictionary=s.get("gems",{})
	var ids:Array=gems.get("cores",[])
	var id:String=str(ids[0]) if not ids.is_empty() else str(gems.get("core",""))
	var spec:Dictionary=_gem_names.rules.cores.get(id,{})
	if spec.is_empty():return ""
	var school:Dictionary=gems.get("schools",{})
	var text:String="核心 · "+str(spec.name)
	match id:
		"inferno":
			var ticks:int=0
			var amount:float=0.0
			for entry in gems.get("embers",{}).values():
				ticks=maxi(ticks,int(entry.get("ticks",0)))
				amount+=float(entry.get("amount",0))
			text+=" · %d靶 · 余烬%.0f · 最高%d/%d跳"%[gems.get("embers",{}).size(),amount,ticks,int(spec.ticks_required)]
		"coffin":
			var amount:float=0.0
			for entry in gems.get("coffin_reserves",{}).values():amount+=float(entry.get("amount",0))
			text+=" · 封存 %.0f · %d靶"%[amount,gems.get("coffin_reserves",{}).size()]
		"lightning":
			var charges:int=int(school.get("lightning_charges",0))
			text+=" · %d/%d荷 · 储雷%.0f%s"%[charges,int(spec.charge_count),float(school.get("lightning_stored",0))," · 待放电" if charges>=int(spec.charge_count) else ""]
		"wind":text+=" · 风势%d/%d · 气流%.1f秒"%[int(school.get("wind_layers",0)),int(spec.max_stacks),maxf(0,float(school.get("wind_flow_until",0))-float(gems.get("clock",0)))]
		"earth":
			if int(school.get("earth_anchor_id",-1))<0:text+=" · 等待真实构装"
			elif float(school.get("earth_leave_remaining",0))>0:text+=" · 离阵宽限%.1f秒"%float(school.earth_leave_remaining)
			elif bool(school.get("earth_mature",false)):text+=" · 已成熟 · 脉冲%.1f秒"%float(school.get("earth_pulse_remaining",0))
			else:text+=" · 驻留%d%%"%roundi(clampf(float(school.get("earth_progress",0)),0,1)*100)
		"spirit":
			var points:int=int(school.get("spirit_points",0))
			text+=" · 协同%d/%d%s"%[points,int(spec.charge_count)," · 下次普攻合奏" if points>=int(spec.charge_count) else ""]
		"fracture","echo":text+=" · 待兑现 %d"%int(gems.get("pending_count",0))
		"sacrifice":
			var p:Dictionary=s.get("player",{})
			var fraction:float=float(p.get("health",0))/maxf(1,float(p.get("max_health",1)))
			text+=" · 缺血增伤＋%.0f%%%s"%[(1-clampf(fraction,0,1))*float(spec.damage_per_missing_fraction)*100," · 自耗停止" if fraction<=float(spec.drain_floor_fraction) else ""]
		"aegis":text+=" · 治疗转盾 · 满盾不储存"
	return text

func _effects_tooltip(ids: Array) -> String:
	var lines: PackedStringArray = []
	for id in ids: lines.append(_gem_names.core_description(str(id)))
	return "\n\n".join(lines)

func refresh(s:Dictionary):
	if _finished:return
	var p:Dictionary=s.player
	_boss_bar.refresh(s)
	_attribute_summary=_attribute_text(s)
	var gem_state:Dictionary=s.get("gems",{})
	var core_ids:Array=gem_state.get("cores",[])
	if core_ids.is_empty() and not str(gem_state.get("core","")).is_empty(): core_ids=[str(gem_state.get("core",""))]
	var core_id:String=str(core_ids[0]) if not core_ids.is_empty() else ""
	_gem_status.visible=_gem_names.rules.cores.has(core_id)
	_gem_icon.visible=_gem_status.visible
	if _gem_status.visible:
		_gem_icon.item_id="core:"+core_id
		_gem_icon.queue_redraw()
		_gem_status.text=gem_status_text(s)+("   ／ 效果×%d"%core_ids.size() if core_ids.size()>1 else "")
		_gem_status.add_theme_color_override("font_color",GemIcon.tint_for(core_id))
		_gem_status.tooltip_text=_effects_tooltip(core_ids)
	_vitals.tooltip_text=_attribute_summary+"\n暴击率无额外封顶；达到100%时必定暴击。六系本体沿用全局暴击，火系另含炎法精通。\n风系补压／交剪、岩系明确回响和契灵普攻可暴击；派生不触发普通本体命中链。\n燃烧、引爆、非暴击电弧与灵契号令不暴击。冷却缩减不影响吟唱、召唤物攻击间隔与宝物间隔。"
	_generic_status.text=_generic_status_text(s)
	health_label.text="莉奈    生命  %d / %d"%[p.health,p.max_health]
	shield_label.text="护盾  %d / %d"%[p.shield,p.max_shield]
	health_bar.value=clampf(float(p.health)/maxf(1,float(p.max_health)),0,1)
	shield_bar.value=clampf(float(p.shield)/maxf(1,float(p.max_shield)),0,1)
	timer_label.text="%02d:%02d    ·    地下城"%[int(s.time)/60,int(s.time)%60]
	currency_label.text="金币  %d    魔尘  %d"%[s.gold,s.dust]
	var alive=0
	for actor in s.actors:
		if actor.health>0:alive+=1
	var phase:String=s.phase
	var route=s.get("scope","")=="early_route_map_trial"
	route_title_backdrop.visible=route
	objective.visible=not route
	enemies_label.visible=not route
	_sync_artifact_bar(s.get("artifacts",[]))
	var objectives={"choosing":"选择起始法术", "combat":"地下城 · 击败所有敌人", "pickup":"前往门前领取奖励", "reward":"已清场 · 选择成长", "exit":"前往上方传送门", "complete":"首房试炼完成", "dead":"试炼结束"}
	objective.text=objectives.get(phase,"")
	enemies_label.text="存活敌人  %d / 2"%alive if phase=="combat" else "第一间 · 地下城入口"
	if route:
		var difficulty_band:Dictionary=s.get("difficulty_band",{})
		var band_name=str(difficulty_band.get("name",""))
		var band_description=str(difficulty_band.get("description",""))
		room_index_label.text=("%s · 第 %02d / %02d 房"%[band_name,int(s.room_index),int(s.room_total)]) if not band_name.is_empty() else ("第 %02d / %02d 房"%[int(s.room_index),int(s.room_total)])
		room_index_label.tooltip_text=(band_description+"\n" if not band_description.is_empty() else "")+str(s.room_name)
		room_index_label.mouse_filter=Control.MOUSE_FILTER_PASS
		route_progress.refresh(s)
		currency_label.text="金币 %d"%int(s.gold)
		if bool(s.get("in_shop",false)):
			room_index_label.text="旅途商店 · 第 %02d 房后 / %02d 房"%[int(s.room_index),int(s.room_total)]
		timer_label.text="总时间  %02d:%02d"%[int(s.time)/60,int(s.time)%60]
		timer_label.tooltip_text="战斗、房内行进和选择奖励均计入总时间；暂停不计时。\n战斗用时 %02d:%02d"%[int(s.get("combat_time",0))/60,int(s.get("combat_time",0))%60]
	else:
		timer_label.tooltip_text="当前独立首房计时仅累计战斗阶段。"
	detail.text=("靠近门前的宝物箱\n领取后开启传送门" if s.get("reward_pickup",{}).get("kind","")=="artifact" else "靠近门前的法术书\n领取后开启传送门") if phase=="pickup" else ("护盾已补满\n生命保留当前值" if phase in ["reward","exit"] else "留意红色攻击预警\n石质掩体会阻挡直射")
	detail.visible=bool(preferences.get("view_hints",true)) and phase in ["combat","pickup"]
	if phase=="pickup" and not s.get("boss_rewards",{}).is_empty():
		detail.text="先领取法术书，再开必金宝箱\n两份奖励领完开启传送门" if not bool(s.boss_rewards.book_resolved) else "靠近门前金色宝箱\n必出合资格金色宝物"
	if phase=="shop":
		detail.text="靠近左侧柜台领取补给\n上方传送门继续旅途"
		detail.visible=bool(preferences.get("view_hints",true))
	for hint in hint_nodes:hint.visible=bool(preferences.get("view_hints",true)) and phase=="combat"
	for i in range(8):
		if i>=s.spells.size():
			if slot_icons[i].spell_id!="empty":
				slot_icons[i].spell_id="empty"
				slot_icons[i].tint=T.LINE
				slot_icons[i].queue_redraw()
			spell_labels[i].text="空槽"
			cooldown_labels[i].text=""
			cooldown_labels[i].visible=false
			slot_bars[i].value=0
			slots[i].tooltip_text="尚未习得法术；清房时可以选择新法术。"
			continue
		var spell:Dictionary=s.spells[i]
		cooldown_labels[i].visible=true
		if slot_icons[i].spell_id!=str(spell.id):
			slot_icons[i].spell_id=str(spell.id)
			slot_icons[i].tint=Catalog.school_color(str(Catalog.describe_spell(str(spell.id)).get("school","fire")))
			slot_icons[i].queue_redraw()
		spell_labels[i].text=str(spell.name)
		var remaining=float(spell.get("remaining",0))
		var chant=float(spell.get("cast_remaining",0))
		var passive=str(Catalog.SPELL_ROLES.get(str(spell.id),"")).begins_with("被动")
		var status="被动" if passive else ("战后" if phase!="combat" else ("吟唱中" if chant>0 else ("冷却 %.1f秒"%remaining if remaining>0 else "就绪")))
		cooldown_labels[i].text="%d级"%spell.level
		slots[i].tooltip_text="%s · %d级\n%s\n%s"%[spell.name,spell.level,status,Catalog.SPELL_SUMMARIES.get(str(spell.id),"")]
		slot_bars[i].value=1-clampf(remaining/maxf(.001,float(spell.get("cooldown",1))),0,1)
		slot_bars[i].modulate=T.CYAN if chant>0 else Color.WHITE
	var modal_kind="pause" if s.paused else phase if phase in ["choosing","reward","artifact","shopping"] else ""
	var pending:Dictionary=s.get("pending_replacement",{})
	if not s.paused and phase=="reward" and not pending.is_empty():
		modal_kind="replace:%d:%d"%[int(pending.get("room_revision",-1)),int(pending.get("request_id",-1))]
	if modal_kind!=last_modal:
		last_modal=modal_kind
		_clear_modal()
		if modal_kind=="pause":_pause_modal(route)
		elif modal_kind.begins_with("replace:"):_replacement_modal(pending)
		elif modal_kind=="artifact":_artifact_modal(s)
		elif modal_kind=="shopping":
			_new_modal()
			_shop_ui=ShopUI.new()
			modal.add_child(_shop_ui)
			_shop_ui.requested.connect(emit)
			_shop_ui.build(s)
		elif modal_kind in ["choosing","reward"]:_choice_modal(s,modal_kind)
	elif modal_kind=="shopping" and is_instance_valid(_shop_ui):
		_shop_ui.refresh(s)

func _sync_artifact_bar(items:Array):
	artifact_bar.visible=not items.is_empty()
	var signature=""
	for item in items:signature+=str(item.id)+";"
	if signature==_artifact_signature:return
	_artifact_signature=signature
	artifact_bar.size.x=140+maxi(0,items.size()-1)*47
	for child in artifact_bar.get_children():
		artifact_bar.remove_child(child)
		child.queue_free()
	T.label(artifact_bar,"宝 物",Rect2(13,10,70,28),17,T.GOLD)
	for i in range(items.size()):
		var item:Dictionary=items[i]
		var slot=Control.new()
		slot.position=Vector2(88+i*47,4)
		slot.size=Vector2(40,40)
		var description:Dictionary=Catalog.describe_artifact(str(item.id))
		slot.tooltip_text="%s · %s\n%s"%[str(item.name),str(description.get("scope_name","宝物")),str(description.get("description",""))]
		artifact_bar.add_child(slot)
		var icon=ArtifactIcon.new()
		icon.size=Vector2(40,40)
		icon.set_item(str(item.id),str(item.rarity))
		slot.add_child(icon)

func _artifact_modal(s:Dictionary):
	_new_modal()
	_choice_heading("首领宝箱 · 必得金色宝物" if not s.get("boss_rewards",{}).is_empty() else "选择一件宝物","本局持续生效，不占法术槽。")
	var choices:Array=s.get("artifact_choices",[])
	var start=800.0-(choices.size()*280.0+maxi(0,choices.size()-1)*24.0)*0.5
	for i in range(choices.size()):
		var item:Dictionary=choices[i]
		var id=str(item.id)
		var description:Dictionary=Catalog.describe_artifact(id)
		var color=Color("81d5f0") if item.rarity=="blue" else Color("c5a0f3") if item.rarity=="purple" else T.GOLD
		var card=_make_choice_card(Vector2(start+i*304,246),"room_artifact",id,color)
		var p:Control=card.face
		T.label(p,str(description.get("rarity_name",item.rarity))+" · "+str(description.get("school_name",description.get("scope_name","宝物"))),Rect2(26,30,228,26),16,color)
		var icon=ArtifactIcon.new()
		icon.position=Vector2(96,60)
		icon.size=Vector2(88,88)
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		icon.set_item(id,str(item.rarity))
		p.add_child(icon)
		var title=T.label(p,str(item.name),Rect2(20,153,240,40),25)
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		T.paragraph(p,str(description.get("card_description",description.get("description",""))),Rect2(22,204,236,166),16 if id.begins_with("GT") else 17,T.TEXT)
		var requirement_y=358 if str(description.get("scope",""))=="ice" else 374
		T.paragraph(p,str(description.get("card_requirement",description.get("requirement","本局生效"))),Rect2(22,requirement_y,236,56),16,T.MUTED)
		card.hit.tooltip_text=str(item.name)+" · "+str(description.get("scope_name","宝物"))+"\n"+str(description.get("description",""))+"\n"+str(description.get("requirement",""))+_acquisition_hint(id,description,s)
	_finish_choice_setup()
func _clear_modal():
	_shop_ui=null
	_choice_buttons.clear()
	_choice_cards.clear()
	_choice_active=false
	_choice_keyboard=false
	_reward_skip_button=null
	_replacement_buttons.clear()
	_replacement_pending={}
	_replacement_active=false
	_replacement_target=null
	_replacement_confirm=null
	if is_instance_valid(modal):
		root.remove_child(modal)
		modal.queue_free()
	modal=null
func _new_modal():
	_clear_modal()
	modal=Control.new()
	modal.size=root.size
	root.add_child(modal)
	var dim=ColorRect.new()
	dim.color=Color(.025,.035,.07,.7)
	dim.size=root.size
	modal.add_child(dim)
func _focus_first(activate:bool=true):
	if not is_inside_tree() or not is_instance_valid(modal) or not modal.is_inside_tree():return
	var buttons:Array=[]
	for b in modal.find_children("*","Button",true,false):
		if not b.disabled:buttons.append(b)
	for i in range(buttons.size()):
		var b:Button=buttons[i]
		var next=b.get_path_to(buttons[(i+1)%buttons.size()])
		var previous=b.get_path_to(buttons[(i+buttons.size()-1)%buttons.size()])
		b.focus_next=next
		b.focus_previous=previous
		b.focus_neighbor_right=next
		b.focus_neighbor_bottom=next
		b.focus_neighbor_left=previous
		b.focus_neighbor_top=previous
	if activate and not buttons.is_empty():buttons[0].grab_focus()

func _choice_heading(title:String,subtitle:String):
	var heading=T.label(modal,title,Rect2(340,165,920,48),32)
	heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var intro=T.label(modal,subtitle,Rect2(340,218,920,28),18,T.MUTED)
	intro.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var keyboard=T.label(modal,"点击卡牌选择    ·    方向键 / Tab 切换    ·    Enter 确认",Rect2(340,700,920,32),17,T.MUTED)
	keyboard.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

func _make_choice_card(position:Vector2,action:String,id:String,color:Color):
	var card=ChoiceCard.new()
	card.position=position
	modal.add_child(card)
	card.setup(action,id,color)
	var revision=_choice_room_revision
	var modal_token=last_modal
	card.hit.pressed.connect(func():_accept_choice(action,id,revision,modal_token))
	card.hit.mouse_entered.connect(func():_set_choice_keyboard(false))
	card.reveal_finished.connect(_unlock_choices)
	_choice_cards.append(card)
	_choice_buttons.append(card.hit)
	return card

func _finish_choice_setup():
	for i in range(_choice_cards.size()):
		_choice_cards[i].reveal(i,bool(preferences.get("reduced_motion",false)))

func _unlock_choices():
	for card in _choice_cards:
		if not card.reveal_complete:return
	for card in _choice_cards:
		card.hit.disabled=false
		card._restyle()
	if is_instance_valid(_reward_skip_button):_reward_skip_button.disabled=false
	var focused=get_viewport().gui_get_focus_owner()
	if focused!=null:focused.release_focus()
	_choice_active=true
	call_deferred("_focus_first",false)

func _accept_choice(action:String,id:String,expected_revision:int=-1,modal_token:String=""):
	if not _choice_active:return
	if not modal_token.is_empty() and modal_token!=last_modal:return
	if action=="room_reward" and expected_revision!=-1 and expected_revision!=_choice_room_revision:return
	_choice_active=false
	for button in _choice_buttons:button.disabled=true
	emit(action,{"spell_id":id,"room_revision":expected_revision if expected_revision!=-1 else _choice_room_revision} if action=="room_reward" else id)

func _set_choice_keyboard(value:bool):
	if value!=_choice_keyboard:
		_choice_keyboard=value
		for card in _choice_cards:card.set_keyboard_focus(value)
		if is_instance_valid(_reward_skip_button):
			_reward_skip_button.add_theme_stylebox_override("focus",T.box(Color.TRANSPARENT,T.GOLD,2) if value else StyleBoxEmpty.new())
	if not value:
		for button in _choice_buttons:
			if not is_instance_valid(button):continue
			# Releasing focus during a mouse press cancels BaseButton's click.
			if button.has_focus() and not button.is_pressed():button.release_focus()

func _input(event:InputEvent):
	if not _replacement_pending.is_empty() and is_instance_valid(modal):
		_replacement_input(event)
		return
	if not is_instance_valid(modal) or _choice_cards.is_empty():return
	if not _choice_active:
		# A modal still owns keyboard input while its cards turn over. Never let
		# Tab/Enter reach a HUD button behind the disabled reveal targets.
		if event is InputEventKey and (event.is_action("ui_accept") or event.is_action("ui_left") or event.is_action("ui_right") or event.is_action("ui_up") or event.is_action("ui_down") or event.is_action("ui_focus_next") or event.is_action("ui_focus_prev")):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_set_choice_keyboard(false)
	elif event is InputEventKey and event.pressed and not event.echo:
		var backwards=event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_focus_prev")
		var navigation=backwards or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_focus_next")
		if not navigation:return
		_set_choice_keyboard(true)
		if not _choice_buttons.has(get_viewport().gui_get_focus_owner()) and not _choice_buttons.is_empty():
			if backwards:
				_choice_buttons.back().grab_focus()
			else:
				_choice_buttons[0].grab_focus()
			get_viewport().set_input_as_handled()
func _choice_modal(s:Dictionary,kind:String):
	_new_modal()
	_choice_room_revision=int(s.get("room_revision",-1))
	var full_slots=kind=="reward" and s.get("spells",[]).size()>=8
	_choice_heading("选择起始法术" if kind=="choosing" else "选择法术成长","选一张，开始试炼。法术会自动施放。" if kind=="choosing" else "槽位已满：新术可替换旧术，已学法术可升级。" if full_slots else "学习新法术，或强化已掌握的法术。")
	var choices:Array=s.get("initial_choices",[{"id":"F01"},{"id":"F04"},{"id":"F08"}]) if kind=="choosing" else s.reward_choices
	var card_start=800.0-(float(choices.size())*280.0+float(maxi(0,choices.size()-1))*24.0)*0.5
	for i in range(choices.size()):
		var choice:Dictionary=choices[i]
		var id=str(choice.id)
		var level=1 if kind=="choosing" else int(choice.get("next_level",1))
		var data:Dictionary=Catalog.describe_spell(id,level,s.has("room_total"))
		var color=Catalog.school_color(str(data.get("school","fire")))
		var card=_make_choice_card(Vector2(card_start+i*304,246),"room_initial" if kind=="choosing" else "room_reward",id,color)
		var p:Control=card.face
		T.label(p,("起始法术" if kind=="choosing" else ("替换学习" if full_slots and level==1 else "新法术" if level==1 else "法术升级"))+" · "+str(data.get("element","")),Rect2(26,30,172,26),16,T.CYAN)
		T.label(p,"Ⅰ" if level==1 else "Ⅱ" if level==2 else "Ⅲ",Rect2(230,30,28,26),17,T.GOLD)
		T.icon(p,id,Rect2(104,58,72,72),color)
		var name_label=T.label(p,str(data.name),Rect2(20,130,240,36),25)
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var role=T.label(p,str(data.role),Rect2(22,169,236,26),16,T.GOLD)
		role.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		T.paragraph(p,str(data.summary),Rect2(22,205,236,64),18,T.TEXT)
		T.label(p,"获得 · 1级" if level==1 else "%d级 → %d级"%[level-1,level],Rect2(22,274,236,24),16,T.CYAN)
		T.paragraph(p,str(data.upgrade_text) if level>1 else str(data.get("card_description",data.description)),Rect2(22,304,236,126),17,T.MUTED)
		card.hit.tooltip_text=str(data.name)+"\n"+str(data.description)+"\n"+str(data.boundary)
	if kind=="reward" and bool(s.get("can_skip_spell_reward",false)):
		var revision=_choice_room_revision
		_reward_skip_button=T.button(modal,"保留构筑，放弃本次奖励",Rect2(550,746,500,48),func():_skip_spell_reward(revision),false,true)
		_reward_skip_button.name="SkipSpellReward"
		_reward_skip_button.set_meta("choice_action","room_reward_skip")
		_reward_skip_button.set_meta("room_revision",_choice_room_revision)
		_reward_skip_button.tooltip_text="保留当前法术，放弃本次法术奖励并开启传送门。不会重抽。"
		_reward_skip_button.mouse_entered.connect(func():_set_choice_keyboard(false))
		_choice_buttons.append(_reward_skip_button)
	_finish_choice_setup()

func _skip_spell_reward(expected_revision:int):
	if not _choice_active or not is_instance_valid(_reward_skip_button) or _reward_skip_button.disabled:return
	if last_modal!="reward" or expected_revision!=_choice_room_revision:return
	_choice_active=false
	for button in _choice_buttons:button.disabled=true
	emit("room_reward_skip",{"room_revision":expected_revision})

func _upgrade_changes(id:String,level:int)->String:
	return Catalog.spell_upgrade_text(id,level)

func _replacement_modal(pending:Dictionary):
	_new_modal()
	_replacement_pending=pending.duplicate(true)
	var request_id=int(pending.get("request_id",-1))
	if request_id!=_replacement_last_request:
		_replacement_last_request=request_id
		_replacement_focus_index=0
		_replacement_keyboard=false
		_replacement_selected_index=-1
	modal.name="SpellReplacementModal"
	modal.set_meta("replacement_request_id",request_id)
	modal.set_meta("room_revision",int(pending.get("room_revision",-1)))
	var id=str(pending.get("spell_id",""))
	var data:Dictionary=Catalog.describe_spell(id,1)
	var new_name=str(data.get("name",id))
	var title=T.label(modal,"替换一个法术",Rect2(300,152,1000,48),32)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var intro=T.label(modal,"槽位已满。选择遗忘一项旧术，新学法术从1级开始。",Rect2(300,208,1000,30),19,T.MUTED)
	intro.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var preview=ChoiceCard.new()
	preview.name="ReplacementNewSpell"
	preview.position=Vector2(252,266)
	modal.add_child(preview)
	preview.setup("replacement_preview",id,Catalog.school_color(str(data.get("school","fire"))))
	preview.reveal_immediately()
	preview.hit.disabled=true
	var face:Control=preview.face
	T.label(face,"待学法术 · 1级",Rect2(26,30,228,26),16,T.CYAN)
	T.icon(face,id,Rect2(104,58,72,72),Catalog.school_color(str(data.get("school","fire"))))
	var name_label=T.label(face,new_name,Rect2(20,130,240,36),25)
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var role=T.label(face,str(data.get("role","")),Rect2(22,169,236,26),16,T.GOLD)
	role.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	T.paragraph(face,str(data.get("summary","")),Rect2(22,205,236,64),18,T.TEXT)
	T.label(face,"替换后获得 · 1级",Rect2(22,274,236,24),16,T.CYAN)
	T.paragraph(face,str(data.get("card_numeric",data.get("description",""))),Rect2(22,304,236,126),17,T.MUTED)
	preview.tooltip_text=new_name+" · 1级\n"+str(data.get("description",""))+"\n"+str(data.get("boundary",""))
	preview.hit.tooltip_text=preview.tooltip_text
	preview.mouse_filter=Control.MOUSE_FILTER_PASS
	_replacement_target=T.label(modal,"先选一个旧槽，再确认替换",Rect2(574,250,774,32),20,T.GOLD)
	_replacement_target.name="ReplacementTarget"
	var old_slots:Array=pending.get("slots",[])
	for index in old_slots.size():
		var old:Dictionary=old_slots[index]
		var old_id=str(old.get("id",""))
		var old_name=Catalog.spell_name(old_id)
		var old_level=int(old.get("level",1))
		var button=T.button(modal,"",Rect2(574+(index%4)*198,292+(index/4)*180,180,164),func():_select_replacement(index,true,request_id))
		button.name="ReplaceSpellSlot%d"%index
		button.set_meta("choice_action","replacement_select")
		button.set_meta("replacement_slot_index",index)
		button.set_meta("replacement_old_id",old_id)
		button.set_meta("replacement_request_id",request_id)
		button.tooltip_text="选择待替换法术：%s · %d级\n确认后学会%s · 1级。取消可返回原三张奖励，不会重抽。"%[old_name,old_level,new_name]
		var socket=TextureRect.new()
		socket.texture=SLOT_TEXTURE
		socket.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		socket.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		socket.position=Vector2(40,28)
		socket.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(socket)
		socket.size=Vector2(100,92)
		T.icon(button,old_id,Rect2(61,42,58,58),Catalog.school_color(str(Catalog.describe_spell(old_id).get("school","fire"))))
		var slot_label=T.label(button,"第%d槽 · %d级"%[index+1,old_level],Rect2(10,5,160,24),16,T.MUTED)
		slot_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var old_label=T.label(button,old_name,Rect2(8,118,164,28),20,T.TEXT)
		old_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		button.focus_entered.connect(func():_replacement_focus(index))
		button.mouse_entered.connect(func():_set_replacement_keyboard(false);_replacement_focus(index))
		_replacement_buttons.append(button)
	var cancel=btn(modal,"返回原三张奖励",Rect2(574,666,378,48),"room_replace_cancel",_replacement_payload())
	cancel.name="CancelSpellReplacement"
	cancel.set_meta("choice_action","room_replace_cancel")
	cancel.set_meta("replacement_request_id",request_id)
	cancel.focus_entered.connect(func():_replacement_focus(8))
	cancel.mouse_entered.connect(func():_set_replacement_keyboard(false);_replacement_focus(8))
	_replacement_buttons.append(cancel)
	_replacement_confirm=T.button(modal,"确认替换",Rect2(970,666,378,48),func():_confirm_replacement(request_id),true,true)
	_replacement_confirm.name="ConfirmSpellReplacement"
	_replacement_confirm.set_meta("choice_action","room_replace")
	_replacement_confirm.set_meta("replacement_request_id",request_id)
	_replacement_confirm.focus_entered.connect(func():_replacement_focus(9))
	_replacement_confirm.mouse_entered.connect(func():_set_replacement_keyboard(false);_replacement_focus(9))
	_replacement_buttons.append(_replacement_confirm)
	var pause=btn(modal,"暂停选择",Rect2(1448,28,120,50),"room_pause")
	pause.name="PauseSpellReplacement"
	pause.tooltip_text="暂停后继续，返回当前替换选择。"
	pause.focus_entered.connect(func():_replacement_focus(10))
	pause.mouse_entered.connect(func():_set_replacement_keyboard(false);_replacement_focus(10))
	_replacement_buttons.append(pause)
	var footer=T.label(modal,"选中旧槽，再确认替换    ·    方向键 / Tab 切换    ·    Enter 选择    ·    Esc 返回三选一",Rect2(240,738,1120,32),17,T.MUTED)
	footer.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_replacement_active=true
	if _replacement_selected_index>=0:_select_replacement(_replacement_selected_index,false)
	_set_replacement_keyboard(_replacement_keyboard)
	call_deferred("_restore_replacement_focus",request_id)

func _replacement_payload()->Dictionary:
	return {"request_id":int(_replacement_pending.get("request_id",-1)),"room_revision":int(_replacement_pending.get("room_revision",-1))}

func _select_replacement(index:int,move_focus:bool=true,expected_request_id:int=-1):
	if expected_request_id!=-1 and expected_request_id!=int(_replacement_pending.get("request_id",-2)):return
	var old_slots:Array=_replacement_pending.get("slots",[])
	if index<0 or index>=old_slots.size():return
	_replacement_selected_index=index
	for slot_index in old_slots.size():
		var selected=slot_index==index
		_replacement_buttons[slot_index].add_theme_stylebox_override("normal",T.box(Color("30394e") if selected else Color("252d42"),T.GOLD if selected else T.LINE,2 if selected else 1))
	var old:Dictionary=old_slots[index]
	var old_name=Catalog.spell_name(str(old.id))
	_replacement_target.text="确认替换：%s · %d级 → %s · 1级"%[old_name,int(old.get("level",1)),Catalog.spell_name(str(_replacement_pending.get("spell_id","")))]
	_replacement_confirm.text="确认替换「%s」"%old_name
	_replacement_confirm.set_meta("replacement_slot_index",index)
	_replacement_confirm.disabled=false
	if move_focus and _replacement_keyboard:_replacement_confirm.grab_focus()

func _confirm_replacement(expected_request_id:int):
	if not _replacement_active or _replacement_selected_index<0:return
	if expected_request_id!=int(_replacement_pending.get("request_id",-2)):return
	_replacement_active=false
	for button in _replacement_buttons:button.disabled=true
	var payload=_replacement_payload()
	payload["slot_index"]=_replacement_selected_index
	emit("room_replace",payload)

func _replacement_focus(index:int):
	_replacement_focus_index=index

func _set_replacement_keyboard(value:bool):
	_replacement_keyboard=value
	for button in _replacement_buttons:
		button.add_theme_stylebox_override("focus",T.box(Color.TRANSPARENT,T.GOLD,2) if value else StyleBoxEmpty.new())
		if not value and button.has_focus() and not button.is_pressed():button.release_focus()

func _restore_replacement_focus(request_id:int):
	if int(_replacement_pending.get("request_id",-2))!=request_id:return
	if _replacement_keyboard and not _replacement_buttons.is_empty():
		_replacement_buttons[clampi(_replacement_focus_index,0,_replacement_buttons.size()-1)].grab_focus()

func _replacement_input(event:InputEvent):
	if not _replacement_active:return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_set_replacement_keyboard(false)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			emit("room_replace_cancel",_replacement_payload())
			return
		var navigation=event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev")
		if not navigation and not event.is_action_pressed("ui_accept"):return
		var owner=get_viewport().gui_get_focus_owner()
		var index=_replacement_buttons.find(owner)
		_set_replacement_keyboard(true)
		if index<0:
			index=clampi(_replacement_focus_index,0,_replacement_buttons.size()-1)
		elif event.is_action_pressed("ui_focus_prev"):
			index=(index+_replacement_buttons.size()-1)%_replacement_buttons.size()
			while _replacement_buttons[index].disabled:index=(index+_replacement_buttons.size()-1)%_replacement_buttons.size()
		elif event.is_action_pressed("ui_focus_next"):
			index=(index+1)%_replacement_buttons.size()
			while _replacement_buttons[index].disabled:index=(index+1)%_replacement_buttons.size()
		elif event.is_action_pressed("ui_left"):
			index=(index+7)%8 if index<8 else 7
		elif event.is_action_pressed("ui_right"):
			index=(index+1)%8 if index<8 else 0
		elif event.is_action_pressed("ui_up"):
			index=index-4 if index>=4 and index<8 else 8 if index<4 else 4
		elif event.is_action_pressed("ui_down"):
			index=index+4 if index<4 else 8 if index<8 else 0
		elif event.is_action_pressed("ui_accept"):
			_replacement_buttons[index].pressed.emit()
			get_viewport().set_input_as_handled()
			return
		_replacement_buttons[index].grab_focus()
		get_viewport().set_input_as_handled()

func _attribute_text(s:Dictionary)->String:
	var p:Dictionary=s.get("player",{})
	var stats:Dictionary=s.get("combat_stats",{})
	var base:Dictionary=_display_catalog.get("base",{})
	var synergy:Dictionary=base.get("fire_synergy",{})
	var limits:Dictionary=base.get("limits",{})
	var reduction=float(stats.get("cooldown_reduction_add",0.0))+float(p.get("gem_cdr",0.0))
	var formal_count=int(stats.get("formal_fire_count",s.get("spells",[]).size()))
	if formal_count>=int(synergy.get("distinct_spells",0)):
		reduction+=float(synergy.get("cooldown_reduction",0.0))
	var cap=float(limits.get("cooldown_reduction",0.0))
	var global_multiplier=float(p.get("crit_multiplier",base.get("player",{}).get("crit_multiplier",0.0)))+float(stats.get("crit_multiplier_add",0.0))
	var ice_reduction=float(stats.get("ice_cooldown_reduction",stats.get("cooldown_reduction_add",0.0)))
	var lightning_reduction=float(stats.get("lightning_cooldown_reduction",stats.get("cooldown_reduction_add",0.0)))
	var wind_reduction=float(stats.get("wind_cooldown_reduction",stats.get("cooldown_reduction_add",0.0)))
	var earth_reduction=float(stats.get("earth_cooldown_reduction",stats.get("cooldown_reduction_add",0.0)))
	var spirit_reduction=float(stats.get("spirit_cooldown_reduction",stats.get("cooldown_reduction_add",0.0)))
	return "攻击%s · 防御%s · 减伤%s／飞弹%s\n全局暴击%s×%s · 火%s×%s\n冷却火%s／冰%s／雷%s\n冷却风%s／岩%s／灵契%s（最高%s）\n移速%s · 通用增伤%s\n本系增伤：火%s／冰%s／雷%s\n风%s／岩%s／灵契%s"%[
		Catalog._number(p.get("attack",0)),Catalog._number(stats.get("defense",0)),Catalog._percent(stats.get("damage_reduction",0)),Catalog._percent(stats.get("projectile_damage_reduction",0)),
		Catalog._percent(p.get("crit_rate",0)),Catalog._number(global_multiplier),Catalog._percent(stats.get("fire_crit_rate",p.get("crit_rate",0))),Catalog._number(stats.get("fire_crit_multiplier",global_multiplier)),Catalog._percent(minf(cap,reduction)),Catalog._percent(minf(cap,ice_reduction)),Catalog._percent(minf(cap,lightning_reduction)),Catalog._percent(minf(cap,wind_reduction)),Catalog._percent(minf(cap,earth_reduction)),Catalog._percent(minf(cap,spirit_reduction)),Catalog._percent(cap),
		Catalog._number(float(p.get("move_speed",0))*float(stats.get("move_speed_multiplier",1))),Catalog._percent(stats.get("generic_damage_bonus",0)),Catalog._percent(stats.get("fire_bonus",0)),Catalog._percent(stats.get("ice_bonus",0)),Catalog._percent(stats.get("lightning_bonus",0)),Catalog._percent(stats.get("wind_bonus",0)),Catalog._percent(stats.get("earth_bonus",0)),Catalog._percent(stats.get("spirit_bonus",0))]

func _generic_status_text(s:Dictionary)->String:
	var state:Dictionary=s.get("generic_items",{})
	var stats:Dictionary=s.get("combat_stats",{})
	var parts:Array[String]=[]
	for item in s.get("artifacts",[]):
		match str(item.id):
			"GU17":parts.append("狩猎 %d层 · %.1f秒"%[int(state.get("hunting_stacks",0)),float(state.get("hunting_remaining",0))])
			"GT01":parts.append("蓄能 %s"%Catalog._number(state.get("charge",0)))
			"GU15":
				if bool(stats.get("undamaged_active",false)):parts.append("完璧生效")
			"GU18":
				if bool(stats.get("stationary_active",false)):parts.append("凝定生效")
			"GT02":
				if bool(stats.get("low_health_active",false)):parts.append("逆境生效")
	return "   ·   ".join(parts)

func _acquisition_hint(id:String,description:Dictionary,s:Dictionary)->String:
	var values:Dictionary=description.get("values",{})
	if id in ["GU04","GU12"]:
		var stats:Dictionary=s.get("combat_stats",{})
		var rules:Dictionary=_display_catalog.get("generic_source",{}).get("rules",{})
		var coefficient=float(rules.get("defense_coefficient",0))
		var cap=float(rules.get("maximum_damage_reduction",0))
		var defense=float(stats.get("defense",0))
		var after=1.0-maxf(1.0-cap,coefficient/(coefficient+defense+float(values.get("defense_add",0)))) if coefficient>0 else 0.0
		return "\n普通伤害减免：%s → %s（领取后）"%[Catalog._percent(stats.get("damage_reduction",0)),Catalog._percent(after)]
	if id=="GT02":
		var player:Dictionary=s.get("player",{})
		var active=float(player.get("health",0))<=float(player.get("max_health",0))*float(values.get("health_fraction_threshold",0))
		return "\n当前生命条件："+("已满足，领取后生效" if active else "未满足")
	return ""

func _pause_modal(route:bool=false):
	_new_modal()
	var p=T.panel(modal,Rect2(520,210,560,478),true)
	T.icon(p,"F10",Rect2(42,29,68,68),T.CYAN)
	T.label(p,"休息片刻",Rect2(127,28,390,66),38)
	T.paragraph(p,"时间已暂停 · 结束后结算已清战斗房的魔尘。",Rect2(42,123,476,56),20)
	var attributes=T.paragraph(p,_attribute_summary,Rect2(42,187,476,90),15,T.CYAN)
	attributes.name="PausedAttributes"
	btn(p,"继续试炼",Rect2(42,282,476,60),"room_resume","",true)
	btn(p,"结束试玩",Rect2(42,364,476,56),"room_end")
	T.label(p,"Esc 继续",Rect2(42,435,476,26),16,T.MUTED)
	call_deferred("_focus_first")
func show_result(summary:Dictionary,settlement:Dictionary,reason:String):
	_finished=true
	_new_modal()
	var p=T.panel(modal,Rect2(398,166,804,570),true)
	var route=summary.get("scope","")=="early_route_map_trial"
	var route_count:int=int(summary.get("room_total",0))
	T.label(p,(("%d房路线试玩完成"%route_count) if route else "首房试玩完成") if reason=="complete" else "这段旅途暂告一段落",Rect2(42,30,720,66),38)
	var description="你已穿过上方法阵，完成入场、战斗与成长。\n后续房间将在这个流程上继续制作。" if reason=="complete" else "已经清过的房间会保留魔尘收益。\n带上这次的经验，准备下一场试炼。"
	if route:
		description="已完成%d房战斗路线。"%route_count if reason=="complete" else "本次战斗路线已经结束。"
		description+="\n已清战斗房的魔尘会保留；商店不计清房或额外收益。"
	T.paragraph(p,description,Rect2(42,113,720,80),22)
	var labels=["已清房间","击败敌人","路线用时" if route else "战斗时间","本局金币"]
	var values=[str(summary.get("clear_count",0)),str(summary.get("kills",0)),"%02d:%02d"%[int(summary.get("elapsed",0))/60,int(summary.get("elapsed",0))%60],str(summary.get("gold",0))]
	for i in range(4):
		var cell=T.panel(p,Rect2(42+i*184,227,168,99))
		if i==2 and route:
			cell.mouse_filter=Control.MOUSE_FILTER_PASS
			cell.tooltip_text="战斗用时 %02d:%02d；路线用时还包含房内行进和选择奖励的时间。"%[int(summary.get("combat_time",0))/60,int(summary.get("combat_time",0))%60]
		T.label(cell,labels[i],Rect2(16,10,136,28),17,T.MUTED)
		T.label(cell,values[i],Rect2(16,41,136,44),29,T.GOLD)
	if route:
		T.label(p,"金币取得 %d  ·  消费 %d  ·  剩余 %d"%[int(summary.get("gold_earned",0)),int(summary.get("gold_spent",0)),int(summary.get("gold",0))],Rect2(42,335,720,28),18,T.GOLD)
	if settlement.get("ok",false):
		T.label(p,"魔尘 +%d    ·    已保存到账户"%int(settlement.get("dust_earned",0)),Rect2(42,366,720,46),27,T.CYAN)
		btn(p,"再次试玩",Rect2(42,467,338,60),"room_retry","",true)
		btn(p,"返回准备",Rect2(422,467,338,60),"room_return")
	else:
		T.paragraph(p,str(settlement.get("error","保存失败，进度仍保留在本次试玩中。")),Rect2(42,354,720,74),21)
		btn(p,"重试保存",Rect2(42,467,718,60),"room_save_retry","",true)
	call_deferred("_focus_first")
