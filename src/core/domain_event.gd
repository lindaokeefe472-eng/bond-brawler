## 领域事件：领域层向外广播的唯一载体。
## 刻意做成「纯数据 + 无引擎依赖」，可被序列化、录制、回放、跨线程比较。
class_name DomainEvent
extends RefCounted

var type: StringName
var payload: Dictionary
## 全局单调递增序号，由 DomainEventBus 在派发时写入，用于排序与调试。
var sequence: int = 0

func _init(p_type: StringName, p_payload: Dictionary = {}) -> void:
	type = p_type
	payload = p_payload.duplicate(false)

static func make(p_type: StringName, p_payload: Dictionary = {}) -> DomainEvent:
	return DomainEvent.new(p_type, p_payload)

func get_value(key: StringName, fallback: Variant = null) -> Variant:
	return payload.get(key, fallback)

func has(key: StringName) -> bool:
	return payload.has(key)

func _to_string() -> String:
	return "#%d %s %s" % [sequence, type, payload]
