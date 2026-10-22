#!/usr/bin/env bash
# 把构建产物安装进 flutter 的缓存，让 flutter build linux 不再需要 --local-engine。
#   usage: 05-install-artifacts.sh <flutter_root> <out_dir_name>
#
# flutter 的目录规则（flutter_tools/lib/src/artifacts.dart: _getEngineArtifactsPath）：
#   mode == debug || mode == null  →  artifacts/engine/<plat>
#   mode != debug                  →  artifacts/engine/<plat>-<mode>
# 所以 linux-riscv64/ = debug 引擎 + 宿主工具；linux-riscv64-release/ = release 引擎。
set -euo pipefail
FR="${1:?需要 flutter_root}"
OUT="${2:-riscv64-release}"
ROOT="${FLUTTER_ENGINE:-$(cd "$(dirname "$0")/../.." && pwd)}"
SRC="$ROOT/out/$OUT"
C="$FR/bin/cache"
AE="$C/artifacts/engine"
H="$ROOT/flutter/shell/platform/linux/public/flutter_linux"

[ -f "$SRC/libflutter_linux_gtk.so" ] || { echo "找不到 $SRC/libflutter_linux_gtk.so，先跑 02-build.sh" >&2; exit 1; }

is_debug=0
grep -qE '^is_debug = true' "$SRC/args.gn" 2>/dev/null && is_debug=1
if [ $is_debug -eq 1 ]; then DST="$AE/linux-riscv64"; else DST="$AE/linux-riscv64-release"; fi

echo ">>> 安装到 $DST"
mkdir -p "$DST/flutter_linux"

# 引擎本体
cp -af "$SRC/libflutter_linux_gtk.so" "$DST/"
# ICU 数据
[ -f "$SRC/icudtl.dat" ] && cp -af "$SRC/icudtl.dat" "$DST/"
# 26 个公开头（含 umbrella flutter_linux.h）
cp -af "$H"/*.h "$DST/flutter_linux/"
# 工具链
for t in gen_snapshot impellerc font-subset frontend_server_aot.dart.snapshot; do
  [ -f "$SRC/$t" ] && cp -af "$SRC/$t" "$DST/" && chmod +x "$DST/$t"
done
# shader_lib 必须与 impellerc 同级（shader_compiler.dart:223）
[ -d "$SRC/shader_lib" ] && cp -af "$SRC/shader_lib" "$DST/"

# 宿主工具也要在 linux-riscv64/（debug 目录兼作 host 目录）
if [ "$DST" != "$AE/linux-riscv64" ]; then
  for t in impellerc font-subset shader_lib; do
    [ -e "$SRC/$t" ] && cp -af "$SRC/$t" "$AE/linux-riscv64/"
  done
fi
[ -f "$SRC/gen_snapshot" ] && cp -af "$SRC/gen_snapshot" "$AE/linux-riscv64/" 2>/dev/null || true

echo ">>> 安装 Dart SDK（版本必须与引擎一致）"
if [ -d "$SRC/dart-sdk" ]; then
  [ -d "$C/dart-sdk" ] && [ ! -d "$C/dart-sdk.old" ] && mv "$C/dart-sdk" "$C/dart-sdk.old"
  rm -rf "$C/dart-sdk"
  cp -a "$SRC/dart-sdk" "$C/dart-sdk"
  # flutter 从这里取 frontend_server
  if [ -f "$SRC/frontend_server_aot.dart.snapshot" ]; then
    cp -af "$SRC/frontend_server_aot.dart.snapshot" "$C/dart-sdk/bin/snapshots/"
  fi
fi

echo ">>> 伪造缓存 stamp（否则 pub get 会去下载不存在的 riscv64 zip → 404）"
if [ -f "$C/engine.stamp" ]; then
  V=$(cat "$C/engine.stamp")
  for n in flutter_sdk linux-sdk font-subset engine engine-dart-sdk; do
    echo "$V" > "$C/$n.stamp"
  done
  echo "  stamp = $V"
fi
mkdir -p "$C/pkg" "$AE/common"
ls -d "$C/pkg/sky_engine" "$C/pkg/flutter_gpu" >/dev/null 2>&1 || \
  echo "  ⚠️  bin/cache/pkg/{sky_engine,flutter_gpu} 缺失，isUpToDateInner 会失败"

echo ">>> 强制重建 flutter_tools 快照（换 SDK 后必须）"
rm -f "$C/flutter_tools.stamp" "$C/flutter_tools.snapshot"
"$FR/bin/flutter" --version 2>&1 | tail -3

echo ">>> 完成"