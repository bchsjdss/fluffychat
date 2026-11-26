# 桌面端托盘常驻（Windows / Linux）

IM 客户端关掉窗口就退出、通知全停，这事不合理。桌面构建现在关闭窗口只隐藏，
进程和同步循环继续跑；退出走**独立入口**，不会误杀。

## 行为矩阵

| 环境 | 点关闭按钮 | 怎么真正退出 |
|---|---|---|
| Windows | 窗口隐藏，通知区出现图标 | 托盘菜单「退出」/ `Ctrl+Q` |
| Linux，面板支持 StatusNotifierItem（KDE、Xfce、Ubuntu、GNOME + AppIndicator 扩展） | 窗口隐藏，托盘图标常驻 | 托盘菜单「退出」/ `Ctrl+Q` |
| Linux，会话总线上没有 `org.kde.StatusNotifierWatcher`（例如裸 GNOME） | 最小化到任务栏（窗口不能消失，否则没有入口） | `Ctrl+Q` |
| 托盘创建失败（插件缺失等） | 退回旧行为：关闭即退出 | — |

判定「托盘图标是否真的看得见」不靠猜：Linux 上有托盘图标的唯一真凭据是
`org.kde.StatusNotifierWatcher` 上 `IsStatusNotifierHostRegistered = true`。
没有 host 时图标会被创建但永远不绘制，所以这种情况我们选择最小化而不是隐藏。

## 依赖

- Dart：`tray_manager`（图标 + 菜单）、`window_manager`（拦截关闭 / 隐藏 / 最小化）、`dbus`（探测托盘宿主；本来就是 `desktop_drop` 的传递依赖）
- Linux 构建期：`libayatana-appindicator3-dev`（三个 linux 构建任务都已加）
- Linux 运行期：`libayatana-appindicator3-1`。注意 Flutter Linux 的插件是启动时链接进主程序的，**缺这个库会导致程序起不来**，不是"托盘不显示"这种温和降级。Debian/Ubuntu：`apt install libayatana-appindicator3-1`；GNOME 还需要 `gnome-shell-extension-appindicator`（包名因发行版而异）。
- 图标资源：`assets/tray_icon.png`（Linux）、`assets/tray_icon.ico`（Windows，16/24/32/48），由 `windows/runner/resources/app_icon.ico` 转换而来。

## 代码位置

- `lib/utils/desktop_tray.dart`：全部逻辑（`DesktopTray` 单例）
- `lib/main.dart`：`startGui()` 里 Windows/Linux 才 `DesktopTray.instance.init()`
- macOS 不动，沿用平台默认（关最后一个窗口即退出）

## 手工验收

1. 启动应用 → 通知区/面板出现图标
2. 点窗口关闭按钮 → 窗口消失，进程仍在（`ps` / 任务管理器可见），新消息通知照常弹出
3. 点托盘图标 → 窗口回来并聚焦；右键 → 菜单两项
4. 托盘菜单「退出」/ `Ctrl+Q` → 进程真的退出
5. 裸 GNOME（无 AppIndicator 扩展）上重复第 2 步 → 应变成任务栏最小化，且 `Ctrl+Q` 能退出
