## 技能仓库：把 data/skills.json（以 id 为键的字典）转成 skills 上下文的技能定义并建索引。
##
## 为什么在构造时一次性建好索引：技能表在战斗中只读、且按 id / 模板高频查询；
## 懒加载会把解析开销塞进第一次出手的那一帧，恰好是最不能卡的地方。
##
## 依赖说明：infrastructure 是适配器，职责就是「数据 -> 领域对象」的一次性映射，
## 因此可以静态依赖 skills 上下文（见 docs/ARCHITECTURE.md §1）。
## 反过来，领域层永远不知道本文件的存在。
class_name SkillRepository
extends RefCounted

var _by_id: Dictionary[StringName, SkillDef] = {}
var _by_template: Dictionary[StringName, Array] = {}
var _all: Array[SkillDef] = []

func _init(data: IDataSource) -> void:
    _load(data)

## 查不到时返回 null；调用方必须处理 null（数据可能缺条目）。
func find(id: StringName) -> SkillDef:
    var key: StringName = StringName(str(id))
    if not _by_id.has(key):
        return null
    return _by_id[key]

## 返回内部数组，调用方只读遍历即可；复制 124 个引用不值得每帧做一次。
func all() -> Array[SkillDef]:
    return _all

## 返回新数组，防止调用方 append 污染仓库的模板索引。
func by_template(template: StringName) -> Array:
    var out: Array = []
    var key: StringName = StringName(str(template))
    if _by_template.has(key):
        for def: SkillDef in _by_template[key]:
            out.append(def)
    return out

func size() -> int:
    return _all.size()

func _load(data: IDataSource) -> void:
    var raw: Variant = data.read_json("skills.json")
    if not (raw is Dictionary):
        push_warning("SkillRepository: skills.json 不是字典，技能表为空")
        return
    var doc: Dictionary = raw
    # 按 id 排序后构建，保证 all() 的顺序与文件键序无关，回放时结果稳定。
    var ids: Array = doc.keys()
    ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
    for raw_id: Variant in ids:
        var entry: Variant = doc[raw_id]
        if not (entry is Dictionary):
            push_warning("SkillRepository: 跳过非字典技能条目 %s" % str(raw_id))
            continue
        var def: SkillDef = SkillDef.from_dict(entry)
        if def == null:
            push_warning("SkillRepository: 技能条目解析失败 %s" % str(raw_id))
            continue
        # 字典键才是权威 id：数据条目偶尔漏写 id 字段，不能因此丢掉整个技能。
        if str(def.id).is_empty():
            def.id = StringName(str(raw_id))
        if _by_id.has(def.id):
            push_warning("SkillRepository: 技能 id 重复 %s，保留先出现的一条" % def.id)
            continue
        _by_id[def.id] = def
        _all.append(def)
        var bucket: Array = _by_template.get(def.template, [])
        bucket.append(def)
        _by_template[def.template] = bucket
