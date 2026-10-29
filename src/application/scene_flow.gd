## 场景流程状态机：标题 -> 游戏 -> 暂停 -> 结算。
##
## 为什么单独成类：流程判断是纯逻辑，放这里可以脱离场景树单测。
## 表现层只负责「按当前状态显示什么」，不自己判断能不能暂停。
class_name SceneFlow
extends RefCounted

enum State {
	TITLE,
	PLAYING,
	PAUSED,
	RESULT,
}

var _state: int = State.TITLE
var _victory: bool = false

func state() -> int:
	return _state

func is_playing() -> bool:
	return _state == State.PLAYING

func is_paused() -> bool:
	return _state == State.PAUSED

func is_result() -> bool:
	return _state == State.RESULT

func victory() -> bool:
	return _victory

func start() -> bool:
	if _state != State.TITLE:
		return false
	_state = State.PLAYING
	return true

func pause() -> bool:
	if _state != State.PLAYING:
		return false
	_state = State.PAUSED
	return true

func resume() -> bool:
	if _state != State.PAUSED:
		return false
	_state = State.PLAYING
	return true

## 结束本局。只在游戏进行中或暂停中有效。
func finish(p_victory: bool) -> bool:
	if _state != State.PLAYING and _state != State.PAUSED:
		return false
	_victory = p_victory
	_state = State.RESULT
	return true

func restart() -> bool:
	if _state != State.RESULT:
		return false
	_state = State.PLAYING
	return true

func to_title() -> bool:
	if _state != State.RESULT:
		return false
	_state = State.TITLE
	return true
