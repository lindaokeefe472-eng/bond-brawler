## 关卡进度：房间线性解锁 + Memento 快照。
## 只持久化「哪些房间已完成」，解锁状态由房间顺序推导 —— 避免快照里出现两份互相矛盾的真相。
class_name StageProgress
extends RefCounted

const SNAPSHOT_VERSION: int = 1

var _room_ids: Array[StringName] = []
var _order: Dictionary = {}      # StringName -> int，房间在关卡里的序号
var _completed: Dictionary = {}  # StringName -> true
var _bus: DomainEventBus = null

## bus 可选：契约只列了 room_ids，但 complete_room 需要广播 stage.room_cleared。
## 做成可选参数既兼容契约调用，也允许纯逻辑测试不传总线。
func _init(room_order: Array[StringName], bus: DomainEventBus = null) -> void:
	_bus = bus
	for id: StringName in room_order:
		if not _order.has(id):
			_order[id] = _room_ids.size()
			_room_ids.append(id)

func complete_room(id: StringName) -> void:
	if not _order.has(id):
		push_warning("StageProgress: 未知房间 %s" % id)
		return
	if not is_unlocked(id):
		# 线性解锁是契约：跳关完成必须被拒绝，否则进度会分叉。
		push_warning("StageProgress: 房间 %s 尚未解锁，忽略完成" % id)
		return
	if _completed.has(id):
		# 幂等：重复上报同一房间不重复发事件，避免下游重复结算奖励。
		return
	_completed[id] = true
	_emit(GameConstants.EVT_ROOM_CLEARED, {
		"room_id": id,
		"index": int(_order[id]),
	})

func is_unlocked(id: StringName) -> bool:
	if not _order.has(id):
		return false
	var index: int = int(_order[id])
	if index == 0:
		return true
	return _completed.has(_room_ids[index - 1])

func snapshot() -> Dictionary:
	# 全部用 String，保证快照能直接 JSON 序列化进存档。
	var rooms: Array[String] = []
	for id: StringName in _room_ids:
		rooms.append(String(id))
	var completed: Array[String] = []
	for id: StringName in _room_ids:
		if _completed.has(id):
			completed.append(String(id))
	return {
		"version": SNAPSHOT_VERSION,
		"rooms": rooms,
		"completed": completed,
	}

func restore(data: Dictionary) -> void:
	if data.is_empty():
		return
	if data.has("rooms"):
		var rooms_v: Variant = data["rooms"]
		if rooms_v is Array:
			_room_ids.clear()
			_order.clear()
			_completed.clear()
			for raw: Variant in rooms_v:
				var id: StringName = StringName(str(raw))
				if not _order.has(id):
					_order[id] = _room_ids.size()
					_room_ids.append(id)
	var saved: Dictionary = {}
	var completed_v: Variant = data.get("completed", [])
	if completed_v is Array:
		for raw: Variant in completed_v:
			saved[StringName(str(raw))] = true
	_completed.clear()
	# 只接受连续前缀：即使快照被外部篡改，也不会还原出「跳过前置房间」的非法进度。
	for id: StringName in _room_ids:
		if not saved.has(id):
			break
		_completed[id] = true

## 已完成的房间，按关卡顺序返回。
func completed_rooms() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _room_ids:
		if _completed.has(id):
			out.append(id)
	return out

func room_ids() -> Array[StringName]:
	return _room_ids.duplicate()

func is_stage_complete() -> bool:
	return _completed.size() == _room_ids.size()

func _emit(type: StringName, payload: Dictionary) -> void:
	if _bus != null:
		_bus.emit_type(type, payload)
