## 伤害跳字池：基于 NodePool 的 Label3D，战斗中零 instantiate。
##
## 为什么把飘字动画也放在池里：标签的「归还」必须和生命周期绑定，
## 谁创建谁回收，FeedbackDirector 只负责发起，不会漏掉回收。
class_name DamageNumberPool
extends RefCounted

const DEFAULT_PREWARM: int = 16
const FONT_SIZE: int = 48
const OUTLINE_SIZE: int = 8
const PIXEL_SIZE: float = 0.006
const RISE_SPEED: float = 1.2
const LIFETIME: float = 0.7
## 生命周期最后这段比例内淡出，前段保持全不透明便于读数字。
const FADE_START_RATIO: float = 0.55
const NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const CRIT_COLOR: Color = Color(1.0, 0.78, 0.2, 1.0)
const GUARD_COLOR: Color = Color(0.62, 0.82, 1.0, 1.0)
const HEAL_COLOR: Color = Color(0.45, 1.0, 0.55, 1.0)

var _pool: NodePool = null
var _active: Array[Dictionary] = []
var _parent: Node3D = null

func _init(parent: Node3D = null, prewarm_count: int = DEFAULT_PREWARM) -> void:
	_parent = parent
	_pool = NodePool.new(_make_label)
	if _parent != null:
		_pool.set_parent(_parent)
	_pool.prewarm(prewarm_count)
	# 战斗期间禁止增长：池不够用时宁可少显示一个数字，也不要在命中帧卡一下。
	_pool.set_allow_growth(false)

## 取一个标签并开始飘字。池空时返回 null，调用方无需特殊处理。
func spawn(world_position: Vector3, amount: int, kind: StringName = &"normal") -> Label3D:
	var label: Label3D = _pool.acquire() as Label3D
	if label == null:
		return null
	label.text = str(amount)
	label.modulate = _color_for(kind)
	if label.is_inside_tree():
		label.global_position = world_position
	else:
		label.position = world_position
	_active.append({
		"label": label,
		"life": LIFETIME,
		"rise": RISE_SPEED,
		"alpha": label.modulate.a,
	})
	return label

## 推进所有活动标签；到期归还池。delta 为 0 时（顿帧）自然冻结。
func tick(delta: float) -> void:
	if _active.is_empty():
		return
	var step: float = maxf(delta, 0.0)
	for i: int in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[i]
		var label: Label3D = entry["label"]
		if label == null or not is_instance_valid(label):
			_active.remove_at(i)
			continue
		entry["life"] = float(entry["life"]) - step
		var life: float = float(entry["life"])
		if life <= 0.0:
			_active.remove_at(i)
			_pool.release(label)
			continue
		label.position.y += float(entry["rise"]) * step
		var fade_window: float = LIFETIME * FADE_START_RATIO
		var ratio: float = 1.0
		if life < fade_window:
			ratio = life / fade_window
		var color: Color = label.modulate
		color.a = float(entry["alpha"]) * clampf(ratio, 0.0, 1.0)
		label.modulate = color

## 释放全部标签（测试与场景切换用）。
func clear() -> void:
	_active.clear()
	_pool.clear()

func active_count() -> int:
	return _active.size()

func free_count() -> int:
	return _pool.free_count()

func created_count() -> int:
	return _pool.created_count()

func _color_for(kind: StringName) -> Color:
	match kind:
		&"crit":
			return CRIT_COLOR
		&"guard":
			return GUARD_COLOR
		&"heal":
			return HEAL_COLOR
	return NORMAL_COLOR

## 必须是静态方法：NodePool 的 Callable 若绑定实例，会和池形成 RefCounted 循环引用。
static func _make_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = FONT_SIZE
	label.outline_size = OUTLINE_SIZE
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.pixel_size = PIXEL_SIZE
	label.visible = false
	return label
