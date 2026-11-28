// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// 回归测试：登录页的服务器列表必须是内置的、不联网的，而且默认值不能再是
// matrix.org（那个域名在部分网络里 TCP 443 直接超时，会把登录页卡在 waiting）。
//
// 外加把手输裸地址的规范化钉住：输入 `matrix.toolokai.com:23456` 时必须得到
// `https://matrix.toolokai.com:23456`，不能再出现
// `No host specified in URI matrix.toolokai.com:_matrix/client/versions`。

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/sign_in_flows/check_homeserver.dart';
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

  group('normalizeHomeserverUri', () {
    test('bug 现场：裸 host:port 被 Uri.parse 解成 scheme，host 为空', () {
      // 这就是安卓上报错的形状，保留断言防止以后回退。
      final broken = Uri.parse('matrix.toolokai.com:23456');
      expect(broken.scheme, 'matrix.toolokai.com');
      expect(broken.host, isEmpty);
      expect(
        '${broken.resolve('/_matrix/client/versions')}',
        isNot(startsWith('https://matrix.toolokai.com')),
      );

      final fixed = normalizeHomeserverUri('matrix.toolokai.com:23456');
      expect(fixed.scheme, 'https');
      expect(fixed.host, 'matrix.toolokai.com');
      expect(fixed.port, 23456);
      expect(
        '${fixed.resolve('/_matrix/client/versions')}',
        'https://matrix.toolokai.com:23456/_matrix/client/versions',
      );
    });

    test('各种裸地址写法都拿到同一个 base URL', () {
      for (final input in [
        'matrix.toolokai.com:23456',
        'matrix.toolokai.com:23456/',
        '  matrix.toolokai.com:23456  ',
        '//matrix.toolokai.com:23456',
      ]) {
        final uri = normalizeHomeserverUri(input);
        // 尾斜杠有没有都行，探测时是 resolve('/_matrix/client/versions')，
        // 所以这里比的是 origin（scheme + host + port）。
        expect(
          uri.origin,
          'https://matrix.toolokai.com:23456',
          reason: 'input: $input',
        );
        expect(uri.host, 'matrix.toolokai.com', reason: 'input: $input');
        expect(uri.port, 23456, reason: 'input: $input');
      }
    });

    test('写了协议的保留协议，别再套一层 https', () {
      expect(
        normalizeHomeserverUri('https://example.org:8448').origin,
        'https://example.org:8448',
      );
      expect(
        normalizeHomeserverUri('http://example.org:8008').origin,
        'http://example.org:8008',
      );
      // 其他协议按 https 处理，不再拼出不可能成立的 URI。
      expect(
        normalizeHomeserverUri('ftp://example.org').origin,
        'https://example.org',
      );
    });

    test('主机名、ipv6、带路径的输入也能规范化', () {
      expect(
        normalizeHomeserverUri('matrix.toolokai.com').host,
        'matrix.toolokai.com',
      );
      expect(normalizeHomeserverUri('localhost:8448').port, 8448);
      expect(normalizeHomeserverUri('[::1]:8448').host, '::1');
      final withPath = normalizeHomeserverUri('example.org/matrix');
      expect(withPath.host, 'example.org');
      expect(withPath.path, '/matrix');
    });

    test('空串 / 纯斜杠直接报错，不会发出无 host 的请求', () {
      expect(() => normalizeHomeserverUri(''), throwsFormatException);
      expect(() => normalizeHomeserverUri('   '), throwsFormatException);
      expect(() => normalizeHomeserverUri('https://'), throwsFormatException);
    });

    test('规范化后的地址拼出来的探测 URL 一定带 host', () {
      // 这是“能不能探测成功”的硬前提：错误报文就是
      // `No host specified in URI matrix.toolokai.com:_matrix/client/versions`。
      for (final input in [
        'matrix.toolokai.com:23456',
        '127.0.0.1:6167',
        'localhost:8008',
      ]) {
        final probe = normalizeHomeserverUri(
          input,
        ).resolve('/_matrix/client/versions');
        expect(probe.host, isNotEmpty, reason: 'input: $input');
        expect(probe.scheme, 'https', reason: 'input: $input');
        expect(probe.path, '/_matrix/client/versions', reason: 'input: $input');
        expect(probe.toString(), contains('${probe.host}:${probe.port}'));
      }
    });
  });
}
