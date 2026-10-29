## 动作状态机：把「输入 + 时间」翻译成「位置 + 速度 + 状态」。
## 这是全项目最影响手感的地方，因此：
##   1. 所有可调数值来自构造参数 profile（对应 data/actions.json 的映射），
##      只有世界级常量（缓冲窗口、土狼时间、跳跃切断、纵深带）来自 GameConstants。
##   2. 状态推进只发生在 tick(dt) 里，纯 RefCounted、无场景树，可回放可单测。
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

## profile 缺省值：与 data/actions.json 的还原数值保持一致。
## 数值集中在这里，逻辑里不再出现裸数字，改手感只改这一处或外部 JSON。
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
	"attack_move_multiplier": 0.2,
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
## 硬直免疫：刚被打进 HURT 后的一小段时间内不再吃新的硬直，
## 否则三个敌人轮流出手就能把玩家永久锁在 HURT 里。
var _hitstun_immunity: float = 0.0
var _skill_timer: float = 0.0
var _land_timer: float = 0.0

var _attack_phase: int = ATTACK_PHASE_WINDUP
var _attack_phase_time: float = 0.0
var _combo_index: int = 0
var _combo_timer: float = 0.0

var _buffer: InputBuffer = InputBuffer.new()
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
	_plane_pos = _read_vec2(_profile.get("start_pos", Vector2.ZERO), Vector2.ZERO)
	_height = maxf(float(_profile.get("start_height", 0.0)), 0.0)
	var start_facing: int = int(_profile.get("facing", 1))
	_facing = 1 if start_facing >= 0 else -1
	_state = LocoActionState.FALL if _height > 0.0 else LocoActionState.IDLE

# ------------------------------------------------------------------ 主循环
func tick(dt: float, input: LocoInputFrame, alive: bool) -> LocoActionOutput:
	var step: float = maxf(dt, 0.0)
	_time += step
	_buffer.advance(step)

	if not alive:
		_enter_dead()
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

func _update_timers(dt: float) -> void:
	_invulnerable_timer = maxf(0.0, _invulnerable_timer - dt)
	_hitstun_immunity = maxf(0.0, _hitstun_immunity - dt)
	if _combo_timer > 0.0:
		_combo_timer = maxf(0.0, _combo_timer - dt)
		# 窗口一过就回到第一段，避免「隔了很久再按」直接出第三段。
		if _combo_timer <= 0.0:
			_combo_index = 0

## 只认上升沿：输入帧里的布尔是「按住」语义，缓冲记录的是「按下」时刻。
func _read_input(input: LocoInputFrame) -> void:
	if input == null:
		_prev_jump = false
		_prev_dash = false
		_prev_attack = false
		return
	if input.jump and not _prev_jump:
		_buffer.press(InputBuffer.ACTION_JUMP)
	if input.dash and not _prev_dash:
		_buffer.press(InputBuffer.ACTION_DASH)
	if input.attack and not _prev_attack:
		_buffer.press(InputBuffer.ACTION_ATTACK)
	_prev_jump = input.jump
	_prev_dash = input.dash
	_prev_attack = input.attack

## 高度 > 0 就是空中；地面/空中状态由高度单向推导，避免两套状态互相打架。
func _refresh_ground_state() -> void:
	if _is_airborne():
		if _state == LocoActionState.IDLE or _state == LocoActionState.RUN or _state == LocoActionState.LAND:
			_set_state(LocoActionState.FALL)
	elif _state == LocoActionState.FALL:
		_set_state(LocoActionState.IDLE)

func _update_state(dt: float, input: LocoInputFrame, move: Vector2) -> void:
	match _state:
		LocoActionState.IDLE, LocoActionState.RUN, LocoActionState.LAND:
			_update_ground(dt, move)
		LocoActionState.JUMP, LocoActionState.FALL:
			_update_air(input, move)
		LocoActionState.DASH:
			_update_dash(dt)
		LocoActionState.ATTACK:
			_update_attack(dt, move)
		LocoActionState.SKILL:
			_update_skill(dt)
		LocoActionState.HURT:
			_update_hurt(dt)
		_:
			_velocity = Vector2.ZERO

# ------------------------------------------------------------------ 地面
func _update_ground(dt: float, move: Vector2) -> void:
	_facing = PlaneMath.facing_from_input(move.x, _facing)
	_apply_ground_velocity(move, 1.0)

	if _state == LocoActionState.LAND:
		_land_timer = maxf(0.0, _land_timer - dt)
		if _land_timer <= 0.0:
			_set_state(LocoActionState.IDLE)

	# 优先级：攻击 > 跳跃 > 冲刺。攻击最常按，先给它，减少误触发。
	if _try_attack():
		return
	if _try_jump():
		return
	if _try_dash():
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
func _update_air(input: LocoInputFrame, move: Vector2) -> void:
	_facing = PlaneMath.facing_from_input(move.x, _facing)
	var air_control: float = float(_profile.get("air_control", 1.0))
	_apply_ground_velocity(move, air_control)

	# 可变跳跃高度：只在上升段切断一次。重复切断会把速度越乘越小，手感发黏。
	if _state == LocoActionState.JUMP and not _jump_cut_used:
		var jump_held: bool = input != null and input.jump
		if not jump_held and _vertical_velocity > 0.0:
			_vertical_velocity *= GameConstants.JUMP_CUT_MULTIPLIER
			_jump_cut_used = true

	if _state == LocoActionState.JUMP and _vertical_velocity <= 0.0:
		_set_state(LocoActionState.FALL)

	if _try_attack():
		return
	if _try_jump():
		return
	if _try_dash():
		return

# ------------------------------------------------------------------ 冲刺
func _update_dash(dt: float) -> void:
	_dash_timer = maxf(0.0, _dash_timer - dt)
	_velocity = Vector2(float(_facing) * float(_profile.get("dash_speed", 0.0)), 0.0)
	if _dash_timer > 0.0:
		return

	_invulnerable_timer = 0.0
	_set_state(LocoActionState.IDLE if not _is_airborne() else LocoActionState.FALL)
	# 冲刺尾帧允许接攻击/跳跃，避免「冲过去打不到」的断层。
	if _try_attack():
		return
	if _try_jump():
		return

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

# ------------------------------------------------------------------ 攻击
func _update_attack(dt: float, move: Vector2) -> void:
	_attack_phase_time += dt
	while true:
		var duration: float = _attack_phase_duration(_attack_phase)
		if _attack_phase_time + TIME_EPSILON < duration:
			break
		_attack_phase_time -= duration
		_attack_phase += 1
		if _attack_phase > ATTACK_PHASE_RECOVERY:
			_finish_attack()
			return

	# 攻击中不能自由走位，但保留一点位移，让攻击可以微调距离（速度乘 0.2）。
	var multiplier: float = float(_profile.get("attack_move_multiplier", 0.0))
	_apply_ground_velocity(move, multiplier)

func _attack_phase_duration(phase: int) -> float:
	var key: String = "attack_recovery"
	if phase == ATTACK_PHASE_WINDUP:
		key = "attack_windup"
	elif phase == ATTACK_PHASE_ACTIVE:
		key = "attack_active"
	return _stage_value(key, _combo_index, 0.0)

func _stage_value(key: String, index: int, fallback: float) -> float:
	var raw: Variant = _profile.get(key, fallback)
	if raw is Array:
		var values: Array = raw
		if values.is_empty():
			return fallback
		var i: int = clampi(index, 0, values.size() - 1)
		return float(values[i])
	if raw is float or raw is int:
		return float(raw)
	return fallback

func _start_attack() -> void:
	var combo_count: int = maxi(int(_profile.get("attack_combo_count", 1)), 1)
	if _combo_timer > 0.0 and _combo_index + 1 < combo_count:
		_combo_index += 1
	else:
		_combo_index = 0
	_combo_timer = 0.0
	_attack_phase = ATTACK_PHASE_WINDUP
	_attack_phase_time = 0.0
	_set_state(LocoActionState.ATTACK)

## recovery 结束：缓冲里的攻击优先接段，其次跳跃、冲刺。
func _finish_attack() -> void:
	_combo_timer = float(_profile.get("attack_combo_window", 0.0))
	var combo_count: int = maxi(int(_profile.get("attack_combo_count", 1)), 1)
	# 直接接下一段，不经过 IDLE，避免状态事件与动画来回抖一下。
	if _combo_index + 1 < combo_count \
			and _buffer.is_buffered(InputBuffer.ACTION_ATTACK, GameConstants.INPUT_BUFFER_WINDOW):
		_buffer.consume(InputBuffer.ACTION_ATTACK, GameConstants.INPUT_BUFFER_WINDOW)
		_start_attack()
		return

	_set_state(LocoActionState.IDLE if not _is_airborne() else LocoActionState.FALL)
	if _try_attack():
		return
	if _try_jump():
		return
	if _try_dash():
		return

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
func _try_attack() -> bool:
	if not _buffer.is_buffered(InputBuffer.ACTION_ATTACK, GameConstants.INPUT_BUFFER_WINDOW):
		return false
	if not _can_attack():
		return false
	_buffer.consume(InputBuffer.ACTION_ATTACK, GameConstants.INPUT_BUFFER_WINDOW)
	_start_attack()
	return true

func _try_jump() -> bool:
	if not _buffer.is_buffered(InputBuffer.ACTION_JUMP, GameConstants.INPUT_BUFFER_WINDOW):
		return false
	if not _can_jump():
		return false
	_buffer.consume(InputBuffer.ACTION_JUMP, GameConstants.INPUT_BUFFER_WINDOW)
	_start_jump()
	return true

func _try_dash() -> bool:
	if not _buffer.is_buffered(InputBuffer.ACTION_DASH, GameConstants.INPUT_BUFFER_WINDOW):
		return false
	if not _can_dash():
		return false
	_buffer.consume(InputBuffer.ACTION_DASH, GameConstants.INPUT_BUFFER_WINDOW)
	_start_dash()
	return true

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
		elif _height < 0.0:
			_height = 0.0

	_plane_pos += _velocity * dt
	_plane_pos = PlaneMath.clamp_lane(_plane_pos)

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
	_combo_timer = 0.0
	_combo_index = 0
	_set_state(LocoActionState.SKILL)

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
	_combo_timer = 0.0
	_combo_index = 0
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

## 外部（application / 测试）注入身份的入口，事件载荷里的 actor_id 由这里决定。
func set_actor_id(value: int) -> void:
	_actor_id = value

func set_super_armor(enabled: bool) -> void:
	_super_armor = enabled

func set_plane_pos(p: Vector2) -> void:
	_plane_pos = PlaneMath.clamp_lane(p)

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
		"combo_timer": _combo_timer,
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

func _read_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
