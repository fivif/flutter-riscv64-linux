#!/usr/bin/env bash
# 构建引擎核心产物。
#   usage: 02-build.sh <out_dir_name>
set -euo pipefail
OUT="${1:-riscv64-release}"
ROOT="${FLUTTER_ENGINE:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT/out/$OUT"

# 这些就是 flutter 在 artifacts/engine/<dir>/ 下需要的东西
TARGETS=(
  libflutter_linux_gtk.so          # GTK embedder
  gen_snapshot                     # AOT 编译器
  impellerc                        # 着色器编译器
  font-subset                      # 图标字体裁剪
  frontend_server_aot.dart.snapshot # 决定 kernel 的 SDK hash
)

echo ">>> ninja ${TARGETS[*]}"
echo ">>> 预计 4000~4500 步，1.5~2.5 小时（16 核 riscv64）"
ninja "${TARGETS[@]}"
echo ">>> 完成"
for f in "${TARGETS[@]}"; do
  [ -e "$f" ] && printf "  ✅ %-40s %s B\n" "$f" "$(stat -c%s "$f")" || printf "  ❌ %s 缺失\n" "$f"
done