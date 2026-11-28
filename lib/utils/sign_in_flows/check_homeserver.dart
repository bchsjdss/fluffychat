// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/oidc_login.dart';
import 'package:fluffychat/utils/sign_in_flows/sso_login.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// 把手输的 homeserver 地址规范成 http(s) URI。
///
/// 登录页、注册页、`presetHomeserver`、内置列表拿到的都是裸字符串，可能写成
/// `matrix.toolokai.com:23456`、`matrix.toolokai.com:23456/`、
/// `https://matrix.toolokai.com:23456`。
///
/// 关键坑：`Uri.parse('matrix.toolokai.com:23456')` 里 `matrix.toolokai.com:`
/// 符合 URI scheme 的语法，于是 scheme 被解成 `matrix.toolokai.com`、host 为空。
/// 探测器再往这个 URI 上 resolve `_matrix/client/versions`，拼出来的就是
/// `matrix.toolokai.com:_matrix/client/versions`，报 `No host specified in URI`。
///
/// 也不能用 `Uri.https(input, '')` 兜底：它的第一个参数必须是纯 authority，
/// `host:port/` 或 `host/sub` 会抛 FormatException。这里统一走
/// `Uri.parse('https://…')`，端口和可选路径都交给它解析。
///
/// 只认 http/https：homeserver 的 base URL 只有这两种协议有意义，别的协议
/// （手滑写成 `ftp://…`、`matrix://…`）也按 https 处理，而不是拼出一个不可能
/// 成立的 URI 再让探测器报一个看不懂的网络错误。
Uri normalizeHomeserverUri(String input) {
  final trimmed = input.trim();
  final parsed = Uri.tryParse(trimmed);
  final hasHttpScheme =
      parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https');
  if (hasHttpScheme && parsed.host.isNotEmpty) {
    return parsed;
  }
  // 写了 http(s) 却没写主机名（例如 `https://`）：直接报错，而不是拼出一个
  // host 为空的 URI 再让探测器报 `No host specified in URI`。
  if (hasHttpScheme) {
    throw FormatException('Not a valid homeserver address', input);
  }
  if (parsed != null && parsed.hasAuthority && parsed.host.isNotEmpty) {
    return parsed.replace(scheme: 'https');
  }
  final withoutLeadingSlashes = trimmed.replaceFirst(RegExp(r'^/+'), '');
  final uri = Uri.tryParse('https://$withoutLeadingSlashes');
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException('Not a valid homeserver address', input);
  }
  return uri;
}

Future<void> connectToHomeserverFlow(
  PublicHomeserverData homeserverData,
  BuildContext context,
  void Function(AsyncSnapshot<bool>) setState,
  bool signUp,
) async {
  setState(AsyncSnapshot.waiting());
  try {
    final homeserverInput = homeserverData.name!;
    // 登录与注册两条流程共用这里，所有入口（手输、内置列表、presetHomeserver、
    // 深链）拿到的裸地址都在这里一次性规范化。
    final homeserver = normalizeHomeserverUri(homeserverInput);
    final l10n = L10n.of(context);
    final client = await Matrix.of(context).getLoginClient();
    final (_, _, loginFlows, authMetadata) = await client
        .checkHomeserver(homeserver, fetchAuthMetadata: true)
        .timeout(AppConfig.homeserverConnectTimeout);

    final regLink = homeserverData.regLink;
    final supportsSso = loginFlows.any((flow) => flow.type == 'm.login.sso');

    if ((kIsWeb || PlatformInfos.isLinux) &&
        (supportsSso || authMetadata != null || (signUp && regLink != null))) {
      if (!context.mounted) return;
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: l10n.appWantsToUseForLogin(homeserverInput),
        message: l10n.appWantsToUseForLoginDescription,
        okLabel: l10n.continueText,
      );
      if (consent != OkCancelResult.ok) return;
      if (!context.mounted) return;
    }
    if (!context.mounted) return;

    if (authMetadata != null && AppSettings.enableMatrixNativeOIDC.value) {
      await oidcLoginFlow(client, context, signUp);
    } else if (supportsSso) {
      await ssoLoginFlow(client, context, signUp, loginFlows);
    } else {
      if (signUp && regLink != null) {
        await launchUrlString(regLink);
      }
      if (!context.mounted) return;
      final pathSegments = List.of(
        GoRouter.of(context).routeInformationProvider.value.uri.pathSegments,
      );
      if (pathSegments.last != 'home') pathSegments.removeLast();
      pathSegments.add('login');
      context.push('/${pathSegments.join('/')}', extra: client);
      setState(AsyncSnapshot.withData(ConnectionState.done, true));
      return;
    }

    await AppSettings.defaultHomeserver.setItem(homeserverInput);

    if (context.mounted) {
      setState(AsyncSnapshot.withData(ConnectionState.done, true));
      context.go('/backup');
    }
  } catch (e, s) {
    Logs().w('Unable to login', e, s);
    setState(AsyncSnapshot.withError(ConnectionState.done, e, s));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          e.toLocalizedString(context, ExceptionContext.checkHomeserver),
        ),
      ),
    );
  }
}
