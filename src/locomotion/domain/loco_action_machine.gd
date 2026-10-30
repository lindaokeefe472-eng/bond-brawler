## 动作状态机：把「输入 + 时间」翻译成「位置 + 速度 + 状态」。
##
## 三层职责（改之前先读）：
##   1. 输入层（InputAdapter）：渲染帧锁存按下沿，逻辑步消费，只保证「按下的键不丢」。
##   2. 仲裁层（InputContract + IntentArbiter）：每个 tick 最多选出一个意图，优先级固定。
##   3. 运动层（MotionMode）：只有 FREE/AIR 状态读方向键；SCRIPTED 状态只执行脚本曲线。
##
## 因此攻击/冲刺/受击/施法期间，方向输入没有任何代码路径能改坐标 ——
## 「攻击时还能缓慢移动」是结构上不可能，而不是靠参数调成 0。
##
## 状态推进只发生在 tick() 里，纯 RefCounted、无场景树，可回放可单测。
class_name LocoActionMachine
extends RefCounted

## 攻击的三个阶段。表现层/判定层需要知道哪一段真正有判定。
const ATTACK_PHASE_WINDUP: int = 0
const ATTACK_PHASE_ACTIVE: int = 1
const ATTACK_PHASE_RECOVERY: int = 2

## 移动向量的死区，避免 32 位浮点噪声让角色原地抖动。
const MOVE_DEADZONE_SQUARED: float = 0.0001
## 浮点阶段推进的容差，防止 dt 累加后差 1e-16 卡在阶段边界。
const TIME_EPSILON: float = 0.000001
## 进入硬直后的免疫窗口（秒）：这段时间内再挨打只吃击退不吃硬直。
const HITSTUN_IMMUNITY: float = 0.35
## 预输入窗口：按键距离「可执行时刻」不超过这么多 tick 才保留（约 0.15 秒）。
##
## 窗口锚定在可执行时刻，而不是按下时刻 —— 否则按住动作里的键会保留到
## 0.8 秒后自己触发，看起来就是「按了一下，过一会儿角色自己动」。
const BUFFER_TICKS: int = 9
## 收招可取消的比例：恢复段的后半段才能接冲刺/跳跃/技能。
const CANCEL_RATIO: float = 0.5

## 运动模式：决定这个状态读不读方向键。
## FREE  = 地面自由移动（读方向）
## AIR   = 空中控制（读方向）
## SCRIPTED = 攻击/冲刺/施法/受击/死亡（不读方向，只执行脚本曲线）
enum MotionMode {
	FREE,
	AIR,
	SCRIPTED,
}

## 一段普攻的时序与窗口（秒；比较时按 tick 量化）。
class AttackSegment:
	const CANCEL_RATIO: float = 0.5
	var windup: float = 0.0
	var active: float = 0.0
	var recovery: float = 0.0
	## 起手到判定结束之间的前冲距离（米）。默认 0：攻击不位移。
	var lunge_distance: float = 0.0

	func _init(p_windup: float, p_active: float, p_recovery: float, p_lunge: float) -> void:
		windup = p_windup
		active = p_active
		recovery = p_recovery
		lunge_distance = p_lunge

	## 取消窗口相对恢复段起点的偏移（秒）。
	func cancel_offset() -> float:
		return recovery * CANCEL_RATIO

## profile 缺省值：与 data/actions.json 的还原数值保持一致。
const DEFAULT_PROFILE: Dictionary = {
	"move_speed": 6.0,
	"depth_speed_multiplier": 0.7,
	"air_control": 0.75,
	"gravity": 32.0,
	"jump_velocity": 9.47,
	"land_duration": 0.08,
	"dash_speed": 16.0,
	"dash_duration": 0.36,
	"dash_invulnerable_duration": 0.18,
	"attack_combo_count": 3,
	"attack_combo_window": 1.2,
	"attack_windup": [0.17, 0.17, 0.23],
	"attack_active": [0.10, 0.10, 0.12],
	"attack_recovery": [0.29, 0.29, 0.46],
	## 逐段前冲距离。默认全 0：攻击期间不因任何输入产生位移。
	"attack_lunge": [0.0, 0.0, 0.0],
	"hitstun_friction": 24.0,
	"super_armor": false,
}

var _profile: Dictionary = {}
var _bus: DomainEventBus = null
var _actor_id: int = 0

var _state: int = LocoActionState.IDLE
var _time: float = 0.0
var _state_time: float = 0.0
var _plane_pos: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _height: float = 0.0
var _vertical_velocity: float = 0.0
var _facing: int = 1

var _super_armor: bool = false
var _invulnerable_timer: float = 0.0
var _coyote_timer: float = GameConstants.COYOTE_TIME
var _jump_cut_used: bool = false

var _dash_timer: float = 0.0
var _hurt_timer: float = 0.0
var _hitstun_immunity: float = 0.0
var _skill_timer: float = 0.0
var _land_timer: float = 0.0

var _segments: Array = []
var _attack_phase: int = ATTACK_PHASE_WINDUP
var _attack_phase_time: float = 0.0
var _combo_index: int = 0
## 连段标志：判定段开始后按下的攻击会置位，收招段一开始就接下一段。
## 只保留一个标志，切段即清零 —— 任何情况下最多额外出一段。
var _link: bool = false
## 单槽预输入：冲刺/跳跃（以及冲刺中的攻击）。新按键覆盖旧按键，用后即清。
var _buffered: StringName = &""
## 本 tick 的按下沿。由 _read_input 填，_update_state 里的仲裁消费。
var _pressed: Dictionary = {}

var _prev_jump: bool = false
var _prev_dash: bool = false
var _prev_attack: bool = false

func _init(profile: Dictionary = {}, bus: DomainEventBus = null) -> void:
	_profile = DEFAULT_PROFILE.duplicate(true)
	for key: Variant in profile.keys():
		_profile[key] = profile[key]
	_bus = bus
	_actor_id = int(_profile.get("actor_id", 0))
	_super_armor = bool(_profile.get("super_armor", false))
	_plane_pos = PlaneMath.clamp_arena(_read_vec2(_profile.get("start_pos", Vector2.ZERO), Vector2.ZERO))
	_height = maxf(float(_profile.get("start_height", 0.0)), 0.0)
	var start_facing: int = int(_profile.get("facing", 1))
	_facing = 1 if start_facing >= 0 else -1
	_state = LocoActionState.FALL if _height > 0.0 else LocoActionState.IDLE
	_build_segments()

func _build_segments() -> void:
	var count: int = maxi(int(_profile.get("attack_combo_count", 1)), 1)
	_segments.clear()
	for i: int in range(count):
		_segments.append(AttackSegment.new(
				_stage_value(_profile.get("attack_windup"), i),
				_stage_value(_profile.get("attack_active"), i),
				_stage_value(_profile.get("attack_recovery"), i),
				_stage_value(_profile.get("attack_lunge"), i)))

# ------------------------------------------------------------------ 主循环
func tick(dt: float, input: LocoInputFrame, alive: bool) -> LocoActionOutput:
	var step: float = maxf(dt, 0.0)
	_time += step
	_pressed.clear()

	if not alive:
		_enter_dead()
		_settle_dead(step)
		return _build_output()
	if _state == LocoActionState.DEAD:
		return _build_output()

	_state_time += step
	_update_timers(step)
	_read_input(input)
	_refresh_ground_state()
	var move: Vector2 = input.clamped_move() if input != null else Vector2.ZERO
	_update_state(step, input, move)
	_integrate(step)
	_update_coyote(step)
	return _build_output()

func _enter_dead() -> void:
	if _state == LocoActionState.DEAD:
		return
	_set_state(LocoActionState.DEAD)
	_velocity = Vector2.ZERO
	_vertical_velocity = 0.0
	_dash_timer = 0.0
	_invulnerable_timer = 0.0
	_hurt_timer = 0.0
	_skill_timer = 0.0
	_link = false
	_buffered = &""

## 死亡后继续下落：空中被打死不该停在半空。横向不再移动。
func _settle_dead(dt: float) -> void:
	if _height <= 0.0:
		_height = 0.0
		_vertical_velocity = 0.0
		return
	_vertical_velocity -= float(_profile.get("gravity", 0.0)) * dt
	_height += _vertical_velocity * dt
	if _height <= 0.0:
		_height = 0.0
		_vertical_velocity = 0.0

func _update_timers(dt: float) -> void:
	_invulnerable_timer = maxf(0.0, _invulnerable_timer - dt)
	_hitstun_immunity = maxf(0.0, _hitstun_immunity - dt)

## 只认上升沿：输入帧里的布尔是「按下」语义，一次按键只处理一次。
func _read_input(input: LocoInputFrame) -> void:
	if input == null:
		_prev_jump = false
		_prev_dash = false
		_prev_attack = false
		return
	if input.jump and not _prev_jump:
		_on_press(&"jump")
	if input.dash and not _prev_dash:
		_on_press(&"dash")
	if input.attack and not _prev_attack:
		_on_press(&"attack")
	_prev_jump = input.jump
	_prev_dash = input.dash
	_prev_attack = input.attack

## 按契约表处置一次按下。技能不在这里 —— ActorRuntime 先于动作机处理。
func _on_press(action: StringName) -> void:
	match InputContract.disposition(_state, action):
		InputContract.Disposition.ACCEPT:
			_pressed[action] = true
		InputContract.Disposition.LINK:
			# 连段窗口从判定段开始；起手阶段的按键直接丢弃。
			if _attack_phase >= ATTACK_PHASE_ACTIVE:
				_link = true
		InputContract.Disposition.BUFFER:
			# 只有距离可执行时刻足够近的按键才保留，更早的丢弃。
			if _ticks_until_executable(action) <= BUFFER_TICKS:
				_buffered = action
		_:
			pass

## 高度 > 0 就是空中；地面/空中状态由高度单向推导，避免两套状态互相打架。
func _refresh_ground_state() -> void:
	if _is_airborne():
		if _state == LocoActionState.IDLE or _state == LocoActionState.RUN or _state == LocoActionState.LAND:
			_set_state(LocoActionState.FALL)
	elif _state == LocoActionState.FALL:
		_set_state(LocoActionState.IDLE)

func _update_state(dt: float, _input: LocoInputFrame, move: Vector2) -> void:
	# 运动模式是 R1 的结构保证：只有 FREE/AIR 会拿到 move。
	match motion_mode_for(_state):
		MotionMode.FREE:
			_update_ground(dt, move)
		MotionMode.AIR:
			_update_air(dt, move)
		_:
			_update_scripted(dt)

## 脚本状态：只执行自己的曲线（lunge / 冲刺 / 击退），不读方向键。
func _update_scripted(dt: float) -> void:
	match _state:
		LocoActionState.DASH:
			_update_dash(dt)
		LocoActionState.ATTACK:
			_update_attack(dt)
		LocoActionState.SKILL:
			_update_skill(dt)
		LocoActionState.HURT:
			_update_hurt(dt)
		_:
			_velocity = Vector2.ZERO

## 每个状态属于哪种运动模式。攻击/冲刺/施法/受击/死亡一律 SCRIPTED。
static func motion_mode_for(state: int) -> int:
	match state:
		LocoActionState.IDLE, LocoActionState.RUN, LocoActionState.LAND:
			return MotionMode.FREE
		LocoActionState.JUMP, LocoActionState.FALL:
			return MotionMode.AIR
	return MotionMode.SCRIPTED

# ------------------------------------------------------------------ 地面
func _update_ground(dt: float, move: Vector2) -> void:
	_facing = PlaneMath.facing_from_input(move.x, _facing)
	_apply_ground_velocity(move, 1.0)

	if _state == LocoActionState.LAND:
		_land_timer = maxf(0.0, _land_timer - dt)
		if _land_timer <= 0.0:
			_set_state(LocoActionState.IDLE)

	if _try_intents():
		return

	if _state == LocoActionState.IDLE or _state == LocoActionState.RUN:
		_set_state(LocoActionState.RUN if _is_moving(move) else LocoActionState.IDLE)

func _apply_ground_velocity(move: Vector2, speed_scale: float) -> void:
	var speed: float = float(_profile.get("move_speed", 0.0)) * speed_scale
	var depth: float = float(_profile.get("depth_speed_multiplier", 1.0))
	# 纵深方向移动更慢：清版游戏的走位需要「横向快、纵向稳」。
	_velocity = Vector2(move.x * speed, move.y * speed * depth)

func _is_moving(move: Vector2) -> bool:
	return move.length_squared() > MOVE_DEADZONE_SQUARED

# ------------------------------------------------------------------ 空中
func _update_air(_dt: float, move: Vector2) -> void:
	_facing = PlaneMath.facing_from_input(move.x, _facing)
	var air_control: float = float(_profile.get("air_control", 1.0))
	_apply_ground_velocity(move, air_control)

	# 可变跳跃高度：只在上升段切断一次。重复切断会把速度越乘越小，手感发黏。
	if _state == LocoActionState.JUMP and not _jump_cut_used:
		var jump_held: bool = _prev_jump
		if not jump_held and _vertical_velocity > 0.0:
			_vertical_velocity *= GameConstants.JUMP_CUT_MULTIPLIER
			_jump_cut_used = true

	if _state == LocoActionState.JUMP and _vertical_velocity <= 0.0:
		_set_state(LocoActionState.FALL)

	if _try_intents():
		return

# ------------------------------------------------------------------ 意图仲裁
## 同帧多键：按 冲刺 > 跳跃 > 攻击 取第一个能执行的；其余丢弃。
## 技能在 ActorRuntime 里先处理，所以实际优先级是 技能 > 冲刺 > 跳跃 > 攻击。
func _try_intents() -> bool:
	var airborne: bool = _is_airborne()
	for action: StringName in IntentArbiter.PRIORITY:
		if not bool(_pressed.get(action, false)):
			continue
		if action == &"dash":
			# v1 不开放空中冲刺。
			if airborne:
				continue
			if _can_dash():
				_start_dash()
				return true
		elif action == &"jump":
			if _can_jump():
				_start_jump()
				return true
		elif action == &"attack":
			if _can_attack():
				_start_attack()
				return true
	return false

# ------------------------------------------------------------------ 冲刺
func _update_dash(dt: float) -> void:
	_dash_timer = maxf(0.0, _dash_timer - dt)
	if _dash_timer > 0.0:
		_velocity = Vector2(float(_facing) * float(_profile.get("dash_speed", 0.0)), 0.0)
		return

	# 计时归零的这一拍不能再按冲刺速度走，否则实际位移比 dash_duration 多一帧。
	_invulnerable_timer = 0.0
	_velocity = Vector2.ZERO
	_set_state(LocoActionState.IDLE if not _is_airborne() else LocoActionState.FALL)
	_consume_buffered_after_dash()

func _start_dash() -> void:
	_set_state(LocoActionState.DASH)
	_dash_timer = float(_profile.get("dash_duration", 0.0))
	_invulnerable_timer = float(_profile.get("dash_invulnerable_duration", 0.0))
	_velocity = Vector2(float(_facing) * float(_profile.get("dash_speed", 0.0)), 0.0)
	_jump_cut_used = false

func _can_dash() -> bool:
	return _state == LocoActionState.IDLE \
		or _state == LocoActionState.RUN \
		or _state == LocoActionState.LAND \
		or _state == LocoActionState.JUMP \
		or _state == LocoActionState.FALL

## 冲刺结束兑现预输入：攻击优先于跳跃。
func _consume_buffered_after_dash() -> void:
	if _buffered == &"":
		return
	var action: StringName = _buffered
	_buffered = &""
	if action == &"attack" and _can_attack():
		_start_attack()
		return
	if action == &"jump" and _can_jump():
		_start_jump()

# ------------------------------------------------------------------ 攻击
func _update_attack(dt: float) -> void:
	_attack_phase_time += dt
	while true:
		var duration: float = _quantize(_phase_duration(_attack_phase))
		if _attack_phase_time + TIME_EPSILON < duration:
			break
		_attack_phase_time -= duration
		_attack_phase += 1
		if _attack_phase > ATTACK_PHASE_RECOVERY:
			_finish_attack()
			return

	# 连段：恢复段一开始就接下一段（连段窗口内按过攻击）。
	if _attack_phase == ATTACK_PHASE_RECOVERY and _link \
			and _combo_index + 1 < _segments.size():
		_start_attack(true)
		return

	# 取消窗口：恢复段后半段可以接冲刺/跳跃。
	if _attack_phase == ATTACK_PHASE_RECOVERY and _attack_phase_time >= _cancel_offset():
		if _consume_buffered_cancel():
			return

	_apply_lunge()

func _phase_duration(phase: int) -> float:
	if _segments.is_empty():
		return 0.0
	var seg: AttackSegment = _segments[_combo_index]
	match phase:
		ATTACK_PHASE_WINDUP:
			return seg.windup
		ATTACK_PHASE_ACTIVE:
			return seg.active
		_:
			return seg.recovery

## 当前段内已经过去的秒数（按 tick 量化后的相位时长累计）。
func _segment_elapsed() -> float:
	var seg: AttackSegment = _segments[_combo_index]
	match _attack_phase:
		ATTACK_PHASE_WINDUP:
			return _attack_phase_time
		ATTACK_PHASE_ACTIVE:
			return _quantize(seg.windup) + _attack_phase_time
		_:
			return _quantize(seg.windup) + _quantize(seg.active) + _attack_phase_time

## 取消窗口相对恢复段起点的偏移（秒，已量化）。
func _cancel_offset() -> float:
	if _segments.is_empty():
		return 0.0
	var seg: AttackSegment = _segments[_combo_index]
	return _quantize(seg.cancel_offset())

## 距离取消窗口开启还有多少 tick；不在攻击中返回一个很大的数。
func _ticks_until_cancel() -> int:
	if _state != LocoActionState.ATTACK or _segments.is_empty():
		return 1 << 30
	var seg: AttackSegment = _segments[_combo_index]
	var cancel_at: float = _quantize(seg.windup) + _quantize(seg.active) \
			+ _quantize(seg.cancel_offset())
	return int(ceil((cancel_at - _segment_elapsed()) * float(GameConstants.TICK_RATE)))

## 距离冲刺结束还有多少 tick。
func _ticks_until_dash_end() -> int:
	return int(ceil(_dash_timer * float(GameConstants.TICK_RATE)))

## 距离「这个动作可以执行」还有多少 tick。预输入窗口用它判断是否保留按键。
func _ticks_until_executable(_action: StringName) -> int:
	match _state:
		LocoActionState.ATTACK:
			return _ticks_until_cancel()
		LocoActionState.DASH:
			return _ticks_until_dash_end()
	return 1 << 30

## 恢复段后半段可以接冲刺/跳跃；方向键永远不能取消攻击。
func _consume_buffered_cancel() -> bool:
	if _buffered == &"":
		return false
	var action: StringName = _buffered
	_buffered = &""
	if action == &"dash" and not _is_airborne():
		_start_dash()
		return true
	if action == &"jump" and not _is_airborne():
		_start_jump()
		return true
	return false

## 攻击位移只来自这一段自己的 lunge 曲线，默认 0 —— 方向输入不参与。
func _apply_lunge() -> void:
	if _segments.is_empty():
		_velocity = Vector2.ZERO
		return
	var seg: AttackSegment = _segments[_combo_index]
	if seg.lunge_distance <= 0.0:
		_velocity = Vector2.ZERO
		return
	var from: float = _quantize(seg.windup)
	var to: float = from + _quantize(seg.active)
	var elapsed: float = _segment_elapsed()
	if to > from and elapsed >= from and elapsed <= to:
		_velocity = Vector2(float(_facing) * seg.lunge_distance / (to - from), 0.0)
	else:
		_velocity = Vector2.ZERO

func _start_attack(chain: bool = false) -> void:
	if chain and _combo_index + 1 < _segments.size():
		_combo_index += 1
	else:
		_combo_index = 0
	_link = false
	_buffered = &""
	_attack_phase = ATTACK_PHASE_WINDUP
	_attack_phase_time = 0.0
	# 攻击起手零位移：地面不继承跑动速度，空中也不保留水平速度。
	_velocity = Vector2.ZERO
	_set_state(LocoActionState.ATTACK)

func _finish_attack() -> void:
	# 连段：收招里按下的攻击如果同一 tick 跨过了恢复段，也要接上。
	if _link and _combo_index + 1 < _segments.size():
		_link = false
		_start_attack(true)
		return
	var buffered: StringName = _buffered
	_buffered = &""
	_link = false
	_set_state(LocoActionState.IDLE if not _is_airborne() else LocoActionState.FALL)
	# 取消窗口内按下的冲刺/跳跃：即使这一 tick 刚好把攻击播完，也要兑现。
	if buffered == &"dash" and not _is_airborne():
		_start_dash()
		return
	if buffered == &"jump" and _can_jump():
		_start_jump()

func _can_attack() -> bool:
	return _state == LocoActionState.IDLE \
		or _state == LocoActionState.RUN \
		or _state == LocoActionState.LAND \
		or _state == LocoActionState.JUMP \
		or _state == LocoActionState.FALL

# ------------------------------------------------------------------ 技能 / 受击
func _update_skill(dt: float) -> void:
	_velocity = Vector2.ZERO
	_skill_timer = maxf(0.0, _skill_timer - dt)
	if _skill_timer > 0.0:
		return
	_set_state(LocoActionState.IDLE if not _is_airborne() else LocoActionState.FALL)

func _update_hurt(dt: float) -> void:
	_hurt_timer = maxf(0.0, _hurt_timer - dt)
	var friction: float = float(_profile.get("hitstun_friction", 0.0))
	# 线性摩擦而不是指数衰减：击退距离可预测，方便数值调平。
	_velocity = _velocity.move_toward(Vector2.ZERO, friction * dt)
	if _hurt_timer > 0.0:
		return
	_set_state(LocoActionState.IDLE if not _is_airborne() else LocoActionState.FALL)

# ------------------------------------------------------------------ 动作入口
func _can_jump() -> bool:
	if not _can_dash():
		return false
	if _state == LocoActionState.JUMP:
		return false
	if not _is_airborne():
		return true
	# 土狼时间：刚离地（或刚被顶飞）的一小段时间内仍算「能起跳」。
	return _coyote_timer > 0.0

func _start_jump() -> void:
	_set_state(LocoActionState.JUMP)
	_vertical_velocity = float(_profile.get("jump_velocity", 0.0))
	_jump_cut_used = false
	# 起跳立刻清空土狼时间，否则空中还能再跳一次。
	_coyote_timer = 0.0

# ------------------------------------------------------------------ 物理
func _integrate(dt: float) -> void:
	if _state == LocoActionState.DEAD:
		_velocity = Vector2.ZERO
		return

	if _height > 0.0 or _vertical_velocity > 0.0 \
			or _state == LocoActionState.JUMP or _state == LocoActionState.FALL:
		var gravity: float = float(_profile.get("gravity", 0.0))
		_vertical_velocity -= gravity * dt
		_height += _vertical_velocity * dt
		# 起跳首帧高度仍是 0 但速度向上，不能判成落地。
		if _height <= 0.0 and _vertical_velocity <= 0.0:
			_height = 0.0
			_vertical_velocity = 0.0
			_on_landed()

	_plane_pos += _velocity * dt
	_plane_pos = PlaneMath.clamp_arena(_plane_pos)

func _on_landed() -> void:
	_jump_cut_used = false
	_coyote_timer = GameConstants.COYOTE_TIME
	if _state == LocoActionState.JUMP or _state == LocoActionState.FALL:
		_set_state(LocoActionState.LAND)
		_land_timer = float(_profile.get("land_duration", 0.0))

func _update_coyote(dt: float) -> void:
	if not _is_airborne() and _state != LocoActionState.JUMP and _state != LocoActionState.FALL:
		_coyote_timer = GameConstants.COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - dt)

func _is_airborne() -> bool:
	return _height > 0.0

# ------------------------------------------------------------------ 对外契约
func request_skill_lock(duration: float) -> void:
	if _state == LocoActionState.DEAD:
		return
	_skill_timer = maxf(duration, 0.0)
	_velocity = Vector2.ZERO
	_link = false
	_buffered = &""
	_set_state(LocoActionState.SKILL)

## 恢复段后半段允许用技能取消攻击（ActorRuntime 在起手前问一次）。
func can_cancel_into_skill() -> bool:
	if _state != LocoActionState.ATTACK or _attack_phase != ATTACK_PHASE_RECOVERY:
		return false
	return _attack_phase_time >= _cancel_offset()

## 距离技能可取消窗口还有多少 tick（给技能预输入用）。
func ticks_until_skill_cancel() -> int:
	return _ticks_until_cancel()

func apply_hitstun(duration: float, knockback: Vector2) -> void:
	if _state == LocoActionState.DEAD:
		return
	# 无敌帧与霸体都不进 HURT：前者连伤害都不吃，后者只扣血（扣血由 combat 负责）。
	if _super_armor or _invulnerable_timer > 0.0:
		return
	if duration <= 0.0:
		set_knockback(knockback)
		return
	# 免疫窗口内只吃击退、不吃硬直：伤害照扣，控制不叠。
	if _hitstun_immunity > 0.0:
		set_knockback(knockback)
		return
	_hitstun_immunity = HITSTUN_IMMUNITY
	_hurt_timer = duration
	_velocity = knockback
	_link = false
	_buffered = &""
	_jump_cut_used = true
	_set_state(LocoActionState.HURT)

## 供上层判断「刚才那下硬直有没有真的生效」。
func is_in_hurt() -> bool:
	return _state == LocoActionState.HURT

func set_knockback(v: Vector2) -> void:
	_velocity = v

func current_state() -> int:
	return _state

func attack_phase() -> int:
	return _attack_phase

func combo_index() -> int:
	return _combo_index

## 调试/测试用：当前是否存着预输入。
func buffered_action() -> StringName:
	return _buffered

## 外部（application / 测试）注入身份的入口，事件载荷里的 actor_id 由这里决定。
func set_actor_id(value: int) -> void:
	_actor_id = value

func set_super_armor(enabled: bool) -> void:
	_super_armor = enabled

func set_plane_pos(p: Vector2) -> void:
	_plane_pos = PlaneMath.clamp_arena(p)

## 供传送/复活/测试改变高度；状态由下一帧的 _refresh_ground_state 自动修正。
func set_height(value: float) -> void:
	_height = maxf(value, 0.0)
	if _height <= 0.0:
		_vertical_velocity = 0.0

func set_facing(value: int) -> void:
	_facing = 1 if value >= 0 else -1

func snapshot() -> Dictionary:
	return {
		"state": _state,
		"state_name": LocoActionState.name_of(_state),
		"plane_pos": _plane_pos,
		"velocity": _velocity,
		"height": _height,
		"vertical_velocity": _vertical_velocity,
		"facing": _facing,
		"state_time": _state_time,
		"combo_index": _combo_index,
		"attack_phase": _attack_phase,
		"coyote_timer": _coyote_timer,
		"super_armor": _super_armor,
		"invulnerable": _invulnerable_timer > 0.0,
		"time": _time,
	}

# ------------------------------------------------------------------ 内部工具
func _set_state(next: int) -> void:
	if _state == next:
		return
	var from: StringName = LocoActionState.name_of(_state)
	_state = next
	_state_time = 0.0
	if _bus == null:
		return
	_bus.emit(DomainEvent.new(GameConstants.EVT_ACTION_CHANGED, {
		"actor_id": _actor_id,
		"from": from,
		"to": LocoActionState.name_of(next),
	}))

func _build_output() -> LocoActionOutput:
	var out: LocoActionOutput = LocoActionOutput.new()
	out.plane_pos = _plane_pos
	out.velocity = _velocity
	out.height = _height
	out.vertical_velocity = _vertical_velocity
	out.facing = _facing
	out.state = _state
	out.super_armor = _super_armor
	out.invulnerable = _invulnerable_timer > 0.0
	out.can_be_interrupted = _compute_can_be_interrupted()
	return out

func _compute_can_be_interrupted() -> bool:
	if _state == LocoActionState.DEAD or _super_armor:
		return false
	# 无敌帧内打不动；冲刺后半段、技能、攻击后摇都可以被受击打断。
	return _invulnerable_timer <= 0.0

## 时长按 tick 量化：图集给的是秒，统一四舍五入到逻辑帧，避免浮点边界抖动。
static func _quantize(seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	var ticks: int = maxi(int(round(seconds * float(GameConstants.TICK_RATE))), 1)
	return float(ticks) / float(GameConstants.TICK_RATE)

## 逐段数组按下标取；单值（float/int）对每一段都生效。
static func _stage_value(raw: Variant, index: int) -> float:
	if raw is Array:
		var values: Array = raw
		if values.is_empty():
			return 0.0
		return float(values[clampi(index, 0, values.size() - 1)])
	if raw is float or raw is int:
		return float(raw)
	return 0.0

func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
