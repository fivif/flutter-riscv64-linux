#!/usr/bin/env bash
# 检查构建 riscv64 Flutter 引擎所需的环境。
set -uo pipefail
fail=0
chk(){ printf "  %-42s %s\n" "$1" "${2:-}"; }
need(){ command -v "$1" >/dev/null 2>&1 && chk "$1" "✅ $(command -v "$1")" || { chk "$1" "❌ 缺失"; fail=1; }; }

echo "=== 必需工具 ==="
need ninja
need gn
need clang
need clang++
need python3
need pkg-config

echo
echo "=== 版本 ==="
chk "gn"        "$(gn --version 2>/dev/null)"
chk "ninja"     "$(ninja --version 2>/dev/null)"
chk "clang"     "$(clang --version 2>/dev/null | head -1)"
chk "python3"   "$(python3 --version 2>/dev/null)"

echo
echo "=== 架构检查 ==="
chk "uname -m"  "$(uname -m)"
[ "$(uname -m)" = "riscv64" ] || { chk "" "⚠️  非 riscv64 主机，本文档流程针对原生构建"; }

echo
echo "=== 关键坑位 =="
# 1) llvm 版本（-flto 需要 lld）
LLVM=$(clang --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
chk "llvm major" "$LLVM"
if [ -e "/usr/lib/llvm-$LLVM/lib/LLVMgold.so" ]; then
  chk "LLVMgold.so" "存在（bfd LTO 可用）"
else
  chk "LLVMgold.so" "缺失 → 必须用 lld 链接 LTO（本仓库 wrapper 已处理）"
fi

# 2) libpci 头文件位置（SystemInfo 需要）
if [ -f /usr/include/pci/pci.h ]; then
  chk "pci/pci.h" "/usr/include/pci/pci.h ✅"
elif [ -f /usr/include/riscv64-linux-gnu/pci/pci.h ]; then
  chk "pci/pci.h" "在 riscv64-linux-gnu/ 下，需要软链（见 docs/01）"
  fail=1
else
  chk "pci/pci.h" "❌ 未找到（apt install libpci-dev）"
  fail=1
fi

# 3) python 脚本执行器
chk "gn --script-executable" "必须显式传 /usr/bin/python3（见 docs/01）"

echo
[ $fail -eq 0 ] && echo "✅ 环境检查通过" || echo "⚠️  有未满足项，见上"
exit $fail