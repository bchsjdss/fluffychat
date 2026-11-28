#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# 生成一次「长期固定」的 Android 签名密钥，并打印配置 GitHub secrets 需要的命令。
#
# 为什么要固定：APK 只能被同一张证书签名的包覆盖升级。以前 CI 每次 keytool
# -genkeypair 现生成一次性 key，指纹每次都变，用户升级必须先卸载（本地数据全丢）。
#
# 重要：keystore 与密码只存本地 + 仓库 secrets，绝不提交到仓库。
# 丢了这份文件，已装用户就再也升不了级（只能卸载重装）。
#
# 用法：
#   scripts/create-android-keystore.sh [输出目录]
# 默认输出目录：./android-signing（已在 .gitignore 里排除）
#
# 生成后按脚本打印的 gh secret set 命令配置 4 个 secret 即可。

set -euo pipefail

OUT_DIR="${1:-./android-signing}"
KEYSTORE="$OUT_DIR/android-custom.keystore"
PASS_FILE="$OUT_DIR/keystore-password.txt"
ALIAS="fluffychatCustom"

if ! command -v keytool >/dev/null 2>&1; then
  echo "找不到 keytool，先装 JDK 17（apt install openjdk-17-jdk-headless）" >&2
  exit 1
fi

if [ -e "$KEYSTORE" ]; then
  echo "已存在 $KEYSTORE，不覆盖（覆盖等于换签名，老用户就升不了了）。" >&2
  echo "确实要重新生成的，先自己挪走旧文件。" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

# 32 位随机密码，只含字母数字（免得 key.properties / shell 转义踩坑）
STORE_PASS=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)

keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -storetype PKCS12 \
  -storepass "$STORE_PASS" \
  -keypass "$STORE_PASS" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 \
  -validity 10950 \
  -dname "CN=FluffyChat Custom Build, OU=Custom clients, C=CN"

printf '%s' "$STORE_PASS" >"$PASS_FILE"
chmod 600 "$KEYSTORE" "$PASS_FILE"
base64 -w0 "$KEYSTORE" >"$KEYSTORE.b64"

echo
echo "生成完成："
echo "  keystore: $KEYSTORE"
echo "  密码:     $PASS_FILE（备份好，丢了就再也发不出能覆盖升级的包）"
echo "  base64:   $KEYSTORE.b64"
echo
keytool -list -v -keystore "$KEYSTORE" -storepass "$STORE_PASS" |
  grep -E 'Alias name|Owner|Valid from|SHA256:' || true
echo
echo "把下面的命令跑一遍（需要带 admin/Secrets 权限的 token）："
echo
printf 'gh secret set ANDROID_KEYSTORE_BASE64     --repo <owner>/<repo> < %s\n' "$KEYSTORE.b64"
printf 'gh secret set ANDROID_KEYSTORE_PASSWORD   --repo <owner>/<repo> --body %q\n' "$STORE_PASS"
printf 'gh secret set ANDROID_KEY_ALIAS           --repo <owner>/<repo> --body %q\n' "$ALIAS"
printf 'gh secret set ANDROID_KEY_PASSWORD        --repo <owner>/<repo> --body %q\n' "$STORE_PASS"
