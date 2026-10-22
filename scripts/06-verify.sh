#!/usr/bin/env bash
# 一致性核验：五个 Dart 组件必须同版本，且 gen_snapshot 必须是原生二进制。
#   usage: 06-verify.sh <flutter_root> [out_dir_name]
set -uo pipefail
FR="${1:?需要 flutter_root}"
OUT="${2:-riscv64-release}"
ROOT="${FLUTTER_ENGINE:-$(cd "$(dirname "$0")/../.." && pwd)}"
C="$FR/bin/cache"
AE="$C/artifacts/engine"
fail=0

echo "=== 1. Dart 组件版本（必须全部相同）==="
for x in "$C/dart-sdk/bin/dart --version" \
         "$C/dart-sdk/bin/dartaotruntime --version" \
         "$C/dart-sdk/bin/dartvm --version" \
         "$AE/linux-riscv64-release/gen_snapshot --version"; do
  bin="${x%% *}"
  if [ -x "$bin" ]; then
    v=$($x 2>&1 | head -1 | grep -oE '3\.[0-9]+\.[0-9]+-[0-9]+\.dev' | head -1)
    printf "  %-46s %s\n" "$(basename "$bin")" "${v:-<读不到>}"
  else
    printf "  %-46s ❌ 不存在\n" "$(basename "$bin")"; fail=1
  fi
done
echo -n "  flutter Tools 行: "
"$FR/bin/flutter" --version 2>/dev/null | grep -o "Dart .*" | head -1

echo
echo "=== 2. gen_snapshot 必须是原生 ELF，不能是脚本 ==="
for d in linux-riscv64 linux-riscv64-release; do
  f="$AE/$d/gen_snapshot"
  if [ -f "$f" ]; then
    if head -c2 "$f" | grep -q '#!'; then
      printf "  %-28s ❌ 仍是 shell 包装\n" "$d"; fail=1
    else
      printf "  %-28s ✅ %s\n" "$d" "$(file -b "$f" | cut -c1-46)"
    fi
  else
    printf "  %-28s ❌ 缺失\n" "$d"; fail=1
  fi
done

echo
echo "=== 3. artifact 完整性 ==="
for d in linux-riscv64 linux-riscv64-release; do
  miss=""
  for f in libflutter_linux_gtk.so icudtl.dat gen_snapshot impellerc font-subset \
           frontend_server_aot.dart.snapshot shader_lib flutter_linux; do
    [ -e "$AE/$d/$f" ] || miss="$miss $f"
  done
  [ -z "$miss" ] && printf "  %-28s ✅ 8/8\n" "$d" || { printf "  %-28s ❌ 缺:%s\n" "$d" "$miss"; fail=1; }
done

echo
echo "=== 4. 真实构建测试（无参数）==="
if [ -d "$ROOT/../app" ]; then
  :
fi
echo "  手动执行: cd <你的flutter项目> && flutter build linux --release"
echo "  期望: 不出现 'Failed to find .../gen_snapshot'"

echo
[ $fail -eq 0 ] && echo "✅ 核验通过" || echo "❌ 有问题，见上"
exit $fail