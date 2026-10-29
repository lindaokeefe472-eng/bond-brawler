## 受击盒（宽相）：只携带身份，不做任何判定。
##
## 为什么连血量都不碰：伤害数字只由领域层产生；这里被撞到只说明「可能被打中」，
## 真正的命中由 PlaneMath 的窄相决定，物理层永远不改战斗状态。
class_name HurtboxAdapter
extends Area3D

var actor_id: int = 0
var faction: StringName = GameConstants.FACTION_NEUTRAL
var _invulnerable: bool = false

func _ready() -> void:
	# 受击盒只需要被别人检测，自己从不主动扫描。
	monitoring = false

func configure(p_actor_id: int, p_faction: StringName) -> void:
	actor_id = p_actor_id
	faction = p_faction
	collision_layer = CollisionLayers.hurtbox_layer_for(p_faction)
	collision_mask = 0
	monitoring = false
	monitorable = true
	_invulnerable = false

## 死亡或无敌帧时关掉可检测性；延迟设置避免在物理回调里改碰撞状态。
func set_invulnerable(invulnerable: bool) -> void:
	_invulnerable = invulnerable
	if is_inside_tree():
		set_deferred("monitorable", not invulnerable)
	else:
		monitorable = not invulnerable

func is_invulnerable() -> bool:
	return _invulnerable
