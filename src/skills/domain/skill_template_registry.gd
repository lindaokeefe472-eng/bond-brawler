## 模板注册表：把原游戏 56 种 template 归一到 10 种已实现模板。
##
## 为什么不在数据里直接改模板名：原始数据是对外契约，改数据会丢信息；
## 归一放在领域层，未知模板一律回退 melee，保证任何技能都有可执行行为。
class_name SkillTemplateRegistry
extends RefCounted

const TEMPLATE_MELEE: StringName = &"melee"
const TEMPLATE_LUNGE_MELEE: StringName = &"lunge_melee"
const TEMPLATE_PROJECTILE: StringName = &"projectile"
const TEMPLATE_VOLLEY: StringName = &"volley"
const TEMPLATE_BEAM: StringName = &"beam"
const TEMPLATE_AREA_BURST: StringName = &"area_burst"
const TEMPLATE_DASH_ATTACK: StringName = &"dash_attack"
const TEMPLATE_HEAL: StringName = &"heal"
const TEMPLATE_BUFF: StringName = &"buff"
const TEMPLATE_CHANNEL: StringName = &"channel"

## 已实现模板白名单（顺序即优先级展示顺序）。
const IMPLEMENTED_TEMPLATES: Array[StringName] = [
	TEMPLATE_MELEE, TEMPLATE_LUNGE_MELEE, TEMPLATE_PROJECTILE, TEMPLATE_VOLLEY,
	TEMPLATE_BEAM, TEMPLATE_AREA_BURST, TEMPLATE_DASH_ATTACK,
	TEMPLATE_HEAL, TEMPLATE_BUFF, TEMPLATE_CHANNEL,
]

## 56 种原始模板 -> 10 种实现。未列出的模板统一回退 melee。
const ALIASES: Dictionary = {
	# 近身类
	&"melee": TEMPLATE_MELEE,
	&"custom_melee": TEMPLATE_MELEE,
	&"melee_combo": TEMPLATE_MELEE,
	&"control": TEMPLATE_MELEE,
	&"counter": TEMPLATE_MELEE,
	&"drain": TEMPLATE_MELEE,
	# 突进类
	&"lunge_melee": TEMPLATE_LUNGE_MELEE,
	&"space_slash": TEMPLATE_LUNGE_MELEE,
	&"dash_attack": TEMPLATE_DASH_ATTACK,
	&"air_dive": TEMPLATE_DASH_ATTACK,
	&"burrow": TEMPLATE_DASH_ATTACK,
	&"vanish_attack": TEMPLATE_DASH_ATTACK,
	# 弹体类
	&"projectile": TEMPLATE_PROJECTILE,
	&"target_effect": TEMPLATE_PROJECTILE,
	&"ground_target": TEMPLATE_PROJECTILE,
	&"sacred_flame": TEMPLATE_PROJECTILE,
	&"portal_attack": TEMPLATE_PROJECTILE,
	&"volley": TEMPLATE_VOLLEY,
	&"multi_core_wave": TEMPLATE_VOLLEY,
	&"seed_burst": TEMPLATE_VOLLEY,
	# 射线类
	&"beam": TEMPLATE_BEAM,
	&"spiral_beam": TEMPLATE_BEAM,
	&"time_beam": TEMPLATE_BEAM,
	&"purifying_beam": TEMPLATE_BEAM,
	&"electric_arc": TEMPLATE_BEAM,
	&"sound_cone": TEMPLATE_BEAM,
	&"wind_cone": TEMPLATE_BEAM,
	&"wave": TEMPLATE_BEAM,
	&"field_wave": TEMPLATE_BEAM,
	# 范围爆发类
	&"area_burst": TEMPLATE_AREA_BURST,
	&"overload_burst": TEMPLATE_AREA_BURST,
	&"psychic_burst": TEMPLATE_AREA_BURST,
	&"ground_blades": TEMPLATE_AREA_BURST,
	&"divine_sky": TEMPLATE_AREA_BURST,
	&"wish_starfall": TEMPLATE_AREA_BURST,
	&"wall": TEMPLATE_AREA_BURST,
	&"custom_wall": TEMPLATE_AREA_BURST,
	&"zone": TEMPLATE_AREA_BURST,
	&"shadow_sleep_zone": TEMPLATE_AREA_BURST,
	&"smoke": TEMPLATE_AREA_BURST,
	&"weather": TEMPLATE_AREA_BURST,
	&"mist_feathers": TEMPLATE_AREA_BURST,
	&"reverse_portal": TEMPLATE_AREA_BURST,
	# 治疗 / 增益类
	&"heal": TEMPLATE_HEAL,
	&"delayed_heal": TEMPLATE_HEAL,
	&"buff": TEMPLATE_BUFF,
	&"charged_buff": TEMPLATE_BUFF,
	&"team_buff": TEMPLATE_BUFF,
	&"guard": TEMPLATE_BUFF,
	&"transform": TEMPLATE_BUFF,
	&"clone": TEMPLATE_BUFF,
	&"status_exchange": TEMPLATE_BUFF,
	&"switch_skill": TEMPLATE_BUFF,
	# 持续引导类
	&"channel": TEMPLATE_CHANNEL,
	&"tether": TEMPLATE_CHANNEL,
	&"grip_pressure": TEMPLATE_CHANNEL,
}

## 把任意原始模板名归一为 10 种已实现模板之一。
static func normalize_template(template: StringName) -> StringName:
	return ALIASES.get(template, TEMPLATE_MELEE)

## 按模板产出效果链。顺序即结算顺序：先伤害，再位移，最后状态。
static func build(skill_def: SkillDef) -> Array[SkillEffect]:
	var out: Array[SkillEffect] = []
	if skill_def == null:
		return out
	var extra: Dictionary = skill_def.extra if skill_def.extra != null else {}
	var template: StringName = normalize_template(skill_def.template)

	match template:
		TEMPLATE_LUNGE_MELEE:
			out.append(_damage(skill_def))
		TEMPLATE_PROJECTILE:
			out.append(_damage(skill_def))
			out.append(_projectile(skill_def, extra, 1))
		TEMPLATE_VOLLEY:
			out.append(_damage(skill_def))
			var count: int = int(round(float(extra.get("volley_count", 1.0))))
			out.append(_projectile(skill_def, extra, count))
		TEMPLATE_BEAM:
			out.append(_damage(skill_def))
		TEMPLATE_AREA_BURST:
			out.append(_damage(skill_def))
			if skill_def.knockback > 0.0:
				out.append(SkillKnockbackEffect.new(skill_def.knockback))
		TEMPLATE_DASH_ATTACK:
			out.append(_damage(skill_def))
			if skill_def.knockback > 0.0:
				out.append(SkillKnockbackEffect.new(skill_def.knockback))
		TEMPLATE_HEAL:
			out.append(SkillHealEffect.new(skill_def.power, float(extra.get("heal_ratio", 0.0))))
		TEMPLATE_BUFF:
			_append_buff(out, skill_def, extra)
		TEMPLATE_CHANNEL:
			out.append(_damage(skill_def))
		_:
			out.append(_damage(skill_def))

	_append_status(out, skill_def, extra)
	return out

## 命中盒参数：reach 取技能射程，半张角取数据里的 cone（弧度），
## 纵深容差默认沿用全局对齐容差，光束类按 width 放宽。
static func hitbox(skill_def: SkillDef) -> Dictionary:
	if skill_def == null:
		return {
			"reach": 0.0,
			"half_arc": 0.0,
			"lane_tolerance": GameConstants.LANE_ALIGN_TOLERANCE,
		}
	var extra: Dictionary = skill_def.extra if skill_def.extra != null else {}
	var half_arc: float = float(extra.get("cone", extra.get("half_arc", 0.0)))
	var lane_tolerance: float = float(extra.get("lane_tolerance", 0.0))
	if lane_tolerance <= 0.0:
		lane_tolerance = maxf(GameConstants.LANE_ALIGN_TOLERANCE, float(extra.get("width", 0.0)) * 0.5)
	return {
		"reach": maxf(0.0, skill_def.range),
		"half_arc": maxf(0.0, half_arc),
		"lane_tolerance": lane_tolerance,
	}

static func _damage(skill_def: SkillDef) -> SkillDamageEffect:
	return SkillDamageEffect.new(skill_def.power, skill_def.type, skill_def.knockback)

static func _projectile(skill_def: SkillDef, extra: Dictionary, count: int) -> SkillSpawnProjectileEffect:
	return SkillSpawnProjectileEffect.new(
		count,
		float(extra.get("speed", 0.0)),
		float(extra.get("volley_spread", extra.get("spread", 0.0))),
		skill_def.power,
		skill_def.type,
		bool(extra.get("piercing", false)),
		float(extra.get("duration", skill_def.duration)),
		float(extra.get("volley_interval", 0.0)))

## 增益模板的数值来自数据里的各类 *_mult；self_multiplier 表示施法者自损，
## 单独成一发 buff，方便下游按 stat 区分。
static func _append_buff(out: Array[SkillEffect], skill_def: SkillDef, extra: Dictionary) -> void:
	var buff_id: StringName = StringName(str(extra.get("buff", "")))
	var duration: float = float(extra.get("duration", skill_def.duration))
	var stacks: int = maxi(1, int(round(float(extra.get("max_stacks", 1.0)))))
	var stat_map: Dictionary = {
		"attack_mult": &"attack",
		"defense_mult": &"defense",
		"speed_mult": &"speed",
	}
	var added: bool = false
	for key: String in stat_map.keys():
		if not extra.has(key):
			continue
		var mult: float = float(extra.get(key, 1.0))
		out.append(SkillBuffEffect.new(stat_map[key], 0.0, mult - 1.0, duration, stacks, buff_id))
		added = true
	if extra.has("self_multiplier"):
		var self_duration: float = float(extra.get("self_duration", duration))
		out.append(SkillBuffEffect.new(&"attack", 0.0, float(extra.get("self_multiplier", 1.0)) - 1.0, self_duration, stacks, buff_id))
		added = true
	# 数据只有 buff 名字没有倍率时，也要给出一发占位效果，保持模板可观测。
	if not added:
		out.append(SkillBuffEffect.new(&"attack", 0.0, 0.0, duration, stacks, buff_id))

static func _append_status(out: Array[SkillEffect], skill_def: SkillDef, extra: Dictionary) -> void:
	if skill_def.status == &"":
		return
	out.append(SkillStatusEffect.new(
		skill_def.status,
		float(extra.get("status_duration", 0.0)),
		1,
		float(extra.get("status_chance", 1.0))))
