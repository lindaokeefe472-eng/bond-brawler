## 判定盒微调器：暂停战斗、强制显示选中角色的攻击盒，用键盘实时改尺寸。
##
## 为什么必须是运行时工具：判定盒的尺寸由 melee_config() 现算（CLAUDE.md「判定盒四条」
## 第 1 条），在编辑器里拖 CollisionShape3D 不会生效 —— 每次 bind() 都会被重新算掉。
## 所以只能在运行时改参数，再让视图重算一遍。
##
## 窄相读的是同一份 melee_config()，所以调完「看到的范围」就是「打得到的范围」。
class_name HitboxTuner
extends Node

const DEFAULT_SAVE_PATH: String = "user://melee_tuning.json"

## 可调参数：键 -> [中文名, 步长, 下限, 上限]
const PARAMS: Dictionary = {
	"range": ["前伸 reach", 0.05, 0.2, 6.0],
	"lane_tolerance": ["纵深 lane", 0.05, 0.0, 2.6],
	"hit_height": ["高度 height", 0.05, 0.2, 3.0],
	"margin": ["余量 margin", 0.01, 0.0, 0.5],
}

## 测试可以改到别处，避免污染真实的微调存档。
var save_path: String = DEFAULT_SAVE_PATH

var _views: Dictionary = {}     # actor_id -> ActorView
var _chars: Dictionary = {}     # actor_id -> character_id
var _ids: Array[int] = []
var _index: int = 0
var _tuning: bool = false
var _defaults: Dictionary = {}  # actor_id -> melee_config 快照，用于复位

## 屏幕上的数值面板。只打日志的话，Output 面板没开就等于什么都没发生。
var _hud_layer: CanvasLayer = null
var _hud: Label = null

func _ready() -> void:
	_build_hud()

func register(view: ActorView, character_id: String) -> void:
	if view == null or view.runtime == null:
		return
	var actor_id: int = view.actor_id
	_views[actor_id] = view
	_chars[actor_id] = character_id
	if not _ids.has(actor_id):
		_ids.append(actor_id)
		_ids.sort()
	_defaults[actor_id] = view.runtime.melee_config()

func is_tuning() -> bool:
	return _tuning

func selected_id() -> int:
	if _ids.is_empty():
		return 0
	return _ids[clampi(_index, 0, _ids.size() - 1)]

## 直接选中某个角色（调试脚本用；键盘走 Tab 循环）。
func select(actor_id: int) -> void:
	var index: int = _ids.find(actor_id)
	if index < 0:
		return
	_index = index
	_apply_preview()

## 把一次微调折算成新值。纯函数，方便单测。
static func stepped(param: StringName, current: float, steps: float) -> float:
	var spec: Variant = PARAMS.get(String(param))
	if not (spec is Array) or (spec as Array).size() < 4:
		return current
	var cols: Array = spec
	return clampf(current + steps * float(cols[1]), float(cols[2]), float(cols[3]))

## 改一个参数并让视图重算。返回是否真的改到了。
func tune_actor(actor_id: int, param: StringName, steps: float) -> bool:
	var view: ActorView = _views.get(actor_id, null) as ActorView
	if view == null or not is_instance_valid(view) or view.runtime == null:
		return false
	var cfg: Dictionary = view.runtime.melee_config()
	var key: String = String(param)
	if not cfg.has(key):
		return false
	var next: float = stepped(param, float(cfg[key]), steps)
	if is_equal_approx(next, float(cfg[key])):
		return false
	view.runtime.set_melee_param(param, next)
	view.refresh_hitbox()
	return true

func tune(param: StringName, steps: float) -> bool:
	return tune_actor(selected_id(), param, steps)

## 复位到启动时的参数（不受存档影响）。
func reset_actor(actor_id: int) -> void:
	var view: ActorView = _views.get(actor_id, null) as ActorView
	var defaults: Variant = _defaults.get(actor_id)
	if view == null or not is_instance_valid(view) or view.runtime == null or not (defaults is Dictionary):
		return
	for key: String in (defaults as Dictionary).keys():
		view.runtime.set_melee_param(StringName(key), float((defaults as Dictionary)[key]))
	view.refresh_hitbox()

## 键位处理。返回 true 表示这次按键被调参器消费掉了。
func handle_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_F4:
		_set_tuning(not _tuning)
		return true
	if not _tuning:
		return false
	match event.keycode:
		KEY_TAB:
			_cycle(1)
		KEY_LEFT:
			tune(&"range", -1.0)
		KEY_RIGHT:
			tune(&"range", 1.0)
		KEY_UP:
			tune(&"lane_tolerance", -1.0)
		KEY_DOWN:
			tune(&"lane_tolerance", 1.0)
		KEY_PAGEUP:
			tune(&"hit_height", 1.0)
		KEY_PAGEDOWN:
			tune(&"hit_height", -1.0)
		KEY_COMMA:
			tune(&"margin", -1.0)
		KEY_PERIOD:
			tune(&"margin", 1.0)
		KEY_P:
			print_tuning()
		KEY_R:
			reset_actor(selected_id())
			_report()
		_:
			pass
	_save()
	_report()
	# 调参模式下吞掉所有按键，避免顺手把角色操控了。
	return true

## 启动时套用上次的微调。headless 下跳过，避免开发机的数值污染用例。
func apply_saved_overrides() -> void:
	if DisplayServer.get_name() == "headless" or not FileAccess.file_exists(save_path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (raw is Dictionary):
		return
	var saved: Dictionary = raw
	var applied: int = 0
	for actor_id: int in _ids:
		var cid: String = str(_chars.get(actor_id, ""))
		var view: ActorView = _views.get(actor_id, null) as ActorView
		if cid.is_empty() or not saved.has(cid) or view == null or not is_instance_valid(view):
			continue
		var entry: Variant = saved[cid]
		if not (entry is Dictionary):
			continue
		for key: String in (entry as Dictionary).keys():
			view.runtime.set_melee_param(StringName(key), float((entry as Dictionary)[key]))
		view.refresh_hitbox()
		applied += 1
	if applied > 0:
		print("[tune] 已套用 %d 个角色的微调存档：%s" % [applied, save_path])

## 打印可粘回 data/ 的 JSON。
func print_tuning() -> void:
	var data: Dictionary = {}
	for actor_id: int in _ids:
		var cid: String = str(_chars.get(actor_id, ""))
		var view: ActorView = _views.get(actor_id, null) as ActorView
		if cid.is_empty() or view == null or not is_instance_valid(view) or view.runtime == null:
			continue
		data[cid] = _params_of(view)
	print("[tune] 当前微调：")
	print(JSON.stringify(data, "  ", false))

func _params_of(view: ActorView) -> Dictionary:
	var cfg: Dictionary = view.runtime.melee_config()
	return {
		"range": snappedf(float(cfg.get("range", 0.0)), 0.01),
		"lane_tolerance": snappedf(float(cfg.get("lane_tolerance", 0.0)), 0.01),
		"hit_height": snappedf(float(cfg.get("hit_height", 0.0)), 0.01),
		"margin": snappedf(float(cfg.get("margin", 0.0)), 0.01),
	}

func _set_tuning(on: bool) -> void:
	_tuning = on
	_apply_preview()
	if on:
		print("[tune] 判定盒微调：Tab 换角色  ←→ 前伸  ↑↓ 纵深  PgUp/PgDn 高度  ,/. 余量  P 打印  R 复位  F4 退出")
	else:
		print("[tune] 退出微调，继续战斗")
	_report()

func _apply_preview() -> void:
	var sel: int = selected_id()
	for actor_id: int in _ids:
		var view: ActorView = _views.get(actor_id, null) as ActorView
		if view != null and is_instance_valid(view):
			view.set_hitbox_preview(_tuning and actor_id == sel)

func _cycle(step: int) -> void:
	if _ids.is_empty():
		return
	_index = wrapi(_index + step, 0, _ids.size())
	_apply_preview()

func _report() -> void:
	var view: ActorView = _views.get(selected_id(), null) as ActorView
	_refresh_hud(view)
	if view == null or not is_instance_valid(view) or view.runtime == null:
		return
	var cfg: Dictionary = view.runtime.melee_config()
	var hitbox: Area3D = view.get_node_or_null(ActorView.HITBOX_NODE) as Area3D
	var shape_node: CollisionShape3D = null
	if hitbox != null:
		shape_node = hitbox.get_node_or_null(ActorView.HITBOX_SHAPE_NODE) as CollisionShape3D
	var size: Vector3 = Vector3.ZERO
	if shape_node != null and shape_node.shape is BoxShape3D:
		size = (shape_node.shape as BoxShape3D).size
	print("[tune] %s(%s) reach=%.2f lane=%.2f height=%.2f margin=%.2f | 盒 %.2f x %.2f x %.2f | 前沿 %.2f" % [
		view.name, str(_chars.get(view.actor_id, "?")),
		float(cfg.get("range", 0.0)), float(cfg.get("lane_tolerance", 0.0)),
		float(cfg.get("hit_height", 0.0)), float(cfg.get("margin", 0.0)),
		size.x, size.y, size.z, float(cfg.get("range", 0.0)) + float(cfg.get("margin", 0.0))])

## 左上角常驻一行提示（仅调试构建），进微调后换成数值面板。
func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "TunerHud"
	_hud_layer.layer = 100
	add_child(_hud_layer)
	_hud = Label.new()
	_hud.position = Vector2(12.0, 10.0)
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_content_margin_all(8)
	style.set_corner_radius_all(4)
	_hud.add_theme_stylebox_override("normal", style)
	_hud_layer.add_child(_hud)
	_refresh_hud(null)

func _refresh_hud(view: ActorView) -> void:
	if _hud == null:
		return
	if not _tuning:
		_hud.text = "F3 碰撞形状    F4 判定盒微调"
		_hud.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.45))
		_hud.visible = OS.is_debug_build()
		return
	_hud.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_hud.visible = true
	if view == null or not is_instance_valid(view) or view.runtime == null:
		_hud.text = "判定盒微调（没有可调角色）"
		return
	var cfg: Dictionary = view.runtime.melee_config()
	var hitbox: Area3D = view.get_node_or_null(ActorView.HITBOX_NODE) as Area3D
	var shape_node: CollisionShape3D = null
	if hitbox != null:
		shape_node = hitbox.get_node_or_null(ActorView.HITBOX_SHAPE_NODE) as CollisionShape3D
	var size: Vector3 = Vector3.ZERO
	if shape_node != null and shape_node.shape is BoxShape3D:
		size = (shape_node.shape as BoxShape3D).size
	var lines: PackedStringArray = [
		"判定盒微调    %s (%s)    [Tab 换角色]" % [view.name, str(_chars.get(view.actor_id, "?"))],
		"前伸 reach   %.2f    ← →" % float(cfg.get("range", 0.0)),
		"纵深 lane    %.2f    ↑ ↓" % float(cfg.get("lane_tolerance", 0.0)),
		"高度 height  %.2f    PgUp PgDn" % float(cfg.get("hit_height", 0.0)),
		"余量 margin  %.2f    , ." % float(cfg.get("margin", 0.0)),
		"盒子 %.2f × %.2f × %.2f    前沿 %.2f" % [
			size.x, size.y, size.z, float(cfg.get("range", 0.0)) + float(cfg.get("margin", 0.0))],
		"P 打印 JSON    R 复位    F4 退出（战斗继续）",
	]
	_hud.text = "\n".join(lines)

func _save() -> void:
	var data: Dictionary = {}
	for actor_id: int in _ids:
		var cid: String = str(_chars.get(actor_id, ""))
		var view: ActorView = _views.get(actor_id, null) as ActorView
		if cid.is_empty() or view == null or not is_instance_valid(view) or view.runtime == null:
			continue
		data[cid] = _params_of(view)
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "  ", false))
	file.close()
