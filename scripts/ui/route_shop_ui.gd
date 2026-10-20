extends Control
## Read-only shop view. Requests carry the room revision captured on creation.
signal requested(action: String, payload: Variant)

const T = preload("res://scripts/ui/atelier_theme.gd")
const Catalog = preload("res://scripts/ui/grimoire_catalog.gd")
const ArtifactIcon = preload("res://scripts/ui/artifact_icon.gd")
var _revision: int = -1
var _balance: Label
var _status: Label
var _supply: Label
var _buy_buttons: Array = []
var _offers: Array = []
var _close: Button


func build(snapshot: Dictionary) -> void:
	_revision = int(snapshot.room_revision)
	size = Vector2(1600, 900)
	var shop: Dictionary = snapshot.shop
	var panel = T.panel(self, Rect2(214, 100, 1172, 704), true)
	panel.name = "ShopPanel"
	T.label(panel, "旅 途 商 店", Rect2(36, 22, 700, 50), 32, T.GOLD)
	T.label(panel, "第 %d 房后  ·  每店最多购买一件宝物" % int(shop.after_room), Rect2(36, 77, 800, 28), 18, T.MUTED)
	_balance = T.label(panel, "", Rect2(892, 29, 244, 40), 26, T.GOLD)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_supply = T.label(panel, "免费补给已领取：生命上限 +%s  ·  实际恢复 %s 生命" % [Catalog._number(shop.max_health_gain), Catalog._number(shop.health_restored)], Rect2(36, 117, 1098, 34), 19, T.CYAN)
	_offers = shop.offers.duplicate(true)
	var start: float = (1172.0 - float(_offers.size()) * 344.0 - float(maxi(0, _offers.size() - 1)) * 24.0) * 0.5
	for index in _offers.size():
		var item: Dictionary = _offers[index]
		var description: Dictionary = Catalog.describe_artifact(str(item.id))
		var color: Color = Color("81d5f0") if str(item.rarity) == "blue" else Color("c5a0f3") if str(item.rarity) == "purple" else T.GOLD
		var card = T.panel(panel, Rect2(start + index * 368.0, 172, 344, 420))
		card.name = "ShopItem%d" % index
		card.add_theme_stylebox_override("panel", T.box(T.PANEL, color.darkened(0.4), 1, 6))
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.tooltip_text = str(description.get("description", "")) + "\n" + str(description.get("requirement", ""))
		T.label(card, str(description.get("rarity_name", item.rarity)) + " · " + str(description.get("school_name", description.get("scope_name", "宝物"))), Rect2(18, 12, 308, 27), 16, color)
		var icon = ArtifactIcon.new()
		icon.position = Vector2(24, 51)
		icon.size = Vector2(68, 68)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_item(str(item.id), str(item.rarity))
		card.add_child(icon)
		T.label(card, str(item.name), Rect2(106, 59, 218, 42), 24)
		T.paragraph(card, str(description.get("card_description", description.get("description", ""))), Rect2(20, 130, 304, 154), 16 if str(item.id).begins_with("GT") else 17, T.TEXT)
		T.paragraph(card, str(description.get("card_requirement", description.get("requirement", "本局生效"))), Rect2(20, 290, 304, 64), 15, T.MUTED)
		var id: String = str(item.id)
		var revision: int = _revision
		var buy = T.button(card, "", Rect2(20, 360, 304, 46), func(): requested.emit("room_shop_buy", {"id": id, "room_revision": revision}), false)
		buy.name = "BuyShopItem%d" % index
		buy.set_meta("shop_item_id", id)
		_buy_buttons.append(buy)
	if _offers.is_empty():
		var empty = T.label(panel, "当前没有符合构筑条件的未持有宝物，补给已正常领取。", Rect2(54, 255, 1064, 80), 23, T.MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = T.label(panel, "", Rect2(36, 610, 776, 50), 18, T.CYAN)
	var revision: int = _revision
	_close = T.button(panel, "返回房间", Rect2(866, 610, 270, 52), func(): requested.emit("room_shop_close", {"room_revision": revision}), true)
	_close.name = "CloseShop"
	T.label(panel, "方向键 / Tab 选择  ·  Enter 确认  ·  Esc 暂停  ·  走进上方传送门继续旅途", Rect2(36, 674, 1100, 26), 15, T.MUTED)
	refresh(snapshot)


func refresh(snapshot: Dictionary) -> void:
	if int(snapshot.room_revision) != _revision:
		return
	var shop: Dictionary = snapshot.shop
	_balance.text = "金币  %d" % int(snapshot.gold)
	var purchased: String = str(shop.purchased_id)
	_status.text = "本店已购 · 宝物已生效，可以继续前进。" if not purchased.is_empty() else "本店商品固定；不买也可以返回房间，走门继续。"
	for index in _buy_buttons.size():
		var offer: Dictionary = _offers[index]
		var bought: bool = str(offer.id) == purchased
		var affordable: bool = int(snapshot.gold) >= int(offer.price)
		var button: Button = _buy_buttons[index]
		button.disabled = not purchased.is_empty() or not affordable
		button.text = "已购买 · %d 金币" % int(offer.price) if bought else "本店额度已用" if not purchased.is_empty() else "购买 · %d 金币" % int(offer.price) if affordable else "金币不足 · 需 %d" % int(offer.price)
		button.tooltip_text = "本店最多购买一件宝物。" if not purchased.is_empty() else "购买后立即生效。" if affordable else "还差 %d 金币。" % (int(offer.price) - int(snapshot.gold))
	_wire_focus()


func _wire_focus() -> void:
	var buttons: Array = _buy_buttons.filter(func(button): return not button.disabled)
	buttons.append(_close)
	for index in buttons.size():
		var button: Button = buttons[index]
		var next: NodePath = button.get_path_to(buttons[(index + 1) % buttons.size()])
		var previous: NodePath = button.get_path_to(buttons[(index + buttons.size() - 1) % buttons.size()])
		button.focus_next = next
		button.focus_previous = previous
		button.focus_neighbor_right = next
		button.focus_neighbor_bottom = next
		button.focus_neighbor_left = previous
		button.focus_neighbor_top = previous
	var focused = get_viewport().gui_get_focus_owner()
	if focused == null or (focused is BaseButton and focused.disabled):
		_close.grab_focus()
