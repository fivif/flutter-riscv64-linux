# Flutter RISC-V 64 Linux Engine

**在 riscv64 上从源码构建 Flutter Linux 引擎，使 `flutter build linux` 可用。**

[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20riscv64-blue)]()
[![Flutter](https://img.shields.io/badge/flutter-3.41.0-02569B)]()
[![Dart](https://img.shields.io/badge/dart-3.15.0--51.0.dev-0175C2)]()
[![Verified](https://img.shields.io/badge/clean%20build-4490%20steps%20%2F%200%20failures-brightgreen)]()
[![License](https://img.shields.io/badge/license-BSD--3--Clause-lightgrey)](LICENSE)

Flutter 官方未发布 riscv64 Linux 引擎产物，`storage.googleapis.com/flutter_infra_release/flutter/<rev>/linux-riscv64/artifacts.zip` 始终返回 404。
本仓库提供构建该产物所需的脚本、配置、补丁与验证方法，并发布可用的预编译结果。

已完成从零验证：干净构建 4490 步、92 分钟、0 失败；随后无参数执行
`flutter build linux --release` 成功，应用正常运行。

```bash
flutter build linux --debug
flutter build linux --release
```

装好引擎后，任意 Flutter 项目均可使用上述命令，无需额外参数。

---

## 快速开始

### 方式一：使用预编译产物

从 [Releases](../../releases) 下载并安装：

```bash
tar xzf flutter-riscv64-sdk-min-dart3.15.0-51.0.tar.gz
cd flutter-riscv64-linux-dart3.15.0-51.0-release
./install.sh /path/to/flutter
```

| 包 | 大小 | 适用场景 |
|---|---|---|
| `sdk-min-*.tar.gz` | 104.6 MB | 常规使用：引擎 + 编译所需的 2 个 snapshot |
| `engine-*.tar.gz` | 22.7 MB | 已具备匹配的 Dart SDK，仅需引擎产物 |
| `sdk-*.tar.gz.part-00/01/02` | 90 + 90 + 2.4 MB | 完整 SDK（13 个 snapshot），需先执行 `rejoin.sh` |

### 方式二：从源码构建

```bash
git clone https://github.com/flutter/flutter.git
cd flutter && git checkout 6597889f57b4922b95b3917967f8530fcbdd9515
cd engine/src && gclient sync -r 57d5122cd9dcfd0174ba963e61df20a328378c64

git clone <this-repo> engine-build && cd engine-build
export FLUTTER_ENGINE=/path/to/engine/src

./scripts/00-check-env.sh                        # 环境检查
cp scripts/wrappers/clang* "$FLUTTER_ENGINE/buildtools/linux-x64/clang/bin/"
./scripts/01-gen.sh    riscv64-release release   # gn gen
./scripts/02-build.sh  riscv64-release           # 4490 步，92 分钟
./scripts/03-build-dart-sdk.sh          riscv64-release
./scripts/04-rebuild-frontend-server.sh riscv64-release
./scripts/05-install-artifacts.sh /path/to/flutter riscv64-release
./scripts/06-verify.sh            /path/to/flutter riscv64-release
```

源码版本锁定信息见 [`pinned/`](pinned/)，含 271 个依赖的 revision 与产物 sha256。

---

## 背景：缺失的是产物，不是支持

Flutter 的 `flutter_tools` 已将 riscv64 作为一等目标：

```dart
// features.dart:307
const riscv64 = Feature(
  name: 'support for riscv64 architecture',
  configSetting: 'enable-riscv64',
  master: FeatureChannelSetting(available: true, enabledByDefault: true),
);

// artifacts.dart:1530
case TargetPlatform.linux_riscv64: return 'linux-riscv64';

// artifacts.dart:33
genSnapshotRiscv64('gen_snapshot_riscv64'),

// os.dart:636
linux_riscv64('linux-riscv64', 'riscv64'),
```

`TargetPlatform.linux_riscv64`、`HostPlatform.linux_riscv64`、产物目录名 `linux-riscv64`、
feature flag `enable-riscv64` 均已存在。

**工具链支持 riscv64，但 Google 未发布对应的引擎二进制。** 因此本仓库不修改 Flutter，
仅负责构建缺失的产物并将其安装到正确位置。

---

## 核心难点：Dart SDK 必须与引擎同版本

这是构建过程中最容易出错、也最难自查的环节。

引擎源码的 `flutter/third_party/dart/tools/VERSION` 声明 `PRERELEASE 51`。
若所用 `dart-sdk` 二进制来自其他版本（例如 40.0），会形成版本混合状态：

| 症状 | 根因 |
|---|---|
| 窗口出现但全黑，`Can't load Kernel binary: Invalid SDK hash` | `frontend_server` 版本与引擎 VM 不一致 |
| `ERROR: ApiError` / AOT exit 254 | `gen_snapshot` 期望的 hash 与 `app.dill` 不符 |
| `Wrong full snapshot version, expected '9190...' found '79a4...'` | `flutter_tools.snapshot` 或 `dart` 版本不符 |

**注意**：`sdk/version` 文件的内容可能已更新，而 `bin/` 下的二进制仍是旧版本。
文件内容不可作为判断依据，必须执行：

```bash
$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart --version
```

因此 `03-build-dart-sdk.sh` 从引擎源码构建 SDK，确保版本一致。这也解释了
`pinned/DEPS` 中 `dart_revision`（`69672e35b996...`）的前 10 位 `69672e35b9`
为何恰好等于引擎校验 kernel 时使用的 SDK hash。

<details>
<summary>为何不使用 <code>create_sdk</code> 目标</summary>

`ninja "flutter/third_party/dart:create_sdk"`（注意冒号为 GN 的 `toolchain:target`
语法，build.ninja 中写作 `dart$:create_sdk`）需要 3700+ 步，且会触发
`analysis_server` 自身的崩溃：

```
PathNotFoundException(path=.../dart/sdk/version)     # 需先补此文件
Bad state: Future already completed                   # 补齐后仍崩溃，属其自身缺陷
```

对仅需 `flutter build` 的引擎而言，`analysis_server`、`dart2js`、`dartdevc`
均非必需。脚本仅构建必需子集（约 1200 步）。
</details>

---

## 产物安装位置

`flutter_tools/lib/src/artifacts.dart` 的 `_getEngineArtifactsPath()`：

```dart
if (mode == BuildMode.debug || mode == null) {
  return join(engineDir, platformName);              // → linux-riscv64
}
return join(engineDir, platformName + suffix);        // → linux-riscv64-release
```

- **`artifacts/engine/linux-riscv64/`**：debug 引擎与宿主工具
- **`artifacts/engine/linux-riscv64-release/`**：release 引擎

每个目录包含 9 项，缺失任一项会触发对应错误：

| 文件 | 缺失时的错误 |
|---|---|
| `libflutter_linux_gtk.so` | 链接失败 |
| `icudtl.dat` | 运行时失败 |
| `flutter_linux/*.h`（26 个） | `'flutter_linux/flutter_linux.h' file not found` |
| `gen_snapshot` | `Failed to find ".../linux-riscv64-release/gen_snapshot"` |
| `impellerc` | 着色器编译失败 |
| `shader_lib/` | `'#include' : Included file not found ... runtime_effect.glsl` |
| `font-subset` | `IconTreeShakerException: The font-subset utility is missing` |
| `frontend_server_aot.dart.snapshot` | `Invalid SDK hash`，窗口全黑 |
| Dart SDK（`../cache/dart-sdk`） | `Wrong full snapshot version` |

`shader_lib` 必须与 `impellerc` 同级：`shader_compiler.dart:223` 中固定使用
`join(impellerc.parent.path, 'shader_lib')`，其他位置无效。

---

## 两个必要的适配

### clang wrapper（`scripts/wrappers/`）

<details>
<summary><b>a) <code>--rtlib</code> 与 <code>--unwindlib</code> 冲突</b></summary>

Bianbu 的 clang 默认使用 `--rtlib=libgcc`，而 `build/config/compiler/BUILD.gn:645`
在 `use_flutter_cxx` 时注入 `--unwindlib=libunwind`，两者冲突。
wrapper 在链接阶段追加 `--rtlib=compiler-rt`，不影响编译命令。
</details>

<details>
<summary><b>b) <code>-flto</code> 需要 lld</b></summary>

`enable_lto=true`（`build/toolchain/clang.gni:12`）使 release 构建带 `-flto`。
以 bfd 链接 LLVM bitcode 需要 gold 插件：

```
riscv64-linux-gnu-ld.bfd: /usr/lib/llvm-21/lib/LLVMgold.so: error loading plugin
```

Bianbu 的 llvm-21 未提供 `LLVMgold.so`。在 `args.gn` 中设置 `use_lld = true` 无效，
GN 会提示 `Build argument has no effect`（该变量在此构建图中未声明）。

wrapper 仅将带 `-flto` 的链接步骤路由至 `-fuse-ld=lld`，
其余链接与编译步骤保持不变，debug 构建不受影响。
</details>

### Skia 字体族匹配补丁（`patches/`）

修改 `SkFontMgr_fontconfig.cpp`，`+59 / −2`：pattern 侧最多 272 个族名
在字体循环中被重复提取与排序。

该问题不限于 Flutter。723 个字体是 Bianbu 的默认配置，
板上所有 GTK4 / libadwaita / Chromium 程序均受影响。

实测数据（同一宿主、Xvfb、llvmpipe、`dbus-run-session`，3 次取中位数）：

| 配置 | 首帧耗时 | 相对 |
|---|---|---|
| 723 字体，无补丁 | 9043 ms | 1.0× |
| 723 字体，有补丁 | **1616 ms** | **5.6×** |
| 56 字体，无补丁 | 3690 ms | 2.5× |
| 56 字体，有补丁 | **894 ms** | **10.1×** |

补丁与减少字体数量为**替代关系而非叠加**：56 字体下两者分别为 3653 ms 与 3690 ms，无显著差异。

---

## 验证状态

在空的 `out/` 目录上从零完整验证：

| 项目 | 结果 |
|---|---|
| 干净构建 | 4490 步 / 92 分钟 / 0 失败 |
| `gn gen` | 19,632 个目标，1 秒 |
| 引擎产物 | 6 个文件、`shader_lib`、26 个头文件全部生成 |
| Dart SDK（13 个 snapshot、471 个 lib） | 版本一致，`dart run` 与 `dart compile exe` 正常 |
| `flutter --version` | `Tools • Dart 3.15.0 (build 3.15.0-51.0.dev)`，无异常 |
| 无参数 `flutter build linux --release` | exit 0，543 秒 |
| bundle 引擎 sha256 | 与 [`pinned/sdk-hashes.txt`](pinned/sdk-hashes.txt) 完全一致 |
| 应用运行 | 窗口 400×500，3 个 isolate 就绪，`Server started (Port: 53317)`，无黑屏 |

版本一致性（五个组件必须相同）：

```
flutter        3.41.0
dart           3.15.0-51.0.dev
dartaotruntime 3.15.0-51.0.dev
dartvm         3.15.0-51.0.dev
gen_snapshot   3.15.0-51.0.dev     原生 ELF 可执行文件
```

### 已知限制

1. **未构建 profile 引擎**：`flutter build linux --profile` 会失败。
2. **`analysis_server` 快照未生成**：其自身生成快照时崩溃（`Bad state: Future already completed`），与版本无关。不影响 `flutter build`，但 `dart analyze` 可能受影响。
3. **仅以一个应用完成验证**（LocalSend GUI），未运行 Flutter 自身测试套件。
4. **显示验证在 Xvfb + llvmpipe 下完成**：日志中的 `DRI3 error` 属显示环境限制，不影响构建；真实 Xorg / Wayland 环境未验证。
5. **`bin/resources/devtools/` 易遗漏**：缺失时 `flutter --version` 抛出 `Could not find directory .../resources/devtools`。脚本已覆盖此项。

---

## 环境与版本锁定

| 项 | 值 |
|---|---|
| 硬件 | SpacemiT K3（16 核：8×X100 @2.4 GHz + 8×A100 @2.0 GHz），7.7 GiB |
| 系统 | Bianbu 4.0.1，kernel 6.18.3-generic，riscv64（rv64imafdcvh，VLEN=256） |
| 工具链 | clang 21.1.8，ninja 1.13.2，gn 1000，lld 21 |
| Flutter | 3.41.0，engine `57d5122cd9dcfd0174ba963e61df20a328378c64` |

[`pinned/`](pinned/) 以 40 KB 文本锁定版本，替代约 2 GB 源码：

```
pinned/DEPS                  271 个依赖的 revision（skia 09b14219…，dart 69672e35…）
pinned/gclient-solution      gclient 配置
pinned/flutter.version       framework 6597889f57 / engine 57d5122c
pinned/dart.VERSION          3.15.0-51.0.dev
pinned/sdk-hashes.txt        6 个产物 sha256
pinned/gn-args-notes.txt     必需与无效的构建参数
```

引擎源码由 271 个独立仓库组成（约 2 GB），通过 `gclient sync` 按 revision 拉取，
不纳入本仓库。`DEPS` 的语义即为按 revision 获取，各组件的许可证由对应上游负责。

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/01-环境准备](docs/01-环境准备.md) | 系统依赖、`gn --script-executable`、libpci 软链、clang wrapper 原理 |
| [docs/02-踩坑记录](docs/02-踩坑记录.md) | 16 项问题的症状、根因与修复方法，附速查表 |
| [docs/03-实测数据](docs/03-实测数据.md) | 构建耗时、产物体积、字体基准、AOT 收益、测量注意事项 |

---

## 相关项目

- **[fivif/localsend-riscv64](https://github.com/fivif/localsend-riscv64)**：
  使用本引擎构建的 LocalSend 桌面 GUI，含 deb 打包与端到端传输验证（手机 → 板子，MD5 一致）
- [Flutter Engine 源码](https://github.com/flutter/flutter/tree/master/engine)

---

## License

本仓库内容（脚本、补丁、文档）以 BSD-3-Clause 发布，与 Flutter 引擎一致。
Flutter 引擎本身版权归 Google 及贡献者所有，见上游 `LICENSE` 与 [NOTICE](NOTICE)。
