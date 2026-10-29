extends GdUnitTestSuite

func _def(data: Dictionary) -> SkillDef:
	return SkillDef.from_dict(data)

func test_unknown_template_falls_back_to_melee() -> void:
	assert_that(SkillTemplateRegistry.normalize_template(&"totally_unknown")).is_equal(SkillTemplateRegistry.TEMPLATE_MELEE)
	var effects := SkillTemplateRegistry.build(_def({
		"id": "mystery",
		"template": "totally_unknown",
		"power": 12.0,
	}))
	assert_int(effects.size()).is_equal(1)
	assert_bool(effects[0] is SkillDamageEffect).is_true()
	var damage := effects[0] as SkillDamageEffect
	assert_float(damage.power).is_equal_approx(12.0, 0.0001)

func test_alias_table_covers_56_templates() -> void:
	assert_int(SkillTemplateRegistry.ALIASES.size()).is_equal(56)
	for raw: Variant in SkillTemplateRegistry.ALIASES.keys():
		var normalized: StringName = SkillTemplateRegistry.normalize_template(raw)
		assert_bool(SkillTemplateRegistry.IMPLEMENTED_TEMPLATES.has(normalized)).override_failure_message(
			"模板 %s 归一到未实现模板 %s" % [raw, normalized]).is_true()

func test_dual_type_volley_uses_template_params() -> void:
	var def := _def({
		"id": "dual_volley",
		"type": ["fire", "flying"],
		"template": "volley",
		"power": 9.0,
		"range": 8.0,
		"volley_count": 4.0,
		"volley_spread": 0.05,
		"speed": 15.0,
		"status": "burn",
		"status_chance": 1.0,
		"status_duration": 2.0,
	})
	assert_that(def.type).is_equal(&"fire")
	var effects := SkillTemplateRegistry.build(def)
	var projectile: SkillSpawnProjectileEffect = null
	var status: SkillStatusEffect = null
	for effect: SkillEffect in effects:
		if effect is SkillSpawnProjectileEffect:
			projectile = effect as SkillSpawnProjectileEffect
		elif effect is SkillStatusEffect:
			status = effect as SkillStatusEffect
	assert_object(projectile).is_not_null()
	assert_object(status).is_not_null()
	assert_int(projectile.count).is_equal(4)
	assert_float(projectile.spread).is_equal_approx(0.05, 0.0001)
	assert_float(projectile.speed).is_equal_approx(15.0, 0.0001)
	# 双属性技能的主属性必须传给弹体，伤害计算才查得到克制表。
	assert_that(projectile.damage_type).is_equal(&"fire")
	assert_that(status.status).is_equal(&"burn")
	assert_float(status.duration).is_equal_approx(2.0, 0.0001)

func test_heal_and_buff_templates_produce_their_effects() -> void:
	var heal := SkillTemplateRegistry.build(_def({
		"id": "h",
		"template": "heal",
		"power": 30.0,
		"heal_ratio": 0.2,
	}))
	assert_int(heal.size()).is_equal(1)
	assert_bool(heal[0] is SkillHealEffect).is_true()
	var heal_fx := heal[0] as SkillHealEffect
	assert_float(heal_fx.flat).is_equal_approx(30.0, 0.0001)
	assert_float(heal_fx.ratio).is_equal_approx(0.2, 0.0001)

	var buff := SkillTemplateRegistry.build(_def({
		"id": "b",
		"template": "buff",
		"attack_mult": 1.2,
		"duration": 5.0,
		"max_stacks": 3.0,
	}))
	assert_bool(buff.size() >= 1).is_true()
	assert_bool(buff[0] is SkillBuffEffect).is_true()
	var buff_fx := buff[0] as SkillBuffEffect
	assert_that(buff_fx.stat).is_equal(&"attack")
	assert_float(buff_fx.percent).is_equal_approx(0.2, 0.0001)
	assert_int(buff_fx.stacks).is_equal(3)
	assert_float(buff_fx.duration).is_equal_approx(5.0, 0.0001)

func test_hitbox_uses_range_cone_and_width() -> void:
	var box := SkillTemplateRegistry.hitbox(_def({
		"id": "beam",
		"template": "beam",
		"range": 12.0,
		"cone": 0.4,
		"width": 2.0,
	}))
	assert_float(float(box.get("reach", 0.0))).is_equal_approx(
			SkillTemplateRegistry.instant_reach(_def({"template": "beam", "range": 12.0})), 0.0001)
	assert_float(float(box.get("half_arc", 0.0))).is_equal_approx(0.4, 0.0001)
	assert_float(float(box.get("lane_tolerance", 0.0))).is_equal_approx(1.0, 0.0001)

## 原游戏的 range 是它自己的尺度，必须换算到本项目（角色统一 1.8 m）。
## 回归：以前直接用原始值，一个写着「近战」的技能能隔 4.3 米瞬发打人。
func test_instant_reach_is_scaled_and_capped() -> void:
	var def := _def({"id": "beam", "template": "beam", "range": 12.0})
	assert_float(SkillTemplateRegistry.world_reach(def)).is_equal_approx(
			12.0 * GameConstants.MELEE_RANGE_SCALE, 0.0001)
	assert_float(SkillTemplateRegistry.instant_reach(def)).is_equal_approx(
			GameConstants.SKILL_INSTANT_REACH_CAP, 0.0001)

## 弹体技能有可见弹道，射程只换算不夹取。
func test_projectile_reach_is_scaled_not_capped() -> void:
	var def := _def({"id": "orb", "template": "projectile", "range": 20.0})
	var expected: float = 20.0 * GameConstants.MELEE_RANGE_SCALE
	assert_float(float(SkillTemplateRegistry.hitbox(def).get("reach", 0.0))).is_equal_approx(expected, 0.0001)
	assert_float(SkillTemplateRegistry.instant_reach(def)).is_equal_approx(
			GameConstants.SKILL_INSTANT_REACH_CAP, 0.0001)
