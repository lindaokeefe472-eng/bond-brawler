## 一帧输入快照：表现层（InputAdapter）填好后交给领域层。
## 领域层只认识这个纯值对象，因此键鼠、手柄、AI 都能复用同一套动作逻辑。
class_name LocoInputFrame
extends RefCounted

## move 的每个分量都约定在 [-1, 1]：x 是横轴，y 是纵深（朝向镜头为正）。
## 归一化由采集方负责；领域层仍会再夹一次，防止外部数据越界破坏手感。
const MOVE_MIN: float = -1.0
const MOVE_MAX: float = 1.0
## 小于这个平方长度视为「没有方向输入」，避免摇杆漂移把 IDLE 顶成 RUN。
const MOVE_DEADZONE_SQUARED: float = 0.0001
## 技能槽位数与技能系统保持一致，下游可以直接按下标取用。
const SKILL_SLOTS: int = 4

var move: Vector2 = Vector2.ZERO
var jump: bool = false
var dash: bool = false
var attack: bool = false
var guard: bool = false
var skills: Array[bool] = [false, false, false, false]

static func empty() -> LocoInputFrame:
	return LocoInputFrame.new()

## 夹取后的移动向量。采集方应已归一化，这里只做最后一道防线。
func clamped_move() -> Vector2:
	return Vector2(
		clampf(move.x, MOVE_MIN, MOVE_MAX),
		clampf(move.y, MOVE_MIN, MOVE_MAX)
	)

## 是否有方向输入；纵深移动同样算「在动」，否则侧向走位会播成待机。
func has_move() -> bool:
	return clamped_move().length_squared() > MOVE_DEADZONE_SQUARED
