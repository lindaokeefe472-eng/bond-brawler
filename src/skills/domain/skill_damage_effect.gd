## 伤害效果：只发「伤害结算请求」事件，由 combat 的伤害管线决定最终数字。
## 这里带上属性与命中类型，下游才能查属性克制、决定暴击与击退。
class_name SkillDamageEffect
extends SkillEffect

var power: float = 0.0
var damage_type: StringName = &"neutral"
var knockback: float = 0.0
var hit_kind: StringName = &"skill"
var can_crit: bool = true
var tags: Array = []

func _init(p_power: float = 0.0,
		p_damage_type: StringName = &"neutral",
		p_knockback: float = 0.0,
		p_hit_kind: StringName = &"skill",
		p_can_crit: bool = true,
		p_tags: Array = []) -> void:
	power = p_power
	damage_type = p_damage_type
	knockback = p_knockback
	hit_kind = p_hit_kind
	can_crit = p_can_crit
	tags = p_tags.duplicate()

func apply(ctx: SkillEffectContext) -> void:
	if ctx == null:
		return
	for target_id: int in ctx.target_ids:
		ctx.emit_event(EVT_DAMAGE, {
			"attacker_id": ctx.caster_id,
			"target_id": target_id,
			"power": power,
			"damage_type": damage_type,
			"hit_kind": hit_kind,
			"knockback": knockback,
			"can_crit": can_crit,
			"tags": tags.duplicate(),
		})
