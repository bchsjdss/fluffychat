// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// What the window close button does while the app keeps running.
enum DesktopCloseAction {
  /// Tray icon is reachable: hide the window, the tray keeps the app visible.
  hideToTray,

  /// No tray host on this desktop: minimize instead, so the taskbar entry
  /// stays and the app can never become invisible with no way back.
  minimize,
}

/// Keeps the desktop app alive in the system tray.
///
/// IM clients are expected to stay reachable: closing the window only hides it
/// and the process keeps syncing, so notifications still arrive. Quitting is a
/// separate action (tray menu → 退出, or Ctrl+Q) so nobody kills their session
/// by accident.
///
/// Only Windows and Linux are handled; macOS keeps its platform default
/// (closing the last window is a documented quit there).
class DesktopTray with TrayListener, WindowListener {
  DesktopTray._();

  static final DesktopTray instance = DesktopTray._();

  /// Tray icon file, resolved by the plugin relative to
  /// `<executable>/data/flutter_assets/`. Windows' `LoadImage` needs an `.ico`,
  /// Linux' appindicator is happy with a `.png`.
  static String get _iconAsset =>
      Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png';

  static const String _tooltip = 'FluffyChat · 在后台运行';
  static const String _tooltipMinimized = 'FluffyChat · 关闭窗口会最小化';
  static const String _menuShow = 'show';
  static const String _menuQuit = 'quit';

  /// Cut-off for the D-Bus probe; a hung bus must not delay app start.
  static const Duration _probeTimeout = Duration(seconds: 2);

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  bool _ready = false;
  bool _quitting = false;
  bool _trayHostRegistered = true;
  DesktopCloseAction _closeAction = DesktopCloseAction.hideToTray;

  /// Whether the tray icon is actually available.
  ///
  /// When the platform refuses (e.g. Linux without libayatana-appindicator) we
  /// keep the old "close means quit" behaviour instead of trapping the user in
  /// a process with no window and no tray icon.
  bool get isReady => _ready;

  /// What closing the window is expected to do; exposed for diagnostics.
  DesktopCloseAction get closeAction => _closeAction;

  Future<void> init() async {
    if (!isSupported || _ready) return;
    try {
      await windowManager.ensureInitialized();

      // Linux tray icons are StatusNotifierItems: without a host (KDE/Xfce
      // panels, or the GNOME AppIndicator extension) the icon is created but
      // never shown, so hiding the window would strand the app.
      if (Platform.isLinux) {
        _trayHostRegistered = await _isStatusNotifierHostRegistered();
        if (!_trayHostRegistered) {
          Logs().w(
            '[DesktopTray] no StatusNotifier host on the session bus '
            '(GNOME needs the AppIndicator extension): closing will minimize '
            'instead of hiding',
          );
        }
      }

      await trayManager.setIcon(_iconAsset);
      await trayManager.setToolTip(
        _trayHostRegistered ? _tooltip : _tooltipMinimized,
      );
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: _menuShow, label: '打开主窗口'),
            MenuItem.separator(),
            MenuItem(key: _menuQuit, label: '退出'),
          ],
        ),
      );
      trayManager.addListener(this);
      windowManager.addListener(this);
      // Ctrl+Q stays available even when the tray icon is invisible.
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      await windowManager.setPreventClose(true);
      _closeAction = _trayHostRegistered
          ? DesktopCloseAction.hideToTray
          : DesktopCloseAction.minimize;
      _ready = true;
      Logs().i(
        '[DesktopTray] tray ready, closing the window will '
        '${_closeAction == DesktopCloseAction.hideToTray ? 'hide to tray' : 'minimize'}',
      );
    } catch (e, s) {
      _ready = false;
      Logs().w(
        '[DesktopTray] tray unavailable, keeping close-quits behaviour',
        e,
        s,
      );
      await _setPreventClose(false);
    }
  }

  Future<void> dispose() async {
    if (!isSupported || !_ready) return;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _ready = false;
  }

  /// Hides the window and keeps the process (and the sync loop) running.
  Future<void> hideToTray() async {
    if (!_ready || _quitting) return;
    try {
      await windowManager.hide();
    } catch (e, s) {
      Logs().w('[DesktopTray] hide failed', e, s);
    }
  }

  /// Keeps the taskbar entry, used when no tray host can show the icon.
  Future<void> minimizeWindow() async {
    if (!_ready || _quitting) return;
    try {
      await windowManager.minimize();
    } catch (e, s) {
      Logs().w('[DesktopTray] minimize failed', e, s);
    }
  }

  /// Real quit: reachable from the tray menu and Ctrl+Q.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    await _setPreventClose(false);
    try {
      await trayManager.destroy();
    } catch (e, s) {
      Logs().w('[DesktopTray] tray destroy failed', e, s);
    }
    try {
      await windowManager.destroy();
    } catch (e, s) {
      Logs().w('[DesktopTray] window destroy failed, falling back', e, s);
      exit(0);
    }
  }

  /// Asks the session bus whether somebody would display our tray icon.
  ///
  /// `org.kde.StatusNotifierWatcher` is the single source of truth for
  /// StatusNotifierItem trays: panels and extensions register a host there, and
  /// without a registered host a created icon is simply never drawn.
  Future<bool> _isStatusNotifierHostRegistered() async {
    DBusClient? client;
    try {
      client = DBusClient.session();
      final watcher = DBusRemoteObject(
        client,
        name: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      final registered = await watcher
          .getProperty(
            'org.kde.StatusNotifierWatcher',
            'IsStatusNotifierHostRegistered',
          )
          .timeout(_probeTimeout);
      return registered.asBoolean();
    } catch (e, s) {
      Logs().d('[DesktopTray] StatusNotifier watcher probe failed', e, s);
      return false;
    } finally {
      try {
        await client?.close();
      } catch (_) {
        // Closing a dead bus connection is not worth reporting.
      }
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_quitting || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyQ) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed || keyboard.isAltPressed) return false;
    unawaited(quit());
    return true;
  }

  Future<void> _setPreventClose(bool value) async {
    try {
      await windowManager.setPreventClose(value);
    } catch (e, s) {
      Logs().w('[DesktopTray] setPreventClose($value) failed', e, s);
    }
  }

  Future<void> _showWindow() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      if (!await windowManager.isVisible()) {
        await windowManager.show();
      }
      await windowManager.focus();
    } catch (e, s) {
      Logs().w('[DesktopTray] show window failed', e, s);
    }
  }

  @override
  void onWindowClose() {
    // window_manager with setPreventClose(true) routes the close button here
    // instead of destroying the window.
    if (!_ready || _quitting) return;
    switch (_closeAction) {
      case DesktopCloseAction.hideToTray:
        unawaited(hideToTray());
      case DesktopCloseAction.minimize:
        unawaited(minimizeWindow());
    }
  }

  @override
  void onTrayIconMouseDown() => unawaited(_showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(_popUpMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _menuShow:
        unawaited(_showWindow());
      case _menuQuit:
        unawaited(quit());
    }
  }

  Future<void> _popUpMenu() async {
    try {
      await trayManager.popUpContextMenu();
    } catch (e, s) {
      Logs().w('[DesktopTray] popup menu failed', e, s);
    }
  }
}
