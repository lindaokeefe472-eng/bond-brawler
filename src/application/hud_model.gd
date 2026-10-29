## HUD 视图模型：把「界面要显示什么」收敛成一份纯数据。
##
## 为什么不直接让 Control 读 ActorRuntime：UI 一旦持有领域对象，就会开始
## 依赖内部字段、偷偷改状态，测试也没法脱离整局战斗跑。
## 这里只认一份快照（字典数组），所以可以纯逻辑单测。
class_name HudModel
extends RefCounted

## 连击窗口：超过这个时间没有新命中，连击数清零。
const COMBO_WINDOW: float = 1.2
## 受击闪白在血条上的持续时间。
const FLASH_SECONDS: float = 0.12

var _entries: Dictionary = {}   # id -> entry
var _order: Array[int] = []
var _combo: int = 0
var _combo_left: float = 0.0
var _flash: Dictionary = {}     # id -> 剩余秒数

## 一条 HUD 条目的规范形状。presenter 按这个造快照，view 按这个读。
static func make_entry(id: int, display_name: String, hp: float, max_hp: float,
		energy: float, energy_max: float, cooldowns: Array, alive: bool) -> Dictionary:
	var safe_max: float = maxf(max_hp, 0.0001)
	var safe_energy: float = maxf(energy_max, 0.0001)
	return {
		"id": id,
		"name": display_name,
		"hp": hp,
		"max_hp": max_hp,
		"hp_ratio": clampf(hp / safe_max, 0.0, 1.0),
		"energy": energy,
		"energy_max": energy_max,
		"energy_ratio": clampf(energy / safe_energy, 0.0, 1.0),
		"cooldowns": cooldowns.duplicate(),
		"alive": alive,
	}

## 整份替换。**顺序保持首次出现的位置**，新角色追加到末尾。
## 不跟着快照重排，是为了血条不会因为生成顺序变化而跳来跳去。
func apply_snapshot(snapshot: Array) -> void:
	var fresh: Dictionary = {}
	for raw: Variant in snapshot:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		fresh[int(entry.get("id", 0))] = entry
	var order: Array[int] = []
	for id: int in _order:
		if fresh.has(id):
			order.append(id)
	for key: Variant in fresh.keys():
		if not order.has(int(key)):
			order.append(int(key))
	_entries = fresh
	_order = order

func entries() -> Array:
	var out: Array = []
	for id: int in _order:
		if _entries.has(id):
			out.append(_entries[id])
	return out

func combo() -> int:
	return _combo

## 玩家命中一次：连击 +1，并刷新窗口。
func note_player_hit() -> void:
	_combo += 1
	_combo_left = COMBO_WINDOW

func note_damage(actor_id: int) -> void:
	_flash[actor_id] = FLASH_SECONDS

func flash_ratio(actor_id: int) -> float:
	var left: float = float(_flash.get(actor_id, 0.0))
	return clampf(left / FLASH_SECONDS, 0.0, 1.0)

func tick(dt: float) -> void:
	var step: float = maxf(dt, 0.0)
	if _combo > 0:
		_combo_left -= step
		if _combo_left <= 0.0:
			_combo = 0
			_combo_left = 0.0
	if _flash.is_empty():
		return
	var expired: Array[int] = []
	for key: Variant in _flash.keys():
		var left: float = float(_flash[key]) - step
		if left <= 0.0:
			expired.append(int(key))
		else:
			_flash[key] = left
	for id: int in expired:
		_flash.erase(id)
