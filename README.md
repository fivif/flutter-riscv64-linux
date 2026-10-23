# flutter-riscv64-linux

**从源码构建可用的 RISC-V 64 Flutter Linux 引擎** —— 构建配方、补丁、脚本、验证方法。

产出的引擎能让 `flutter build linux` 在 riscv64 上正常工作（Flutter 官方从未发布
riscv64 Linux 产物，所有 `storage.googleapis.com/.../linux-riscv64/artifacts.zip` 都是 404）。

> 本仓库**不是** Flutter 的分支，也不包含引擎源码。
> 它是「怎么把 Google 的引擎在 riscv64 上编出来并用起来」的完整配方。

---

## 这是什么，不是什么

| | |
|---|---|
| ✅ 是 | 构建脚本、`args.gn`、clang shim、Skia 字体补丁、安装/验证脚本、逐条踩坑记录 |
| ✅ 是 | [`pinned/`](pinned/) —— 271 个依赖的 revision 锁定 + 产物 sha256 |
| ✅ 是 | [Releases](../../releases) —— 构建好的引擎产物（约 60 MB，解压即用） |
| ❌ 不是 | Flutter 引擎源码（**271 个仓库、约 2 GB**，见 [docs/05](docs/05-为什么不放源码.md)） |
| ❌ 不是 | 官方支持。Flutter 官方没有 riscv64 Linux 目标 |

## 两条路，按需要选

### 只要能用 → 下 Release

到 [Releases](../../releases) 下载引擎产物，解压后跑 `scripts/05-install-artifacts.sh`。
**不用编 92 分钟。**

### 要自己编 → 走脚本 + pinned 锁版本

源码来自 Flutter 官方，用 `gclient` 按 revision 拉取：

```bash
git clone https://github.com/flutter/flutter.git
cd flutter && git checkout 6597889f57b4922b95b3917967f8530fcbdd9515
cd engine/src && gclient sync -r 57d5122cd9dcfd0174ba963e61df20a328378c64
```

`pinned/DEPS` 里 pin 了全部 271 个依赖的确切 revision（skia、dart、icu、harfbuzz…）。

**为什么源码不进仓库**：271 个仓库、约 2 GB、每个组件独立许可证、
`DEPS` 语义是「按 revision 拉取」而不是「复制文件」。
详述见 [docs/05-为什么不放源码.md](docs/05-为什么不放源码.md)。

---

## 已验证环境

| 项 | 值 |
|---|---|
| 硬件 | SpacemiT K3（16 核：8×X100@2.4GHz + 8×A100@2.0GHz），7.7 GiB RAM |
| 系统 | Bianbu 4.0.1，kernel 6.18.3-generic，riscv64 |
| ISA | rv64imafdcvh，VLEN=256 |
| 工具链 | clang 21.1.8，ninja 1.13.2，gn 1000，lld-21 |
| Flutter | 3.41.0，engine revision `57d5122cd9dcfd0174ba963e61df20a328378c64` |
| Dart | 3.15.0-51.0.dev（**必须与引擎源码一致**，见下） |

---

## 完整流程

```bash
# 0. 环境检查（会告诉你缺什么、哪里有坑）
./scripts/00-check-env.sh

# 1. 打 clang shim（解决 libgcc/libunwind 冲突 + LTO 用 lld）
ENGINE_SRC=/path/to/engine/src
cp scripts/wrappers/clang scripts/wrappers/clang++ \
   "$ENGINE_SRC/buildtools/linux-x64/clang/bin/"

# 2. 生成 + 构建引擎（4490 步，实测 92 分钟）
export FLUTTER_ENGINE=$ENGINE_SRC
./scripts/01-gen.sh    riscv64-release release
./scripts/02-build.sh  riscv64-release

# 3. Dart SDK + frontend_server（关键！见下一节）
./scripts/03-build-dart-sdk.sh           riscv64-release
./scripts/04-rebuild-frontend-server.sh  riscv64-release

# 4. 装进 flutter 缓存
./scripts/05-install-artifacts.sh /path/to/flutter riscv64-release

# 5. 核验
./scripts/06-verify.sh /path/to/flutter riscv64-release

# 6. 锁定版本（抓 DEPS / .gclient / sha256）
./scripts/07-pin.sh riscv64-release

# 7. 打包可分发的产物（约 60 MB）
./scripts/08-package-release.sh riscv64-release ./dist
```

装好之后，**任何 Flutter 项目**都可以直接：

```bash
flutter build linux --debug
flutter build linux --release
```

不需要 `--local-engine`，不需要 `--no-tree-shake-icons`。

### 脚本一览

| 脚本 | 作用 | 实测耗时 |
|---|---|---|
| `00-check-env.sh` | 环境检查，指出缺什么、哪里有坑 | 秒级 |
| `01-gen.sh` | `gn gen`（**必须带 `--script-executable`**） | 1 秒 |
| `02-build.sh` | 引擎核心 5 个产物 | **92 分钟**（4490 步） |
| `03-build-dart-sdk.sh` | 从源码编 Dart SDK（含 snapshots） | 20~30 分钟 |
| `04-rebuild-frontend-server.sh` | 重建 frontend_server（决定 kernel hash） | 7 分钟（383 步） |
| `05-install-artifacts.sh` | 铺进 flutter 缓存 + 伪造 stamp | 1 分钟 |
| `06-verify.sh` | 一致性核验（5 个 Dart 组件必须同版本） | 秒级 |
| `07-pin.sh` | 抓版本锁定信息到 `pinned/` | 秒级 |
| `08-package-release.sh` | 打包 60 MB 分发 tarball | 1 分钟 |

---

> ⚠️ **构建前必读**：同一时间只跑一个 ninja，并用 `-j 8` 而不是默认 16。
> 并发构建会把 16 核 / 7.7 GiB 的板子压到 sshd 无法握手，见
> [docs/04-并发构建的代价.md](docs/04-并发构建的代价.md)。

## 最重要的一个坑：Dart SDK 必须与引擎同版本

这是整件事里最容易翻车、也最难自查的地方。

引擎源码里有 `flutter/third_party/dart/tools/VERSION`：

```
CHANNEL dev
MAJOR 3
MINOR 15
PATCH 0
PRERELEASE 51        ← 源码是 3.15.0-51.0
PRERELEASE_PATCH 0
```

如果你的 `dart-sdk` 二进制是从别处拿的（比如某个 40.0 的包），就会出现
**「源是 51.0，二进制是 40.0」** 的混合状态。后果：

| 症状 | 根因 |
|---|---|
| 窗口出现但全黑，日志 `Can't load Kernel binary: Invalid SDK hash` | `frontend_server` 版本 ≠ 引擎 VM 版本 |
| `ERROR: ApiError` / AOT snapshotter exit 254 | `gen_snapshot` 期望的 hash ≠ `app.dill` 里写的 |
| `Wrong full snapshot version, expected '9190...' found '79a4...'` | `flutter_tools.snapshot` 或 `dart` 与 VM 不同版本 |

**更阴的是：`sdk/version` 文件可能写着新版本，`bin/` 下的二进制却是旧的。**
看文件会被骗，必须实际执行 `--version`：

```bash
$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart --version
# 不要相信 cat $FLUTTER_ROOT/bin/cache/dart-sdk/version
```

所以我们用 `03-build-dart-sdk.sh` **从引擎源码自己编**，天然同版本。

### 为什么不用 `create_sdk`

`ninja "flutter/third_party/dart:create_sdk"`（注意目标名里的**冒号**，
GN 的 `toolchain:target` 语法，build.ninja 里是 `dart$:create_sdk`）会编 3700+ 步，
而且会撞 `analysis_server` 自身的崩溃：

```
PathNotFoundException(path=.../dart/sdk/version)     # 先补这个文件
Bad state: Future already completed                   # 补完还是崩，analysis_server 自己的 bug
```

对只需要 `flutter build` 的引擎来说，`analysis_server` / `dart2js` / `dartdevc`
都是废重。`03-build-dart-sdk.sh` 只编 4 个二进制 + `lib/` 的拷贝（约 1200 步）。

---

## artifact 目录规则

`flutter_tools/lib/src/artifacts.dart` 的 `_getEngineArtifactsPath()`：

```dart
case .linux || .macos || .windows:
  if (mode == BuildMode.debug || mode == null) {
    return join(engineDir, platformName);              // → linux-riscv64
  }
  final suffix = mode != BuildMode.debug ? '-${kebabCase(mode.cliName)}' : '';
  return join(engineDir, platformName + suffix);        // → linux-riscv64-release
```

所以：

- **`artifacts/engine/linux-riscv64/`** = debug 引擎 + **宿主工具**
- **`artifacts/engine/linux-riscv64-release/`** = release 引擎

每个目录需要 9 样：

| 文件 | 缺失时的报错 |
|---|---|
| `libflutter_linux_gtk.so` | 链接失败 |
| `icudtl.dat` | 运行时失败 |
| `flutter_linux/*.h`（26 个） | `'flutter_linux/flutter_linux.h' file not found` |
| `gen_snapshot` | `Failed to find ".../linux-riscv64-release/gen_snapshot"` |
| `impellerc` | 着色器编译失败 |
| `shader_lib/` | `'#include' : Included file not found. for header name: flutter/runtime_effect.glsl` |
| `font-subset` | `IconTreeShakerException: The font-subset utility is missing` |
| `frontend_server_aot.dart.snapshot` | `Invalid SDK hash` + 黑屏 |
| Dart SDK（`.. /cache/dart-sdk`） | `Wrong full snapshot version` |

### `shader_lib` 必须紧邻 `impellerc`

```dart
// shader_compiler.dart:223
final String shaderLibPath = _fs.path.join(impellerc.parent.absolute.path, 'shader_lib');
```

放别处无效，必须同级。

---

## 两个必须打的 shim / 补丁

### 1. clang wrapper（`scripts/wrappers/`）

解决两个冲突：

**a) `--rtlib` 冲突。** Bianbu 的 clang 默认 `--rtlib=libgcc`，而
`build/config/compiler/BUILD.gn:645` 在 `use_flutter_cxx` 时注入 `--unwindlib=libunwind`，
两者冲突。wrapper 在**链接**时加 `--rtlib=compiler-rt` 解决，不污染编译命令。

**b) `-flto` 需要 lld。** `enable_lto=true`（`build/toolchain/clang.gni:12`）让 release
带 `-flto`，链接 LLVM bitcode 需要 gold 插件：

```
riscv64-linux-gnu-ld.bfd: /usr/lib/llvm-21/lib/LLVMgold.so: error loading plugin
```

**Bianbu 的 llvm-21 不提供 `LLVMgold.so`。** 而 `use_lld = true` 写在 `args.gn` 里
GN 会警告 `Build argument has no effect` —— 这个变量在这个 GN 图里根本没被声明。

所以 wrapper 把**带 `-flto` 的链接步骤**路由到 `-fuse-ld=lld`，其余链接和所有编译步骤不变
（debug 构建完全不受影响）。

### 2. Skia 字体族匹配补丁（`patches/`）

`+59 / −2`，改 `SkFontMgr_fontconfig.cpp`：pattern 侧最多 272 个族名在字体循环里
被重复抽取、重复排序。

**这不是 Flutter 专属问题** —— 723 个字体是 Bianbu 的默认配置，板上每个
GTK4 / libadwaita / Chromium 程序都在付这笔钱。

实测（同一宿主、同一 Xvfb、llvmpipe、`dbus-run-session`，3 次取中位数）：

| 配置 | 首帧 |
|---|---|
| 723 字体，无补丁 | 9043 ms |
| 723 字体，有补丁 | **1616 ms**（5.6×） |
| 56 字体，有补丁 | 894 ms（10.1×） |

补丁和「减少字体数」是**替代关系，不是叠加**（56 字体下 3653 vs 3690，无差别）。

---

## 缓存 stamp

即便引擎完备，`flutter pub get` 仍会检查 `bin/cache/<name>.stamp` 内容是否等于
`cache.engineRevision`，不等就触发下载（然后 404）：

```bash
C=$FLUTTER_ROOT/bin/cache
V=$(cat $C/engine.stamp)
for n in font-subset flutter_sdk linux-sdk engine engine-dart-sdk; do echo "$V" > $C/$n.stamp; done
```

`05-install-artifacts.sh` 已包含这一步。

另外 `flutter --version` 若报 `0.0.0-unknown`，说明 clone 没有 git tag：

```bash
cd $FLUTTER_ROOT && git tag -f 3.41.0
```

---

## 验证状态

### 已从零验证 ✅

在干净的空 `out/` 目录上完整走了一遍，全部通过：

| 项目 | 结果 |
|---|---|
| 干净构建 | **4490 步 / 92 分钟 / 0 失败** |
| `gn gen` | 19632 个目标，1 秒 |
| 引擎产物 | 6 个文件 + `shader_lib` + 26 头文件，全部生成 |
| Dart SDK（含 13 个 snapshots） | 全部 51.0，`dart run` 正常输出 |
| `flutter --version` | `Tools • Dart 3.15.0 (build 3.15.0-51.0.dev)`，零异常 |
| **无参数 `flutter build linux --release`** | **exit 0，543 秒** |
| bundle 引擎 sha256 | 与 `pinned/sdk-hashes.txt` **完全一致** |
| 应用运行 | 窗口 400×500、3 个 isolate 就绪、`Server started (Port: 53317)`、截图 33,958 B |
| debug kernel hash | `69672e35b9` 天然对齐 |

**已发布产物**：见 [Releases](../../releases) —— 22.7 MB（引擎）/ 104.6 MB（最小 SDK）/
182 MB（完整 SDK，分卷）。

### 已知限制

诚实记录，别当它完美：

1. **`linux-riscv64-profile/` 是空的** —— 没有 profile 引擎，
   `flutter build linux --profile` 会失败。
2. **`analysis_server` 快照没编出来** —— 它自己在生成快照时崩
   （`Bad state: Future already completed`），与版本无关。不影响 `flutter build`，
   但 `dart analyze` 可能受影响。
3. **只用过一个应用验证**（LocalSend GUI）。没有跑 Flutter 自己的测试套件。
4. **显示验证在 Xvfb + llvmpipe 下完成**。真实 Xorg/Wayland 下的表现未验证
   （日志里的 `DRI3 error` 是显示环境问题，不影响构建）。
5. **`dart-sdk/bin/resources/` 容易漏** —— 少了 `devtools/` 整个目录，
   `flutter --version` 会抛 `Could not find directory .../resources/devtools`。
   本仓库的 `02-build.sh` + `03-build-dart-sdk.sh` 已覆盖，但自己手搓时容易忘。

---

## 相关

- 用这个引擎编出来的实际应用：[fivif/localsend-riscv64](https://github.com/fivif/localsend-riscv64)
  （LocalSend 桌面 GUI 的 riscv64 适配，含 deb 打包与端到端传输验证）
- Flutter 引擎源码：https://github.com/flutter/flutter/tree/master/engine
- Flutter 从未发布的 riscv64 产物：
  `https://storage.googleapis.com/flutter_infra_release/flutter/<rev>/linux-riscv64/artifacts.zip` → 404

---

## License

本仓库内容（脚本、补丁、文档）以 **BSD-3-Clause** 发布，与 Flutter 引擎一致。
Flutter 引擎本身版权归 Google 及贡献者所有，见上游 `LICENSE`。
