#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# 检查 Linux 桌面产物里每个 ELF（可执行文件、.so）要求的最低 glibc / libstdc++ 版本。
#
# 为什么需要：Flutter 的 Linux 插件（flutter_webrtc、livekit_client、
# flutter_secure_storage、sqlcipher、webcrypto…）是构建机上现编译的，构建机的
# glibc 决定产物里 GLIBC_x.y 符号引用的上限。构建机换成更新的发行版，产物就会
# 悄悄要求用户没有的 glibc，装上都起不来（ldd 报 "version `GLIBC_2.43' not found"）。
#
# 用法：
#   scripts/check-linux-glibc-baseline.sh <bundle-dir> [max-glibc] [max-glibcxx]
# 例：
#   scripts/check-linux-glibc-baseline.sh build/linux/x64/release/bundle 2.35 3.4.30
#
# 环境变量：
#   REPORT_FILE  额外把结论写成 key=value 行（给 release 的 BUILD-INFO.txt 用）
#
# 退出码：0 达标；1 超出基线（并打印是哪个文件）；2 用法错误。

set -uo pipefail

BUNDLE_DIR="${1:-}"
MAX_GLIBC="${2:-2.35}"
MAX_GLIBCXX="${3:-3.4.30}"

usage() {
  echo "用法: $0 <bundle-dir> [max-glibc=2.35] [max-glibcxx=3.4.30]" >&2
  exit 2
}

[ -n "$BUNDLE_DIR" ] || usage
[ -d "$BUNDLE_DIR" ] || {
  echo "目录不存在: $BUNDLE_DIR" >&2
  exit 2
}

# sort -V：2.9 < 2.10 < 2.35，纯字典序会排错
vmax() { sort -V | tail -1; }

# $1=文件 $2=符号前缀（GLIBC_ / GLIBCXX_）；只返回版本号本身（2.43 / 3.4.32），
# 方便按 sort -V 比较，打印时再补前缀。
# 优先用 readelf -V（只看动态符号的版本需求，不会把字符串表里的注释也算进去）；
# 没有 readelf 时退回 grep -aoh，跟人工排查时的命令一致。
max_version() {
  local file="$1" prefix="$2"
  if command -v readelf >/dev/null 2>&1; then
    readelf -V "$file" 2>/dev/null | grep -o "${prefix}[0-9.]*" | sed "s/^${prefix}//" | vmax
  else
    grep -aoh "${prefix}[0-9.]*" "$file" 2>/dev/null | sed "s/^${prefix}//" | vmax
  fi
}

is_elf() {
  # ELF 魔数 7f 45 4c 46；用 od 避开 bash 命令替换丢失 NUL 字节的告警
  [ "$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]
}

# 版本比较：a > b 返回 0
gt_version() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ] && [ "$1" != "$2" ]; }

echo "bundle:      $BUNDLE_DIR"
echo "glibc 基线:  $MAX_GLIBC"
echo "libstdc++ 基线: $MAX_GLIBCXX"
echo

printf '%-58s %-10s %-12s\n' 'FILE' 'GLIBC' 'GLIBCXX'
printf '%-58s %-10s %-12s\n' '----' '-----' '-------'

worst_glibc=''
worst_glibc_file=''
worst_glibcxx=''
worst_glibcxx_file=''
bad_glibc=()
bad_glibcxx=()
total=0

while IFS= read -r -d '' file; do
  is_elf "$file" || continue
  total=$((total + 1))

  g=$(max_version "$file" 'GLIBC_')
  cxx=$(max_version "$file" 'GLIBCXX_')
  rel="${file#"$BUNDLE_DIR"/}"
  printf '%-58s %-10s %-12s\n' "$rel" "${g:+GLIBC_$g}" "${cxx:+GLIBCXX_$cxx}"

  if [ -n "$g" ]; then
    if [ -z "$worst_glibc" ] || gt_version "$g" "$worst_glibc"; then
      worst_glibc="$g"
      worst_glibc_file="$rel"
    fi
    gt_version "$g" "$MAX_GLIBC" && bad_glibc+=("$rel (GLIBC_$g)")
  fi

  if [ -n "$cxx" ]; then
    if [ -z "$worst_glibcxx" ] || gt_version "$cxx" "$worst_glibcxx"; then
      worst_glibcxx="$cxx"
      worst_glibcxx_file="$rel"
    fi
    gt_version "$cxx" "$MAX_GLIBCXX" && bad_glibcxx+=("$rel (GLIBCXX_$cxx)")
  fi
done < <(find "$BUNDLE_DIR" -type f -print0 | sort -z)

echo
echo "共检查 ELF 文件: $total"
echo "实测最高 GLIBC:    ${worst_glibc:-none}${worst_glibc:+   }${worst_glibc_file:-n/a}"
echo "实测最高 GLIBCXX:  ${worst_glibcxx:-none}${worst_glibcxx:+   }${worst_glibcxx_file:-n/a}"

status=0
if [ "${#bad_glibc[@]}" -gt 0 ]; then
  status=1
  echo
  echo "::error::以下文件要求的 glibc 高于基线 $MAX_GLIBC，在 Ubuntu 22.04 上会起不来："
  printf '  - %s\n' "${bad_glibc[@]}"
fi
if [ "${#bad_glibcxx[@]}" -gt 0 ]; then
  status=1
  echo
  echo "::error::以下文件要求的 libstdc++ 高于基线 $MAX_GLIBCXX："
  printf '  - %s\n' "${bad_glibcxx[@]}"
fi

if [ -n "${REPORT_FILE:-}" ]; then
  {
    echo "min-glibc=${worst_glibc:-unknown}"
    echo "min-glibcxx=${worst_glibcxx:-unknown}"
    echo "glibc-baseline=$MAX_GLIBC"
    echo "glibcxx-baseline=$MAX_GLIBCXX"
    echo "elf-files=$total"
  } >"$REPORT_FILE"
  echo
  echo "报告写入: $REPORT_FILE"
  cat "$REPORT_FILE"
fi

if [ "$status" -eq 0 ]; then
  echo
  echo "OK: 所有文件都在 GLIBC_$MAX_GLIBC / GLIBCXX_$MAX_GLIBCXX 基线以内。"
else
  echo
  echo "FAIL: 产物超出基线，检查构建 runner 的发行版（见 BUILD.md「Linux 构建基线」）。"
fi

exit "$status"
