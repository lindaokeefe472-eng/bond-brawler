## 侧视相机：只平滑跟随目标的 x，y/z 固定，并把 trauma 换算成抖动。
##
## 为什么用 trauma 平方：线性衰减的位移在结尾会「啪」地停住；
## trauma 先线性衰减、再平方作用于振幅，尾巴自然收敛，打击感更干脆。
class_name CameraRig
extends Camera3D

const FOLLOW_SMOOTHING: float = 9.0
const TRAUMA_DECAY_PER_SECOND: float = 1.8
const MIN_TRAUMA_DECAY: float = 0.01
const MAX_SHAKE_OFFSET: Vector3 = Vector3(0.35, 0.22, 0.0)
const MAX_SHAKE_ROLL: float = 0.04
const SHAKE_FREQUENCY: float = 38.0
const NOISE_X_FREQUENCY: float = 1.0
const NOISE_Y_FREQUENCY: float = 1.37
const NOISE_Y_PHASE: float = 1.1
const NOISE_ROLL_FREQUENCY: float = 1.73

var target: Node3D = null
var follow_smoothing: float = FOLLOW_SMOOTHING

var _home: Vector3 = Vector3.ZERO
var _home_rotation: Vector3 = Vector3.ZERO
var _trauma: float = 0.0
var _decay: float = TRAUMA_DECAY_PER_SECOND
var _noise_time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_home = position
	_home_rotation = rotation
	_rng.randomize()
	# 随机相位让多次震屏不会每次都从同一个波形开始。
	_noise_time = _rng.randf() * 100.0

## 由 ArenaBuilder 在搭场时调用：确定机位与朝向。
func set_home(home_position: Vector3, look_target: Vector3) -> void:
	position = home_position
	look_at(look_target, Vector3.UP)
	_home = position
	_home_rotation = rotation

func set_target(node: Node3D) -> void:
	target = node

## duration > 0 时把衰减速度调到「duration 秒内归零」，便于按打击力度区分余震。
func add_trauma(amount: float, duration: float = 0.0) -> void:
	_trauma = clampf(_trauma + maxf(amount, 0.0), 0.0, 1.0)
	if duration > 0.0:
		_decay = maxf(_trauma / duration, MIN_TRAUMA_DECAY)

func trauma() -> float:
	return _trauma

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_trauma = maxf(0.0, _trauma - _decay * delta)
	_noise_time += delta * SHAKE_FREQUENCY
	var follow_x: float = _home.x
	if target != null and is_instance_valid(target):
		follow_x = target.global_position.x
	# 指数平滑与帧率无关：不同刷新率下跟随手感一致。
	var smoothing: float = clampf(1.0 - exp(-follow_smoothing * delta), 0.0, 1.0)
	var x: float = lerpf(position.x, follow_x, smoothing)
	var shake: float = _trauma * _trauma
	var offset := Vector3(
		sin(_noise_time * NOISE_X_FREQUENCY),
		sin(_noise_time * NOISE_Y_FREQUENCY + NOISE_Y_PHASE),
		0.0) * MAX_SHAKE_OFFSET * shake
	position = Vector3(x, _home.y, _home.z) + offset
	rotation = _home_rotation + Vector3(
		0.0, 0.0, sin(_noise_time * NOISE_ROLL_FREQUENCY) * MAX_SHAKE_ROLL * shake)
