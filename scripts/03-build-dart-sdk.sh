#!/usr/bin/env bash
# 从引擎源码构建与引擎同版本的 Dart SDK（关键！
# 直接用官方 dart-sdk 二进制会和引擎版本不一致，导致
#   - Invalid SDK hash / 黑屏
#   - Wrong full snapshot version
#   - AOT ApiError exit 254
#
# create_sdk 全量 3700+ 步且会撞 analysis_server 自身的崩溃，
# 这里只编 flutter build 真正需要的子集（约 1200 步）。
#   usage: 03-build-dart-sdk.sh <out_dir_name>
set -euo pipefail
OUT="${1:-riscv64-release}"
ROOT="${FLUTTER_ENGINE:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT/out/$OUT"

BIN=(
  dart-sdk/bin/dart
  dart-sdk/bin/dartaotruntime
  dart-sdk/bin/dartvm
  dart-sdk/bin/dartcliruntime
)
mapfile -t LIB < <(ninja -t targets all | grep -E '^dart-sdk/lib.*: copy$' | cut -d: -f1)

# -k 0：单个目标失败不中断其余
ninja -k 0 "${BIN[@]}" "${LIB[@]}"

echo ">>> 版本确认"
for b in dart dartaotruntime dartvm dartcliruntime; do
  printf "  %-16s %s\n" "$b" "$("./dart-sdk/bin/$b" --version 2>&1 | head -1)"
done