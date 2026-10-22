#!/usr/bin/env bash
# 从引擎源码构建与引擎同版本的 Dart SDK。
#
# 【为什么必须自己做这一步】
# 直接用官方 dart-sdk 二进制会和引擎版本不一致，导致：
#   - Can't load Kernel binary: Invalid SDK hash  → 窗口全黑
#   - ERROR: ApiError / AOT snapshotter exit 254
#   - Wrong full snapshot version, expected '9190...' found '79a4...'
#
# 【为什么不用 create_sdk】
# `ninja "flutter/third_party/dart:create_sdk"` 全量 3700+ 步，而且会撞
# analysis_server 自身崩溃（Bad state: Future already completed）。
# flutter build 不需要它。这里只编必需子集。
#
# 【为什么需要 snapshots】
# 如果这套 SDK 要替换 flutter 自己的 bin/cache/dart-sdk，就必须包含
# bin/snapshots/ —— flutter 工具本身要跑 dartdev_aot.dart.snapshot。
# 少了它，flutter 会报：
#   Unable to find snapshot: dartdev_aot.dart.snapshot
#   Unable to 'pub upgrade' flutter tool.
# （这是实测踩到的，不是猜的）
#
#   usage: 03-build-dart-sdk.sh <out_dir_name>
set -euo pipefail
OUT="${1:-riscv64-release}"
ROOT="${FLUTTER_ENGINE:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT/out/$OUT"

# ---- 1. 四个可执行文件 ----
BIN=(
  dart-sdk/bin/dart
  dart-sdk/bin/dartaotruntime
  dart-sdk/bin/dartvm
  dart-sdk/bin/dartcliruntime
)

# ---- 2. lib/ 的拷贝（核心库必须与 VM 同版本，否则 platform dill 不匹配）----
mapfile -t LIB < <(ninja -t targets all | grep -E '^dart-sdk/lib.*: copy$' | cut -d: -f1)

# ---- 3. bin/snapshots/ 的拷贝（flutter 工具需要 dartdev_aot 等）----
# 排除 analysis_server：它自己在生成快照时崩，与版本无关，且 flutter build 不需要。
mapfile -t SNAPS < <(ninja -t targets all \
  | grep -E '^dart-sdk/bin/snapshots/.*: copy$' \
  | cut -d: -f1 \
  | grep -v analysis_server)

echo ">>> 目标统计: bin ${#BIN[@]} / lib ${#LIB[@]} / snapshots ${#SNAPS[@]}"
echo ">>> 预计 1300~1800 步（取决于 out 目录里已有多少对象）"
echo ">>> 注意：不要和其他 ninja 同时跑（见 docs/04）"

# -k 0：单个目标失败不中断其余
ninja -k 0 "${BIN[@]}" "${LIB[@]}" "${SNAPS[@]}"

# ---- 4. 版本自检：全部必须一致 ----
echo
echo ">>> 版本自检（必须全部相同）"
for b in dart dartaotruntime dartvm dartcliruntime; do
  f="./dart-sdk/bin/$b"
  if [ -x "$f" ]; then
    printf "  %-16s %s\n" "$b" "$("$f" --version 2>&1 | head -1)"
  else
    printf "  %-16s ⚠️ 未生成（该目标可能不在本配置的依赖里）\n" "$b"
  fi
done
echo "  snapshots: $(ls dart-sdk/bin/snapshots 2>/dev/null | wc -l) 个"
echo "  lib      : $(find dart-sdk/lib -name '*.dart' 2>/dev/null | wc -l) 个 .dart"

echo
echo ">>> 功能自测（能跑才算成功）"
printf 'void main(){print("ok");}\n' > /tmp/_sdktest.dart
./dart-sdk/bin/dart run /tmp/_sdktest.dart 2>&1 | tail -2
