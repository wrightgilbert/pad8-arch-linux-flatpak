[中文](README.md) | English

# Flatpak kernel patches for Arch Linux on Xiaomi Pad 8 (yupei)

Adds the kernel features **Flatpak / bubblewrap** needs on top of the [arch-xiaomi-pad8](https://github.com/KoryoSony/arch-xiaomi-pad8) port, and ships a ready-to-flash `boot.img` plus post-install scripts.

**Quick start:** grab `boot.img` from [Releases](../../releases) → `fastboot flash boot boot.img` → boot → `bash scripts/post-install.sh` → `flatpak install flathub org.gnome.Calculator`.

## What is inside

- **Three kernel patches**: stop `CONFIG_SYSVIPC` from breaking the module ABI, tolerate vendor symbol CRCs that a local rebuild cannot reproduce, and let a user namespace mount `procfs` when `/proc/cpuinfo` is a file bind mount.
- **Prebuilt `boot.img`**: kernel `6.6.118-4k-arch+` with `SYSVIPC`, `IPC_NS`, `PID_NS`, `USER_NS` and all three patches.
- **Post-install tooling**: `scripts/post-install.sh` (drop the setuid bit on bwrap, add Flathub) and `scripts/verify.sh` (nine-point self check).
- **Reproducible**: `scripts/build-kernel.sh` rebuilds the kernel on any aarch64 host; `scripts/mkboot.py` swaps the kernel into a stock `boot.img`.

## The three patches

| Patch | Problem it fixes | Symptom without it |
|---|---|---|
| `0001` sched | Enabling `CONFIG_SYSVIPC` inserts members into `struct task_struct`, shifting every following field; 950+ stock modules then fail their CRC check | Kernel boots, no driver loads, stuck on boot logo |
| `0002` module | A locally rebuilt kernel produces `module_layout` CRC `0x6500052f` while the vendor modules advertise `0x4e276f37`, even with an identical config and compiler | `module_layout: disagrees about version`, every module rejected |
| `0003` namespace | The port rewrites `/proc/cpuinfo` as a **file** bind mount; `mount_too_revealing()` then treats procfs as unsafe to mount inside a user namespace | `bwrap: Can't mount proc on /proc: Operation not permitted` |

## Requirements

- Xiaomi Pad 8 (`yupei`, SM8735), unlocked bootloader, data wipe.
- Base firmware **HyperOS 4.0.5.0.XPZCNXM** (hard requirement of the upstream port; the OEM vendor modules in `/vendor` are built from the 6.6.57 vendor tree and must match the base).
- Upstream port `v0.1.0-alpha`; only the kernel image is replaced by this project.

## Docs

- [Quick start](docs/zh/快速开始.md) (Chinese)
- [Kernel changes explained](docs/zh/内核改动.md) (Chinese)
- [Building it yourself](docs/zh/构建与复现.md) (Chinese)
- [Debugging log](docs/zh/调试过程.md) (Chinese)

## Credits

- [arch-xiaomi-pad8](https://github.com/KoryoSony/arch-xiaomi-pad8) — the port this builds on.
- [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) — the Android ABI padding approach for `SYSVIPC`.
- [bubblewrap](https://github.com/containers/bubblewrap), [Flatpak](https://flathub.org), Android common kernel `android15-6.6`, LLVM 18.1.8.
