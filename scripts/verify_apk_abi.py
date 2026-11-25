#!/usr/bin/env python3
"""检查按 ABI 拆分出来的 APK 是否真的只含一个架构的原生库。

用法：
    python3 scripts/verify_apk_abi.py build/app/outputs/apk/release

对目录下每个 *.apk 读出 ZIP 中央目录，统计 lib/<abi>/ 下的条目体积：
- 每个 APK 只允许出现一个 ABI 目录，否则退出码 1（说明 abiFilters 之类的
  配置把别的架构又塞回来了，包体积会白白翻几倍）。
- 顺带打印签名方式是 v1/v2/v3 中的哪些，安装不上时先看这一行。

不依赖 apksigner / Android SDK，只用 Python 标准库。
"""

from __future__ import annotations

import collections
import os
import struct
import sys

EOCD_SIG = b"PK\x05\x06"
CD_SIG = b"PK\x01\x02"
SIG_BLOCK_MAGIC = b"APK Sig Block 42"

SCHEME_IDS = {
    0x7109871A: "v2",
    0xF05368C0: "v3",
    0x1B93AD61: "v3.1",
    0x2B09189E: "v4",
}
# APK 签名方案 v1 的清单文件，出现即视为有 JAR 签名
V1_MARKERS = (b"META-INF/CERT.RSA", b"META-INF/CERT.SF", b"META-INF/CERT.DSA")


def read_eocd(handle, size: int) -> tuple[int, int]:
    """返回 (central_directory_offset, central_directory_size)。"""
    tail_len = min(size, 1 << 20)
    handle.seek(size - tail_len)
    tail = handle.read(tail_len)
    idx = tail.rfind(EOCD_SIG)
    if idx < 0:
        raise SystemExit("不是 ZIP（找不到 EOCD）")
    cd_size, cd_off = struct.unpack("<II", tail[idx + 12 : idx + 20])
    if cd_size == 0xFFFFFFFF or cd_off == 0xFFFFFFFF:
        raise SystemExit("ZIP64 暂不支持")
    return cd_off, cd_size


def inspect(path: str) -> tuple[dict[str, int], list[str]]:
    size = os.path.getsize(path)
    with open(path, "rb") as handle:
        cd_off, cd_size = read_eocd(handle, size)

        handle.seek(cd_off)
        cd = handle.read(cd_size)

        # 签名方案：在中央目录前找 APK Signing Block，以及 v1 的 META-INF 条目
        probe = min(cd_off, 1 << 20)
        handle.seek(cd_off - probe)
        before_cd = handle.read(probe)
        ids: list[str] = []
        if before_cd.endswith(SIG_BLOCK_MAGIC):
            block_total = struct.unpack("<Q", before_cd[-24:-16])[0] + 8
            handle.seek(cd_off - block_total)
            block = handle.read(block_total)
            pos = 8
            while pos < len(block) - 24:
                pair_len = struct.unpack("<Q", block[pos : pos + 8])[0]
                if pair_len == 0 or pos + 8 + pair_len > len(block):
                    break
                pair_id = struct.unpack("<I", block[pos + 8 : pos + 12])[0]
                if pair_id in SCHEME_IDS:
                    ids.append(SCHEME_IDS[pair_id])
                pos += 8 + pair_len
        v1 = any(marker in cd for marker in V1_MARKERS)
        if v1:
            ids.insert(0, "v1")

    abi_bytes: dict[str, int] = collections.Counter()
    pos = 0
    while pos + 46 <= len(cd) and cd[pos : pos + 4] == CD_SIG:
        fields = struct.unpack("<IHHHHHHIIIHHHHHII", cd[pos : pos + 46])
        comp_size, name_len, extra_len, comment_len = (
            fields[8],
            fields[10],
            fields[11],
            fields[12],
        )
        name = cd[pos + 46 : pos + 46 + name_len].decode("utf-8", "replace")
        parts = name.split("/")
        if len(parts) > 2 and parts[0] == "lib":
            abi_bytes[parts[1]] += comp_size
        pos += 46 + name_len + extra_len + comment_len

    return abi_bytes, ids


def main(argv: list[str]) -> int:
    target = argv[1] if len(argv) > 1 else "build/app/outputs/apk/release"
    if not os.path.isdir(target):
        print(f"目录不存在: {target}", file=sys.stderr)
        return 2

    apks = sorted(f for f in os.listdir(target) if f.endswith(".apk"))
    if not apks:
        print(f"{target} 下没有 APK", file=sys.stderr)
        return 2

    failures = 0
    for name in apks:
        path = os.path.join(target, name)
        abi_bytes, schemes = inspect(path)
        size_mib = os.path.getsize(path) / 1024 / 1024
        lib_total = sum(abi_bytes.values()) / 1024 / 1024
        abis = " ".join(f"{k}={v / 1024 / 1024:.1f}MiB" for k, v in sorted(abi_bytes.items()))
        print(f"{name}")
        print(f"  大小 {size_mib:.1f} MiB（lib/ {lib_total:.1f} MiB）")
        print(f"  ABI  {abis or '（无原生库）'}")
        print(f"  签名 {', '.join(schemes) or '未签名'}")
        if len(abi_bytes) > 1:
            print(f"  ✗ 这个包里有 {len(abi_bytes)} 个 ABI，不是单架构包")
            failures += 1

    if failures:
        print(f"\n{failures} 个 APK 没通过 ABI 隔离检查", file=sys.stderr)
        return 1
    print("\nABI 隔离检查通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
