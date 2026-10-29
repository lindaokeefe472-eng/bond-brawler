## 攻击盒（宽相）：攻击 ACTIVE 帧内扫描重叠的受击盒，把 actor_id 上报给视图。
##
## 为什么只上报 id 而不是在这里扣血：ARCHITECTURE §3 规定宽相可以漏、窄相不能错。
## 这里报出的候选最终仍要经过领域层的扇形/纵深判定，物理层只是「可能命中」的提示器。
class_name HitboxAdapter
extends Area3D

var actor_id: int = 0
var faction: StringName = GameConstants.FACTION_NEUTRAL
## 回调签名 func(attacker_id: int, target_id: int)。
var candidate_sink: Callable = Callable()

var _active: bool = false
var _shape: CollisionShape3D = null
## 一次 ACTIVE 窗口内每个目标只上报一次，避免持续重叠刷爆表现层。
var _reported: Dictionary = {}

func _ready() -> void:
	monitoring = false
	monitorable = false
	_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D

func configure(p_actor_id: int, p_faction: StringName) -> void:
	actor_id = p_actor_id
	faction = p_faction
	collision_layer = CollisionLayers.hitbox_layer_for(p_faction)
	collision_mask = CollisionLayers.hitbox_mask_for(p_faction)
	_active = false
	_reported.clear()
	# 常开扫描。之前是在 ACTIVE 帧才打开 monitoring，但物理引擎要到下一帧才填重叠列表，
	# 而领域层在 ACTIVE 首帧就结算完了 —— 那一刻重叠永远是空的，宽相等于没开。
	# 常开之后重叠列表一直是最新的，只在「要不要上报」上按相位过滤。
	monitoring = true
	monitorable = false

## 由 ActorView 在攻击 ACTIVE 窗口开关。开启瞬间立刻扫一次，
## 因为本帧的重叠可能早于下一次 _physics_process 才建立。
## 切换「是否上报」，同时开关形状本身：
##   - monitoring 常开，保证物理引擎一直在维护重叠列表；
##   - 形状只在起手/判定帧启用，调试视图里不会一直挂着一个方框，
##     也不会在待机时挡住鼠标拾取。
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	_reported.clear()
	if _shape != null:
		_shape.set_deferred("disabled", not active)
	if active:
		_scan()

func is_active() -> bool:
	return _active

func _physics_process(_delta: float) -> void:
	_scan()

func _scan() -> void:
	if not _active or not monitoring:
		return
	for area: Area3D in get_overlapping_areas():
		if not (area is HurtboxAdapter):
			continue
		var hurtbox: HurtboxAdapter = area as HurtboxAdapter
		if hurtbox.actor_id == actor_id or hurtbox.faction == faction:
			continue
		if hurtbox.is_invulnerable():
			continue
		if _reported.has(hurtbox.actor_id):
			continue
		_reported[hurtbox.actor_id] = true
		if candidate_sink.is_valid():
			candidate_sink.call(actor_id, hurtbox.actor_id)
