// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/bot_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BotMenu.fromContent', () {
    test('parses the documented format', () {
      final menu = BotMenu.fromContent({
        'commands': [
          {'cmd': '/help', 'desc': 'Show help'},
          {'cmd': '/poll start', 'desc': 'Start a poll'},
        ],
      });
      expect(menu.commands.map((c) => c.display), ['/help', '/poll start']);
      expect(menu.commands.first.description, 'Show help');
      // Multi word commands keep only the first word as name.
      expect(menu.commands.last.name, 'poll');
    });

    test('accepts strings, aliases and missing slashes', () {
      final menu = BotMenu.fromContent({
        'commands': [
          '/help',
          {'command': 'echo', 'description': 'Echo text'},
          {'name': '/Ping', 'help': 'Pong'},
          {'cmd': '  /status  ', 'desc': ' Status '},
        ],
      });
      expect(menu.commands.map((c) => c.name), [
        'help',
        'echo',
        'ping',
        'status',
      ]);
      expect(menu.commands.map((c) => c.display), [
        '/help',
        '/echo',
        '/Ping',
        '/status',
      ]);
      expect(menu.commands[1].description, 'Echo text');
      expect(menu.commands[3].description, 'Status');
    });

    test('skips invalid and duplicate entries', () {
      final menu = BotMenu.fromContent({
        'commands': [
          {'desc': 'no command name'},
          '/',
          42,
          '/help',
          {'cmd': '/HELP'},
          {'cmd': '/help', 'desc': 'duplicate'},
        ],
      });
      expect(menu.commands.map((c) => c.name), ['help']);
      // First occurrence wins.
      expect(menu.commands.single.description, '');
    });

    test('handles missing or malformed content', () {
      expect(BotMenu.fromContent(null).commands, isEmpty);
      expect(BotMenu.fromContent({}).commands, isEmpty);
      expect(BotMenu.fromContent({'commands': 'nope'}).commands, isEmpty);
    });
  });

  group('BotMenu lookups', () {
    final menu = BotMenu.fromContent({
      'commands': [
        {'cmd': '/help', 'desc': 'Show help'},
        {'cmd': '/poll start', 'desc': 'Start a poll'},
        {'cmd': '/refresh', 'desc': 'Refresh'},
      ],
    });

    test('baseName strips slash and arguments', () {
      expect(BotMenu.baseName('/poll start'), 'poll');
      expect(BotMenu.baseName('/POLL'), 'poll');
      expect(BotMenu.baseName('poll'), '');
      expect(BotMenu.baseName('/'), '');
      expect(BotMenu.baseName('/  '), '');
    });

    test('containsText matches the command name', () {
      expect(menu.containsText('/poll start'), isTrue);
      expect(menu.containsText('/HELP'), isTrue);
      expect(menu.containsText('/unknown'), isFalse);
      expect(menu.containsText('help'), isFalse);
    });

    test('search puts prefix matches first', () {
      expect(menu.search('').map((c) => c.name), ['help', 'poll', 'refresh']);
      expect(menu.search('re').map((c) => c.name), ['refresh']);
      // Prefix matches must come before substring matches.
      final mixed = BotMenu.fromContent({
        'commands': [
          {'cmd': '/reload'},
          {'cmd': '/refresh'},
          {'cmd': '/styles'},
        ],
      });
      expect(mixed.search('re').map((c) => c.name), ['reload', 'refresh']);
    });
  });
}
