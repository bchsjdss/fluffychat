// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_state.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

class SignInViewModel extends ValueNotifier<SignInState> {
  final MatrixState matrixService;
  final bool signUp;
  final TextEditingController filterTextController = TextEditingController();

  SignInViewModel(this.matrixService, {required this.signUp})
    : super(SignInState()) {
    refreshPublicHomeservers();
    filterTextController.addListener(_filterHomeservers);
  }

  @override
  void dispose() {
    filterTextController.removeListener(_filterHomeservers);
    filterTextController.dispose();
    super.dispose();
  }

  void _filterHomeservers() {
    final filterText = filterTextController.text.trim().toLowerCase();
    final filteredPublicHomeservers =
        value.publicHomeservers.data
            ?.where(
              (homeserver) =>
                  homeserver.name?.toLowerCase().contains(filterText) ?? false,
            )
            .toList() ??
        [];
    if (filterText.length >= 3 &&
        (filterText.contains('.') || filterText.endsWith('localhost')) &&
        Uri.tryParse(filterText) != null &&
        !filteredPublicHomeservers.any(
          (homeserver) => homeserver.name == filterText,
        )) {
      filteredPublicHomeservers.add(PublicHomeserverData(name: filterText));
    }
    value.filteredPublicHomeservers = filteredPublicHomeservers;
    notifyListeners();
  }

  /// 填充登录 / 注册页的 homeserver 列表。
  ///
  /// 这里刻意**不发任何网络请求**，全部由 [AppConfig.builtInHomeservers] 同步生成：
  ///
  /// 旧实现会 GET `AppConfig.homeserverList`（该常量已删除）去
  /// raw.githubusercontent.com 拉 recommended_homeservers.json，而且没有超时。
  /// 那个域名在部分网络里 TCP 443 直接超时，future 永远不 resolve，
  /// AsyncSnapshot 就永远停在 waiting：登录页输入框 readOnly、列表处转圈 ——
  /// 正是 Linux 版那个“一直转圈、输入框不可用”的故障。
  ///
  /// 现在的收敛方式是让 waiting 状态**不可能出现**：构造函数里直接算出 done
  /// 状态，没有 await 点，也就没有“请求失败但状态没改回来”的窗口。
  /// 将来若真要恢复远端列表，必须满足两条：请求带 ≤5s 超时，
  /// 且 catch 里一定要把 AsyncSnapshot 从 waiting 改成 error 或回落到内置列表。
  void refreshPublicHomeservers() {
    final defaultHomeserver = AppSettings.defaultHomeserver.value;
    final defaultHomeserverData = PublicHomeserverData(name: defaultHomeserver);

    final publicHomeservers = <PublicHomeserverData>[
      for (final name in AppConfig.builtInHomeservers)
        PublicHomeserverData(
          name: name,
          // 注册页会过滤掉 regMethod == null 的条目，内置服务器必须是可注册的，
          // 否则注册页会拿到一个空列表。
          regMethod: AppConfig.enableRegistration ? 'vanilla' : null,
        ),
    ];

    if (!publicHomeservers.any((server) => server.name == defaultHomeserver)) {
      publicHomeservers.insert(0, defaultHomeserverData);
    }

    value.selectedHomeserver =
        value.selectedHomeserver ??
        publicHomeservers.singleWhereOrNull(
          (server) => server.name == defaultHomeserver,
        ) ??
        publicHomeservers.first;
    value.publicHomeservers = AsyncSnapshot.withData(
      ConnectionState.done,
      publicHomeservers,
    );
    _filterHomeservers();
    Logs().i(
      'Using built-in homeservers (no network request): ${publicHomeservers.map((s) => s.name).join(', ')}',
    );
    notifyListeners();
  }

  void selectHomeserver(PublicHomeserverData? publicHomeserverData) {
    value.selectedHomeserver = publicHomeserverData;
    notifyListeners();
  }

  void setLoginLoading(AsyncSnapshot<bool> loginLoading) {
    value.loginLoading = loginLoading;
    notifyListeners();
  }
}
