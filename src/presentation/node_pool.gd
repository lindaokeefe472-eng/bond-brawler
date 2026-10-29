## 通用对象池：把「建节点」的成本从战斗中挪到 prewarm 阶段。
##
## 为什么池本身是 RefCounted：它没有自己的场景语义，挂到哪个父节点由调用方决定；
## DamageNumberPool 这类消费者因此能在无场景树的单测里直接验证复用逻辑。
class_name NodePool
extends RefCounted

var _factory: Callable = Callable()
var _parent: Node = null
var _free: Array[Node] = []
var _active: Dictionary = {}
var _created: int = 0
## 默认禁止增长：acquire() 永远不会在战斗中 instantiate，容量必须靠 prewarm 准备。
var _allow_growth: bool = false

func _init(factory: Callable = Callable(), parent: Node = null) -> void:
	_factory = factory
	_parent = parent

func set_factory(factory: Callable) -> void:
	_factory = factory

## 池创建出来的节点统一挂在这个父节点下；设为 null 时节点保持无父状态。
func set_parent(parent: Node) -> void:
	_parent = parent
	for node: Node in _free:
		_attach(node)

## 只有离线预热的场景才需要打开；战斗期间保持关闭，池空时 acquire() 返回 null。
func set_allow_growth(enabled: bool) -> void:
	_allow_growth = enabled

## 一次性建好 n 个实例并停放，返回实际创建数量（工厂缺失时提前停止）。
func prewarm(n: int) -> int:
	var made: int = 0
	for _i: int in range(maxi(n, 0)):
		var node: Node = _create()
		if node == null:
			break
		_park(node)
		made += 1
	return made

## 取一个可用节点。池空且禁止增长时返回 null —— 调用方必须容忍这种降级。
func acquire() -> Node:
	var node: Node = null
	while not _free.is_empty():
		var candidate: Node = _free.pop_back()
		if is_instance_valid(candidate):
			node = candidate
			break
	if node == null:
		if not _allow_growth:
			return null
		node = _create()
	if node == null:
		return null
	_active[node.get_instance_id()] = node
	_wake(node)
	return node

## 归还节点。重复归还只告警不报错：多条命中路径可能指向同一个跳字。
func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var key: int = node.get_instance_id()
	if not _active.has(key):
		push_warning("NodePool.release: 节点不属于本池或已归还，忽略")
		return
	_active.erase(key)
	_park(node)

## 释放池内全部节点（场景卸载 / 测试清理用）。工厂保留，池可以继续 prewarm。
func clear() -> void:
	for node: Node in _free:
		if is_instance_valid(node):
			node.free()
	for key: Variant in _active.keys():
		var active_node: Node = _active[key]
		if is_instance_valid(active_node):
			active_node.free()
	_free.clear()
	_active.clear()
	_created = 0

func free_count() -> int:
	return _free.size()

func active_count() -> int:
	return _active.size()

func created_count() -> int:
	return _created

func _create() -> Node:
	if not _factory.is_valid():
		push_warning("NodePool: 未设置工厂，无法创建节点")
		return null
	var value: Variant = _factory.call()
	if not (value is Node):
		push_warning("NodePool: 工厂返回值不是 Node")
		return null
	var node: Node = value
	_created += 1
	_attach(node)
	return node

func _attach(node: Node) -> void:
	if _parent != null and is_instance_valid(_parent) and node.get_parent() == null:
		_parent.add_child(node)

func _park(node: Node) -> void:
	_set_visible(node, false)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_free.append(node)

func _wake(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT
	_set_visible(node, true)

static func _set_visible(node: Node, value: bool) -> void:
	if node is Node3D:
		(node as Node3D).visible = value
	elif node is CanvasItem:
		(node as CanvasItem).visible = value
