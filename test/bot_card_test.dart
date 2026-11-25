// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/bot_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BotCard.fromContent', () {
    test('parses the documented base card', () {
      final card = BotCard.fromContent({
        'v': 1,
        'id': 'card-1',
        'kind': 'confirm',
        'title': 'Deploy?',
        'body': 'Deploy build 42 to prod.',
        'actions': [
          {'id': 'yes', 'label': 'Deploy', 'style': 'primary'},
          {'id': 'no', 'label': 'Cancel', 'style': 'secondary'},
        ],
        'state': 'pending',
        'expires_at': '2026-11-26T12:00:00Z',
        'fallback': 'Deploy build 42 to prod?',
      })!;
      expect(card.id, 'card-1');
      expect(card.kind, 'confirm');
      expect(card.title, 'Deploy?');
      expect(card.body, 'Deploy build 42 to prod.');
      expect(card.actions.map((a) => a.id), ['yes', 'no']);
      expect(card.actions.first.isPrimary, isTrue);
      expect(card.state, 'pending');
      expect(card.isPending, isTrue);
      expect(card.isExpired(now: DateTime.utc(2026, 11, 26, 11)), isFalse);
      expect(card.isExpired(now: DateTime.utc(2026, 11, 26, 13)), isTrue);
      expect(card.expiresAt, isNotNull);
    });

    test('builds the /action text', () {
      final card = BotCard.fromContent({
        'id': 'card-1',
        'title': 'T',
        'actions': [
          {'id': 'yes', 'label': 'Y'},
        ],
      })!;
      expect(card.actionText('yes'), '/action card-1 yes');
    });

    test('keeps long bodies intact', () {
      final body = 'x' * 2000;
      final card = BotCard.fromContent({'id': 'c', 'body': body})!;
      expect(card.body.length, 2000);
    });

    test('parses a paginated picker', () {
      final card = BotCard.fromContent({
        'id': 'pick-1',
        'kind': 'picker',
        'title': 'Choose a repo',
        'page': {'index': 2, 'total': 3},
        'items': [
          {'id': 'r1', 'label': 'fluffychat', 'hint': 'Dart'},
          {'id': 'r2', 'label': 'hermes', 'hint': 'Python'},
        ],
      })!;
      expect(card.isPicker, isTrue);
      expect(card.page!.index, 2);
      expect(card.page!.total, 3);
      expect(card.page!.label, '2/3');
      expect(card.items.map((i) => i.id), ['r1', 'r2']);
      expect(card.items.last.hint, 'Python');
      expect(card.actionText('r2'), '/action pick-1 r2');
    });

    test('a finished card is not interactive', () {
      final card = BotCard.fromContent({
        'id': 'card-1',
        'title': 'Done',
        'state': 'approved',
        'actions': [
          {'id': 'yes', 'label': 'Y'},
        ],
      })!;
      expect(card.isPending, isFalse);
      expect(card.canInteract(), isFalse);
    });

    test('pending cards expire', () {
      final card = BotCard.fromContent({
        'id': 'card-1',
        'state': 'pending',
        'expires_at': 1000000000,
      })!;
      expect(
        card.isExpired(now: DateTime.fromMillisecondsSinceEpoch(2000000000000)),
        isTrue,
      );
      expect(
        card.canInteract(
          now: DateTime.fromMillisecondsSinceEpoch(2000000000000),
        ),
        isFalse,
      );
    });

    test('accepts aliases and plain string buttons', () {
      final card = BotCard.fromContent({
        'card_id': 'c2',
        'text': 'Body only',
        'actions': ['yes', 'no'],
      })!;
      expect(card.id, 'c2');
      expect(card.body, 'Body only');
      expect(card.actions.map((a) => a.label), ['yes', 'no']);
    });

    test('uses the fallback as body when the body is missing', () {
      final card = BotCard.fromContent({
        'id': 'c3',
        'fallback': 'Fallback text',
      })!;
      expect(card.body, 'Fallback text');
    });

    test('returns null for content without card fields', () {
      expect(BotCard.fromContent(null), isNull);
      expect(BotCard.fromContent({'foo': 'bar'}), isNull);
      expect(BotCard.fallbackOf({'fallback': 'F'}), 'F');
      expect(BotCard.fallbackOf(null), botCardEventType);
    });
  });

  group('BotCard.resolve', () {
    test('applies the last m.replace edit', () {
      final card = BotCard.resolve(
        {
          'id': 'card-1',
          'title': 'Old',
          'state': 'pending',
          'actions': [
            {'id': 'yes', 'label': 'Y'},
          ],
        },
        editContents: [
          {
            'm.new_content': {
              'id': 'card-1',
              'title': 'New',
              'state': 'approved',
              'actions': [
                {'id': 'ok', 'label': 'OK'},
              ],
            },
            'm.relates_to': {'rel_type': 'm.replace', 'event_id': '\$card'},
          },
        ],
      )!;
      expect(card.title, 'New');
      expect(card.state, 'approved');
      expect(card.isPending, isFalse);
      expect(card.actions.single.id, 'ok');
    });

    test('ignores unrelated edits', () {
      final card = BotCard.resolve(
        {'id': 'card-1', 'title': 'Keep'},
        editContents: [
          {'body': '* Keep'},
        ],
      )!;
      expect(card.title, 'Keep');
    });
  });
}
