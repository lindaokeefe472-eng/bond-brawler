## 战斗 HUD：玩家血条 / 能量 / 技能格 / 连击，以及右上角的敌人血条。
##
## 只读 HudModel，不认识 ActorRuntime，也不订阅事件 —— 这是 presenter + view-model
## 的分工：视图是纯渲染，任何「显示什么」的判断都在模型里，可以脱离引擎单测。
class_name HudView
extends CanvasLayer

const BAR_WIDTH: float = 240.0
const BAR_HEIGHT: float = 14.0
const PIP_SIZE: float = 20.0
const ENEMY_BAR_WIDTH: float = 120.0
const MARGIN: float = 18.0

const HP_COLOR: Color = Color(0.85, 0.25, 0.25)
const ENERGY_COLOR: Color = Color(0.30, 0.60, 0.95)
const ENEMY_COLOR: Color = Color(0.90, 0.45, 0.30)
const PIP_READY: Color = Color(0.95, 0.95, 0.95)
const PIP_COOLING: Color = Color(0.30, 0.30, 0.34)

var _hp_bar: ProgressBar = null
var _energy_bar: ProgressBar = null
var _combo_label: Label = null
var _pips: Array[ColorRect] = []
var _enemy_box: VBoxContainer = null
## 敌人 id -> {row, bar, label}
var _enemy_rows: Dictionary = {}

func _ready() -> void:
	layer = 20
	_build_player_panel()
	_build_enemy_panel()

func render(model: HudModel, player_id: int) -> void:
	if model == null:
		return
	var player: Dictionary = {}
	var enemies: Array = []
	for raw: Variant in model.entries():
		var entry: Dictionary = raw
		if int(entry.get("id", 0)) == player_id:
			player = entry
		elif bool(entry.get("alive", false)):
			enemies.append(entry)
	_render_player(model, player, player_id)
	_render_enemies(enemies)

func _render_player(model: HudModel, player: Dictionary, player_id: int) -> void:
	if player.is_empty():
		return
	_hp_bar.value = float(player.get("hp_ratio", 0.0)) * 100.0
	_energy_bar.value = float(player.get("energy_ratio", 0.0)) * 100.0
	var cooldowns: Array = player.get("cooldowns", [])
	for i: int in range(_pips.size()):
		var ratio: float = float(cooldowns[i]) if i < cooldowns.size() else 0.0
		_pips[i].color = PIP_COOLING.lerp(PIP_READY, 1.0 - ratio)
	var combo: int = model.combo()
	_combo_label.visible = combo >= 2
	if combo >= 2:
		_combo_label.text = "连击 ×%d" % combo
	# 受击闪白：血条底色闪一下，比数字更容易被眼睛捕捉到。
	var flash: float = model.flash_ratio(player_id)
	_hp_bar.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.6, 1.6, 1.6), flash)

func _render_enemies(enemies: Array) -> void:
	var seen: Dictionary = {}
	for raw: Variant in enemies:
		var entry: Dictionary = raw
		var id: int = int(entry.get("id", 0))
		seen[id] = true
		var row: Dictionary = _enemy_row(id)
		(row["bar"] as ProgressBar).value = float(entry.get("hp_ratio", 0.0)) * 100.0
		(row["label"] as Label).text = str(entry.get("name", ""))
	for key: Variant in _enemy_rows.keys():
		if seen.has(int(key)):
			continue
		var stale: Dictionary = _enemy_rows[key]
		(stale["row"] as Control).visible = false

func _enemy_row(id: int) -> Dictionary:
	if _enemy_rows.has(id):
		var existing: Dictionary = _enemy_rows[id]
		(existing["row"] as Control).visible = true
		return existing
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	var bar := _make_bar(ENEMY_BAR_WIDTH, 8.0, ENEMY_COLOR)
	row.add_child(label)
	row.add_child(bar)
	_enemy_box.add_child(row)
	var record: Dictionary = {"row": row, "bar": bar, "label": label}
	_enemy_rows[id] = record
	return record

func _build_player_panel() -> void:
	var panel := VBoxContainer.new()
	panel.name = "PlayerPanel"
	panel.add_theme_constant_override("separation", 6)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(MARGIN, -MARGIN - 78.0)
	add_child(panel)

	_hp_bar = _make_bar(BAR_WIDTH, BAR_HEIGHT, HP_COLOR)
	_energy_bar = _make_bar(BAR_WIDTH, BAR_HEIGHT * 0.6, ENERGY_COLOR)
	panel.add_child(_hp_bar)
	panel.add_child(_energy_bar)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	panel.add_child(bottom)
	for _i: int in range(4):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
		pip.color = PIP_READY
		bottom.add_child(pip)
		_pips.append(pip)
	_combo_label = Label.new()
	_combo_label.add_theme_font_size_override("font_size", 18)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_combo_label.visible = false
	bottom.add_child(_combo_label)

func _build_enemy_panel() -> void:
	_enemy_box = VBoxContainer.new()
	_enemy_box.name = "EnemyPanel"
	_enemy_box.add_theme_constant_override("separation", 8)
	_enemy_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_box.position = Vector2(-ENEMY_BAR_WIDTH - MARGIN, MARGIN)
	add_child(_enemy_box)

func _make_bar(width: float, height: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.08, 0.10, 0.85)
	background.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar
