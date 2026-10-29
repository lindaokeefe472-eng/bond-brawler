## 关卡波次生成器：把「一波敌人何时出现、何时算清空」的规则收敛成纯逻辑。
## 表现层只负责消费 pending_spawns() 并真正实例化角色，因此这里可以单测、可重放。
## 注意：pending_spawns() 是「取出即清空」的语义 —— 契约没有额外的 ack 方法，
## 若改成只读，调用方每帧都会重复生成同一批敌人。
class_name StageWaveSpawner
extends RefCounted

## 波次状态机。刻意用整数而不是 enum，便于调试输出与外部快照直接比较。
const STATE_PENDING: int = 0
const STATE_DELAYING: int = 1
const STATE_SPAWNED: int = 2
const STATE_CLEARED: int = 3

## 触发器语义：immediate 不等上一波清空就排队；clear 必须等上一波清空。
const TRIGGER_IMMEDIATE: StringName = &"immediate"
const TRIGGER_CLEAR: StringName = &"clear"

## species 数据缺失时的占位符：数据错误要降级，不能让整局崩掉。
const FALLBACK_SPECIES: StringName = &"unknown"

var _waves: Array = []
var _bus: DomainEventBus = null
var _states: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _alive: int = 0
var _current_wave: int = -1

func _init(waves: Array, bus: DomainEventBus) -> void:
	_bus = bus
	for i: int in range(waves.size()):
		var raw: Variant = waves[i]
		var d: Dictionary = {}
		if raw is Dictionary:
			d = raw
		else:
			# 外部数据（JSON）可能给错类型，按空波降级并告警。
			push_warning("StageWaveSpawner: 第 %d 波不是字典，按空波处理" % i)
		var species_v: Variant = d.get("species", [])
		var species: Array = []
		if species_v is Array:
			species = (species_v as Array).duplicate()
		_waves.append(d)
		_states.append({
			"status": STATE_PENDING,
			"delay_left": 0.0,
			"count": maxi(int(d.get("count", 0)), 0),
			"species": species,
			"trigger": _normalize_trigger(d.get("trigger", TRIGGER_IMMEDIATE)),
			"spawn_x": float(d.get("spawn_x", 0.0)),
			"lane": d.get("lane", null),
		})

func tick(dt: float) -> void:
	var delta: float = maxf(dt, 0.0)
	_activate_ready_waves()
	_advance_delays(delta)
	# 延迟为 0 的 immediate 波可能在上一波刚生成时就能启动，需要再扫一遍形成连锁。
	_activate_ready_waves()

func on_actor_died(actor_id: int) -> void:
	if _alive <= 0:
		# 同一帧可能收到重复死亡通知，计数不能被打成负数。
		push_warning("StageWaveSpawner: 收到多余死亡回调 actor_id=%d" % actor_id)
		return
	_alive -= 1
	if _alive > 0:
		return
	# 存活归零：所有已生成且未清空的波都视为清空（immediate 连锁时会一次清多波）。
	for i: int in range(_states.size()):
		if int(_states[i]["status"]) == STATE_SPAWNED:
			_mark_cleared(i)

## 返回自上次调用以来新产生的生成请求，并清空队列。
func pending_spawns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_pending)
	_pending.clear()
	return out

func is_cleared() -> bool:
	if _states.is_empty():
		return true
	if _alive > 0:
		return false
	for st: Dictionary in _states:
		if int(st["status"]) != STATE_CLEARED:
			return false
	return true

func current_wave() -> int:
	return _current_wave

## 当前仍存活（已生成未死亡）的敌人数，供 HUD / 测试读取。
func alive_count() -> int:
	return _alive

func total_waves() -> int:
	return _waves.size()

# ------------------------------------------------------------------ 内部推进

func _activate_ready_waves() -> void:
	var changed: bool = true
	while changed:
		changed = false
		for i: int in range(_states.size()):
			if int(_states[i]["status"]) != STATE_PENDING:
				continue
			if _can_start(i):
				_start_wave(i)
				changed = true

func _can_start(index: int) -> bool:
	if index <= 0:
		return true
	var prev_status: int = int(_states[index - 1]["status"])
	if prev_status == STATE_CLEARED:
		return true
	# immediate：上一波刚生成完就允许下一波开始倒计时，形成叠加压力。
	return prev_status == STATE_SPAWNED and StringName(_states[index]["trigger"]) == TRIGGER_IMMEDIATE

func _start_wave(index: int) -> void:
	var st: Dictionary = _states[index]
	st["status"] = STATE_DELAYING
	st["delay_left"] = maxf(float(_waves[index].get("delay", 0.0)), 0.0)
	_current_wave = index
	_emit(GameConstants.EVT_WAVE_STARTED, {
		"wave": index,
		"count": int(st["count"]),
		"trigger": StringName(st["trigger"]),
		"species": (st["species"] as Array).duplicate(),
	})
	# delay 为 0 的波在同一 tick 内就生成，避免空等一帧。
	if float(st["delay_left"]) <= 0.0:
		_spawn_wave(index)

func _advance_delays(dt: float) -> void:
	if dt <= 0.0:
		return
	for i: int in range(_states.size()):
		var st: Dictionary = _states[i]
		if int(st["status"]) != STATE_DELAYING:
			continue
		st["delay_left"] = float(st["delay_left"]) - dt
		if float(st["delay_left"]) <= 0.0:
			_spawn_wave(i)

func _spawn_wave(index: int) -> void:
	var st: Dictionary = _states[index]
	st["status"] = STATE_SPAWNED
	st["delay_left"] = 0.0
	var count: int = int(st["count"])
	var species: Array = st["species"]
	var spawn_x: float = float(st["spawn_x"])
	if species.is_empty() and count > 0:
		push_warning("StageWaveSpawner: 第 %d 波没有 species，使用占位物种" % index)
	for k: int in range(count):
		var species_id: StringName = FALLBACK_SPECIES
		if not species.is_empty():
			# 轮转取用，保证同一波内物种分布可预测、可回放。
			species_id = StringName(str(species[k % species.size()]))
		var pos: Vector2 = Vector2(spawn_x, _lane_for(k, count, st["lane"]))
		var request: StageSpawnRequest = StageSpawnRequest.new(
			species_id, pos, index, GameConstants.FACTION_ENEMY)
		_pending.append(request.to_dict())
	_alive += count
	if count <= 0:
		# 空波不阻塞后续波次，立即视为已清空。
		_mark_cleared(index)

## 同一波的敌人均匀铺在可走纵深带内，既不会重叠也不会出界。
func _lane_for(index: int, count: int, lane: Variant) -> float:
	if lane is float or lane is int:
		return clampf(float(lane), GameConstants.LANE_MIN, GameConstants.LANE_MAX)
	if count <= 1:
		return (GameConstants.LANE_MIN + GameConstants.LANE_MAX) * 0.5
	return lerpf(GameConstants.LANE_MIN, GameConstants.LANE_MAX, float(index + 1) / float(count + 1))

func _mark_cleared(index: int) -> void:
	var st: Dictionary = _states[index]
	if int(st["status"]) == STATE_CLEARED:
		return
	st["status"] = STATE_CLEARED
	_emit(GameConstants.EVT_WAVE_CLEARED, {
		"wave": index,
		"count": int(st["count"]),
	})

func _normalize_trigger(value: Variant) -> StringName:
	var trigger: StringName = StringName(str(value))
	if trigger == TRIGGER_CLEAR:
		return TRIGGER_CLEAR
	if trigger != TRIGGER_IMMEDIATE:
		push_warning("StageWaveSpawner: 未知 trigger '%s'，按 immediate 处理" % trigger)
	return TRIGGER_IMMEDIATE

func _emit(type: StringName, payload: Dictionary) -> void:
	if _bus != null:
		_bus.emit_type(type, payload)
