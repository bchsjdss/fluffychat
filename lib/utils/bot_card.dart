// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Room event type of a bot card that the server (Hermes) sends into a room.
///
/// In an encrypted room the event is `m.room.encrypted` on the wire. The
/// matrix SDK replaces [Event.type] with the decrypted type, so by the time
/// the timeline is rendered the card has this type.
const String botCardEventType = 'im.pi.bot.card';

/// Prefix of the plain text message that is sent when the user taps an action.
const String botCardActionPrefix = '/action';

/// One button of a bot card.
class BotCardAction {
  /// Id that is sent back to the bot as `/action <card_id> <action_id>`.
  final String id;

  /// Text on the button.
  final String label;

  /// Optional style hint, e.g. `primary`, `secondary` or `danger`.
  final String style;

  const BotCardAction({required this.id, required this.label, this.style = ''});

  bool get isPrimary => style == 'primary';

  bool get isDanger => style == 'danger' || style == 'destructive';

  @override
  String toString() => 'BotCardAction($id)';
}

/// One entry of a paginated picker card.
class BotCardItem {
  final String id;
  final String label;
  final String hint;

  const BotCardItem({required this.id, required this.label, this.hint = ''});

  @override
  String toString() => 'BotCardItem($id)';
}

/// Pagination of a picker card: `{"index": 2, "total": 3}`.
class BotCardPage {
  final int index;
  final int total;

  const BotCardPage({required this.index, required this.total});

  String get label => '$index/$total';

  @override
  String toString() => 'BotCardPage($label)';
}

/// Parsed content of an [botCardEventType] event.
///
/// The content looks like this:
///
/// ```json
/// {
///   "v": 1,
///   "id": "card-1",
///   "kind": "confirm",
///   "title": "Deploy?",
///   "body": "Deploy build 42 to prod.",
///   "actions": [{"id": "yes", "label": "Deploy", "style": "primary"}],
///   "state": "pending",
///   "expires_at": "2026-11-26T12:00:00Z",
///   "fallback": "Deploy build 42 to prod?"
/// }
/// ```
///
/// Picker cards additionally carry [page] and [items].
class BotCard {
  final int version;
  final String id;
  final String kind;
  final String title;
  final String body;
  final List<BotCardAction> actions;

  /// Lifecycle state, e.g. `pending`, `approved` or `cancelled`.
  ///
  /// Only `pending` cards are interactive.
  final String state;
  final DateTime? expiresAt;
  final String fallback;
  final BotCardPage? page;
  final List<BotCardItem> items;

  const BotCard({
    this.version = 1,
    required this.id,
    this.kind = '',
    this.title = '',
    this.body = '',
    this.actions = const <BotCardAction>[],
    this.state = 'pending',
    this.expiresAt,
    this.fallback = '',
    this.page,
    this.items = const <BotCardItem>[],
  });

  /// True while the card still waits for a decision.
  bool get isPending => state.isEmpty || state == 'pending';

  /// True if [expiresAt] is in the past. Pending cards expire, finished ones
  /// keep their state.
  bool isExpired({DateTime? now}) {
    final at = expiresAt;
    if (at == null) return false;
    return at.isBefore(now ?? DateTime.now());
  }

  /// True if the action buttons may be tapped.
  bool canInteract({DateTime? now}) => isPending && !isExpired(now: now);

  /// True if the card carries a picker (`page` + `items`).
  bool get isPicker => page != null || items.isNotEmpty;

  /// Text that is sent to the bot when [actionId] is tapped.
  String actionText(String actionId) => '$botCardActionPrefix $id $actionId';

  /// Read [content]; returns null when it does not look like a card at all.
  static BotCard? fromContent(Map<String, Object?>? content) {
    if (content == null) return null;
    final id = _str(content['id'] ?? content['card_id']).trim();
    final title = _str(content['title']).trim();
    final fallback = _str(content['fallback']).trim();
    final body = _str(content['body'] ?? content['text']).trim();
    if (id.isEmpty && title.isEmpty && body.isEmpty && fallback.isEmpty) {
      return null;
    }
    return BotCard(
      version: _int(content['v'] ?? content['version']) ?? 1,
      id: id,
      kind: _str(content['kind']).trim(),
      title: title,
      body: body.isEmpty ? fallback : body,
      actions: _actions(content['actions']),
      state: _str(content['state']).trim().toLowerCase(),
      expiresAt: _date(content['expires_at'] ?? content['expiresAt']),
      fallback: fallback,
      page: _page(content['page']),
      items: _items(content['items']),
    );
  }

  /// Read the card of an event, applying `m.replace` edits.
  ///
  /// [baseContent] is the content of the card event, [editContents] are the
  /// contents of the edit events, oldest first. An edit carries the new card
  /// in `m.new_content`; the whole content is replaced, not merged.
  static BotCard? resolve(
    Map<String, Object?>? baseContent, {
    Iterable<Map<String, Object?>> editContents = const [],
  }) {
    Map<String, Object?>? content = baseContent;
    for (final edit in editContents) {
      final replacement = edit['m.new_content'];
      if (replacement is Map) {
        content = replacement.cast<String, Object?>();
      }
    }
    return fromContent(content);
  }

  /// Text that is shown when the content cannot be parsed.
  static String fallbackOf(Map<String, Object?>? content) {
    final fallback = _str(content?['fallback']).trim();
    return fallback.isEmpty ? botCardEventType : fallback;
  }

  static List<BotCardAction> _actions(Object? raw) {
    if (raw is! List) return const <BotCardAction>[];
    final result = <BotCardAction>[];
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        result.add(BotCardAction(id: item.trim(), label: item.trim()));
        continue;
      }
      if (item is! Map) continue;
      final id = _str(item['id'] ?? item['action_id']).trim();
      if (id.isEmpty) continue;
      final label = _str(item['label'] ?? item['title']).trim();
      result.add(
        BotCardAction(
          id: id,
          label: label.isEmpty ? id : label,
          style: _str(item['style']).trim().toLowerCase(),
        ),
      );
    }
    return result;
  }

  static List<BotCardItem> _items(Object? raw) {
    if (raw is! List) return const <BotCardItem>[];
    final result = <BotCardItem>[];
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        result.add(BotCardItem(id: item.trim(), label: item.trim()));
        continue;
      }
      if (item is! Map) continue;
      final id = _str(item['id']).trim();
      if (id.isEmpty) continue;
      final label = _str(item['label'] ?? item['title']).trim();
      result.add(
        BotCardItem(
          id: id,
          label: label.isEmpty ? id : label,
          hint: _str(item['hint'] ?? item['description']).trim(),
        ),
      );
    }
    return result;
  }

  static BotCardPage? _page(Object? raw) {
    if (raw is! Map) return null;
    final index = _int(raw['index']);
    final total = _int(raw['total']);
    if (index == null && total == null) return null;
    return BotCardPage(index: index ?? 1, total: total ?? 1);
  }

  static String _str(Object? value) => value is String ? value : '';

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static DateTime? _date(Object? value) {
    if (value is String) return DateTime.tryParse(value.trim())?.toLocal();
    final millis = _int(value);
    if (millis == null) return null;
    // Matrix timestamps are milliseconds, but seconds are accepted too.
    final ms = millis > 100000000000 ? millis : millis * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
