## 弹体：技能放出去之后真正在场上飞的那个东西。
##
## 为什么放在领域层：命中规则是玩法契约，必须能脱离引擎单测和回放。
## 物理层（Area3D）将来做宽相也只是提示器，权威判定在这里 —— 和普攻的
## 两段式判定同一个思路（见 docs/adr/0002-two-phase-hit-detection.md）。
class_name Projectile
extends RefCounted

## 数据里没给半径时的兜底，约等于角色体宽的一半。
const DEFAULT_RADIUS: float = 0.35
const MIN_SPEED: float = 0.01

var id: int = 0
var owner_id: int = 0
var faction: StringName = GameConstants.FACTION_NEUTRAL
var plane_pos: Vector2 = Vector2.ZERO
var height: float = 1.0
var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 1.0
var age: float = 0.0
var radius: float = DEFAULT_RADIUS
## 剩余可穿透次数。0 = 命中一个就消失。
var pierce_remaining: int = 0
var power: float = 0.0
var damage_type: StringName = &"neutral"
var knockback: float = 0.0
var alive: bool = true

## 已经命中过的目标，保证同一发弹体不会对同一个人重复结算。
var _hit_ids: Dictionary = {}

## 从技能参数造一发弹体。config 由 SkillSpawnProjectileEffect 的事件负载转来。
##   speed / range / power / damage_type / knockback / radius / piercing / lifetime
## lifetime 缺省时按 range / speed 推 —— 射程之外自然消失，不用手填。
static func create(p_owner_id: int, p_faction: StringName, origin: Vector2, facing: int,
		config: Dictionary) -> Projectile:
	var out := Projectile.new()
	out.owner_id = p_owner_id
	out.faction = p_faction
	out.plane_pos = origin
	var speed: float = maxf(float(config.get("speed", 0.0)), 0.0)
	# angle 是齐射用的散布角（弧度），绕朝向偏转，不改朝向本身。
	var angle: float = float(config.get("angle", 0.0))
	out.velocity = Vector2(float(1 if facing >= 0 else -1), 0.0).rotated(angle) * speed
	out.power = float(config.get("power", 0.0))
	out.damage_type = StringName(str(config.get("damage_type", "neutral")))
	out.knockback = maxf(float(config.get("knockback", 0.0)), 0.0)
	out.radius = maxf(float(config.get("radius", DEFAULT_RADIUS)), 0.01)
	out.height = float(config.get("height", 1.0))
	if bool(config.get("piercing", false)):
		out.pierce_remaining = maxi(int(config.get("pierce", 1)), 1)
	out.lifetime = float(config.get("lifetime", 0.0))
	if out.lifetime <= 0.0:
		var reach: float = maxf(float(config.get("range", 0.0)), 0.0)
		out.lifetime = reach / maxf(speed, MIN_SPEED)
	return out

## 推进一帧。过期就置 alive=false，由调用方回收。
func step(dt: float) -> void:
	if not alive:
		return
	var delta: float = maxf(dt, 0.0)
	age += delta
	plane_pos += velocity * delta
	if age >= lifetime:
		alive = false

## 能否命中某个目标。阵营、重复命中、距离三道过滤。
func can_hit(target_id: int, target_faction: StringName, target_pos: Vector2) -> bool:
	if not alive:
		return false
	if target_faction == faction:
		return false
	if _hit_ids.has(target_id):
		return false
	return PlaneMath.distance(plane_pos, target_pos) <= radius + GameConstants.BODY_RADIUS

## 记录一次命中。返回 true 表示弹体还能继续飞（穿透）。
func register_hit(target_id: int) -> bool:
	_hit_ids[target_id] = true
	if pierce_remaining > 0:
		pierce_remaining -= 1
		return true
	alive = false
	return false

func has_hit(target_id: int) -> bool:
	return _hit_ids.has(target_id)

func direction() -> Vector2:
	return velocity.normalized() if velocity.length_squared() > 0.0 else Vector2(1.0, 0.0)
