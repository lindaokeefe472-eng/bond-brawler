# ADR-0001：领域层零引擎依赖（六边形架构）

- 状态：已接受
- 日期：2026-10-28

## 背景

Godot 的惯用写法是把逻辑写进 `Node` 的 `_process` / `_physics_process`。
这套写法在原型阶段很快，但一旦战斗系统超过几千行就会失控：

- 逻辑无法脱离场景树测试，每次改数值都要开编辑器点一遍
- 物理帧率抖动会污染判定结果，导致同一招有时打得中有时打不中
- 无法回放、无法联机同步、无法做平衡性批量模拟

## 决定

领域层（`src/*/domain/`）全部是 `RefCounted` 纯类：

- 不继承 `Node`，不使用 `signal` / `await` / `get_tree()`
- 不直接调用 `Engine` / `Time` / `Input` / `OS` / `randf()`
- 时间通过 `IClock` 注入，随机通过 `IRng` 注入
- 对外只通过 `DomainEventBus` 广播「发生了什么」

引擎只在两个地方出现：`src/presentation/`（视图）和 `src/infrastructure/`（IO）。

## 后果

**收益**

- 全部战斗规则可在 `godot --headless` 下秒级跑完，TDD 可行
- 同一份逻辑可以跑在客户端、服务器、离线模拟器里
- 数值改动不需要开编辑器

**代价**

- 多一层「领域对象 ↔ 节点」的映射代码
- 新人需要先理解 `DomainEventBus` 与端口的用法
- 不能直接用 Godot 的 `AnimationPlayer` 驱动逻辑（只能用驱动表现）

## 约束检查

`tools/check_architecture.py` 会在 CI 里扫描违规。领域层一旦出现 `Node` / `Engine.` / `signal`
就会失败。
