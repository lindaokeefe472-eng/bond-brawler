## 同步领域事件总线。
##
## 设计约束：
##   1. 同步派发 —— 领域逻辑执行期间状态一致，避免「半更新」的中间态被观察到。
##   2. 可录制 —— 打开录制后所有事件入栈，供回放测试与网络同步使用。
##   3. 重入保护 —— 处理器里再派发事件是允许的，但超过 MAX_DEPTH 会报错，防止无限递归。
##   4. 派发时遍历快照 —— 允许处理器在回调中订阅/退订。
class_name DomainEventBus
extends RefCounted

const MAX_DEPTH: int = 8
const WILDCARD: StringName = &"*"

var _handlers: Dictionary = {}      # StringName -> Array[Dictionary{id, callable, priority}]
var _handles: Dictionary = {}       # int -> StringName
var _next_id: int = 1
var _sequence: int = 0
var _depth: int = 0
var _recording: bool = false
var _recorded: Array[DomainEvent] = []
var _dispatch_count: int = 0

## 订阅一个事件类型。priority 越大越先收到。返回可用于退订的句柄。
func subscribe(type: StringName, handler: Callable, priority: int = 0) -> int:
    if not handler.is_valid():
        push_error("DomainEventBus.subscribe: 无效的 Callable")
        return -1
    var list: Array = _handlers.get(type, [])
    var id: int = _next_id
    _next_id += 1
    list.append({"id": id, "callable": handler, "priority": priority})
    list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["priority"] > b["priority"])
    _handlers[type] = list
    _handles[id] = type
    return id

func unsubscribe(handle: int) -> void:
    if not _handles.has(handle):
        return
    var type: StringName = _handles[handle]
    _handles.erase(handle)
    var list: Array = _handlers.get(type, [])
    for i: int in range(list.size() - 1, -1, -1):
        if list[i]["id"] == handle:
            list.remove_at(i)
            break
    if list.is_empty():
        _handlers.erase(type)
    else:
        _handlers[type] = list

func has_subscribers(type: StringName) -> bool:
    return _handlers.has(type) or _handlers.has(WILDCARD)

func emit(event: DomainEvent) -> void:
    if event == null:
        return
    if _depth >= MAX_DEPTH:
        push_error("DomainEventBus: 事件派发深度超限 (%d)，疑似递归。event=%s" % [MAX_DEPTH, event])
        return
    _sequence += 1
    event.sequence = _sequence
    _dispatch_count += 1
    if _recording:
        _recorded.append(event)

    var targets: Array = []
    if _handlers.has(event.type):
        targets.append_array(_handlers[event.type])
    if _handlers.has(WILDCARD):
        targets.append_array(_handlers[WILDCARD])
    if targets.is_empty():
        return
    # 快照：回调内退订不会影响本轮遍历
    targets = targets.duplicate()
    _depth += 1
    for entry: Dictionary in targets:
        var cb: Callable = entry["callable"]
        if cb.is_valid():
            cb.call(event)
    _depth -= 1

func emit_type(type: StringName, payload: Dictionary = {}) -> void:
    emit(DomainEvent.new(type, payload))

# ------------------------------------------------------------------ 录制 / 回放
func set_recording(enabled: bool) -> void:
    _recording = enabled

func is_recording() -> bool:
    return _recording

func recorded_events() -> Array[DomainEvent]:
    return _recorded.duplicate()

func clear_recording() -> void:
    _recorded.clear()

func dispatch_count() -> int:
    return _dispatch_count

func clear() -> void:
    _handlers.clear()
    _handles.clear()
    _recorded.clear()
    _sequence = 0
    _dispatch_count = 0
    _depth = 0
