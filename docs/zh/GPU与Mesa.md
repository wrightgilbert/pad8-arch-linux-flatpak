# GPU / Mesa 这一层：KGSL 上的 WSI 补丁

## 现象

- 桌面、视频、Wayland 客户端都能硬件加速（KWin 走 zink → Turnip → KGSL），但：
  - `vulkaninfo` 报 `WARNING: tu_knl_kgsl.cc: I can't KHR_display (VK_ERROR_INITIALIZATION_FAILED)`，随后 `vkEnumeratePhysicalDevices failed with error code -3`；
  - 客户端查不到 `VK_EXT_physical_device_drm`，拿不到 GPU 的 DRM 主次号；
  - KWin 启动时偶发 `status=5/TRAP`（SIGTRAP），要靠 `KWIN_NO_TIMER_QUERY=1` 绕开；
  - `gamescope` 完全起不来（它要 `VK_KHR_display` 或可用的 DRM 节点）。

## 原因

这块板子的 GPU 是 `/dev/kgsl-3d0`（字符设备，没有 DRM 节点），显示是另一个 `/dev/dri/card0`（msm KMS，只做扫描输出）。上游 Turnip 在 KGSL 上：

1. 不会把 KGSL 设备的主次号填进 `has_local/has_master`，于是 `VK_EXT_physical_device_drm` 被禁用；
2. `kgsl_device_get_gpu_timestamp()` 是个 `UNREACHABLE("")` 桩，而 `VK_KHR_calibrated_timestamps` / `VK_EXT_present_timing` 仍然打开 —— 任何客户端一问时间戳就 SIGTRAP。

## 改法（`mesa/apply-kgsl-wsi.py`，10 处）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `tu_knl_kgsl.cc` | 补 `sys/stat.h`、`sys/sysmacros.h` |
| 2 | `tu_knl_kgsl.cc` | `fstat(fd)` 拿到 KGSL 字符设备主次号，写进 `has_local/has_master/local_major/...` |
| 3 | `tu_device.cc` | `EXT_physical_device_drm` 改成 `!is_kgsl(...) \|\| device->has_local` |
| 4 | `tu_knl_kgsl.cc` | 删掉 `kgsl_device_get_gpu_timestamp` 桩及其 hook |
| 5 | `tu_knl.cc` | `device_get_gpu_timestamp == NULL` 时返回 `-1` |
| 6–8 | `tu_device.cc` | `KHR/EXT_calibrated_timestamps`、`EXT_present_timing` 追加 `... && timestamp != NULL` |
| 9–11 | `tu_device.cc` | `presentTiming` / `presentAtRelativeTime` / `presentAtAbsoluteTime` 由 `true` 改为受 `EXT_present_timing` 控制 |

同样的思路见 DroidDeck 的 `Drivers/patches/scripts/linux_kgsl_wsi.py`（容器方案）。本仓的脚本是独立实现，锚点断言式、可重复执行。

## 构建

`mesa/build-mesa-wsi.sh` —— 与移植仓 `mesa/build-mesa.sh` **完全相同的 meson 参数**（`26.3.0-devel`、`-Dplatforms=wayland -Dglx=disabled -Dgallium-drivers=zink -Dvulkan-drivers=freedreno -Dfreedreno-kmds=msm,kgsl`），只多做两件事：Adreno 825 条目 + 上面的 WSI 补丁。

```bash
./mesa/build-mesa-wsi.sh          # 产物 $HOME/mesa-wsi/dest/libvulkan_freedreno.so
```

约 4–5 分钟（8 核 ARM）。**不要**拿别处编好的 Turnip 直接换系统里的那份：换过 DroidDeck 的 `27.0.0-devel` 二进制，桌面立刻花屏。同版本 + 只加这 10 处才安全。

## 安装与回滚

```bash
sudo cp -a /opt/mesa-yupei/lib/libvulkan_freedreno.so{,.pre-wsi}
sudo install -m755 $HOME/mesa-wsi/dest/libvulkan_freedreno.so \
     /opt/mesa-yupei/lib/libvulkan_freedreno.so
sudo systemctl restart plasmalogin     # 合成器必须重载 ICD
```

回滚：

```bash
sudo cp /opt/mesa-yupei/lib/libvulkan_freedreno.so.pre-wsi \
        /opt/mesa-yupei/lib/libvulkan_freedreno.so
sudo systemctl restart plasmalogin
```

## 验证

```bash
# 会话里跑（WAYLAND_DISPLAY=wayland-1 注意不是 wayland-0）
vulkaninfo 2>/dev/null | grep -E 'physical_device_drm|calibrated_timestamps'
```

期望：`physical_device_drm` 出现（主次号即 KGSL 的 major:minor，本机 `471:0`），`calibrated_timestamps` / `present_timing` 消失。

固化了这条之后，`KWIN_NO_TIMER_QUERY=1` 就不需要了（我们是先移除它、再重启两次会话确认 KWin 不再 TRAP）。

## 仍然不行的

- `gamescope`：错误从 `I can't KHR_display` 变为 `drmGetDeviceFromDevId() failed`。它需要真正的 DRM 节点或 `VK_KHR_display`，本机 GPU 没有，这条与 Turnip 无关。
- Steam 客户端 UI：仍走 llvmpipe（它自己的 GL 断言，见仓库 README 的 Steam 一节）。
