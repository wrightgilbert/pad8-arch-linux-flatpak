[中文](README.md) | English

# Flatpak kernel patches for Arch Linux on Xiaomi Pad 8 (yupei)

Adds what Flatpak needs on top of the [arch-xiaomi-pad8](https://github.com/KoryoSony/arch-xiaomi-pad8) port, plus a ready-to-flash `boot.img`.

## Quick start

Requires: Arch Linux already installed from the upstream `v0.1.0-alpha` assets, base firmware **HyperOS 4.0.5.0.XPZCNXM**, unlocked bootloader.

```bash
adb reboot bootloader
fastboot flash boot boot.img        # from Releases
fastboot reboot
```

After booting:

```bash
git clone https://github.com/wrightgilbert/pad8-arch-linux-flatpak
bash pad8-arch-linux-flatpak/scripts/post-install.sh
flatpak install --user flathub org.gnome.Calculator
flatpak run org.gnome.Calculator
```

`post-install.sh` clears the setuid bit on `/usr/bin/bwrap`, adds the Flathub remote and runs `scripts/verify.sh`.

## What the patches do

1. **`0001` sched** — moves the `CONFIG_SYSVIPC` members of `task_struct` into the Android ABI padding slots, so enabling SYSVIPC no longer shifts the struct and the stock vendor modules can load.
2. **`0002` module** — relaxes the module symbol CRC check. A locally rebuilt kernel does not reproduce the vendor CRCs even with an identical config and compiler, so without this no module loads at all.
3. **`0003` namespace** — the port bind-mounts `/proc/cpuinfo` as a regular file; the kernel's mount-safety check then refuses to mount procfs inside a sandbox. The patch skips that check for non-directory mountpoints.

The kernel also enables `CONFIG_SYSVIPC`, `CONFIG_IPC_NS`, `CONFIG_PID_NS` and `CONFIG_USER_NS`, required by Flatpak's `--unshare-ipc` and by bubblewrap.

## Caveats

- Only `boot.img` is replaced. Keep `init_boot.img` and `userdata.part1..6.img` from the upstream release, and do not mix base firmware versions.
- Patch `0002` is a workaround, not a fix: it turns off the ABI guard, so after changing base firmware stale modules still load and problems show up without a CRC error.
- Do not flash this kernel on a device whose base firmware is not 4.0.5.

## Docs

- [Quick start and troubleshooting](docs/zh/快速开始.md) (Chinese)
- [What each patch fixes](docs/zh/内核改动.md) (Chinese)
- [Building it yourself](docs/zh/构建与复现.md) (Chinese)
- [GPU / Mesa: KGSL WSI patch](docs/zh/GPU与Mesa.md) (Chinese)

## Credits

- [arch-xiaomi-pad8](https://github.com/KoryoSony/arch-xiaomi-pad8) — the port.
- [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) — the Android ABI padding approach used by `0001`.
- [Flatpak](https://flatpak.org/) / [bubblewrap](https://github.com/containers/bubblewrap) — the sandbox.
