## 生成弹体效果：只描述「该生成几发、什么速度/散布」，实体由表现层/应用层创建。
## 领域层不持有弹体对象，弹体命中后仍走伤害事件，保持判定权威在领域层。
class_name SkillSpawnProjectileEffect
extends SkillEffect

var count: int = 1
var speed: float = 0.0
var spread: float = 0.0
var power: float = 0.0
var damage_type: StringName = &"neutral"
var piercing: bool = false
var lifetime: float = 0.0
var interval: float = 0.0

func _init(p_count: int = 1,
        p_speed: float = 0.0,
        p_spread: float = 0.0,
        p_power: float = 0.0,
        p_damage_type: StringName = &"neutral",
        p_piercing: bool = false,
        p_lifetime: float = 0.0,
        p_interval: float = 0.0) -> void:
    count = maxi(1, p_count)
    speed = p_speed
    spread = p_spread
    power = p_power
    damage_type = p_damage_type
    piercing = p_piercing
    lifetime = p_lifetime
    interval = p_interval

func apply(ctx: SkillEffectContext) -> void:
    if ctx == null:
        return
    ctx.emit_event(EVT_PROJECTILE_SPAWNED, {
        "owner_id": ctx.caster_id,
        "origin": ctx.origin,
        "facing": ctx.facing,
        "count": count,
        "speed": speed,
        "spread": spread,
        "power": power,
        "damage_type": damage_type,
        "piercing": piercing,
        "lifetime": lifetime,
        "interval": interval,
    })
