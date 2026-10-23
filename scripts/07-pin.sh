#!/usr/bin/env bash
# 抓取版本锁定信息到 pinned/，让别人能精确复现这次构建。
#   usage: 07-pin.sh <out_dir_name>
set -euo pipefail
OUT="${1:-riscv64-release}"
ROOT="${FLUTTER_ENGINE:-$(cd "$(dirname "$0")/../.." && pwd)}"
P="$(cd "$(dirname "$0")/../pinned" && pwd)"
D="$ROOT/out/$OUT"

echo ">>> 抓 DEPS"
# engine/src/DEPS 与 flutter 仓库根 DEPS 内容一致（gclient 的 deps_file 指向它）
if [ -f "$ROOT/../DEPS" ]; then
  cp "$ROOT/../DEPS" "$P/DEPS"
elif [ -f "$ROOT/DEPS" ]; then
  cp "$ROOT/DEPS" "$P/DEPS"
fi
[ -f "$P/DEPS" ] && echo "  ${P}/DEPS  $(stat -c%s "$P/DEPS") B"

echo ">>> 抓 .gclient"
for f in "$ROOT/../.gclient" "$ROOT/.gclient"; do
  [ -f "$f" ] && cp "$f" "$P/gclient-solution" && echo "  $(stat -c%s "$P/gclient-solution") B" && break
done

echo ">>> 抓 Dart VERSION"
V="$ROOT/flutter/third_party/dart/tools/VERSION"
[ -f "$V" ] && cp "$V" "$P/dart.VERSION" && echo "  PRERELEASE = $(awk '/^PRERELEASE /{print $2}' "$V")"

echo ">>> 抓产物 sha256"
{
  echo "# 干净构建产物 sha256 - out/$OUT - $(date '+%Y-%m-%d %H:%M')"
  for f in libflutter_linux_gtk.so gen_snapshot impellerc font-subset \
           frontend_server_aot.dart.snapshot icudtl.dat; do
    [ -f "$D/$f" ] && sha256sum "$D/$f" | sed "s|$D/||"
  done
} > "$P/sdk-hashes.txt"
echo "  $(grep -c '^[0-9a-f]' "$P/sdk-hashes.txt") 个产物"

echo ">>> 关键 revision"
grep -oE "'(skia|dart)_revision': '[0-9a-f]+'" "$P/DEPS" 2>/dev/null | sed 's/^/  /'