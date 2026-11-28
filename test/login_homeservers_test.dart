// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// 回归测试：登录页的服务器列表必须是内置的、不联网的，而且默认值不能再是
// matrix.org（那个域名在部分网络里 TCP 443 直接超时，会把登录页卡在 waiting）。

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AppSettings 的 store 是进程级单例（init 只加载一次），所以两件事放在同一个
  // test 里按顺序验证：先验证「旧值 matrix.org 会被迁移」，迁移完再验证
  // 「当前默认值 = 内置服务器，且内置列表里没有 matrix.org」。
  test(
    'built-in homeservers replace matrix.org, stored value migrates',
    () async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.default_homeserver': 'matrix.org',
      });
      final store = await AppSettings.init(loadWebConfigFile: false);

      // 1. 内置列表只有一个服务器，且不是 matrix.org。
      expect(AppConfig.builtInHomeservers.length, 1);
      expect(AppConfig.builtInHomeservers, isNot(contains('matrix.org')));

      // 2. 已经落盘的旧值会被迁移到内置服务器（只改代码默认值救不了老安装）。
      expect(
        store.getString(AppSettings.defaultHomeserver.key),
        AppConfig.builtInHomeservers.first,
      );
      expect(AppSettings.defaultHomeserver.value, isNot('matrix.org'));
      expect(
        AppSettings.defaultHomeserver.defaultValue,
        AppConfig.builtInHomeservers.first,
      );
    },
  );
}
