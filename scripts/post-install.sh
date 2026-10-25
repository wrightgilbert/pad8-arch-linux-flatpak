#!/bin/bash
# 装好系统后跑一次（普通用户，脚本自己 sudo）。
# 做三件事：bubblewrap 去掉 setuid 位、加 Flathub 源、跑自检。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

echo "== 1/3 bubblewrap =="
if [ -u /usr/bin/bwrap ]; then
    # 上游镜像里的 bwrap 带 setuid 位：那个模式只在内核没有 USER_NS 时需要，
    # 而带 USER_NS 的内核上 setuid 模式会被 bubblewrap 自己拒绝。
    sudo chmod 755 /usr/bin/bwrap
    echo "已去掉 setuid 位"
else
    echo "已经是非 setuid 模式"
fi

echo "== 2/3 Flathub 源 =="
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remotes --user

echo "== 3/3 自检 =="
bash "$HERE/verify.sh"
