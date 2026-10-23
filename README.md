# Flutter RISC-V 64 Linux Engine

在 riscv64 上构建 Flutter Linux 引擎，使 `flutter build linux` 可用。

[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20riscv64-blue)]()
[![Flutter](https://img.shields.io/badge/flutter-3.41.0-02569B)]()
[![Dart](https://img.shields.io/badge/dart-3.15.0--51.0.dev-0175C2)]()
[![License](https://img.shields.io/badge/license-BSD--3--Clause-lightgrey)](LICENSE)

Flutter 官方未发布 riscv64 Linux 引擎产物，`.../linux-riscv64/artifacts.zip` 始终返回 404。
本仓库提供构建该产物的脚本与配置，并发布预编译结果。

已完成从零验证：干净构建 4490 步、92 分钟、0 失败；无参数
`flutter build linux --release` 成功（543 秒），应用正常运行。

## 安装

从 [Releases](https://github.com/fivif/flutter-riscv64-linux/releases) 下载：

```bash
tar xzf flutter-riscv64-sdk-min-dart3.15.0-51.0.tar.gz
cd flutter-riscv64-linux-dart3.15.0-51.0-release
./install.sh /path/to/flutter
```

| 包 | 大小 | 适用 |
|---|---|---|
| `sdk-min-*` | 104.6 MB | 常规使用（引擎 + 编译所需 snapshot） |
| `engine-*` | 22.7 MB | 已有匹配 Dart SDK，仅需引擎 |
| `sdk-*.part-00/01/02` | 90+90+2.4 MB | 完整 SDK，先执行 `rejoin.sh` |

安装后任意 Flutter 项目均可直接构建，无需额外参数：

```bash
flutter build linux --debug
flutter build linux --release
```

## 从源码构建

需要 Flutter 源码。依赖由 `gclient` 按 revision 拉取（约 2 GB，271 个仓库）：

```bash
git clone https://github.com/flutter/flutter.git
cd flutter && git checkout 6597889f57b4922b95b3917967f8530fcbdd9515
cd engine/src && gclient sync -r 57d5122cd9dcfd0174ba963e61df20a328378c64

git clone https://github.com/fivif/flutter-riscv64-linux.git engine-build
cd engine-build
export FLUTTER_ENGINE=/path/to/engine/src

./scripts/00-check-env.sh                        # 环境检查
cp scripts/wrappers/clang* "$FLUTTER_ENGINE/buildtools/linux-x64/clang/bin/"
./scripts/01-gen.sh    riscv64-release release
./scripts/02-build.sh  riscv64-release           # 4490 步，92 分钟
./scripts/03-build-dart-sdk.sh          riscv64-release
./scripts/04-rebuild-frontend-server.sh riscv64-release
./scripts/05-install-artifacts.sh /path/to/flutter riscv64-release
./scripts/06-verify.sh            /path/to/flutter riscv64-release
```

脚本逐项说明见 [docs/01](docs/01-环境准备.md)。构建前请只运行一个 ninja，
并使用 `-j 8`。

## 为什么需要这个

Flutter 的 `flutter_tools` 已将 riscv64 作为一等目标 —— `TargetPlatform.linux_riscv64`、
`HostPlatform.linux_riscv64`、`gen_snapshot_riscv64`、产物目录名 `linux-riscv64`
与 feature flag `enable-riscv64` 均已存在。

**工具链支持 riscv64，缺的只是官方未发布引擎二进制。** 因此本仓库不修改 Flutter，
仅构建缺失的产物并安装到正确位置。上游代码零改动。

## 注意事项

**Dart SDK 必须与引擎同版本。** 引擎源码声明 `PRERELEASE 51`；若所用
`dart-sdk` 二进制来自其他版本，会导致 `Invalid SDK hash`（窗口全黑）、
AOT `ApiError`、`Wrong full snapshot version` 等问题。

`dart-sdk/version` 文件内容不可作为判断依据 —— 它可能已更新而 `bin/` 下的
二进制仍是旧版本。必须执行 `dart --version` 确认。

这也是 `scripts/03-build-dart-sdk.sh` 从源码构建 SDK 的原因。
详见 [docs/02](docs/02-踩坑记录.md)。

## 验证状态

| 项目 | 结果 |
|---|---|
| 干净构建 | 4490 步 / 92 分钟 / 0 失败 |
| Dart SDK（13 snapshot + 471 lib） | 版本一致，`dart run` 与 `dart compile exe` 正常 |
| `flutter --version` | `Tools • Dart 3.15.0 (build 3.15.0-51.0.dev)` |
| 无参数 `flutter build linux --release` | exit 0，543 秒 |
| bundle 引擎 sha256 | 与 [`pinned/sdk-hashes.txt`](pinned/sdk-hashes.txt) 一致 |
| 应用运行 | 窗口 402×528，3 isolate 就绪，端口 53317 |

**未验证**：profile 引擎（未构建）、Flutter 自身测试套件、真实 Xorg / Wayland
显示（均在 Xvfb 与 labwc 下测试，GPU 呈现路径未打通）。

## 环境

| 项 | 值 |
|---|---|
| 硬件 | SpacemiT K3（16 核），7.7 GiB |
| 系统 | Bianbu 4.0.1，kernel 6.18.3，riscv64 |
| 工具链 | clang 21.1.8，ninja 1.13.2，gn 1000，lld 21 |
| Flutter | 3.41.0，engine `57d5122c` |

版本锁定见 [`pinned/`](pinned/)：`DEPS`（271 个依赖的 revision）、
`flutter.version`、`dart.VERSION`、`sdk-hashes.txt`。

## 文档

- [docs/01-环境准备](docs/01-环境准备.md) — 系统依赖、`gn --script-executable`、clang shim 原理
- [docs/02-踩坑记录](docs/02-踩坑记录.md) — 16 项问题的症状、根因与修复
- [docs/03-实测数据](docs/03-实测数据.md) — 构建耗时、体积、字体基准、AOT 收益

## 相关

- [fivif/localsend-riscv64](https://github.com/fivif/localsend-riscv64) — 使用本引擎构建的 LocalSend 桌面 GUI

## License

BSD-3-Clause，与 Flutter 引擎一致。引擎本身版权归 Google 及贡献者所有，
见上游 `LICENSE` 与 [NOTICE](NOTICE)。
