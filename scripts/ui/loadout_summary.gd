extends RefCounted
## Read-only loadout presentation shared by the preparation screen and the pause
## panel. It draws prepared numbers only; nothing here feeds combat or RNG.

const T = preload("res://scripts/ui/atelier_theme.gd")
const GemIcon = preload("res://scripts/ui/gem_icon.gd")

const UNIT_FLAT = "flat"
const UNIT_PERCENT = "percent"
const UNIT_MULTIPLIER = "multiplier"
const BONUS = Color("7ddfe6")
const SUB = Color("8d97ad")
const IDLE = Color("7a839a")
## 每项属性的一句话说明；只写成规则，不写具体数值，数值由 data 决定。
const HINTS = {
	"attack": "法术伤害的基准倍率。",
	"health": "生命归零时本局结束。",
	"shield": "优先承受伤害，清场后补满。",
	"defense": "换算为伤害减免，与其他来源共用综合上限。",
	"crit_rate": "决定是否暴击，达到 100% 时必定暴击。",
	"crit_multiplier": "暴击时的伤害倍率。",
	"cdr": "缩短主动法术冷却；不影响吟唱与召唤物攻击。",
	"speed": "只影响战斗中的移动速度。",
}

static func hint_for(key: String) -> String:
	return str(HINTS.get(key, ""))

static func number(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value, roundf(value)) else String.num(value, 1)

static func percent(value: float) -> String:
	var scaled: float = value * 100.0
	return number(scaled) + "%"

static func final_text(row: Dictionary) -> String:
	match str(row.get("unit", UNIT_FLAT)):
		UNIT_PERCENT:
			return percent(float(row.get("final", 0.0)))
		UNIT_MULTIPLIER:
			return "×" + String.num(float(row.get("final", 0.0)), 2)
	return number(float(row.get("final", 0.0)))

static func sub_text(row: Dictionary) -> String:
	var unit: String = str(row.get("unit", UNIT_FLAT))
	var base: float = float(row.get("base", 0.0))
	var bonus: float = float(row.get("bonus", 0.0))
	var mark: String = "＋" if bonus >= 0.0 else "－"
	match unit:
		UNIT_PERCENT:
			return "基础 %s %s %s" % [percent(base), mark, percent(absf(bonus))]
		UNIT_MULTIPLIER:
			return "基础 %s× %s %s" % [String.num(base, 2), mark, String.num(absf(bonus), 2)]
	return "基础 %s %s %s" % [number(base), mark, number(absf(bonus))]

static func stat_grid(parent: Node, rect: Rect2, rows: Array, columns: int = 2, gap: Vector2 = Vector2(14, 10)) -> void:
	if rows.is_empty(): return
	var count: int = rows.size()
	var lines: int = int(ceil(float(count) / float(maxi(1, columns))))
	var width: float = (rect.size.x - gap.x * float(columns - 1)) / float(columns)
	var height: float = (rect.size.y - gap.y * float(maxi(0, lines - 1))) / float(lines)
	for index in count:
		var column: int = index % columns
		var line: int = int(floor(float(index) / float(columns)))
		var tile_rect := Rect2(rect.position + Vector2(float(column) * (width + gap.x), float(line) * (height + gap.y)), Vector2(width, height))
		stat_tile(parent, tile_rect, rows[index], height < 68.0)

static func stat_tile(parent: Node, rect: Rect2, row: Dictionary, compact: bool = false) -> Panel:
	var p := T.panel(parent, rect)
	p.add_theme_stylebox_override("panel", T.box(Color("141a29"), Color("2c3548"), 1, 6))
	var pad: float = 8.0 if compact else 12.0
	var at_cap: bool = bool(row.get("at_cap", false))
	var cap_label: String = str(row.get("cap_label", ""))
	if not cap_label.is_empty():
		var cap := T.label(p, cap_label, Rect2(rect.size.x - pad - 76.0, 4.0 if compact else 6.0, 76.0, 16.0), 11 if compact else 12, T.GOLD if at_cap else IDLE)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	T.label(p, str(row.get("label", "")), Rect2(pad, 4.0 if compact else 6.0, rect.size.x - pad * 2.0 - 78.0, 17.0), 12 if compact else 14, T.MUTED)
	T.label(p, final_text(row), Rect2(pad, 20.0 if compact else 24.0, rect.size.x - pad * 2.0, 26.0), 20 if compact else 27, T.GOLD if at_cap else T.TEXT)
	var bonus: float = float(row.get("bonus", 0.0))
	var sub := T.label(p, sub_text(row), Rect2(pad, rect.size.y - 22.0, rect.size.x - pad * 2.0, 16.0), 10 if compact else 12, BONUS if absf(bonus) > 0.0001 else SUB)
	var hint: String = str(row.get("tooltip", ""))
	if hint.is_empty(): hint = str(row.get("note", ""))
	if hint.is_empty(): hint = hint_for(str(row.get("key", "")))
	if not hint.is_empty():
		sub.tooltip_text = hint
		p.tooltip_text = hint
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p

static func effect_chips(parent: Node, rect: Rect2, effects: Array, empty_text: String) -> void:
	if effects.is_empty():
		T.label(parent, empty_text, rect, 13, IDLE)
		return
	var gap: float = 8.0
	var width: float = minf((rect.size.x - gap * float(effects.size() - 1)) / float(effects.size()), 210.0)
	for index in effects.size():
		var item: Dictionary = effects[index]
		var tint: Color = item.get("tint", T.CYAN)
		var chip := T.panel(parent, Rect2(rect.position.x + float(index) * (width + gap), rect.position.y, width, rect.size.y))
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_theme_stylebox_override("panel", T.box(Color(tint, 0.10), Color(tint, 0.45), 1, 6))
		chip.tooltip_text = str(item.get("description", ""))
		var icon := GemIcon.new()
		icon.item_id = "core:" + str(item.get("id", ""))
		icon.position = Vector2(8, (rect.size.y - 22.0) * 0.5)
		icon.size = Vector2(22, 22)
		chip.add_child(icon)
		var label := T.label(chip, str(item.get("name", "")), Rect2(36, 0, width - 44.0, rect.size.y), 13, tint)
		label.tooltip_text = chip.tooltip_text
