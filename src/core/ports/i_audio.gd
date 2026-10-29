## 出站端口：音效。
##
## 领域层和表现层只发 cue 名（hit / guard / death ...），不关心采样率、
## 总线、混音、并发上限 —— 那些是实现细节，换实现不影响调用方。
class_name IAudio
extends RefCounted

func play(_cue: StringName, _position: Vector2 = Vector2.ZERO) -> void:
	push_error("IAudio.play() 未实现")

func set_bus_volume(_bus_name: StringName, _value: float) -> void:
	pass

## 当前正在发声的实例数，测试用。
func active_voices() -> int:
	return 0

## 累计真正播出去的次数，测试用。
func play_count() -> int:
	return 0
