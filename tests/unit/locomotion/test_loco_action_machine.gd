extends GdUnitTestSuite

# ---------------------------------------------------------------- helpers
func _make(profile: Dictionary = {}) -> LocoActionMachine:
	return LocoActionMachine.new(profile, null)

func _in(mx: float = 0.0, my: float = 0.0, jump: bool = false, dash: bool = false, attack: bool = false) -> LocoInputFrame:
	var f := LocoInputFrame.empty()
	f.move = Vector2(mx, my)
	f.jump = jump
	f.dash = dash
	f.attack = attack
	return f

func _empty() -> LocoInputFrame:
	return LocoInputFrame.empty()

## 缩短攻击三段时长，让测试不必推进很久；窗口仍用真实的 1.2 秒。
func _attack_profile() -> Dictionary:
	return {
		"attack_windup": 0.1,
		"attack_active": 0.1,
		"attack_recovery": 0.1,
		"attack_combo_window": 1.2,
	}

# ---------------------------------------------------------------- 地面移动
func test_idle_without_input() -> void:
	var m := _make()
	var out := m.tick(0.1, _empty(), true)
	assert_int(out.state).is_equal(LocoActionState.IDLE)
	assert_vector(out.plane_pos).is_equal(Vector2.ZERO)
	assert_vector(out.velocity).is_equal(Vector2.ZERO)
	assert_float(out.height).is_equal_approx(0.0, 0.0001)

func test_move_enters_run_and_moves_plane_pos() -> void:
	var m := _make()
	var out := m.tick(0.1, _in(1.0, 0.0), true)
	assert_int(out.state).is_equal(LocoActionState.RUN)
	assert_float(out.velocity.x).is_equal_approx(6.0, 0.001)
	assert_float(out.plane_pos.x).is_equal_approx(0.6, 0.001)

func test_facing_follows_move_and_holds_when_zero() -> void:
	var m := _make()
	var out := m.tick(0.016, _in(-1.0, 0.0), true)
	assert_int(out.facing).is_equal(-1)
	out = m.tick(0.016, _empty(), true)
	assert_int(out.facing).override_failure_message("move.x 为 0 时应保持原朝向").is_equal(-1)
	out = m.tick(0.016, _in(1.0, 0.0), true)
	assert_int(out.facing).is_equal(1)

func test_lane_is_clamped_to_bounds() -> void:
	var m := _make()
	var out := m.tick(1.0, _in(0.0, 1.0), true)
	assert_float(out.plane_pos.y).is_equal_approx(GameConstants.LANE_MAX, 0.001)
	out = m.tick(2.0, _in(0.0, -1.0), true)
	assert_float(out.plane_pos.y).is_equal_approx(GameConstants.LANE_MIN, 0.001)

# ---------------------------------------------------------------- 跳跃
func test_jump_uses_profile_velocity_and_leaves_ground() -> void:
	var m := _make({"jump_velocity": 12.0})
	var out := m.tick(0.0, _in(0.0, 0.0, true), true)
	assert_int(out.state).is_equal(LocoActionState.JUMP)
	assert_float(out.vertical_velocity).is_equal_approx(12.0, 0.001)
	out = m.tick(0.05, _empty(), true)
	assert_float(out.height).is_greater(0.0)

func test_jump_cut_multiplies_rising_velocity() -> void:
	var m := _make()
	var out1 := m.tick(0.016, _in(0.0, 0.0, true), true)
	var rising_before_cut: float = out1.vertical_velocity
	var out2 := m.tick(0.016, _empty(), true)
	# 先切断再施加重力，所以期望值是「切断后的速度 - 本帧重力」
	var expected: float = rising_before_cut * GameConstants.JUMP_CUT_MULTIPLIER - 32.0 * 0.016
	assert_float(out2.vertical_velocity).is_equal_approx(expected, 0.001)
	assert_float(out2.vertical_velocity).is_less(rising_before_cut)

func test_coyote_time_allows_jump_after_leaving_ground() -> void:
	var m := _make()
	m.tick(0.016, _empty(), true)   # 建立地面土狼计时
	m.set_height(1.0)
	m.tick(0.05, _empty(), true)    # 进入 FALL，土狼时间尚未耗尽
	var out := m.tick(0.0, _in(0.0, 0.0, true), true)
	assert_int(out.state).is_equal(LocoActionState.JUMP)
	assert_float(out.vertical_velocity).is_greater(0.0)

func test_coyote_time_expires_after_window() -> void:
	var m := _make()
	m.tick(0.016, _empty(), true)
	m.set_height(1.0)
	m.tick(0.06, _empty(), true)    # 土狼 0.10 -> 0.04
	m.tick(0.06, _empty(), true)    # 土狼 -> 0
	var out := m.tick(0.0, _in(0.0, 0.0, true), true)
	assert_int(out.state).is_not_equal(LocoActionState.JUMP)
	assert_float(out.vertical_velocity).is_less(0.0)

# ---------------------------------------------------------------- 冲刺
func test_dash_speed_and_invulnerability_window() -> void:
	var m := _make()
	var out := m.tick(0.01, _in(0.0, 0.0, false, true, false), true)
	assert_int(out.state).is_equal(LocoActionState.DASH)
	assert_bool(out.invulnerable).is_true()
	assert_float(out.velocity.x).is_equal_approx(16.0, 0.001)
	assert_bool(out.can_be_interrupted).is_false()

	for i: int in range(16):
		out = m.tick(0.01, _empty(), true)
	assert_int(out.state).is_equal(LocoActionState.DASH)
	assert_bool(out.invulnerable).override_failure_message("冲刺前 0.18 秒应无敌").is_true()

	for i: int in range(3):
		out = m.tick(0.01, _empty(), true)
	assert_int(out.state).is_equal(LocoActionState.DASH)
	assert_bool(out.invulnerable).override_failure_message("0.18 秒后无敌应结束").is_false()
	assert_bool(out.can_be_interrupted).is_true()

	for i: int in range(20):
		out = m.tick(0.01, _empty(), true)
	assert_int(out.state).override_failure_message("0.36 秒后冲刺应结束").is_not_equal(LocoActionState.DASH)

func test_dash_invulnerability_ignores_hitstun() -> void:
	var m := _make()
	var out := m.tick(0.01, _in(0.0, 0.0, false, true, false), true)
	assert_int(out.state).is_equal(LocoActionState.DASH)
	m.apply_hitstun(0.3, Vector2(5.0, 0.0))
	out = m.tick(0.01, _empty(), true)
	assert_int(out.state).is_equal(LocoActionState.DASH)
	assert_float(out.velocity.x).is_equal_approx(16.0, 0.001)

# ---------------------------------------------------------------- 攻击
func test_attack_chains_combo_with_buffered_input() -> void:
	var m := _make(_attack_profile())
	m.tick(0.0, _in(0.0, 0.0, false, false, true), true)
	assert_int(m.current_state()).is_equal(LocoActionState.ATTACK)
	assert_int(m.combo_index()).is_equal(0)
	m.tick(0.25, _empty(), true)
	assert_int(m.attack_phase()).is_equal(LocoActionMachine.ATTACK_PHASE_RECOVERY)
	var out := m.tick(0.06, _in(0.0, 0.0, false, false, true), true)
	assert_int(out.state).is_equal(LocoActionState.ATTACK)
	assert_int(m.combo_index()).override_failure_message(
		"recovery 结束前 0.12 秒内的攻击应自动接段").is_equal(1)

func test_attack_combo_resets_after_window() -> void:
	var profile := _attack_profile()
	profile["attack_combo_window"] = 0.2
	var m := _make(profile)
	m.tick(0.0, _in(0.0, 0.0, false, false, true), true)
	m.tick(0.25, _empty(), true)
	m.tick(0.06, _in(0.0, 0.0, false, false, true), true)
	assert_int(m.combo_index()).is_equal(1)
	m.tick(0.31, _empty(), true)
	assert_int(m.current_state()).is_equal(LocoActionState.IDLE)
	m.tick(0.25, _empty(), true)
	assert_int(m.combo_index()).override_failure_message("窗口过期后连段应重置").is_equal(0)
	var out := m.tick(0.0, _in(0.0, 0.0, false, false, true), true)
	assert_int(out.state).is_equal(LocoActionState.ATTACK)
	assert_int(m.combo_index()).override_failure_message("重置后应从第一段开始").is_equal(0)

func test_attack_slows_movement_to_multiplier() -> void:
	var m := _make({"move_speed": 10.0, "attack_move_multiplier": 0.2})
	m.tick(0.0, _in(0.0, 0.0, false, false, true), true)
	var out := m.tick(0.05, _in(1.0, 0.0), true)
	assert_int(out.state).is_equal(LocoActionState.ATTACK)
	assert_float(out.velocity.x).is_equal_approx(2.0, 0.001)

func test_attack_phases_advance_in_order() -> void:
	var m := _make(_attack_profile())
	m.tick(0.0, _in(0.0, 0.0, false, false, true), true)
	assert_int(m.attack_phase()).is_equal(LocoActionMachine.ATTACK_PHASE_WINDUP)
	m.tick(0.1, _empty(), true)
	assert_int(m.attack_phase()).is_equal(LocoActionMachine.ATTACK_PHASE_ACTIVE)
	m.tick(0.1, _empty(), true)
	assert_int(m.attack_phase()).is_equal(LocoActionMachine.ATTACK_PHASE_RECOVERY)
	var out := m.tick(0.1, _empty(), true)
	assert_int(out.state).is_not_equal(LocoActionState.ATTACK)

func test_buffered_jump_chains_after_attack_recovery() -> void:
	var m := _make(_attack_profile())
	m.tick(0.0, _in(0.0, 0.0, false, false, true), true)
	m.tick(0.25, _empty(), true)
	var out := m.tick(0.06, _in(0.0, 0.0, true), true)
	assert_int(out.state).override_failure_message(
		"recovery 末段的跳跃预输入应自动衔接").is_equal(LocoActionState.JUMP)

# ---------------------------------------------------------------- 受击 / 霸体 / 技能
func test_hitstun_enters_hurt_and_friction_decays_knockback() -> void:
	var m := _make()
	m.apply_hitstun(0.3, Vector2(6.0, 0.0))
	var out := m.tick(0.05, _in(-1.0, 0.0), true)
	assert_int(out.state).is_equal(LocoActionState.HURT)
	assert_float(out.velocity.x).override_failure_message(
		"击退速度按 friction 线性衰减").is_equal_approx(4.8, 0.01)
	assert_float(out.plane_pos.x).override_failure_message(
		"受击期间输入不能反向移动").is_greater(0.0)
	out = m.tick(0.05, _in(-1.0, 0.0), true)
	assert_float(out.velocity.x).is_less(4.8)
	out = m.tick(0.3, _empty(), true)
	assert_int(out.state).is_equal(LocoActionState.IDLE)

func test_super_armor_ignores_hitstun() -> void:
	var m := _make()
	m.set_super_armor(true)
	m.apply_hitstun(0.3, Vector2(5.0, 0.0))
	var out := m.tick(0.016, _empty(), true)
	assert_int(out.state).override_failure_message("霸体不应进入 HURT").is_equal(LocoActionState.IDLE)
	assert_bool(out.super_armor).is_true()
	assert_bool(out.can_be_interrupted).is_false()
	assert_vector(out.velocity).is_equal(Vector2.ZERO)
	assert_vector(out.plane_pos).is_equal(Vector2.ZERO)

func test_profile_super_armor_flag_is_honored() -> void:
	var m := _make({"super_armor": true})
	m.apply_hitstun(0.2, Vector2(3.0, 0.0))
	var out := m.tick(0.016, _empty(), true)
	assert_int(out.state).is_equal(LocoActionState.IDLE)
	assert_bool(out.super_armor).is_true()

func test_skill_lock_blocks_movement_then_returns_idle() -> void:
	var m := _make()
	m.request_skill_lock(0.2)
	var out := m.tick(0.1, _in(1.0, 0.0), true)
	assert_int(out.state).is_equal(LocoActionState.SKILL)
	assert_vector(out.velocity).is_equal(Vector2.ZERO)
	assert_vector(out.plane_pos).override_failure_message("技能锁定期间不可移动").is_equal(Vector2.ZERO)
	out = m.tick(0.1, _in(1.0, 0.0), true)
	assert_int(out.state).is_equal(LocoActionState.IDLE)
	out = m.tick(0.1, _in(1.0, 0.0), true)
	assert_int(out.state).is_equal(LocoActionState.RUN)
	assert_float(out.plane_pos.x).is_greater(0.0)

# ---------------------------------------------------------------- 落地 / 死亡 / 事件
func test_land_state_lasts_land_duration() -> void:
	var m := _make({"jump_velocity": 0.0})
	var out := m.tick(0.0, _in(0.0, 0.0, true), true)
	assert_int(out.state).override_failure_message("落地立即进入 LAND").is_equal(LocoActionState.LAND)
	out = m.tick(0.05, _empty(), true)
	assert_int(out.state).is_equal(LocoActionState.LAND)
	out = m.tick(0.04, _empty(), true)
	assert_int(out.state).is_equal(LocoActionState.IDLE)

func test_dead_state_is_terminal() -> void:
	var m := _make()
	var out := m.tick(0.016, _empty(), false)
	assert_int(out.state).is_equal(LocoActionState.DEAD)
	assert_vector(out.velocity).is_equal(Vector2.ZERO)
	assert_bool(out.can_be_interrupted).is_false()
	out = m.tick(0.016, _in(1.0, 0.0, true, true, true), true)
	assert_int(out.state).is_equal(LocoActionState.DEAD)
	assert_vector(out.plane_pos).is_equal(Vector2.ZERO)

func test_action_changed_event_uses_state_names() -> void:
	var bus := DomainEventBus.new()
	var events: Array[Dictionary] = []
	var cb := func(e: DomainEvent) -> void: events.append(e.payload)
	bus.subscribe(GameConstants.EVT_ACTION_CHANGED, cb)
	var m := LocoActionMachine.new({"actor_id": 42}, bus)
	m.tick(0.016, _in(1.0, 0.0), true)
	assert_int(events.size()).is_equal(1)
	assert_str(events[0]["from"]).is_equal(&"idle")
	assert_str(events[0]["to"]).is_equal(&"run")
	assert_int(events[0]["actor_id"]).is_equal(42)
	m.tick(0.016, _empty(), true)
	assert_int(events.size()).is_equal(2)
	assert_str(events[1]["from"]).is_equal(&"run")
	assert_str(events[1]["to"]).is_equal(&"idle")

func test_snapshot_contains_state_name_and_position() -> void:
	var m := _make()
	m.tick(0.1, _in(1.0, 0.0), true)
	var snap := m.snapshot()
	assert_int(snap["state"]).is_equal(LocoActionState.RUN)
	assert_str(snap["state_name"]).is_equal(&"run")
	var p: Vector2 = snap["plane_pos"]
	assert_float(p.x).is_equal_approx(0.6, 0.001)
	assert_bool(snap.has("coyote_timer")).is_true()

# ---------------------------------------------------------------- 硬直
func test_hitstun_enters_hurt_then_recovers() -> void:
	var m := _make()
	m.tick(GameConstants.TICK_DELTA, _empty(), true)
	m.apply_hitstun(0.2, Vector2(2.0, 0.0))
	assert_int(m.current_state()).is_equal(LocoActionState.HURT)
	for i: int in 20:
		m.tick(GameConstants.TICK_DELTA, _empty(), true)
	assert_int(m.current_state()).override_failure_message(
		"硬直结束后必须回到可操作状态").is_equal(LocoActionState.IDLE)

func test_hitstun_immunity_prevents_chain() -> void:
	var m := _make()
	m.tick(GameConstants.TICK_DELTA, _empty(), true)
	m.apply_hitstun(0.1, Vector2.ZERO)
	# 推进到硬直结束，此时免疫窗口（0.35s）还剩一半
	for i: int in 8:
		m.tick(GameConstants.TICK_DELTA, _empty(), true)
	assert_bool(m.is_in_hurt()).is_false()
	m.apply_hitstun(0.1, Vector2.ZERO)
	assert_bool(m.is_in_hurt()).override_failure_message(
		"免疫窗口内不该被再次打入硬直").is_false()
	# 免疫过期后应当能再次吃硬直
	for i: int in 30:
		m.tick(GameConstants.TICK_DELTA, _empty(), true)
	m.apply_hitstun(0.1, Vector2.ZERO)
	assert_bool(m.is_in_hurt()).is_true()

func test_hitstun_ignored_during_invulnerability() -> void:
	var m := _make()
	m.tick(GameConstants.TICK_DELTA, _empty(), true)
	# 冲刺前 0.18 秒无敌，这段时间不该被硬直打断
	m.tick(GameConstants.TICK_DELTA, _in(0.0, 0.0, false, true), true)
	assert_int(m.current_state()).is_equal(LocoActionState.DASH)
	m.apply_hitstun(0.2, Vector2.ZERO)
	assert_int(m.current_state()).is_equal(LocoActionState.DASH)
