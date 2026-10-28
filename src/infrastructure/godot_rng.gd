## 生产随机数适配器：包装引擎的 RandomNumberGenerator。
##
## 为什么还要包一层：领域层只认 IRng，这样换实现（DeterministicRng / 测试假随机）
## 不需要动任何战斗代码；生产环境则可以直接享受引擎实现的性能。
class_name GodotRng
extends IRng

var _rng: RandomNumberGenerator
var _seed: int = 0

func _init(seed_value: int = 0) -> void:
    _rng = RandomNumberGenerator.new()
    reseed(seed_value)

## 重设种子。0 是合法种子（引擎会按 0 派生子序列），不会退化成时间随机种子，
## 否则同种子回放就失去意义了。
func reseed(seed_value: int) -> void:
    _seed = seed_value
    _rng.seed = seed_value

func next_float() -> float:
    return _rng.randf()

func next_int(max_exclusive: int) -> int:
    if max_exclusive <= 0:
        return 0
    return _rng.randi_range(0, max_exclusive - 1)

func get_seed() -> int:
    return _seed

## 子流种子由「父种子 + 标签哈希」推导，而不是消耗父流。
## 这样无论父流此前抽了多少次，fork(&"ai") 都得到同一序列 —— 回放与单测才能稳定复现；
## 不同标签哈希不同，又保证各子流互不相关。
func fork(label: StringName) -> IRng:
    var child_seed: int = _seed ^ (String(label).hash() * 2654435761)
    return GodotRng.new(child_seed)
