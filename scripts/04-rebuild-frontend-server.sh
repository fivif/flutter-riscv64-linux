#!/usr/bin/env bash
# frontend_server 决定 kernel 里写入的 SDK hash。
# 必须用同版本 SDK 重建，否则运行时 "Invalid SDK hash" 黑屏。
#   usage: 04-rebuild-frontend-server.sh <out_dir_name>
set -euo pipefail
OUT="${1:-riscv64-release}"
ROOT="${FLUTTER_ENGINE:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT/out/$OUT"

echo ">>> ninja frontend_server_aot（约 383 步）"
ninja frontend_server_aot
ls -la frontend_server_aot.dart.snapshot | awk '{print "  " $5 " B  " $9}'