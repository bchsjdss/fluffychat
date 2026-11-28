// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

abstract class AppConfig {
  static const Color primaryColor = Color(0xFF261386);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  // 只预置我们自己的服务器（见 builtInHomeservers）。
  //
  // 这里仍然是 true，是为了保住登录页那个可以手输地址的输入框：
  // 关闭它的语义是“不让用户连别人的服务器”，而在本代码库里它唯一可能的
  // 落点就是禁用输入框 / 禁止手输地址，那样用户既改不了地址、也没法连备用
  // 节点。真正把“内置列表只有一个”这件事收住的是 builtInHomeservers。
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'im.fluffychat://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'fluffychat_push';
  static const String pushNotificationsAppId = 'chat.fluffy.fluffychat';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  static const String enablePushTutorial =
      'https://ko-fi.com/post/How-can-I-get-Push-Notifications-without-Google-N7Q825URG6?fromEditor=true';
  static const String encryptionTutorial =
      'https://ko-fi.com/post/How-to-use-end-to-end-encryption-in-FluffyChat-A5O725WDR5';
  static const String howDoIGetStickersTutorial =
      'https://ko-fi.com/post/How-to-add-a-sticker-pack-to-FluffyChat-N4N01OXATI';

  /// 点“继续”后探测 homeserver 的超时上限。
  ///
  /// 被墙 / 挂掉的域名下，httpClient 可能长时间不返回，按钮就一直转圈。
  /// 5 秒内必须给出结果（要么进下一步，要么报错）。
  static const Duration homeserverConnectTimeout = Duration(seconds: 5);

  static const String appId = 'im.fluffychat.app';
  static const String appOpenUrlScheme = 'im.fluffychat';
  static const String appSsoUrlScheme = 'im.fluffychat.auth';
  // Identifies the notification activation callback on Windows. Never change!
  static const String windowsNotificationGuid =
      '4894dfda-c70a-4ebc-b139-acae55f3988d';

  static const String sourceCodeUrl =
      'https://github.com/krille-chan/fluffychat';
  static const String supportUrl =
      'https://github.com/krille-chan/fluffychat/issues';
  static const String changelogUrl = 'https://fluffychat.im/changelog/';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/krille-chan/fluffychat/releases/latest';
  static const String helpUrl =
      'https://ko-fi.com/post/How-can-I-support-FluffyChat-J2G325WE6I';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/krille-chan/fluffychat/issues/new',
  );

  // 登录 / 注册页内置的 homeserver 列表。
  //
  // 刻意写死、不联网：以前这份列表是 GET
  // raw.githubusercontent.com/krille-chan/.../recommended_homeservers.json 拿的，
  // 那条请求没有超时，域名不通时 future 永远不结束，AsyncSnapshot 一直停在
  // waiting —— 登录页输入框 readOnly、列表处转圈，用户什么都做不了。
  // 内置列表让登录页第一帧就是可交互的 done 状态。
  static const List<String> builtInHomeservers = ['matrix.toolokai.com:23456'];

  static final Uri crashReportEndpoint = Uri(
    scheme: 'https',
    host: 'crash.fluffy.chat',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';

  static const String vodozemacVersion = '0.9.0';
}
