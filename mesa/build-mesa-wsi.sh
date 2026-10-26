#!/usr/bin/env bash
# Rebuild /opt/mesa-yupei with KGSL WSI support (physical_device_drm + no
# UNREACHABLE timestamp stub). Same mesa version as the release image, same
# meson flags as the port's mesa/build-mesa.sh; only apply-kgsl-wsi.py is extra.
#
# Run on the tablet (aarch64), as a user with passwordless sudo.
# Result: $HOME/mesa-wsi/dest/libvulkan_freedreno.so
#
# Install (keep a backup first!):
#   sudo cp -a /opt/mesa-yupei/lib/libvulkan_freedreno.so{,.pre-wsi}
#   sudo install -m755 $HOME/mesa-wsi/dest/libvulkan_freedreno.so \
#        /opt/mesa-yupei/lib/libvulkan_freedreno.so
#   sudo systemctl restart plasmalogin     # compositor must reload the ICD
# Revert: restore .pre-wsi and restart plasmalogin.
#
# MESA_PIN pins the commit; default is the last main commit before the release
# date, which is the 26.3.0-devel the image shipped. Change it if you rebuild
# against a newer Mesa (then re-check the WSI anchors in apply-kgsl-wsi.py).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
B=${B:-$HOME/mesa-wsi}
SRC=$B/src
BUILD=$B/build
DEST=$B/dest
MESA_PIN=${MESA_PIN:-2026-10-15}
mkdir -p "$B"

echo "[1/6] build deps"
sudo pacman -S --noconfirm --needed meson ninja python-mako python-packaging python-yaml \
    glslang libdrm wayland wayland-protocols libelf zstd expat bison flex \
    libx11 libxext libxfixes libxshmfence libxxf86vm libxrandr spirv-tools \
    python-ply libglvnd >/dev/null

echo "[2/6] mesa source (pin: last commit before $MESA_PIN)"
if [ ! -d "$SRC/.git" ]; then
  git clone --filter=blob:none --no-checkout https://gitlab.freedesktop.org/mesa/mesa.git "$SRC"
fi
cd "$SRC"
git fetch --quiet origin main
git checkout -q --detach "$(git rev-list -n1 --before="$MESA_PIN" origin/main)"
echo "    VERSION=$(cat VERSION)"

echo "[3/6] Adreno 825 entry (same edit as the port's 0001-...patch.py)"
python3 - "$SRC/src/freedreno/common/freedreno_devices.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = 'GPUId(chip_id=0x44030a20, name="Adreno (TM) 829"), # KGSL'
assert anchor in s, 'Adreno 829 entry not found; update this patch'
if '0x44030000' not in s:
    s = s.replace(anchor, anchor + '\n        GPUId(chip_id=0x44030000, name="Adreno (TM) 825"), # KGSL, yupei')
    open(p, 'w').write(s)
print('    ok')
PY

echo "[4/6] KGSL WSI hunks"
python3 "$HERE/apply-kgsl-wsi.py" "$SRC"

echo "[5/6] meson + ninja (port flags, unchanged)"
meson setup --wipe "$BUILD" "$SRC" \
  --prefix=/opt/mesa-yupei --libdir=lib --buildtype=release \
  -Dplatforms=wayland -Dglx=disabled -Dglvnd=enabled -Degl=enabled -Dgbm=enabled -Dgles1=disabled \
  -Dgallium-drivers=zink -Dvulkan-drivers=freedreno -Dfreedreno-kmds=msm,kgsl \
  -Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dbuild-tests=false \
  -Dvideo-codecs= -Dtools=
ninja -C "$BUILD"

echo "[6/6] stage"
mkdir -p "$DEST"
cp "$BUILD/src/freedreno/vulkan/libvulkan_freedreno.so" "$DEST/libvulkan_freedreno.so"
cat > "$DEST/icd.json" <<JSON
{"file_format_version":"1.0.0","ICD":{"library_path":"$DEST/libvulkan_freedreno.so","api_version":"1.4.318"}}
JSON
strings "$DEST/libvulkan_freedreno.so" | grep -oE 'Mesa [0-9]+\.[0-9]+\.[0-9]+[^ ]*' | sort -u | head -2
echo "built: $(stat -c %s "$DEST/libvulkan_freedreno.so") bytes  sha256=$(sha256sum "$DEST/libvulkan_freedreno.so" | cut -d' ' -f1)"
