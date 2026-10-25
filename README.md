中文 | [English](README_english.md)

# 小米平板 8（yupei）Arch Linux Flatpak 内核补丁

在 [arch-xiaomi-pad8](https://github.com/KoryoSony/arch-xiaomi-pad8) 这套移植的基础上，补上 **Flatpak / bubblewrap 沙箱** 需要的内核能力，并给出可直接刷入的 `boot.img` 与装机脚本。

![状态](https://img.shields.io/badge/Flatpak-可用-brightgreen) ![内核](https://img.shields.io/badge/kernel-6.6.118--4k--arch%2B-blue) ![底包](https://img.shields.io/badge/OS-4.0.5.0.XPZCNXM-orange)

**快速开始：** 从 [Releases](../../releases) 下载 `boot.img` → `fastboot flash boot boot.img` → 开机后 `bash scripts/post-install.sh` → `flatpak install flathub org.gnome.Calculator` 验证。

## 项目内容

- **三个内核补丁**：修好 `CONFIG_SYSVIPC` 破坏模块 ABI、以及 `/proc/cpuinfo` 伪装让沙箱挂 `/proc` 失败这两件事。
- **预编译 `boot.img`**：`6.6.118-4k-arch+`，内建 `SYSVIPC`、`IPC_NS`、`PID_NS`、`USER_NS`，开箱即带上述补丁。
- **装机脚本**：`scripts/post-install.sh` 去 setuid、加 Flathub 源；`scripts/verify.sh` 一条命令自检九项。
- **可复现**：`scripts/build-kernel.sh` 在任意 aarch64 主机上重编内核，`scripts/mkboot.py` 换内核进 `boot.img`。

## 这次改了什么

| 补丁 | 解决 | 不加会怎样 |
|---|---|---|
| `0001` sched：把 SYSVIPC 的成员放进 Android ABI padding | 开 `CONFIG_SYSVIPC` 会让 `struct task_struct` 整体位移，`/vendor` 的 950+ 个模块 CRC 全对不上 | 内核起来但一个驱动都载不进来，屏幕定在开机 Logo，USB/网络全无 |
| `0002` module：放宽符号 CRC 比对 | 同一份配置、同一个 clang 版本，重编出来的 `module_layout` CRC（`0x6500052f`）仍与厂商模块（`0x4e276f37`）不同 | 同上：`module_layout: disagrees about version`，模块全部拒绝加载 |
| `0003` namespace：文件型挂载点不算“会泄漏” | 移植包为了骗过 llvmpipe，把 `/proc/cpuinfo` 做成了**文件**型 bind mount，`mount_too_revealing()` 因此判定整个 procfs 挂载不安全 | `bwrap: Can't mount proc on /proc: Operation not permitted`，Flatpak 一个应用都起不来 |

详细原理、实测数字与排查过程见 [内核改动说明](docs/zh/内核改动.md) 与 [调试过程](docs/zh/调试过程.md)。

## 功能现状

| 功能 | 状态 | 说明 |
|---|---|---|
| Flatpak 安装/运行 | 可用 | 实测 `org.gnome.Calculator 51.1` + `org.gnome.Platform 51` + Mesa 26.2.5，沙箱内 `/app` 可读 |
| bubblewrap 沙箱 | 可用 | `--unshare-all --proc /proc` 通过 |
| SYSVIPC / IPC namespace | 可用 | `/proc/sysvipc` 存在，`unshare -U`/`-p`/`-i` 正常 |
| 厂商模块（显示/GPU/WiFi/蓝牙…） | 可用 | 559 个模块载入，`dmesg` 无 CRC 冲突 |
| Waydroid | 未测试 | 依赖 binder，与本次改动无关 |
| 内核模块签名强制 | 未启用 | 使用方需自行评估 |

## 支持的设备与前提

- 机型：小米平板 8（`yupei`，SM8735 / Adreno 825）。
- 底包：**澎湃 OS 4.0.5.0.XPZCNXM**（上游移植的硬性前提；`/vendor` 里的模块是 OEM 6.6.57 供应商树编的，必须与底包配对）。
- 已解锁 bootloader（`fastboot getvar unlocked` = `yes`），会清空 userdata。
- 上游 port 版本：`v0.1.0-alpha`（`userdata.part1..6.img` 从上游 release 取，本项目只替换内核）。
- 已知限制：键盘保护套、手写笔等外设在部分批次上仍需上游后续版本支持，与本次改动无关。

## 文档

- [快速开始（刷机 + 验证）](docs/zh/快速开始.md)
- [内核改动说明](docs/zh/内核改动.md)
- [自己编译（arm64 主机）](docs/zh/构建与复现.md)
- [调试过程：从「模块加载失败」到「沙箱挂载被拒」](docs/zh/调试过程.md)
- [English README](README_english.md)

## 致谢

- [arch-xiaomi-pad8](https://github.com/KoryoSony/arch-xiaomi-pad8)：整套移植（内核树、rootfs、installer、固件挂载）。
- [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)：`SYSVIPC` 的 Android ABI padding 补丁方案即出自其 `Documentation/resources/kernel-patches/`，本项目的 `0001` 沿用其做法。
- [bubblewrap](https://github.com/containers/bubblewrap) / [Flatpak](https://flatpak.org/)：沙箱与运行时。
- Android 通用内核（`kernel/common` `android15-6.6`）与 LLVM 18.1.8。
