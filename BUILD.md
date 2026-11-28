# 自定义客户端构建说明（bot 菜单版）

本仓库在 FluffyChat 2.11.6 的基础上增加了「服务端动态命令菜单」。

## 一、改了什么

| 文件 | 改动 |
| --- | --- |
| `lib/utils/bot_menu.dart` | 新增。读取房间状态 `im.pi.bot.menu`，解析 `commands` 列表。 |
| `lib/pages/chat/input_bar.dart` | 输入 `/` 时，把服务端命令放在候选浮层顶部。点击后填入 `/cmd ` 并把光标放到末尾。 |
| `lib/pages/chat/chat.dart` | `send()` 拦截器。命令在服务端菜单里时，跳过本地命令解析，直接发文本。 |
| `test/bot_menu_test.dart` | 新增。菜单解析、去重、查找、排序的单元测试。 |

注意：原方案写的 `chat_view.dart` 里没有 `send()`。发送逻辑在 `lib/pages/chat/chat.dart` 的 `ChatController.send()`。

`room.sendTextEvent()` 走房间的加密通道。开启加密的房间中，消息自动端到端加密。

## 二、房间状态格式

事件类型：`im.pi.bot.menu`。状态键：空字符串。

```json
{
  "commands": [
    { "cmd": "/help", "desc": "显示帮助" },
    { "cmd": "/poll start", "desc": "发起投票" }
  ]
}
```

兼容写法：

- 条目可以是字符串，例如 `"/help"`。
- `cmd` 可以写成 `command` 或 `name`。可以不带前导 `/`。
- `desc` 可以写成 `description` 或 `help`。

客户端行为：

1. 输入 `/` 后列出全部命令。继续输入则按名称筛选，前缀匹配在前。
2. 服务端命令排在客户端内置命令之前。同名时只显示服务端条目。
3. 点击条目填入 `/cmd `，光标在末尾。
4. 发送时，命令名在菜单中就跳过本地解析，按原文本发送。
5. 命令名不在菜单、也不在客户端内置命令中时，仍弹出「命令无效」对话框。

服务端可用下面命令发布该状态：

```bash
curl -X PUT \
  "https://matrix.example.org/_matrix/client/v3/rooms/!room:example.org/state/im.pi.bot.menu/" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"commands":[{"cmd":"/help","desc":"显示帮助"}]}'
```

## 三、本地构建

三平台都要求：

- Flutter 3.47.9（见 `.fvmrc`）
- Rust 工具链（`rustup` 稳定版），`flutter_vodozemac` 需要
- 首次构建前执行 `flutter pub get`

### Android

额外要求：Android SDK 37、NDK、JDK 17。

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

产物：`build/app/outputs/apk/release/app-<abi>-release.apk`，每个包只含一个 CPU 架构：

| APK | 适用设备 | 体积 |
|---|---|---|
| `app-arm64-v8a-release.apk` | 2017 年后的 64 位手机（绝大多数） | 约 62 MiB（估算） |
| `app-armeabi-v7a-release.apk` | 老的 32 位手机 | 约 55 MiB（估算） |
| `app-x86_64-release.apk` | Android 模拟器 | 约 69 MiB（估算） |

上面三行体积是拿 universal 包的 `lib/` 分布推算的，没有实测过单 ABI 包；CI 的
`Verify every APK holds exactly one ABI` 步骤会把实际大小打印出来。

**不要再发 universal APK**（不带 `--split-per-abi` 的 `flutter build apk --release`）。
实测 v2.11.6 的 universal 包 189.2 MiB，其中 184.1 MiB 是四个 ABI 各塞一份原生库：
`x86_64` 64.0 MiB、`arm64-v8a` 57.4 MiB、`armeabi-v7a` 50.0 MiB、`x86` 12.6 MiB，
非库部分（dex + 资源）只有 5.1 MiB。

CI 构建后跑 `python3 scripts/verify_apk_abi.py build/app/outputs/apk/release`，
任何一个包出现第二个 ABI 目录就直接失败。`android/app/build.gradle.kts` 里那段
`ndk { abiFilters += ... }` 是绕 Flutter #162153 的 workaround，如果拆分失效先查这里。

签名（v2.11.6-bot7 起固定，见下）：

- 只有 v2 方案，没有 v1 JAR 签名。证书 `CN = FluffyChat Custom Build`（OU = Custom clients），
  自签名，RSA 2048，有效期到 2056-11-20，SHA-256 指纹
  `A2:EA:F9:40:57:E3:01:69:54:CF:9F:39:AC:E5:5A:9E:5D:93:EE:B9:90:5C:58:1B:75:54:AC:3F:ED:B6:94:13`。
- 这张证书由 `scripts/create-android-keystore.sh` 生成一次，base64 后存进仓库 secret
  `ANDROID_KEYSTORE_BASE64`（+ 密码/别名，见第四节）。CI **不再**每次现生成一次性 key：
  没配 secret 时 android job 直接失败，不会静默产出一个升不了级的包。
- 换签名那次升级需要先卸载一次旧版（旧包是历史上的一次性 key 签的，跟新证书对不上）；
  从 bot7 往后同一个包名可以**直接覆盖升级**，本地数据不丢。
- Android 6 及以下不认 v2-only 签名，会报「未包含证书」/「解析软件包出现问题」。

### Windows

必须在 Windows 主机上构建。Flutter 不支持在 Linux 上交叉编译 Windows 应用。

```powershell
flutter pub get
flutter build windows --release
./scripts/package-windows.ps1 -BuildMode Release
```

产物：

- `build/windows/x64/runner/Release/`（可运行目录）
- `build/windows/installer/fluffychat-windows-x64-setup.exe`（安装包，需要 Inno Setup）
- `build/windows/installer/fluffychat-windows-x64.zip`（免安装包）

### Linux

额外要求（Debian/Ubuntu）：

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev \
  libblkid-dev liblzma-dev libjsoncpp-dev libsecret-1-dev libssl-dev \
  libsoup-3.0-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev \
  libayatana-indicator3-dev libdbusmenu-glib-dev
```

```bash
flutter pub get
flutter build linux --release
```

产物：`build/linux/x64/release/bundle/`（x64）。arm64 加 `--target-platform linux-arm64`。

#### Linux 构建基线（glibc 2.35 / libstdc++ 3.4.30）

产物必须能在 **Ubuntu 22.04+** 上直接跑。Flutter 的 Linux 插件（`flutter_webrtc`、
`livekit_client`、`flutter_secure_storage`、`sqlcipher`、`webcrypto`）都是**构建机上现编译的**，
构建机的 glibc 会原样写进产物的 `GLIBC_x.y` 符号引用。在 26.04（glibc 2.43）上构建，
产物会要求 `GLIBC_2.38`/`GLIBC_2.43` 和 `GLIBCXX_3.4.32`，22.04 用户 `ldd` 就报
`version 'GLIBC_2.43' not found`，装上起不来。

所以构建环境固定在 glibc 2.35：CI 的 linux job 跑 `ubuntu-22.04` / `ubuntu-22.04-arm`，
**不要**改回 `ubuntu-latest`/`ubuntu-26.04`。本地用 22.04 或 `ubuntu:22.04` 容器构建。

构建后跑自检（CI 里同名步骤，超标直接让 job 失败）：

```bash
REPORT_FILE=glibc-baseline-linux-x64.txt \
  scripts/check-linux-glibc-baseline.sh build/linux/x64/release/bundle 2.35 3.4.30
```

脚本遍历 bundle 里所有 ELF（可执行文件 + `.so`），取每个文件的最高 `GLIBC_x.y` 与
`GLIBCXX_x.y`（本质上就是 `readelf -V | grep -o 'GLIBC_[0-9.]*' | sort -V | tail -1`，
没有 `readelf` 时退回 `grep -aoh`），超过基线就列出是哪几个文件并退出 1。

第三方预编译库不在这条规则覆盖范围内：`lib/libsqlcipher.so` 来自 `sqlite3` 3.5.0 的
hook（直接下载上游编好的二进制，不在构建机上编译），上游用了新发行版，硬顶
`GLIBC_2.38`。它是桌面版的消息数据库，所以**桌面版实际下限是 glibc 2.38（Ubuntu 24.04+
/ Debian 13+）**；CI 用 `ALLOW_GLIBC='lib/libsqlcipher.so:2.38'` 把这一条降级成
warning，其余文件仍然按 2.35 卡。要在 22.04 上跑，需要改用 `sqlite3` 的
`source: source` 模式自己编 SQLCipher（需要 OpenSSL 开发包），目前没有做。

运行时依赖（不打包，靠系统 apt）：

```bash
sudo apt-get install -y libmpv1    # Ubuntu 22.04；24.04+ 是 libmpv2，没有它语音/视频消息静音
```

`libwebkit2gtk-4.1-0`、`libsecret-1-0`、`libayatana-appindicator3-1`、`libdbusmenu-glib-0`、
`libgtk-3-0` 一般随桌面环境已存在。

## 四、用 GitHub Actions 构建（推荐）

工作流文件：`.github/workflows/build-custom.yaml`（名称 `Build custom clients`）。支持手动触发（workflow_dispatch）和推送 `v*` 标签。

```bash
# 手动触发（targets: all / android / linux / windows）
gh workflow run build-custom.yaml -R bchsjdss/fluffychat -f targets=all
gh run watch -R bchsjdss/fluffychat

# 或把当前提交打成标签，构建成功后自动发布 GitHub Release
git tag v2.11.6-bot2 && git push mine v2.11.6-bot2
```

### 四个 job

| job | 作用 |
| --- | --- |
| `quality` | `flutter analyze` 四个改动文件 + `flutter test test/bot_menu_test.dart`。`dart format` 只报告、不阻塞。 |
| `android` | 产出 `fluffychat-android-apk`（APK + `SHA256SUMS-android.txt` + `cert-sha256`）。缺 keystore secret 时**故意失败**。 |
| `linux` | x64 / arm64 矩阵，跑在 `ubuntu-22.04` / `ubuntu-22.04-arm`（glibc 2.35）；构建后跑 glibc 基线自检，超标即失败；产出 tar.gz + 校验和 + `glibc-baseline-linux-*.txt`。 |
| `windows` | 产出 `fluffychat-windows`（安装包、免安装 zip、`SHA256SUMS-windows.txt`）。 |
| `release` | 仅在 `v*` 标签时运行，等前四个 job 成功后，把全部产物连同合并后的 `SHA256SUMS.txt`、`BUILD-INFO.txt` 发布为 GitHub Release。 |

`quality` 参与 `release` 的 `needs`：静态检查或单测失败时不会发布。

Android 的 `SHA256SUMS-*.txt` 与产物一起上传；`release` 会把它们合并成 `SHA256SUMS.txt`。

### Android 固定签名（必须配置）

CI 只从仓库 secrets 取 keystore，**缺失时 android job 直接失败**（宁可不出包，也不要再发一个
升不了级的包）。四个 secret：

| Secret | 含义 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 android-custom.keystore` 的结果 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码（PKCS12 下 key 密码与它相同） |
| `ANDROID_KEY_ALIAS` | 可选，默认 `fluffychatCustom`（PKCS12 里存成小写） |
| `ANDROID_KEY_PASSWORD` | 可选，默认同 keystore 密码 |

生成一份新的固定密钥：

```bash
scripts/create-android-keystore.sh        # 产物在 ./android-signing/（已 gitignore）
```

脚本会打印对应的 4 条 `gh secret set` 命令。keystore 与密码只留在本地和 secrets，
**绝不进仓库**；备份丢了就等于所有已装用户再也升不了级。

当前在用的证书指纹（SHA-256）：

```
A2:EA:F9:40:57:E3:01:69:54:CF:9F:39:AC:E5:5A:9E:5D:93:EE:B9:90:5C:58:1B:75:54:AC:3F:ED:B6:94:13
```

`Verify APK signing certificate` 步骤会用 `apksigner verify --print-certs` 读**实际产物**的证书，
三个 ABI 的指纹不一致就直接失败，并把 `cert-sha256` 写进 Release 的 `BUILD-INFO.txt`。

### 校验产物

```bash
gh run download <run-id> -R bchsjdss/fluffychat -D /work/dist
cd /work/dist
sha256sum -c SHA256SUMS-*.txt    # 单个 artifact 自带校验文件
# 或从 Release 下载时：
sha256sum -c SHA256SUMS.txt
```

Windows 上：

```powershell
Get-FileHash .\fluffychat-windows-x64-setup.exe -Algorithm SHA256
```

Release 里的 `BUILD-INFO.txt` 记录 tag、commit、构建时间和 Flutter 版本，以及两个跟「能不能跑」
直接相关的字段：

- `min glibc: 2.35` —— 产物里实测的最高 `GLIBC_x.y`（由 linux job 的基线自检写入，不是手填）。
- `runtime apt deps: …` —— 运行时 apt 依赖，至少 `libmpv2`（24.04+）/`libmpv1`（22.04），
  不装则语音/视频消息静音。
- `android signature: <cert-sha256>` —— 实际签名证书指纹（`apksigner verify --print-certs`）。

### 缓存

- Flutter SDK 与 pub 依赖：`subosito/flutter-action` 的 `cache: true`。
- Rust 依赖（`flutter_vodozemac` 等）：`Swatinem/rust-cache`，按平台/架构分 key。

## 五、本机（aarch64 Linux）的限制

当前开发机是 Debian 12 / aarch64，没有 root 权限。因此不能在本机出包：

1. Flutter 官方只发布 x86_64 的 Linux SDK（`releases_linux.json` 中没有 arm64 条目）。工具链无法在本机运行。
2. Linux 桌面构建需要 GTK3 开发头文件、clang、cmake、ninja。无 root 无法安装。
3. Windows 目标需要 MSVC，只能在本机 Windows 上构建。

代码层面的验证已完成（2026-11-24）：

- `dart format`（Dart 3.13.7 / linux_arm64）解析三个改动文件通过，无语法错误。
- `bot_menu.dart` 用桩版 matrix SDK 做了 `dart analyze`（无问题）和 17 项行为断言，全部通过。
- YAML 工作流解析通过。
- 完整编译和 `dart analyze` 需要在 x86_64 构建机上执行。

CI 上的验证：

- 2026-11-24，run `45405808912`：android / linux x64 / linux arm64 / windows 全部构建成功。
- 2026-11-25，run `45548009279`（本版工作流首跑）：quality 2m52s、android 18m9s、linux x64 4m7s、linux arm64 4m16s、windows 10m27s，全部成功；`quality` 的 7 个单测与 `flutter analyze` 均通过，`linux-x64` 的 `SHA256SUMS` 本地校验通过；非 tag 运行下 `release` job 按预期跳过。
- 2026-11-25，tag `v2.11.6-bot2`（run `45552868351`）：5 个 job + `release` 全部成功，发布 https://github.com/bchsjdss/fluffychat/releases/tag/v2.11.6-bot2 ；资产含 `fluffychat-android-v2.11.6-bot2.apk`、`fluffychat-linux-{x64,arm64}.tar.gz`、`fluffychat-windows-x64-{setup.exe,.zip}`、`SHA256SUMS.txt`、`BUILD-INFO.txt`；APK 下载后 `sha256sum -c` 通过。
- 缓存效果：linux x64 从 4m7s 降到 3m14s / 4m35s，quality 约 2m40s，android 仍为耗时瓶颈（18–20 分钟，取决于 Gradle/Rust 缓存命中）。
