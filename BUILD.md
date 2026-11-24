# 自定义客户端构建说明（bot 菜单版）

本仓库在 FluffyChat 2.11.6 的基础上增加了「服务端动态命令菜单」。

## 一、改了什么

| 文件 | 改动 |
| --- | --- |
| `lib/utils/bot_menu.dart` | 新增。读取房间状态 `im.pi.bot.menu`，解析 `commands` 列表。 |
| `lib/pages/chat/input_bar.dart` | 输入 `/` 时，把服务端命令放在候选浮层顶部。点击后填入 `/cmd ` 并把光标放到末尾。 |
| `lib/pages/chat/chat.dart` | `send()` 拦截器。命令在服务端菜单里时，跳过本地命令解析，直接发文本。 |

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

## 三、构建

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

未配置 `android/key.properties` 时，使用仓库自带的占位签名。需要正式签名时，先执行 `./scripts/prepare-android-release.sh`。

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

推送到 GitHub 后，运行工作流 `Build custom clients`（`.github/workflows/build-custom.yaml`）。支持手动触发（workflow_dispatch）和推送 `v*` 标签。

工作流产出三个 artifact：

- `fluffychat-android-apk`：APK
- `fluffychat-linux-x64` / `fluffychat-linux-arm64`：tar.gz
- `fluffychat-windows`：安装包和免安装 zip

不需要任何 secret。Android 使用占位签名。

## 五、本机（aarch64 Linux）的限制

当前开发机是 Debian 12 / aarch64，没有 root 权限。因此不能在本机出包：

1. Flutter 官方只发布 x86_64 的 Linux SDK（`releases_linux.json` 中没有 arm64 条目）。工具链无法在本机运行。
2. Linux 桌面构建需要 GTK3 开发头文件、clang、cmake、ninja。无 root 无法安装。
3. Windows 目标需要 MSVC，只能在本机 Windows 上构建。

代码层面的验证已完成：

- `dart format`（Dart 3.13.7 / linux_arm64）解析三个改动文件通过，无语法错误。
- `bot_menu.dart` 用桩版 matrix SDK 做了 `dart analyze`（无问题）和 17 项行为断言，全部通过。
- YAML 工作流解析通过。
- 完整编译和 `dart analyze` 需要在 x86_64 构建机上执行。
