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
flutter build apk --release
```

产物：`build/app/outputs/apk/release/app-release.apk`

签名：`android/key.properties` 存在时使用其中的 keystore；不存在时使用仓库自带的占位签名（`android/app/dummy.keystore`）。正式签名可参考 `./scripts/prepare-android-release.sh`。

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
  libwebkit2gtk-4.1-dev
```

```bash
flutter pub get
flutter build linux --release
```

产物：`build/linux/x64/release/bundle/`（x64）。arm64 加 `--target-platform linux-arm64`。

## 四、用 GitHub Actions 构建（推荐）

工作流文件：`.github/workflows/build-custom.yaml`（名称 `Build custom clients`）。支持手动触发（workflow_dispatch）和推送 `v*` 标签。

```bash
# 手动触发（targets: all / android / linux / windows）
gh workflow run build-custom.yaml -R bchsjdss/fluffychat -f targets=all
gh run watch -R bchsjdss/fluffychat

# 或把当前提交打成标签，构建成功后自动发布 GitHub Release
git tag v2.11.6-bot1 && git push mine v2.11.6-bot1
```

### 四个 job

| job | 作用 |
| --- | --- |
| `quality` | `flutter analyze` 四个改动文件 + `flutter test test/bot_menu_test.dart`。`dart format` 只报告、不阻塞。 |
| `android` | 产出 `fluffychat-android-apk`（APK + `SHA256SUMS-android.txt`）。 |
| `linux` | x64 / arm64 矩阵，产出 `fluffychat-linux-{x64,arm64}`（tar.gz + 校验和）。 |
| `windows` | 产出 `fluffychat-windows`（安装包、免安装 zip、`SHA256SUMS-windows.txt`）。 |
| `release` | 仅在 `v*` 标签时运行，等前四个 job 成功后，把全部产物连同合并后的 `SHA256SUMS.txt`、`BUILD-INFO.txt` 发布为 GitHub Release。 |

`quality` 参与 `release` 的 `needs`：静态检查或单测失败时不会发布。

Android 的 `SHA256SUMS-*.txt` 与产物一起上传；`release` 会把它们合并成 `SHA256SUMS.txt`。

### Android 正式签名（可选，但建议）

默认情况下每次构建都会临时生成一次性 keystore，因此**不同次构建的 APK 签名不同，无法覆盖安装**（需先卸载旧版）。要固定签名，在仓库 Settings → Secrets and variables → Actions 中添加：

| Secret | 含义 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 your.keystore` 的结果 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 可选，默认 `fluffychatCustom` |
| `ANDROID_KEY_PASSWORD` | 可选，默认同 keystore 密码 |

配置后工作流使用该 keystore，并在 `Show signing fingerprint` 步骤打印 SHA256 指纹。四个 secret 前两个缺失时自动回退到一次性占位签名。

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

Release 里的 `BUILD-INFO.txt` 记录 tag、commit、构建时间和 Flutter 版本，便于确认产物对应哪次代码。

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

CI 上的验证（2026-11-24，run `45405808912`）：android / linux x64 / linux arm64 / windows 全部构建成功。
