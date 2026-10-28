#!/usr/bin/env bash
# GdUnit4 串行执行器：多个 agent 同时调用时会用目录锁排队，避免报告目录与
# .godot 缓存竞争。
#
# 用法:
#   bash tools/test.sh                                   # 全部
#   bash tools/test.sh res://tests/unit/combat           # 单个目录
#   bash tools/test.sh res://tests/unit/combat res://tests/e2e
#
# 新增带 class_name 的脚本后，先跑一次 `godot --headless --path . --import`。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/d/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe}"
LOCK="$ROOT/.godot/_test.lock"

mkdir -p "$ROOT/.godot"
for _ in $(seq 1 900); do
  if mkdir "$LOCK" 2>/dev/null; then break; fi
  sleep 0.2
done
cleanup() { rmdir "$LOCK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then TARGETS=("res://tests"); fi
ARGS=()
for t in "${TARGETS[@]}"; do ARGS+=(-a "$t"); done

"$GODOT" --headless --path "$ROOT" -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  "${ARGS[@]}" -c --ignoreHeadlessMode
