// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Room state type that carries the server side (bot) command menu.
const String botMenuStateType = 'im.pi.bot.menu';

/// One entry of the server side command menu.
class BotMenuCommand {
  /// Command name without the leading slash, e.g. `help`.
  final String name;

  /// Command as the user must send it, including the leading slash.
  final String display;

  /// Short help text that the server put into the menu.
  final String description;

  const BotMenuCommand({
    required this.name,
    required this.display,
    required this.description,
  });

  @override
  String toString() => 'BotMenuCommand($display)';
}

/// Parsed content of the [botMenuStateType] room state event.
///
/// The state event content looks like this:
///
/// ```json
/// { "commands": [ { "cmd": "/help", "desc": "Show the help" } ] }
/// ```
///
/// Strings and the keys `command`/`name`, `description`/`help` are accepted
/// too, so an older server does not break the client.
class BotMenu {
  final List<BotMenuCommand> commands;

  const BotMenu(this.commands);

  static const BotMenu empty = BotMenu(<BotMenuCommand>[]);

  /// Read the menu of [room]. Returns [empty] if the room has no menu.
  static BotMenu of(Room room) {
    final StrippedStateEvent? state;
    try {
      state = room.getState(botMenuStateType);
    } catch (_) {
      return empty;
    }
    return fromContent(state?.content);
  }

  static BotMenu fromContent(Map<String, Object?>? content) {
    final raw = content?['commands'];
    if (raw is! List) return empty;
    final result = <BotMenuCommand>[];
    final seen = <String>{};
    for (final item in raw) {
      String? cmd;
      String? desc;
      if (item is String) {
        cmd = item;
      } else if (item is Map) {
        final c = item['cmd'] ?? item['command'] ?? item['name'];
        if (c is String) cmd = c;
        final d = item['desc'] ?? item['description'] ?? item['help'];
        if (d is String) desc = d;
      }
      if (cmd == null) continue;
      var display = cmd.trim();
      if (display.isEmpty) continue;
      if (!display.startsWith('/')) display = '/$display';
      final name = baseName(display);
      if (name.isEmpty || !seen.add(name)) continue;
      result.add(
        BotMenuCommand(
          name: name,
          display: display,
          description: desc?.trim() ?? '',
        ),
      );
    }
    return BotMenu(result);
  }

  /// Strip the leading slash and the arguments of [text].
  ///
  /// `/poll start` gives `poll`. Text that does not start with a slash gives
  /// an empty string.
  static String baseName(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/')) return '';
    final body = trimmed.substring(1).trimLeft();
    if (body.isEmpty) return '';
    return body.split(RegExp(r'\s+')).first.toLowerCase();
  }

  /// True if the room menu lists the command of [text].
  bool containsText(String text) => containsName(baseName(text));

  bool containsName(String name) =>
      commands.any((c) => c.name == name.toLowerCase());

  /// Prefix matches first, then substring matches. [query] has no slash.
  List<BotMenuCommand> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return commands;
    final prefix = <BotMenuCommand>[];
    final rest = <BotMenuCommand>[];
    for (final command in commands) {
      if (command.name.startsWith(q)) {
        prefix.add(command);
      } else if (command.name.contains(q)) {
        rest.add(command);
      }
    }
    return [...prefix, ...rest];
  }
}
