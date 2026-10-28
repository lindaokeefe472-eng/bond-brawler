# -*- coding: utf-8 -*-
"""GDScript 静态检查：复刻编辑器 Errors 面板里的分析器警告。

Godot 的分析器警告只在编辑器里显示，命令行 `--import` 不会打印（脚本缓存没失效
就不重新编译），所以用这个脚本兜底。已覆盖：

  SHADOWED_GLOBAL_IDENTIFIER      变量/参数与内置函数重名（range / str / max ...）
  SHADOWED_VARIABLE               局部变量或参数遮蔽类成员 / 同名方法
  UNUSED_PARAMETER                函数参数没用到
  UNUSED_VARIABLE                 局部变量声明后没用到
  UNUSED_LOCAL_CONSTANT           局部常量声明后没用到
  UNUSED_PRIVATE_CLASS_VARIABLE   私有成员（_x）从未被引用

显式写了 @warning_ignore 的会跳过。

用法: python -I tools/lint_gdscript.py [目录...]
退出码: 0 干净 / 1 有问题
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BUILTINS = set("""
abs absf absi acos acosh asin asinh atan atan2 atanh bezier_curve bytes_to_var
bytes_to_var_with_objects ceil ceilf ceili char clamp clampf clampi cos cosh
cubic_interpolate cubic_interpolate_angle cubic_interpolate_angle_in_time
cubic_interpolate_in_time db_to_linear deg_to_rad ease error_string exp floor
floorf floori fmod fposmod hash instance_from_id inverse_lerp is_equal_approx
is_instance_id_valid is_instance_valid is_zero_approx lerp lerp_angle lerpf
linear_to_db log max maxf maxi min minf mini move_toward nearest_po2 pingpong
posmod pow print print_rich print_verbose printerr printraw prints printt
push_error push_warning rad_to_deg randf randf_range randfn randi randi_range
randomize range remap rid_allocate_id rid_from_int64 rotate_toward round roundf
roundi seed sign signf signi sin sinh smoothstep snapped snappedf snappedi sqrt
step_decimals str str_to_var tan tanh type_convert type_string typeof var_to_bytes
var_to_bytes_with_objects var_to_str weakref wrap wrapf wrapi
""".split())

DECL = re.compile(r"^(\s*)(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(var|const|signal)\s+([A-Za-z_]\w*)")
FUNC = re.compile(r"^(\s*)(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\((.*?)\)")
LOCAL_VAR = re.compile(r"^(\s*)var\s+([A-Za-z_]\w*)")
LOCAL_CONST = re.compile(r"^(\s*)const\s+([A-Za-z_]\w*)")
WORD = re.compile(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])")


def indent_of(line):
    return len(line) - len(line.lstrip())


def strip_strings_and_comments(line):
    out, i, n = [], 0, len(line)
    quote = None
    while i < n:
        c = line[i]
        if quote:
            if c == chr(92):
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "\"'":
            quote = c
            i += 1
            continue
        if c == "#":
            break
        out.append(c)
        i += 1
    return "".join(out)


def mentions(text, name):
    return WORD.search(text, 0) if False else re.search(WORD.pattern % re.escape(name), text)


def ignored(raw, line_no, code):
    idx = line_no - 2
    while idx >= 0 and not raw[idx].strip():
        idx -= 1
    if idx < 0:
        return False
    prev = raw[idx].strip()
    if not prev.startswith("@warning_ignore"):
        return False
    return ("(" not in prev) or (code.lower() in prev.lower())


def analyse(path, rel):
    with io.open(path, encoding="utf-8") as f:
        raw = f.read().splitlines()
    lines = [strip_strings_and_comments(l) for l in raw]

    members, methods = {}, {}
    for idx, line in enumerate(lines):
        if indent_of(line) != 0:
            continue
        m = DECL.match(line)
        if m:
            members[m.group(3)] = idx + 1
            continue
        fm = FUNC.match(line)
        if fm:
            methods[fm.group(2)] = idx + 1

    problems = []

    def add(ln, kind, msg):
        problems.append((rel, ln, kind, msg))

    for name, ln in members.items():
        if name in BUILTINS and not ignored(raw, ln, "SHADOWED_GLOBAL_IDENTIFIER"):
            add(ln, "SHADOWED_GLOBAL_IDENTIFIER", '变量名 "%s" 与内置函数重名' % name)
        if name.startswith("_") and not ignored(raw, ln, "UNUSED_PRIVATE_CLASS_VARIABLE"):
            hits = sum(1 for l in lines if re.search(WORD.pattern % re.escape(name), l))
            if hits <= 1:
                add(ln, "UNUSED_PRIVATE_CLASS_VARIABLE", '私有成员 "%s" 从未被使用' % name)

    i = 0
    while i < len(lines):
        m = FUNC.match(lines[i])
        if not m:
            i += 1
            continue
        base = indent_of(lines[i])
        sig_line = i + 1
        param_names = []
        for p in [x.strip() for x in m.group(3).split(",") if x.strip()]:
            p = p.split("=")[0].strip()
            p = re.sub(r":.*$", "", p).strip()
            if re.match(r"^[A-Za-z_]\w*$", p):
                param_names.append(p)

        body_start = i + 1
        body_end = body_start
        while body_end < len(lines):
            l = lines[body_end]
            if l.strip() and indent_of(l) <= base:
                break
            body_end += 1
        body = lines[body_start:body_end]

        for p in param_names:
            if p.startswith("_"):
                continue
            if p in BUILTINS and not ignored(raw, sig_line, "SHADOWED_GLOBAL_IDENTIFIER"):
                add(sig_line, "SHADOWED_GLOBAL_IDENTIFIER", '参数名 "%s" 与内置函数重名' % p)
            if p in members and not ignored(raw, sig_line, "SHADOWED_VARIABLE"):
                add(sig_line, "SHADOWED_VARIABLE", '参数 "%s" 遮蔽了第 %d 行的类成员' % (p, members[p]))
            elif p in methods and not ignored(raw, sig_line, "SHADOWED_VARIABLE"):
                add(sig_line, "SHADOWED_VARIABLE", '参数 "%s" 遮蔽了第 %d 行的同名方法' % (p, methods[p]))
            if not any(re.search(WORD.pattern % re.escape(p), l) for l in body):
                add(sig_line, "UNUSED_PARAMETER", '参数 "%s" 没有被使用' % p)

        for j, l in enumerate(body):
            vm = LOCAL_VAR.match(l)
            cm = LOCAL_CONST.match(l)
            if not vm and not cm:
                continue
            name = (vm or cm).group(2)
            decl_ln = body_start + j + 1
            rest = body[j + 1:]
            if name in members and not ignored(raw, decl_ln, "SHADOWED_VARIABLE"):
                add(decl_ln, "SHADOWED_VARIABLE",
                    '局部变量 "%s" 遮蔽了第 %d 行的类成员' % (name, members[name]))
            if not any(re.search(WORD.pattern % re.escape(name), l2) for l2 in rest):
                kind = "UNUSED_LOCAL_CONSTANT" if cm else "UNUSED_VARIABLE"
                add(decl_ln, kind, '局部声明 "%s" 之后没有被使用' % name)
        i = body_end

    return problems


def main():
    targets = sys.argv[1:] or ["src", "tests", "tools"]
    all_problems = []
    for t in targets:
        base = t if os.path.isabs(t) else os.path.join(ROOT, t)
        for dirpath, _dirs, files in os.walk(base):
            for fn in files:
                if not fn.endswith(".gd") or fn.startswith("_"):
                    continue
                full = os.path.join(dirpath, fn)
                try:
                    rel = os.path.relpath(full, ROOT).replace("\\", "/")
                except ValueError:
                    rel = full.replace("\\", "/")
                all_problems.extend(analyse(full, rel))

    if not all_problems:
        print("lint 通过：没有发现分析器警告")
        return 0
    all_problems.sort()
    print("发现 %d 条：" % len(all_problems))
    for rel, ln, kind, msg in all_problems:
        print("  %s:%d  %s  %s" % (rel, ln, kind, msg))
    return 1


if __name__ == "__main__":
    sys.exit(main())
