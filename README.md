# Flutter RISC-V 64 Linux Engine

**在 riscv64 上从源码构建 Flutter Linux 引擎，让 `flutter build linux` 正常工作。**

[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20riscv64-blue)]()
[![Flutter](https://img.shields.io/badge/flutter-3.41.0-02569B)]()
[![Dart](https://img.shields.io/badge/dart-3.15.0--51.0.dev-0175C2)]()
[![Verified](https://img.shields.io/badge/clean%20build-4490%20steps%20%2F%200%20failures-brightgreen)]()
[![License](https://img.shields.io/badge/license-BSD--3--Clause-lightgrey)](LICENSE)

Flutter 官方从未发布 riscv64 Linux 引擎产物 —— `storage.googleapis.com/flutter_infra_release/flutter/<rev>/linux-riscv64/artifacts.zip` 一律 404。
本仓库提供构建它所需的全部脚本、配置、补丁与验证，并发布可直接使用的产物。

**已实测**：干净构建 4490 步 / 92 分钟 / 0 失败 → 无参数 `flutter build linux --release` → 应用正常运行。

```bash
# 装好之后，任何 Flutter 项目都能直接跑，不需要任何特殊参数
flutter build linux --debug
flutter build linux --release
```

---

## 快速开始

### 路线 A：直接用（推荐）

从 [Releases](../../releases) 下载，解压安装，**不用编 92 分钟**。

```bash
tar xzf flutter-riscv64-sdk-min-dart3.15.0-51.0.tar.gz
cd flutter-riscv64-linux-dart3.15.0-51.0-release
./install.sh /path/to/flutter
```

| 包 | 大小 | 适用 |
|---|---|---|
| `sdk-min-*.tar.gz` | 104.6 MB | **多数人**：引擎 + 编译所需的 2 个 snapshot |
| `engine-*.tar.gz` | 22.7 MB | 已有匹配 dart-sdk，只要引擎产物 |
| `sdk-*.tar.gz.part-00/01/02` | 90+90+2.4 MB | 完整 SDK（13 个 snapshot），先跑 `rejoin.sh` |

### 路线 B：自己编

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

源码版本锁定在 [`pinned/`](pinned/)（271 个依赖的 revision + 产物 sha256）。

---

## 为什么需要这个

Flutter 的 `flutter_tools` **原生支持 riscv64**：

```dart
// features.dart
const riscv64 = Feature(
  name: 'support for riscv64 architecture',
  configSetting: 'enable-riscv64',
  master: FeatureChannelSetting(available: true, enabledByDefault: true),
);

// artifacts.dart
case TargetPlatform.linux_riscv64: return 'linux-riscv64';   // 1530 行
genSnapshotRiscv64('gen_snapshot_riscv64'),                  //  33 行

// os.dart
linux_riscv64('linux-riscv64', 'riscv64'),                   // 636 行
```

**工具链认得 riscv64，缺的只是 Google 没有发布预编译的引擎二进制。**
所以本仓库不修改 Flutter，只做两件事：编出缺失的产物，把它放到正确位置。

---

## 核心难点：Dart SDK 必须与引擎同版本

这是整件事里最容易翻车、也最难自查的地方。

引擎源码的 `flutter/third_party/dart/tools/VERSION` 写着 `PRERELEASE 51`，
如果你的 `dart-sdk` 二进制来自别处（比如某个 40.0 的包），就会出现
**「源是 51.0，二进制是 40.0」** 的混合状态：

| 症状 | 根因 |
|---|---|
| 窗口出现但全黑，`Can't load Kernel binary: Invalid SDK hash` | `frontend_server` ≠ 引擎 VM |
| `ERROR: ApiError` / AOT exit 254 | `gen_snapshot` 期望的 hash ≠ `app.dill` |
| `Wrong full snapshot version, expected '9190...' found '79a4...'` | `flutter_tools.snapshot` 或 `dart` 版本不符 |

**陷阱**：`sdk/version` 文件可能写着新版本，`bin/` 下的二进制却是旧的。
看文件会被骗，必须实际执行：

```bash
$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart --version
# 不要相信 cat $FLUTTER_ROOT/bin/cache/dart-sdk/version
```

所以 `03-build-dart-sdk.sh` **从引擎源码自己编**，天然同版本。这也是为什么
`pinned/DEPS` 里的 `dart_revision`（`69672e35b996...`）前 10 位
`69672e35b9` 恰好等于引擎校验 kernel 时用的 SDK hash。

<details>
<summary>为什么不用 <code>create_sdk</code></summary>

`ninja "flutter/third_party/dart:create_sdk"`（注意**冒号**，GN 的
`toolchain:target` 语法，build.ninja 里是 `dart$:create_sdk`）会编 3700+ 步，
而且会撞 `analysis_server` 自身崩溃：

```
PathNotFoundException(path=.../dart/sdk/version)     # 先补这个文件
Bad state: Future already completed                   # 补完还是崩，它自己的 bug
```

对只需要 `flutter build` 的引擎来说，`analysis_server` / `dart2js` / `dartdevc`
都是废重。脚本只编必需子集（约 1200 步）。
</details>

---

## 引擎产物放哪

`flutter_tools/lib/src/artifacts.dart` 的 `_getEngineArtifactsPath()`：

```dart
if (mode == BuildMode.debug || mode == null) {
  return join(engineDir, platformName);              // → linux-riscv64
}
return join(engineDir, platformName + suffix);        // → linux-riscv64-release
```

- **`artifacts/engine/linux-riscv64/`** = debug 引擎 + **宿主工具**
- **`artifacts/engine/linux-riscv64-release/`** = release 引擎

每个目录需要 9 样，缺任何一个都会报特定错误：

| 文件 | 缺失时的报错 |
|---|---|
| `libflutter_linux_gtk.so` | 链接失败 |
| `icudtl.dat` | 运行时失败 |
| `flutter_linux/*.h`（26 个） | `'flutter_linux/flutter_linux.h' file not found` |
| `gen_snapshot` | `Failed to find ".../linux-riscv64-release/gen_snapshot"` |
| `impellerc` | 着色器编译失败 |
| `shader_lib/` | `'#include' : Included file not found ... runtime_effect.glsl` |
| `font-subset` | `IconTreeShakerException: The font-subset utility is missing` |
| `frontend_server_aot.dart.snapshot` | `Invalid SDK hash` + 黑屏 |
| Dart SDK（`../cache/dart-sdk`） | `Wrong full snapshot version` |

`shader_lib` 必须**紧邻** `impellerc`（`shader_compiler.dart:223` 硬编码了
`join(impellerc.parent.path, 'shader_lib')`），放别处无效。

---

## 两个必要的 shim / 补丁

### clang wrapper（`scripts/wrappers/`）

<details>
<summary><b>a) <code>--rtlib</code> 与 <code>--unwindlib</code> 冲突</b></summary>

Bianbu 的 clang 默认 `--rtlib=libgcc`，而 `build/config/compiler/BUILD.gn:645`
在 `use_flutter_cxx` 时注入 `--unwindlib=libunwind`，两者冲突。
wrapper 在**链接**时加 `--rtlib=compiler-rt`，不污染编译命令。
</details>

<details>
<summary><b>b) <code>-flto</code> 需要 lld</b></summary>

`enable_lto=true`（`build/toolchain/clang.gni:12`）让 release 带 `-flto`，
用 bfd 链接 LLVM bitcode 需要 gold 插件：

```
riscv64-linux-gnu-ld.bfd: /usr/lib/llvm-21/lib/LLVMgold.so: error loading plugin
```

**Bianbu 的 llvm-21 不提供 `LLVMgold.so`。** 而在 `args.gn` 里写 `use_lld = true`
没用 —— GN 会警告 `Build argument has no effect`（该变量在这个图里未声明）。

wrapper 只把**带 `-flto` 的链接步骤**路由到 `-fuse-ld=lld`，
其余链接和所有编译步骤不变（debug 完全不受影响）。
</details>

### Skia 字体族匹配补丁（`patches/`）

`+59 / −2`，改 `SkFontMgr_fontconfig.cpp`：pattern 侧最多 272 个族名在字体循环里
被重复抽取、重复排序。

**这不是 Flutter 专属问题** —— 723 个字体是 Bianbu 的默认配置，
板上每个 GTK4 / libadwaita / Chromium 程序都在付这笔钱。

实测（同宿主、同 Xvfb、llvmpipe、`dbus-run-session`，3 次取中位数）：

| 配置 | 首帧 | 相对 |
|---|---|---|
| 723 字体，无补丁 | 9043 ms | 1.0× |
| 723 字体，有补丁 | **1616 ms** | **5.6×** |
| 56 字体，无补丁 | 3690 ms | 2.5× |
| 56 字体，有补丁 | **894 ms** | **10.1×** |

补丁与「减少字体数」是**替代关系，不是叠加**（56 字体下 3653 vs 3690，无差别）。

---

## 验证状态

在空的 `out/` 目录上从零完整走了一遍：

| 项目 | 结果 |
|---|---|
| 干净构建 | **4490 步 / 92 分钟 / 0 失败** |
| `gn gen` | 19,632 个目标，1 秒 |
| 引擎产物 | 6 个文件 + `shader_lib` + 26 头文件，全部生成 |
| Dart SDK（13 个 snapshot + 471 lib） | 全部 51.0，`dart run` / `dart compile exe` 正常 |
| `flutter --version` | `Tools • Dart 3.15.0 (build 3.15.0-51.0.dev)`，零异常 |
| **无参数 `flutter build linux --release`** | **exit 0，543 秒** |
| bundle 引擎 sha256 | 与 [`pinned/sdk-hashes.txt`](pinned/sdk-hashes.txt) **完全一致** |
| 应用运行 | 窗口 400×500、3 isolate 就绪、`Server started (Port: 53317)`、无黑屏 |

版本一致性（五个组件必须相同）：

```
flutter        3.41.0
dart           3.15.0-51.0.dev
dartaotruntime 3.15.0-51.0.dev
dartvm         3.15.0-51.0.dev
gen_snapshot   3.15.0-51.0.dev     ← 原生 ELF，不是脚本包装
```

### 已知限制

1. **没有 profile 引擎** —— `flutter build linux --profile` 会失败。
2. **`analysis_server` 快照未生成** —— 它自己生成快照时崩（`Bad state: Future already completed`），与版本无关。不影响 `flutter build`，但 `dart analyze` 可能受影响。
3. **只用过一个应用验证**（LocalSend GUI），没跑 Flutter 自己的测试套件。
4. **显示验证在 Xvfb + llvmpipe 下完成** —— 日志里的 `DRI3 error` 是显示环境问题，不影响构建；真实 Xorg / Wayland 未验证。
5. **`bin/resources/devtools/` 容易漏** —— 缺了它 `flutter --version` 会抛 `Could not find directory .../resources/devtools`。脚本已覆盖。

---

## 环境与版本锁定

| 项 | 值 |
|---|---|
| 硬件 | SpacemiT K3（16 核：8×X100@2.4GHz + 8×A100@2.0GHz），7.7 GiB |
| 系统 | Bianbu 4.0.1，kernel 6.18.3-generic，riscv64（rv64imafdcvh，VLEN=256） |
| 工具链 | clang 21.1.8 · ninja 1.13.2 · gn 1000 · lld 21 |
| Flutter | 3.41.0 · engine `57d5122cd9dcfd0174ba963e61df20a328378c64` |

[`pinned/`](pinned/) 用 40 KB 文本锁定全部版本，替代约 2 GB 源码：

```
pinned/DEPS                  271 个依赖的 revision（skia 09b14219… / dart 69672e35…）
pinned/gclient-solution      gclient 配置
pinned/flutter.version       framework 6597889f57 / engine 57d5122c
pinned/dart.VERSION          3.15.0-51.0.dev
pinned/sdk-hashes.txt        6 个产物 sha256
pinned/gn-args-notes.txt     哪些 args 必须、哪个无效
```

引擎源码由 271 个独立仓库组成（约 2 GB），按 revision 由 `gclient sync` 拉取，
**不复制进本仓库** —— 那是 `DEPS` 的语义，也让各上游的许可证归各上游负责。

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/01-环境准备](docs/01-环境准备.md) | 系统依赖、`gn --script-executable`、libpci 软链、clang shim 原理 |
| [docs/02-踩坑记录](docs/02-踩坑记录.md) | 16 条，症状 → 根因 → 修法，附速查表 |
| [docs/03-实测数据](docs/03-实测数据.md) | 构建耗时、产物体积、字体基准、AOT 掩盖效应、测量陷阱 |

---

## 相关项目

- **[fivif/localsend-riscv64](https://github.com/fivif/localsend-riscv64)** —— 用本引擎编出的
  LocalSend 桌面 GUI，含 deb 打包与端到端传输验证（手机 → 板子，MD5 一致）
- [Flutter Engine 源码](https://github.com/flutter/flutter/tree/master/engine)

---

## License

本仓库内容（脚本、补丁、文档）以 **BSD-3-Clause** 发布，与 Flutter 引擎一致。
Flutter 引擎本身版权归 Google 及贡献者，见上游 `LICENSE` 与 [NOTICE](NOTICE)。
