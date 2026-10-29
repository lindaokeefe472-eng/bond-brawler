## 出站端口：打击感反馈。
## 领域层只表达「发生了什么、多大力」，具体怎么震、怎么闪由表现层决定。
class_name IFeedbackSink
extends RefCounted

## 顿帧：全局时间缩放冻结。
func hit_stop(_duration: float) -> void:
	pass

## 相机震动。
func camera_shake(_strength: float, _duration: float) -> void:
	pass

## 受击闪白。
func hit_flash(_actor_id: int, _color: Color = Color.WHITE) -> void:
	pass

## 伤害跳字。
func damage_number(_actor_id: int, _amount: int, _kind: StringName = &"normal") -> void:
	pass

## 全屏闪白/闪红（暴击、死亡、Boss 出场）。
func screen_flash(_color: Color, _duration: float) -> void:
	pass

## 音效请求（由表现层映射到具体 AudioStream）。
func play_sfx(_cue: StringName, _position: Vector2 = Vector2.ZERO) -> void:
	pass
