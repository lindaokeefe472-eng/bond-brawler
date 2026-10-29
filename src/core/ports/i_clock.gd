## 出站端口：时间。领域层绝不直接调用 Time / Engine.get_ticks_*。
## 生产实现见 src/infrastructure/godot_clock.gd，测试实现见 src/core/time/fake_clock.gd。
class_name IClock
extends RefCounted

## 当前模拟时间（秒，从会话开始累计）。
func now() -> float:
	push_error("IClock.now() 未实现")
	return 0.0

## 上一逻辑步的步长（秒）。
func delta() -> float:
	push_error("IClock.delta() 未实现")
	return GameConstants.TICK_DELTA
