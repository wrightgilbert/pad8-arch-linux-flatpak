中文 | [English](README_english.md)

# 小米平板 8（yupei）Arch Linux Flatpak 内核补丁

在 [arch-xiaomi-pad8](https://github.com/KoryoSony/arch-xiaomi-pad8) 的移植上补齐 Flatpak 需要的内核能力，并给出可直接刷入的 `boot.img`。

## 快速开始

前提：已按上游 `v0.1.0-alpha` 装好 Arch Linux，底包为澎湃 OS **4.0.5.0.XPZCNXM**，bootloader 已解锁。

```bash
# 1. 刷内核
adb reboot bootloader
fastboot flash boot boot.img        # 从 Releases 下载
fastboot reboot

# 2. 开机后跑一次装机脚本
git clone https://github.com/wrightgilbert/pad8-arch-linux-flatpak
bash pad8-arch-linux-flatpak/scripts/post-install.sh

# 3. 验证
flatpak install --user flathub org.gnome.Calculator
flatpak run org.gnome.Calculator
```

`post-install.sh` 做三件事：去掉 `/usr/bin/bwrap` 的 setuid 位、添加 Flathub 源、跑 `verify.sh` 自检。

## 改了什么

三个内核补丁，每个都对应一条"不加就用不了"的限制：

1. **`0001` sched**：把 `CONFIG_SYSVIPC` 的 `task_struct` 成员放进 Android ABI 预留位，打开 SYSVIPC 不再改变内核结构体布局，厂商模块才能载入。
2. **`0002` module**：放宽模块符号 CRC 比对。同一份配置、同一个编译器，本地重编内核的 CRC 仍与厂商模块不一致，不放宽就一个模块都加载不了。
3. **`0003` namespace**：移植包把 `/proc/cpuinfo` 做成了文件型 bind mount，内核的挂载安全检查会因此拒绝在沙箱里挂 procfs；补丁让"非目录挂载点"跳过这项检查。

同时内核里开了 `CONFIG_SYSVIPC`、`CONFIG_IPC_NS`、`CONFIG_PID_NS`、`CONFIG_USER_NS`（Flatpak 的 `--unshare-ipc` 与 bubblewrap 沙箱都依赖它们）。

## 文件

| 文件 | 用途 |
|---|---|
| `patches/0001..0003.patch` | 可直接 `git apply` 的内核补丁 |
| `scripts/build-kernel.sh` | 在任意 aarch64 主机上重编内核 |
| `scripts/mkboot.py` | 把新编的 `Image` 换进上游 `boot.img` |
| `scripts/post-install.sh` | 装机后一次性的权限与源配置 |
| `scripts/verify.sh` | 十项自检 |

## 注意

- 只替换 `boot.img`。`init_boot.img` 与 `userdata.part1..6.img` 用上游 release 的原件，不要与别的底包混用。
- 补丁 `0002` 是权宜之计：它关闭了"内核与模块 ABI 是否匹配"的校验，换底包后旧模块仍会被加载，出问题不会有 CRC 报错提示。
- 底包不是 4.0.5 的机器不要刷，`/vendor` 里的模块与这个内核不匹配。

## 文档

- [快速开始与排错](docs/zh/快速开始.md)
- [三个补丁分别在修什么](docs/zh/内核改动.md)
- [自己编译](docs/zh/构建与复现.md)

## 致谢

- [arch-xiaomi-pad8](https://github.com/KoryoSony/arch-xiaomi-pad8)：整套移植。
- [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)：`0001` 的 Android ABI padding 做法出自其内核补丁目录。
- [Flatpak](https://flatpak.org/) / [bubblewrap](https://github.com/containers/bubblewrap)：沙箱。
