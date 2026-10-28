## 探针：对比「宽相（Area3D）报出的候选」与「窄相（领域层）真正结算的命中」。
extends SceneTree

var _f: int = 0
var _scene: Node = null
var _session: Variant = null
var _pid: int = 0
var _hits: Array[String] = []

func _initialize() -> void:
    _scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
    root.add_child(_scene)

func _process(_delta: float) -> bool:
    _f += 1
    if _session == null:
        _session = _scene.get("_session")
        _pid = int(_scene.get("_player_id"))
        if _session != null:
            _session.get("_bus").subscribe(GameConstants.EVT_DAMAGE_APPLIED, _on_damage)
        return false
    var frame: LocoInputFrame = LocoInputFrame.empty()
    frame.attack = (_f % 15) == 0
    frame.move = Vector2(1.0, 0.0)
    var inputs: Dictionary = {}
    inputs[_pid] = frame
    _session.tick(GameConstants.TICK_DELTA, inputs)
    if _f % 60 == 0:
        print("f%4d  宽相候选=%d  窄相命中=%d" % [_f, _scene.call("broadphase_hit_count"), _hits.size()])
    if _f >= 300:
        print("--- 前 10 次命中（攻击者->目标 平面距离 / 纵深差）---")
        for s: String in _hits.slice(0, 10):
            print("  " + s)
        quit(0)
        return true
    return false

func _on_damage(e: DomainEvent) -> void:
    var aid: int = int(e.payload.get("attacker_id", 0))
    var tid: int = int(e.payload.get("target_id", 0))
    var a: Variant = _session.get_actor(aid)
    var t: Variant = _session.get_actor(tid)
    if a == null or t == null:
        return
    var d: Vector2 = t.plane_pos - a.plane_pos
    _hits.append("%s%d -> %s%d  kind=%s dx=%.2f lane=%.2f 距离=%.2f" % [
        str(a.faction).substr(0, 1), aid, str(t.faction).substr(0, 1), tid,
        str(e.payload.get("hit_kind", "?")), d.x, d.y, d.length()])
