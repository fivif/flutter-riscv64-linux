#!/usr/bin/env bash
# 打包引擎产物为可分发的 tarball（用于 GitHub Release）。
#   usage: 08-package-release.sh <out_dir_name> [输出目录]
#
# 产物约 60 MB 未压缩 / 40 MB 压缩，这是"拿来就能用"的东西：
# 解压后跑 05-install-artifacts.sh 即可，不用编 92 分钟。
set -euo pipefail
OUT="${1:-riscv64-release}"
DST="${2:-$(pwd)}"
ROOT="${FLUTTER_ENGINE:-$(cd "$(dirname "$0")/../.." && pwd)}"
SRC="$ROOT/out/$OUT"
VER="$(awk '/^PRERELEASE /{print $2}' "$ROOT/flutter/third_party/dart/tools/VERSION" 2>/dev/null || echo unknown)"
H="$ROOT/flutter/shell/platform/linux/public/flutter_linux"

NAME="flutter-riscv64-linux-dart${VER}-${OUT}"
STAGE="$(mktemp -d)/$NAME"
mkdir -p "$STAGE"

echo ">>> 收集产物 -> $STAGE"
cp -af "$SRC/libflutter_linux_gtk.so" "$STAGE/" 2>/dev/null || { echo "缺少 libflutter_linux_gtk.so" >&2; exit 1; }
for f in gen_snapshot impellerc font-subset frontend_server_aot.dart.snapshot icudtl.dat; do
  [ -f "$SRC/$f" ] && cp -af "$SRC/$f" "$STAGE/"
done
[ -d "$SRC/shader_lib" ] && cp -af "$SRC/shader_lib" "$STAGE/"

# 头文件（CMake 需要）
mkdir -p "$STAGE/flutter_linux"
cp -af "$H"/*.h "$STAGE/flutter_linux/" 2>/dev/null || true

# Dart SDK（完整，含 snapshots 与 lib）
if [ -d "$SRC/dart-sdk" ]; then
  echo ">>> 打包 Dart SDK"
  cp -a "$SRC/dart-sdk" "$STAGE/dart-sdk"
fi

# 说明文件
cat > "$STAGE/README.txt" <<EOF
Flutter riscv64 Linux engine artifacts
======================================
Dart       : 3.15.0-${VER}.dev
Build dir  : out/${OUT}
Packed     : $(date -u '+%Y-%m-%d %H:%M UTC')

安装
----
  ./install.sh /path/to/flutter

或手动（详见 upstream repo 的 scripts/05-install-artifacts.sh）：
  1. artifacts/engine/linux-riscv64-release/  <- 本目录所有文件
  2. bin/cache/dart-sdk/                      <- 本目录的 dart-sdk/
  3. bin/cache/flutter_tools.snapshot 删掉，跑 flutter --version 重建

验证
----
  flutter --version | grep Tools        # 应显示同版本 Dart
  cd <任意flutter项目> && flutter build linux --release

注意
----
Xvfb 下会看到 "DRI3 error"，这是显示后端问题，不影响构建。
真实 Xorg/Wayland 才能验证 GPU 呈现路径。
EOF

# install.sh
cat > "$STAGE/install.sh" <<'INST'
#!/usr/bin/env bash
set -euo pipefail
FR="${1:?usage: ./install.sh /path/to/flutter}"
HERE="$(cd "$(dirname "$0")" && pwd)"
AE="$FR/bin/cache/artifacts/engine/linux-riscv64-release"
mkdir -p "$AE/flutter_linux"

cp -af "$HERE/libflutter_linux_gtk.so" "$AE/"
for f in gen_snapshot impellerc font-subset frontend_server_aot.dart.snapshot icudtl.dat; do
  [ -f "$HERE/$f" ] && cp -af "$HERE/$f" "$AE/" && chmod +x "$AE/$f"
done
[ -d "$HERE/shader_lib" ]   && cp -af "$HERE/shader_lib"   "$AE/"
[ -d "$HERE/flutter_linux" ] && cp -af "$HERE/flutter_linux"/*.h "$AE/flutter_linux/"

# 宿主工具也放 linux-riscv64/
AH="$FR/bin/cache/artifacts/engine/linux-riscv64"
mkdir -p "$AH/flutter_linux"
for f in impellerc font-subset gen_snapshot; do
  [ -f "$HERE/$f" ] && cp -af "$HERE/$f" "$AH/" && chmod +x "$AH/$f"
done
[ -d "$HERE/shader_lib" ]   && cp -af "$HERE/shader_lib" "$AH/"
[ -d "$HERE/flutter_linux" ] && cp -af "$HERE/flutter_linux"/*.h "$AH/flutter_linux/"

if [ -d "$HERE/dart-sdk" ]; then
  [ -d "$FR/bin/cache/dart-sdk" ] && rm -rf "$FR/bin/cache/dart-sdk"
  cp -a "$HERE/dart-sdk" "$FR/bin/cache/dart-sdk"
fi

# 伪造 stamp，避免 pub get 去下载不存在的 riscv64 zip
C="$FR/bin/cache"
if [ -f "$C/engine.stamp" ]; then
  V=$(cat "$C/engine.stamp")
  for n in flutter_sdk linux-sdk font-subset engine engine-dart-sdk; do echo "$V" > "$C/$n.stamp"; done
fi

# 换 SDK 后必须重建 flutter 工具快照
rm -f "$C/flutter_tools.stamp" "$C/flutter_tools.snapshot"
"$FR/bin/flutter" --version | tail -3

echo "OK. 现在可以: cd <项目> && flutter build linux --release"
INST
chmod +x "$STAGE/install.sh"

echo ">>> 打 tarball"
mkdir -p "$DST"
TAR="$DST/$NAME.tar.gz"
tar -C "$(dirname "$STAGE")" -czf "$TAR" "$NAME"
echo "  $TAR  $(du -h "$TAR" | cut -f1)"
echo "  未压缩 $(du -sh "$STAGE" | cut -f1)"
echo
echo ">>> sha256"
sha256sum "$TAR" | tee "$TAR.sha256"