## xorshift128 (32-bit words) —— 确定性、可序列化、跨平台一致。
## 战斗里每一处随机都必须走 IRng，这样回放和单测才能复现。
class_name DeterministicRng
extends IRng

const MASK32: int = 0xFFFFFFFF

var _x: int = 0
var _y: int = 0
var _z: int = 0
var _w: int = 0
var _seed: int = 0

func _init(seed_value: int = 0x9E3779B9) -> void:
	reseed(seed_value)

func reseed(seed_value: int) -> void:
	_seed = seed_value & MASK32
	var s: int = _seed if _seed != 0 else 0x9E3779B9
	_x = _mix(s + 1)
	_y = _mix(_x)
	_z = _mix(_y)
	_w = _mix(_z)
	if (_x | _y | _z | _w) == 0:
		_x = 1

static func _mix(v: int) -> int:
	var t: int = (v * 1664525 + 1013904223) & MASK32
	t = (t ^ (t >> 15)) & MASK32
	return t

func _step() -> int:
	var t: int = (_x ^ ((_x << 11) & MASK32)) & MASK32
	_x = _y
	_y = _z
	_z = _w
	_w = (_w ^ (_w >> 19)) ^ (t ^ (t >> 8))
	_w &= MASK32
	return _w

func next_float() -> float:
	return float(_step()) / 4294967296.0

func next_int(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	return _step() % max_exclusive

func get_seed() -> int:
	return _seed

func fork(label: StringName) -> IRng:
	var child_seed: int = (_seed ^ (String(label).hash() * 2654435761)) & MASK32
	return DeterministicRng.new(child_seed)

func get_state() -> Dictionary:
	return {"seed": _seed, "x": _x, "y": _y, "z": _z, "w": _w}

func set_state(state: Dictionary) -> void:
	_seed = int(state.get("seed", 0))
	_x = int(state.get("x", 1))
	_y = int(state.get("y", 0))
	_z = int(state.get("z", 0))
	_w = int(state.get("w", 0))
