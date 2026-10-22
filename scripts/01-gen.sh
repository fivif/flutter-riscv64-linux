#!/usr/bin/env bash
# 生成 ninja 构建文件。
#   usage: 01-gen.sh <out_dir_name> [release|debug]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${FLUTTER_ENGINE:-$(cd "$HERE/../.." && pwd)}"   # engine/src 目录
OUT="${1:-riscv64-release}"
MODE="${2:-release}"

ARGS="$HERE/../args/riscv64-release.gn"
[ "$MODE" = "debug" ] && ARGS="$HERE/../args/riscv64-debug.gn"

cd "$ROOT"
mkdir -p "out/$OUT"
cp "$ARGS" "out/$OUT/args.gn"

# --script-executable 是必须的：
#   引擎默认用 //flutter/third_party/cpython3/bin/python3 执行
#   tools/make_version.py，该路径通常不存在 → gn 报 "Script returned 127"。
# --root=../.. 用于让 out/xxx 内的相对路径正确。
echo ">>> gn gen out/$OUT  (mode=$MODE)"
gn gen "out/$OUT" --script-executable=/usr/bin/python3
echo ">>> 完成，目标数: $(ninja -C "out/$OUT" -t targets all | wc -l)"