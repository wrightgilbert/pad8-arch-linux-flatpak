#!/bin/bash
# 在任意 aarch64 主机（平板自身、树莓派等）上编译带 Flatpak 支持的内核。
#
# 用法：
#   PORT=/path/to/arch-xiaomi-pad8 bash scripts/build-kernel.sh
# 可选环境变量：
#   WORK   工作目录（默认 $PORT/work）
#   OUT    产物目录（默认 $PORT/out）
#   TC     LLVM 18.1.8 解压目录（默认 $WORK/llvm18，需含 bin/clang）
set -euo pipefail

PORT=${PORT:-$PWD}
WORK=${WORK:-$PORT/work}
OUT=${OUT:-$PORT/out}
TC=${TC:-$WORK/llvm18}
PATCHES=${PATCHES:-$PORT/../../patches}
[ -d "$PATCHES" ] || PATCHES=$(cd "$(dirname "$0")/../patches" && pwd)

export WORK OUT
export PATH=$TC/bin:$PATH
export USE_SYSTEM_CLANG=1 LLVM_DIR=$TC/bin

echo "== 工具链 =="
clang --version | head -1
llvm-strip --version | head -1

SRC=$WORK/kernel
if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch android15-6.6-2026-01_r37 \
        https://android.googlesource.com/kernel/common "$SRC"
fi

echo "== 内核补丁 =="
for p in "$PATCHES"/000*.patch; do
    if git -C "$SRC" apply --check "$p" 2>/dev/null; then
        git -C "$SRC" apply "$p" && echo "applied $(basename "$p")"
    elif git -C "$SRC" apply --check -R "$p" 2>/dev/null; then
        echo "already applied $(basename "$p")"
    else
        echo "补丁无法应用：$p" >&2
        exit 1
    fi
done
grep -q 'ANDROID_KABI_USE(6, struct sysv_sem' "$SRC/include/linux/sched.h" && echo "kABI padding 在位"

echo "== 配置片段 =="
FRAG=$PORT/kernel/yupei-linux.fragment
if ! grep -q '^CONFIG_SYSVIPC=y' "$FRAG"; then
    printf 'CONFIG_SYSVIPC=y\nCONFIG_IPC_NS=y\nCONFIG_PID_NS=y\nCONFIG_USER_NS=y\n' >> "$FRAG"
fi
# resolve_btfids 在 Arch 上编不过（asm/sigcontext.h 的 __u128），BTF 对启动与 KMI 无影响。
grep -q '^# CONFIG_DEBUG_INFO_BTF is not set' "$FRAG" || \
    echo '# CONFIG_DEBUG_INFO_BTF is not set' >> "$FRAG"

echo "== 开始编译 =="
cd "$PORT"
bash kernel/build-kernel.sh

echo "== 产物 =="
sha256sum "$OUT/Image"
cat "$OUT/kernel.release"
grep -E 'CONFIG_(SYSVIPC|IPC_NS|PID_NS|USER_NS)=' "$OUT/.config"
echo BUILD_OK
