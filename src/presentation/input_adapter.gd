## 输入适配器：把 InputMap 动作翻译成领域层的输入帧。
##
## 为什么归一化放在这里：领域层只认识 [-1, 1] 的移动向量；
## 采集方保证长度不超过 1，动作机才能用同一套速度逻辑处理键盘与摇杆。
##
## 依赖说明：presentation 可以静态依赖领域上下文的值对象（见 ARCHITECTURE §1），
## 本适配器直接产出 LocoInputFrame，不做类型擦除。
class_name InputAdapter
extends RefCounted

const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_MOVE_UP: StringName = &"move_up"
const ACTION_MOVE_DOWN: StringName = &"move_down"
const ACTION_JUMP: StringName = &"jump"
const ACTION_DASH: StringName = &"dash"
const ACTION_ATTACK: StringName = &"attack"
const ACTION_GUARD: StringName = &"guard"
const SKILL_ACTIONS: Array = [&"skill_1", &"skill_2", &"skill_3", &"skill_4"]

## 小于它视为没有方向输入，避免摇杆漂移把 IDLE 顶成 RUN。
const MOVE_DEADZONE: float = 0.2

## 按下沿锁存。逻辑步与渲染帧不是 1:1（固定步长追赶、顿帧 time_scale=0），
## 在逻辑步里直接读 is_action_just_pressed 会漏掉两次采样之间的按下 ——
## 顿帧有 45~110 ms，那段时间里按下的下一段会整个消失。
var _latched_jump: bool = false
var _latched_dash: bool = false
var _latched_attack: bool = false
var _latched_skills: Array[bool] = [false, false, false, false]

## 每渲染帧调用一次：只记按下，不消费。
func capture() -> void:
	latch_edges(
		Input.is_action_just_pressed(ACTION_JUMP),
		Input.is_action_just_pressed(ACTION_DASH),
		Input.is_action_just_pressed(ACTION_ATTACK),
		_just_pressed_skills())

## 纯函数入口：把一次采样的按下沿并进锁存（headless 用例直接调它）。
func latch_edges(jump: bool, dash: bool, attack: bool, skills: Array) -> void:
	_latched_jump = _latched_jump or jump
	_latched_dash = _latched_dash or dash
	_latched_attack = _latched_attack or attack
	for slot: int in range(mini(skills.size(), LocoInputFrame.SKILL_SLOTS)):
		if bool(skills[slot]):
			_latched_skills[slot] = true

## 丢掉还没被消费的按下。暂停/切场景时调用，避免恢复后补放一个旧按键。
func clear() -> void:
	_latched_jump = false
	_latched_dash = false
	_latched_attack = false
	for slot: int in range(LocoInputFrame.SKILL_SLOTS):
		_latched_skills[slot] = false

## 消费锁存并清空。方向与格挡是「按住」语义，仍然实时采样。
func poll() -> LocoInputFrame:
	var raw_move := Vector2(
		Input.get_action_strength(ACTION_MOVE_RIGHT) - Input.get_action_strength(ACTION_MOVE_LEFT),
		Input.get_action_strength(ACTION_MOVE_DOWN) - Input.get_action_strength(ACTION_MOVE_UP))
	var frame: LocoInputFrame = build_frame(
		raw_move, _latched_jump, _latched_dash, _latched_attack,
		Input.is_action_pressed(ACTION_GUARD), _latched_skills)
	clear()
	return frame

func _just_pressed_skills() -> Array[bool]:
	var out: Array[bool] = []
	for action: StringName in SKILL_ACTIONS:
		out.append(Input.is_action_just_pressed(action))
	return out

## 长度超过 1 时归一化；小于死区归零；介于两者之间保留摇杆的力度。
static func normalize_move(raw: Vector2, deadzone: float = MOVE_DEADZONE) -> Vector2:
	var length: float = raw.length()
	if length < deadzone:
		return Vector2.ZERO
	if length > 1.0:
		return raw / length
	return raw

## 纯函数入口：不碰 Input 单例，方便单测与回放注入。
static func build_frame(raw_move: Vector2, jump: bool, dash: bool, attack: bool,
		guard: bool, skills: Array) -> LocoInputFrame:
	var frame: LocoInputFrame = LocoInputFrame.empty()
	frame.move = normalize_move(raw_move)
	frame.jump = jump
	frame.dash = dash
	frame.attack = attack
	frame.guard = guard
	for slot: int in range(mini(skills.size(), LocoInputFrame.SKILL_SLOTS)):
		frame.skills[slot] = bool(skills[slot])
	return frame
