# -*- coding: utf-8 -*-
"""架构约束检查：领域层零引擎依赖 + 上下文依赖方向。

用法: python -I tools/check_architecture.py
退出码: 0 通过 / 1 有违规
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")

# 领域层禁止出现的标识（正则）
FORBIDDEN = [
    (r"\bextends\s+(Node|Node2D|Node3D|CharacterBody3D|Area3D|Sprite3D|Camera3D|Control|Resource)\b",
     "领域层不得继承引擎节点/资源，只能用 RefCounted"),
    (r"\b(get_tree|get_node|add_child|queue_free|instantiate)\s*\(", "领域层不得操作场景树"),
    (r"\b(Engine|Time|Input|OS|DisplayServer|ProjectSettings)\s*\.", "领域层不得调用引擎全局单例"),
    (r"\b(randf|randi|randf_range|randi_range|randomize)\s*\(", "领域层随机必须走 IRng"),
    (r"^\s*signal\s+", "领域层不得使用信号，请走 DomainEventBus"),
    (r"\bawait\b", "领域层不得使用 await"),
    (r'res://src/(presentation|infrastructure|bootstrap|application)/', "领域层不得依赖外层"),
]

# 上下文 -> 允许依赖的上下文
#
# 关键区分：
#   - 领域上下文之间是**单向**依赖，防止循环。
#   - infrastructure / presentation 是适配器，职责就是「把数据装配成领域对象」
#     和「读取领域值对象渲染」，因此允许依赖全部领域上下文。
#     禁止它们反向被领域层依赖（由上面的 FORBIDDEN 规则保证）。
DOMAINS = {"combat", "skills", "talents", "ai", "locomotion", "stage"}
DEPS = {
    "core": set(),
    "combat": {"core"},
    "skills": {"core", "combat"},
    "talents": {"core", "combat"},
    "ai": {"core", "combat", "skills"},
    "locomotion": {"core"},
    "stage": {"core"},
    "application": {"core"} | DOMAINS,
    "infrastructure": {"core"} | DOMAINS,
    "presentation": {"core", "application"} | DOMAINS,
    "bootstrap": None,  # 组合根不限制
}

CLASS_DECL = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)


def context_of(rel):
    parts = rel.replace("\\", "/").split("/")
    return parts[1] if len(parts) > 1 else "core"


def strip_comments(text):
    out = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        out.append(line.split("#")[0] if "#" in line and '"' not in line else line)
    return "\n".join(out)


def main():
    files = []
    for base, _dirs, names in os.walk(SRC):
        for n in names:
            if n.endswith(".gd"):
                files.append(os.path.join(base, n))

    class_owner = {}
    sources = {}
    for path in files:
        rel = os.path.relpath(path, SRC).replace("\\", "/")
        with io.open(path, encoding="utf-8") as f:
            text = f.read()
        sources[rel] = text
        for m in CLASS_DECL.finditer(text):
            class_owner[m.group(1)] = context_of("src/" + rel)

    violations = []
    for rel, text in sorted(sources.items()):
        ctx = context_of("src/" + rel)
        is_domain = "/domain/" in rel or rel.startswith("core/")
        body = strip_comments(text)

        if is_domain:
            for pattern, why in FORBIDDEN:
                for m in re.finditer(pattern, body, re.M):
                    line_no = body[:m.start()].count("\n") + 1
                    violations.append("%s:%d  %s  [%s]" % (rel, line_no, why, m.group(0).strip()))

        allowed = DEPS.get(ctx)
        if allowed is None:
            continue
        for name, owner in class_owner.items():
            if owner == ctx or owner == "core" and ctx == "core":
                continue
            if owner not in allowed and re.search(r"\b%s\b" % re.escape(name), body):
                line_no = body[:re.search(r"\b%s\b" % re.escape(name), body).start()].count("\n") + 1
                violations.append("%s:%d  上下文越界：%s 属于 %s，%s 只允许依赖 %s"
                                  % (rel, line_no, name, owner, ctx, sorted(allowed)))

    if violations:
        print("架构检查失败，共 %d 项：" % len(violations))
        for v in violations:
            print("  x " + v)
        return 1
    print("架构检查通过：%d 个文件，%d 个类" % (len(sources), len(class_owner)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
