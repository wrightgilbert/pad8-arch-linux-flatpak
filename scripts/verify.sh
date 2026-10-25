#!/bin/bash
# 自检：内核补丁是否生效、沙箱能不能起。
# 全部只读，不需要 root（bwrap/flatpak 用当前用户跑）。
set -uo pipefail

ok() { printf '  [OK]   %s\n' "$1"; }
bad() { printf '  [FAIL] %s\n' "$1"; rc=1; }
rc=0

echo "内核：$(uname -r)"
case $(uname -r) in
    *-4k-arch*) ok "跑的是本次提供的内核" ;;
    *) bad "不是本次提供的内核（预期以 -4k-arch 结尾）" ;;
esac

echo "内核配置："
# 注意别写成 `zcat /proc/config.gz | grep -qx`：grep -q 提前退出会让 zcat 吃到
# SIGPIPE，配合 set -o pipefail 整个管道就变成非零，看起来像"选项没开"。
cfg=$(zcat /proc/config.gz 2>/dev/null || cat "/boot/config-$(uname -r)" 2>/dev/null || true)
if [ -z "$cfg" ]; then
    bad "读不到内核配置（既没有 /proc/config.gz 也没有 /boot/config-*）"
else
    for opt in CONFIG_SYSVIPC CONFIG_IPC_NS CONFIG_PID_NS CONFIG_USER_NS; do
        case $cfg in
            *"$opt=y"*) ok "$opt=y" ;;
            *) bad "$opt 未开启" ;;
        esac
    done
fi

echo "命名空间："
if unshare -U true 2>/dev/null; then ok "user namespace 可用"; else bad "user namespace 不可用"; fi
if ls /proc/sysvipc >/dev/null 2>&1; then ok "/proc/sysvipc 存在（SYSVIPC 生效）"; else bad "/proc/sysvipc 不存在"; fi

echo "沙箱："
if [ -u /usr/bin/bwrap ]; then bad "bwrap 仍是 setuid 模式（跑 scripts/post-install.sh）"; else ok "bwrap 非 setuid"; fi
if bwrap --unshare-all --proc /proc --ro-bind / / sh -c 'exit 0' 2>/dev/null; then
    ok "bwrap 能在 user namespace 里挂 /proc"
else
    bad "bwrap 挂 /proc 失败（内核补丁 3 未生效？）"
fi

echo "模块："
count=$(lsmod | tail -n +2 | wc -l)
if [ "$count" -gt 300 ]; then ok "已载入 $count 个模块"; else bad "只载入 $count 个模块（预期 500+）"; fi
bad_crc=$(sudo dmesg 2>/dev/null | grep -ci "disagrees about version" || true)
if [ "${bad_crc:-0}" -eq 0 ]; then ok "dmesg 无 CRC 冲突"; else bad "dmesg 有 $bad_crc 条 CRC 冲突"; fi

echo
[ "$rc" -eq 0 ] && echo "全部通过" || echo "有项目未通过（见上）"
exit "$rc"
