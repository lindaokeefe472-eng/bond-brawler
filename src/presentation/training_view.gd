## 训练场面板：显示当前角色、站桩、距离，以及「上一次命中时到底隔了多远」。
##
## 只认 TrainingRoot.training_state() 给出的纯字典，不认识 ActorRuntime。
## 这样格式化逻辑可以脱离场景单测（见 test_training_view.gd）。
class_name TrainingView
extends CanvasLayer

## 放在 HUD（20）之上、流程覆盖层（30）之下：暂停时会被压暗，不挡结算界面。
const LAYER: int = 25
const PANEL_WIDTH: float = 620.0
const PANEL_TOP: float = 8.0
const FONT_SIZE: int = 14

var _label: Label = null

func _ready() -> void:
	layer = LAYER
	_build()

func render(state: Dictionary) -> void:
	if _label != null:
		_label.text = format_state(state)

func _build() -> void:
	_label = Label.new()
	_label.name = "Panel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_label.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	# 画布逻辑分辨率固定 1280×720（stretch = canvas_items），所以这里可以按像素居中。
	_label.position = Vector2((1280.0 - PANEL_WIDTH) * 0.5, PANEL_TOP)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_content_margin_all(8)
	style.set_corner_radius_all(4)
	_label.add_theme_stylebox_override("normal", style)
	add_child(_label)

## 纯函数：状态字典 -> 面板文本。用例直接断言它。
static func format_state(state: Dictionary) -> String:
	var player_name: String = str(state.get("player_character", "?"))
	var dummy_name: String = str(state.get("dummy_character", "?"))
	var player_index: int = int(state.get("player_index", 0)) + 1
	var player_count: int = int(state.get("player_count", 0))
	var dummy_index: int = int(state.get("dummy_index", 0)) + 1
	var dummy_count: int = int(state.get("dummy_count", 0))
	var distance: float = float(state.get("distance", -1.0))
	var lane_delta: float = float(state.get("lane_delta", 0.0))
	var lane_tolerance: float = float(state.get("lane_tolerance", 0.0))
	var last_hit: float = float(state.get("last_hit_distance", -1.0))
	var total: float = float(state.get("total_damage", 0.0))
	var hits: int = int(state.get("hit_count", 0))
	var verdict: String = "打得到" if bool(state.get("would_hit", false)) else "打不到"
	var distance_text: String = "—" if distance < 0.0 else "%.2f m" % distance
	var last_hit_text: String = "—" if last_hit < 0.0 else "%.2f m" % last_hit
	return "\n".join(PackedStringArray([
		"训练场",
		"角色  %s  (%d/%d)      Q 上一个    E 下一个" % [player_name, player_index, player_count],
		"站桩  %s  (%d/%d)      Z 上一个    C 下一个" % [dummy_name, dummy_index, dummy_count],
		"距离 %s    判定：%s      [ ] 调远近    ; ' 调纵深" % [distance_text, verdict],
		"普攻三段  %s" % _steps_text(state),
		"纵深容差 %.2f m    当前纵深差 %.2f m" % [lane_tolerance, lane_delta],
		"上次命中 %s    累计伤害 %d    命中 %d 次" % [last_hit_text, roundi(total), hits],
		"G 站桩归位    H 清空统计    Esc 暂停    F3 碰撞形状    F4 判定盒",
	]))

## 三段普攻并成一行：段数 + 形态 + 射程。第 3 段是范围、第 1 段是近战时一眼能看出来。
static func _steps_text(state: Dictionary) -> String:
	var steps: Array = state.get("attacks", [])
	var parts: PackedStringArray = []
	for raw: Variant in steps:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		parts.append("%d %s %.2f m" % [
			int(entry.get("step", 0)),
			kind_label(str(entry.get("kind", "melee"))),
			float(entry.get("range", 0.0))])
	if parts.is_empty():
		return "—"
	return " ｜ ".join(parts)

static func kind_label(kind: String) -> String:
	match kind:
		"aoe":
			return "范围"
		"ranged":
			return "远程"
	return "近战"
