## 真实时钟适配器：把 Godot 的单调毫秒计数包装成 IClock。
##
## 为什么用 get_ticks_msec 而不是 Unix 时间：墙钟会被系统校时/夏令时拨动，
## 一旦回拨，领域层就会收到负的 dt，可能造成计时器倒退甚至死循环；
## 单调计数只增不减，回放与暂停逻辑都更好推理。
class_name GodotClock
extends IClock

var _start_msec: int = 0
var _last_now: float = 0.0
var _last_delta: float = GameConstants.TICK_DELTA

func _init() -> void:
    _start_msec = Time.get_ticks_msec()
    _last_now = 0.0
    # 首次 now() 之前就调用 delta() 也要有合理值，否则编排层会拿到 0 秒的空步。
    _last_delta = GameConstants.TICK_DELTA

func now() -> float:
    var seconds: float = float(Time.get_ticks_msec() - _start_msec) / 1000.0
    # 适配器拿不到 SceneTree 的帧 delta，两次采样之间的间隔就是它能观测到的
    # 最接近「上一逻辑步」的量；用 maxf 兜住同毫秒内重复采样的 0 值。
    _last_delta = maxf(seconds - _last_now, 0.0)
    _last_now = seconds
    return seconds

func delta() -> float:
    return _last_delta
