## 治疗效果：按固定值 + 最大生命比例恢复施法者。
## 比例部分需要 stats_provider，拿不到就退化为固定值，不阻塞结算。
class_name SkillHealEffect
extends SkillEffect

var flat: float = 0.0
var ratio: float = 0.0

func _init(p_flat: float = 0.0, p_ratio: float = 0.0) -> void:
	flat = p_flat
	ratio = p_ratio

func apply(ctx: SkillEffectContext) -> void:
	if ctx == null:
		return
	var amount: float = flat
	if ratio > 0.0 and ctx.stats_provider.is_valid():
		var stats: Variant = ctx.stats_provider.call(ctx.caster_id)
		if stats is Object and (stats as Object).has_method("max_hp"):
			amount += float(stats.call("max_hp")) * ratio
	ctx.emit_event(EVT_HEALED, {
		"actor_id": ctx.caster_id,
		"amount": amount,
		"ratio": ratio,
	})
