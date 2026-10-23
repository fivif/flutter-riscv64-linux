# pinned/ —— 源码版本锁定

本目录**不放源码**（引擎源码约 2 GB，由 271 个独立仓库组成，见 ../docs/05）。

放的是「我们构建时用的到底是哪一版」的**可验证记录**，让别人能精确复现。

---

## 文件清单

| 文件 | 大小 | 作用 |
|---|---|---|
| `flutter.version` | 293 B | framework / engine revision |
| `dart.VERSION` | 892 B | 引擎内 Dart 版本（`PRERELEASE 51`） |
| `DEPS` | **40 KB** | **全部 271 个第三方依赖的 revision 清单** |
| `gclient-solution` | 184 B | gclient 配置（`deps_file: DEPS`） |
| `sdk-hashes.txt` | 567 B | 干净构建产物的 sha256（验证用） |
| `gn-args-notes.txt` | 1.1 KB | 哪些 args 必需、哪个无效 |

**`DEPS` 才是真正的「源码快照」** —— 40 KB 的文本替代 2 GB 代码。

---

## 关键 revision（从 DEPS 读出）

```
skia_revision    09b14219f98e0a73f6a33497e1aa8cd5924a7611
dart_revision    69672e35b9964b2e2af57923f6b19f9fa11a4042
```

⚠️ **注意 `dart_revision` 与 kernel hash 的关系**：

`69672e35b9964b2e2af57923f6b19f9fa11a4042` 的前 10 位是 **`69672e35b9`**，
这正是引擎 VM 校验 kernel 文件头时使用的 SDK hash。

这不是巧合 —— SDK hash 是 Dart revision 的派生值。反过来说：

> **如果你手改 kernel hash 去凑某个值，说明你的 `dart_revision` 与实际用的
> dart-sdk 二进制不一致。** 正确做法是从源码编同版本 SDK（见 ../scripts/03）。

我们一开始就是混用了 40.0 的 dart-sdk，才需要改 177 段 kernel hash；
统一到 51.0 之后 hash 天然对齐，补丁全部删掉。

---

## 怎么复现源码

Flutter 引擎不用 `git clone` 单仓库，用 `gclient`：

```bash
# 1. depot_tools（提供 gclient）
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PWD/depot_tools:$PATH"

# 2. flutter 仓库，checkout 到我们用的 revision
git clone https://github.com/flutter/flutter.git
cd flutter
git checkout 6597889f57b4922b95b3917967f8530fcbdd9515

# 3. 拉引擎依赖（约 2 GB，271 个仓库）
cd engine/src
gclient sync -r 57d5122cd9dcfd0174ba963e61df20a328378c64
```

第 3 步读的就是 `engine/src/DEPS`。本目录的 `DEPS` 是**快照副本**，
作用是「即使上游改动或删除也能查到当时的清单」。

想完全确定用的是我们这一版，可以把本目录的 `DEPS` 覆盖过去：

```bash
cp ../pinned/DEPS engine/src/DEPS
gclient sync
```

---

## 验证产物是否与我们一致

```bash
cd <out_dir>
sha256sum -c ../pinned/sdk-hashes.txt
```

期望全部 `OK`。如果 sha256 不符，可能是：

- 编译器版本不同（我们用的 clang **21.1.8**）
- args 有差异（对比 `../args/`）
- 源码 revision 不同（对比 `flutter.version` + `DEPS`）

---

## 这份清单是怎么抓的

```bash
# DEPS（flutter-tool 副本与 engine/src/DEPS 内容一致，40 KB / 1016 行）
cp <engine>/flutter-tool/DEPS                       pinned/DEPS
cp <engine>/.gclient                                pinned/gclient-solution
cp <engine>/flutter/third_party/dart/tools/VERSION  pinned/dart.VERSION
sha256sum out/clean-rel/{libflutter_linux_gtk.so,gen_snapshot,impellerc,
                         font-subset,frontend_server_aot.dart.snapshot,
                         icudtl.dat} > pinned/sdk-hashes.txt
```

抓取时间：**2026-10-23 09:33**（板子重启后、干净构建产物齐全时）
