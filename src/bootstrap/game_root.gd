## 场景根节点：把已经装配好的服务接到场景树上，并驱动固定步长主循环。
##
## 装配全部交给 src/bootstrap/composition_root.gd —— 表现层自己不做任何 new，
## 这样「具体实现只在组合根里被创建」这条规则可以用 grep 检查。
## 本节点只负责：建场地、挂反馈、绑事件、生成角色、推进 tick。
class_name GameRoot
extends Node3D

const ACTOR_SCENE_PATH: String = "res://scenes/actors/actor_view.tscn"
const MANIFEST_PATH: String = "res://assets/sprites/characters/manifest.json"
const DATA_ROOT: String = "res://data"
const TYPE_CHART_FILE: String = "type_chart.json"
const ACTIONS_FILE: String = "actions.json"
const RNG_SEED: int = 20261028

const PLAYER_CHARACTER: String = "knight"
const ENEMY_CHARACTERS: Array = ["orc", "skeleton", "armored_orc"]
const ENEMY_SPECIES_IDS: Array = ["charmander", "squirtle", "bulbasaur"]
const PLAYER_SPAWN: Vector2 = Vector2(-5.0, 0.0)
const ENEMY_SPAWNS: Array = [Vector2(4.0, -1.2), Vector2(6.5, 1.0), Vector2(9.0, -0.4)]

## 敌人性格：中庸偏进攻，保证测试场里三个敌人会主动压上来。
const ENEMY_BRAIN_PROFILE: Dictionary = {
	"aggression": 0.7,
	"caution": 0.3,
	"range_preference": 1.6,
	"skill_range": 3.0,
	"stickiness": 0.35,
}
## 数据表缺种族时的兜底，保证空数据也能进游戏。
const DEFAULT_STATS: Dictionary = {
	"max_hp": 120.0,
	"attack": 12.0,
	"defense": 0.0,
	"types": [],
}

const HIT_FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const GUARD_FLASH_COLOR: Color = Color(0.6, 0.8, 1.0, 1.0)
const CRIT_FLASH_COLOR: Color = Color(1.0, 0.85, 0.3, 1.0)
const LETHAL_FLASH_COLOR: Color = Color(0.9, 0.2, 0.2, 1.0)
const SHAKE_DURATION: float = 0.32
const SCREEN_FLASH_SECONDS: float = 0.18

var _app: CompositionRoot = null
var _bus: DomainEventBus = null
var _rng: DeterministicRng = null
var _data: JsonDataSource = null
var _species: SpeciesRepository = null
var _skills: SkillRepository = null
var _type_chart: CombatTypeChart = null
var _session: BattleSession = null
var _input: InputAdapter = null
var _feedback: FeedbackDirector = null
var _numbers: DamageNumberPool = null
var _arena: ArenaBuilder = null
var _camera: CameraRig = null
var _actor_scene: PackedScene = null
var _manifest: Dictionary = {}
var _melee_config: Dictionary = {}
var _views: Dictionary = {}
var _player_id: int = 0
var _accumulator: float = 0.0
var _broadphase_hits: int = 0

func _ready() -> void:
	_build_services()
	_build_arena()
	_build_feedback()
	_bind_events()
	_load_assets()
	_spawn_actors()

func _build_services() -> void:
	_app = CompositionRoot.create(DATA_ROOT, RNG_SEED)
	_bus = _app.bus
	_rng = _app.rng
	_data = _app.data
	_species = _app.species
	_skills = _app.skills
	_type_chart = _app.combat_data.type_chart()
	_melee_config = _app.melee_config
	_session = _app.session
	_input = InputAdapter.new()

func _build_arena() -> void:
	_arena = ArenaBuilder.new(self)
	_arena.build()
	_camera = _arena.camera()

func _build_feedback() -> void:
	var number_root := Node3D.new()
	number_root.name = "DamageNumbers"
	add_child(number_root)
	_numbers = DamageNumberPool.new(number_root)
	_feedback = FeedbackDirector.new()
	_feedback.name = "FeedbackDirector"
	add_child(_feedback)
	_feedback.configure(_camera, _numbers)

func _bind_events() -> void:
	_bus.subscribe(GameConstants.EVT_DAMAGE_APPLIED, _on_damage_applied)
	_bus.subscribe(GameConstants.EVT_ACTOR_GUARDED, _on_actor_guarded)
	_bus.subscribe(GameConstants.EVT_ACTOR_DODGED, _on_actor_dodged)
	_bus.subscribe(GameConstants.EVT_ACTOR_DIED, _on_actor_died)

func _load_assets() -> void:
	_actor_scene = load(ACTOR_SCENE_PATH) as PackedScene
	if _actor_scene == null:
		push_warning("GameRoot: 无法加载 %s，角色将不可见" % ACTOR_SCENE_PATH)
	var raw_manifest: Variant = _data.read_json(MANIFEST_PATH)
	if raw_manifest is Dictionary:
		_manifest = raw_manifest

func _spawn_actors() -> void:
	var player_species: Dictionary = _species.starter()
	_player_id = _session.spawn_actor(_build_spec(
		player_species, GameConstants.FACTION_PLAYER, PLAYER_SPAWN, null, PLAYER_CHARACTER))
	var player_view: ActorView = _create_view(_player_id, PLAYER_CHARACTER)
	if player_view != null and _camera != null:
		_camera.set_target(player_view)

	for i: int in range(ENEMY_SPAWNS.size()):
		var character_id: String = str(ENEMY_CHARACTERS[i % ENEMY_CHARACTERS.size()])
		var species_id: String = str(ENEMY_SPECIES_IDS[i % ENEMY_SPECIES_IDS.size()])
		var species: Dictionary = _species.find(StringName(species_id))
		if species.is_empty():
			species = player_species
		var spawn: Vector2 = ENEMY_SPAWNS[i]
		var actor_id: int = _session.spawn_actor(_build_spec(
			species, GameConstants.FACTION_ENEMY, spawn, ENEMY_BRAIN_PROFILE, character_id))
		_create_view(actor_id, character_id)

func _build_spec(species: Dictionary, faction: StringName, spawn: Vector2,
		brain_profile: Variant, character_id: String) -> Dictionary:
	var stats: Dictionary = DEFAULT_STATS.duplicate(true)
	if not species.is_empty():
		# 物种表原样作为 stats：CombatActorStats 会优先取 battle_hp 作为 max_hp。
		stats = species.duplicate(true)
	return {
		"species_id": str(species.get("id", character_id)),
		"faction": faction,
		"plane_pos": spawn,
		"stats": stats,
		"skills": _skill_entries(species),
		"brain_profile": brain_profile,
		"melee": _melee_config.duplicate(true),
	}

func _skill_entries(species: Dictionary) -> Array:
	var entries: Array = []
	var raw: String = str(species.get("initial", species.get("defaults", "")))
	if raw.is_empty():
		return entries
	for part: String in raw.split("/", false):
		var skill_id := StringName(part.strip_edges())
		if skill_id == &"":
			continue
		var def: Variant = _skills.find(skill_id)
		if def != null:
			entries.append(def)
		# 槽位数由 application 的 ActorRuntime 统一声明，避免表现层再依赖 locomotion。
		if entries.size() >= ActorRuntime.SKILL_SLOT_COUNT:
			break
	return entries

func _create_view(actor_id: int, character_id: String) -> ActorView:
	var runtime: ActorRuntime = _session.get_actor(actor_id)
	if runtime == null or _actor_scene == null:
		return null
	var view := _actor_scene.instantiate() as ActorView
	if view == null:
		push_warning("GameRoot: %s 根节点不是 ActorView" % ACTOR_SCENE_PATH)
		return null
	view.name = "Actor_%d" % actor_id
	add_child(view)
	view.bind(runtime, character_id, _manifest)
	view.broadphase_sink = _on_broadphase_candidate
	_views[actor_id] = view
	_feedback.register_actor_view(actor_id, view)
	return view

## 固定步长主循环：累积真实帧时间，按 TICK_DELTA 追赶，最多补 MAX_CATCHUP_TICKS 步。
func _physics_process(delta: float) -> void:
	if _session == null:
		return
	var max_backlog: float = GameConstants.TICK_DELTA * float(GameConstants.MAX_CATCHUP_TICKS)
	_accumulator = minf(_accumulator + delta, max_backlog)
	var steps: int = 0
	while _accumulator >= GameConstants.TICK_DELTA and steps < GameConstants.MAX_CATCHUP_TICKS:
		_accumulator -= GameConstants.TICK_DELTA
		steps += 1
		var inputs: Dictionary = {}
		if _player_id > 0:
			inputs[_player_id] = _input.poll()
		# 宽相提示：每个角色的攻击盒本帧看到了谁；空数组时领域层退化为全量扫描。
		var broadphase: Dictionary = {}
		for key: Variant in _views.keys():
			var view: ActorView = _views[key]
			if view != null and is_instance_valid(view):
				broadphase[key] = view.consume_candidates()
		_session.tick(GameConstants.TICK_DELTA, inputs, broadphase)
		_sync_views()

func _sync_views() -> void:
	for key: Variant in _views.keys():
		var view: ActorView = _views[key]
		if view != null and is_instance_valid(view):
			view.sync_from_runtime()

## 宽相只做提示：真正的伤害仍由 BattleSession 的窄相结算，这里绝不改血量。
func _on_broadphase_candidate(_attacker_id: int, _target_id: int) -> void:
	_broadphase_hits += 1

func broadphase_hit_count() -> int:
	return _broadphase_hits

func _on_damage_applied(event: DomainEvent) -> void:
	if _feedback == null:
		return
	var payload: Dictionary = event.payload
	var hit_kind := StringName(str(payload.get("hit_kind", "light")))
	var is_crit: bool = bool(payload.get("is_crit", false))
	var is_lethal: bool = bool(payload.get("is_lethal", false))
	var target_id: int = int(payload.get("target_id", 0))
	var amount: int = int(roundf(float(payload.get("amount", 0.0))))

	_feedback.damage_number(target_id, amount, &"crit" if is_crit else &"normal")
	_feedback.hit_flash(target_id, CRIT_FLASH_COLOR if is_crit else HIT_FLASH_COLOR)
	_feedback.hit_stop(_hitstop_for(hit_kind, is_crit))
	_feedback.camera_shake(_shake_for(hit_kind, is_crit), SHAKE_DURATION)
	_feedback.play_sfx(&"hit", Vector2.ZERO)
	if is_crit:
		_feedback.screen_flash(CRIT_FLASH_COLOR, SCREEN_FLASH_SECONDS)
	elif is_lethal:
		_feedback.screen_flash(LETHAL_FLASH_COLOR, SCREEN_FLASH_SECONDS)

func _on_actor_guarded(event: DomainEvent) -> void:
	if _feedback == null:
		return
	var target_id: int = int(event.payload.get("target_id", 0))
	_feedback.hit_flash(target_id, GUARD_FLASH_COLOR)
	_feedback.hit_stop(GameConstants.HITSTOP_LIGHT)
	_feedback.camera_shake(GameConstants.SHAKE_LIGHT, SHAKE_DURATION)
	_feedback.play_sfx(&"guard", Vector2.ZERO)

func _on_actor_dodged(event: DomainEvent) -> void:
	if _feedback == null:
		return
	var target_id: int = int(event.payload.get("target_id", 0))
	_feedback.hit_flash(target_id, GUARD_FLASH_COLOR)
	_feedback.play_sfx(&"dodge", Vector2.ZERO)

func _on_actor_died(_event: DomainEvent) -> void:
	if _feedback == null:
		return
	_feedback.camera_shake(GameConstants.SHAKE_HEAVY, SHAKE_DURATION)
	_feedback.screen_flash(LETHAL_FLASH_COLOR, SCREEN_FLASH_SECONDS)
	_feedback.play_sfx(&"death", Vector2.ZERO)

## 打击力度 -> 顿帧时长。轻击和技能用不同档位，重击/技能顿感更强。
func _hitstop_for(hit_kind: StringName, is_crit: bool) -> float:
	match hit_kind:
		&"heavy", &"skill":
			return GameConstants.HITSTOP_HEAVY
		&"light":
			return GameConstants.HITSTOP_MEDIUM if is_crit else GameConstants.HITSTOP_LIGHT
	return GameConstants.HITSTOP_LIGHT

func _shake_for(hit_kind: StringName, is_crit: bool) -> float:
	match hit_kind:
		&"heavy", &"skill":
			return GameConstants.SHAKE_HEAVY
	return GameConstants.SHAKE_MEDIUM if is_crit else GameConstants.SHAKE_LIGHT

func _exit_tree() -> void:
	# 组合根被释放时一定解开时间冻结，否则编辑器/下一局会一直停住。
	if Engine.time_scale <= 0.0:
		Engine.time_scale = 1.0
