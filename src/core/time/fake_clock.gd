## 可控时钟：单测里手动推进时间，不依赖真实帧率。
class_name FakeClock
extends IClock

var _now: float = 0.0
var _delta: float = GameConstants.TICK_DELTA

func _init(start: float = 0.0) -> void:
	_now = start

func now() -> float:
	return _now

func delta() -> float:
	return _delta

func advance(seconds: float) -> float:
	_delta = seconds
	_now += seconds
	return _now

func advance_ticks(count: int) -> float:
	return advance(float(count) * GameConstants.TICK_DELTA)

func set_time(value: float) -> void:
	_now = value
