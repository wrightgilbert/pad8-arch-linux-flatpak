#!/usr/bin/env python3
"""Enable dma-buf feedback / VK_EXT_physical_device_drm for Turnip on KGSL.

Why: on this device the GPU is /dev/kgsl-3d0 (a char device with no DRM node),
so upstream Turnip refuses to report VK_EXT_physical_device_drm and its GPU
timestamp path hits an UNREACHABLE() stub. Compositors then have to work around
both (KWin needed KWIN_NO_TIMER_QUERY=1, and clients cannot query the DRM node
for dma-buf negotiation).

This applies the same ten edits as DroidDeck's linux_kgsl_wsi.py, but as a
standalone, idempotent script so it can be replayed after an upstream rebase.
Run it on a Mesa source tree, AFTER the Adreno 825 patch and BEFORE meson.

Usage: python3 apply-kgsl-wsi.py <mesa-src-dir>
"""
import sys
from pathlib import Path

KGSL = 'src/freedreno/vulkan/tu_knl_kgsl.cc'
DEVICE = 'src/freedreno/vulkan/tu_device.cc'
KNL = 'src/freedreno/vulkan/tu_knl.cc'
TIMESTAMP = ('static int\n'
             'kgsl_device_get_gpu_timestamp(struct tu_device *dev, uint64_t *ts)\n'
             '{\n'
             '   UNREACHABLE("");\n'
             '   return 0;\n'
             '}\n\n')


def rep(root, rel, old, new, label):
    p = Path(root) / rel
    s = p.read_text()
    if new in s and old not in s:
        print(f'  [skip] {label}')
        return
    if old not in s:
        sys.exit(f'{rel}: anchor for "{label}" not found; upstream changed, update this script')
    p.write_text(s.replace(old, new, 1))
    print(f'  [ok]   {label}')


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    print(f'patching KGSL WSI support in {root}')

    rep(root, KGSL, '#include <sys/mman.h>',
        '#include <sys/mman.h>\n#include <sys/stat.h>\n#include <sys/sysmacros.h>',
        'include sys/stat + sys/sysmacros')

    rep(root, KGSL, '   result = tu_physical_device_init(device, instance);',
        '''   struct stat kgsl_st;
   if (fstat(fd, &kgsl_st) == 0 && S_ISCHR(kgsl_st.st_mode)) {
      device->has_local = device->has_master = true;
      device->local_major = device->master_major = major(kgsl_st.st_rdev);
      device->local_minor = device->master_minor = minor(kgsl_st.st_rdev);
   }

   result = tu_physical_device_init(device, instance);''',
        'kgsl device major/minor for dma-buf feedback')

    rep(root, DEVICE, '.EXT_physical_device_drm = !is_kgsl(device->instance),',
        '.EXT_physical_device_drm = !is_kgsl(device->instance) || device->has_local,',
        'VK_EXT_physical_device_drm on KGSL')

    p = Path(root) / KGSL
    text = p.read_text()
    if TIMESTAMP in text:
        text = text.replace(TIMESTAMP, '')
        text = text.replace('      .device_get_gpu_timestamp = kgsl_device_get_gpu_timestamp,\n', '')
        p.write_text(text)
        print('  [ok]   drop UNREACHABLE() GPU timestamp stub')
    else:
        print('  [skip] GPU timestamp stub (already gone)')

    rep(root, KNL, '   return dev->instance->knl->device_get_gpu_timestamp(dev, ts);',
        '''   if (dev->instance->knl->device_get_gpu_timestamp == NULL)
      return -1;
   return dev->instance->knl->device_get_gpu_timestamp(dev, ts);''',
        'NULL check before GPU timestamp')

    for ext in ('KHR_calibrated_timestamps', 'EXT_calibrated_timestamps', 'EXT_present_timing'):
        rep(root, DEVICE, f'.{ext} = device->info->props.has_persistent_counter,',
            f'.{ext} = device->info->props.has_persistent_counter && '
            f'device->instance->knl->device_get_gpu_timestamp != NULL,',
            f'{ext} gated on GPU timestamps')

    for feat in ('presentTiming', 'presentAtRelativeTime', 'presentAtAbsoluteTime'):
        rep(root, DEVICE, f'features->{feat} = true;',
            f'features->{feat} = pdevice->vk.supported_extensions.EXT_present_timing;',
            f'feature {feat} gated on EXT_present_timing')

    print('done. Expect VK_EXT_physical_device_drm=1 (kgsl major:minor) and no calibrated timestamps.')


if __name__ == '__main__':
    main()
