## 极端场景压测：让敌人速死、玩家速死，把死亡/移除/淡出/对象池回收全跑一遍。
extends SceneTree

const FRAMES: int = 900
var _f: int = 0
var _scene: Node = null
var _session: Variant = null
var _player_id: int = 0

func _initialize() -> void:
    _scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
    root.add_child(_scene)

func _process(_delta: float) -> bool:
    _f += 1
    if _session == null:
        _session = _scene.get("_session")
        _player_id = int(_scene.get("_player_id"))
        return false
    # 第 30 帧把敌人血量打到 1，逼出连续击杀
    if _f == 30:
        for id: int in _session.actor_ids():
            var a: Variant = _session.get_actor(id)
            if a.id != _player_id:
                a.stats.current_hp = 1.0
    # 第 400 帧把玩家打死
    if _f == 400:
        var p: Variant = _session.get_actor(_player_id)
        if p != null:
            p.stats.current_hp = 1.0
    var frame: LocoInputFrame = LocoInputFrame.empty()
    frame.attack = (_f % 12) == 0
    frame.move = Vector2(1.0 if (_f / 9) % 2 == 0 else -1.0, 0.0)
    var inputs: Dictionary = {}
    inputs[_player_id] = frame
    _session.tick(GameConstants.TICK_DELTA, inputs)
    if _f % 150 == 0:
        var line: String = "f%4d:" % _f
        for id: int in _session.actor_ids():
            var a: Variant = _session.get_actor(id)
            line += " [%s%d hp=%.0f]" % [str(a.faction).substr(0, 1), id, a.stats.current_hp]
        print(line)
    if _f >= FRAMES:
        print("done")
        quit(0)
        return true
    return false
