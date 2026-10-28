## 一次生成请求的纯值对象：波次生成器产出它，application 层消费它并分配真实 actor_id。
## 不持有任何 actor 引用，因此可以安全地跨帧排队、序列化、做回放比对。
class_name StageSpawnRequest
extends RefCounted

var species_id: StringName = &""
var plane_pos: Vector2 = Vector2.ZERO
var wave: int = 0
var faction: StringName = GameConstants.FACTION_ENEMY

func _init(
    p_species_id: StringName = &"",
    p_plane_pos: Vector2 = Vector2.ZERO,
    p_wave: int = 0,
    p_faction: StringName = GameConstants.FACTION_ENEMY
) -> void:
    species_id = p_species_id
    plane_pos = p_plane_pos
    wave = p_wave
    faction = p_faction

## 供 StageWaveSpawner.pending_spawns() 的契约形状使用。
func to_dict() -> Dictionary:
    return {
        "species_id": species_id,
        "plane_pos": plane_pos,
        "wave": wave,
        "faction": faction,
    }

## 缺字段时降级为默认值：数据来自外部，不能假设键一定存在。
static func from_dict(data: Dictionary) -> StageSpawnRequest:
    var sid: StringName = StringName(str(data.get("species_id", "")))
    var pos: Vector2 = data.get("plane_pos", Vector2.ZERO)
    var wave_index: int = int(data.get("wave", 0))
    var fac: StringName = StringName(str(data.get("faction", GameConstants.FACTION_ENEMY)))
    return StageSpawnRequest.new(sid, pos, wave_index, fac)

func _to_string() -> String:
    return "StageSpawnRequest(%s wave=%d pos=%s faction=%s)" % [species_id, wave, plane_pos, faction]
