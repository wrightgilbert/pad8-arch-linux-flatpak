#!/usr/bin/env python3
"""把 Android v4 boot.img 的内核换成新编的 Image。

上游 release 的 boot.img 是 header_version=4、ramdisk_size=0、无 AVB 签名的
裸内核容器，所以换内核只需要改 kernel_size 并重新按 4096 对齐。

用法：
    python scripts/mkboot.py --base boot.img --kernel out/Image --out boot-new.img
"""
import argparse
import hashlib
import struct

PAGE = 4096


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="上游 release 的 boot.img")
    ap.add_argument("--kernel", required=True, help="新编的 arm64 Image")
    ap.add_argument("--out", required=True, help="输出 boot.img")
    args = ap.parse_args()

    base = open(args.base, "rb").read()
    image = open(args.kernel, "rb").read()

    assert base[:8] == b"ANDROID!", base[:8]
    kernel_size, ramdisk_size, _ = struct.unpack_from("<III", base, 8)
    header_size, = struct.unpack_from("<I", base, 20)
    header_version, = struct.unpack_from("<I", base, 40)
    cmdline = base[44:44 + 1536].split(b"\0")[0].decode()
    sig_size = struct.unpack_from("<I", base, 1580)[0] if header_size >= 1584 else 0
    print(f"base: header_version={header_version} header_size={header_size} "
          f"kernel_size={kernel_size} ramdisk_size={ramdisk_size} "
          f"signature_size={sig_size} file={len(base)}")
    print(f"base cmdline={cmdline!r}")
    assert header_version == 4 and ramdisk_size == 0 and sig_size == 0, \
        "只支持无 ramdisk、无签名的 v4 boot.img"
    assert len(image) % 4 == 0, len(image)

    base_kernel = base[PAGE:PAGE + kernel_size]
    assert hashlib.sha256(base_kernel).digest() != hashlib.sha256(image).digest()

    header = bytearray(base[:PAGE])
    struct.pack_into("<I", header, 8, len(image))
    pad = (-(PAGE + len(image))) % PAGE
    out = bytes(header) + image + b"\0" * pad
    assert len(out) <= len(base), f"新镜像 {len(out)} 超过原镜像 {len(base)}"

    with open(args.out, "wb") as fh:
        fh.write(out)

    check = open(args.out, "rb").read()
    assert check[:8] == b"ANDROID!"
    assert struct.unpack_from("<I", check, 8)[0] == len(image)
    assert check[44:44 + 1536] == base[44:44 + 1536]
    assert check[PAGE:PAGE + len(image)] == image

    print(f"new: kernel_size={len(image)} pad={pad} file={len(out)} "
          f"(base {len(base)}, delta {len(out) - len(base):+d})")
    print(f"base kernel sha256 = {hashlib.sha256(base_kernel).hexdigest()}")
    print(f"new  kernel sha256 = {hashlib.sha256(image).hexdigest()}")
    print(f"sha256({args.out}) = {hashlib.sha256(out).hexdigest()}")


if __name__ == "__main__":
    main()
