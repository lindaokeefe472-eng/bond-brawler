## 状态效果：命中后按概率施加异常状态（burn / slow / sleep ...）。
## 概率必须走 IRng，否则回放会漂移；没有随机源时只允许必然命中。
class_name SkillStatusEffect
extends SkillEffect

var status: StringName = &""
var duration: float = 0.0
var stacks: int = 1
var chance: float = 1.0

func _init(p_status: StringName = &"", p_duration: float = 0.0, p_stacks: int = 1, p_chance: float = 1.0) -> void:
	status = p_status
	duration = p_duration
	stacks = p_stacks
	chance = p_chance

func apply(ctx: SkillEffectContext) -> void:
	if ctx == null or status == &"":
		return
	var always: bool = chance >= 1.0
	if not always:
		if ctx.rng == null:
			return
	for target_id: int in ctx.target_ids:
		if not always and not ctx.rng.chance(chance):
			continue
		ctx.emit_event(EVT_STATUS_APPLIED, {
			"actor_id": target_id,
			"source_id": ctx.caster_id,
			"status": status,
			"duration": duration,
			"stacks": stacks,
		})
