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
## 一次 ACTIVE 窗口内每个目标只上报一次，避免持续重叠刷爆表现层。
var _reported: Dictionary = {}

func _ready() -> void:
    monitoring = false
    monitorable = false

func configure(p_actor_id: int, p_faction: StringName) -> void:
    actor_id = p_actor_id
    faction = p_faction
    collision_layer = CollisionLayers.hitbox_layer_for(p_faction)
    collision_mask = CollisionLayers.hitbox_mask_for(p_faction)
    _active = false
    _reported.clear()
    monitoring = false
    monitorable = false

## 由 ActorView 在攻击 ACTIVE 窗口开关。开启瞬间立刻扫一次，
## 因为本帧的重叠可能早于下一次 _physics_process 才建立。
func set_active(active: bool) -> void:
    if active == _active:
        if active:
            _scan()
        return
    _active = active
    monitoring = active
    if active:
        _reported.clear()
        _scan()
    else:
        _reported.clear()

func is_active() -> bool:
    return _active

func _physics_process(_delta: float) -> void:
    if _active:
        _scan()

func _scan() -> void:
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
