// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/bot_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Renders an [botCardEventType] event: title, body and the action buttons.
///
/// Tapping an action sends a plain text `/action <card_id> <action_id>` into
/// the room, as a reply to the card event, so the bot can correlate it.
class BotCardWidget extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final Color textColor;
  final double fontSize;

  const BotCardWidget({
    super.key,
    required this.event,
    required this.timeline,
    required this.textColor,
    required this.fontSize,
  });

  @override
  State<BotCardWidget> createState() => _BotCardWidgetState();
}

class _BotCardWidgetState extends State<BotCardWidget> {
  static const int _collapsedLines = 8;

  bool _expanded = false;
  String? _sendingActionId;

  /// Latest card content, including `m.replace` edits.
  BotCard? get _card {
    final edits =
        widget.event
            .aggregatedEvents(widget.timeline, RelationshipTypes.edit)
            // Only the sender of the card may replace it, like normal edits.
            .where((event) => event.senderId == widget.event.senderId)
            .toList()
          ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    return BotCard.resolve(
      widget.event.content,
      editContents: edits.map((event) => event.content),
    );
  }

  Future<void> _sendAction(BotCard card, String actionId) async {
    if (_sendingActionId != null) return;
    setState(() => _sendingActionId = actionId);
    try {
      // Send the exact body `/action <card_id> <action_id>` and attach the
      // reply relation by hand. `sendTextEvent(inReplyTo: ...)` would prepend
      // a `> <@sender>` reply fallback to the body, which breaks the bot.
      await widget.event.room.sendEvent({
        'msgtype': MessageTypes.Text,
        'body': card.actionText(actionId),
        'm.relates_to': {
          // Standard Matrix reply relation, understood by the matrix SDK.
          'm.in_reply_to': {'event_id': widget.event.eventId},
          // The flat form documented for the bot cards.
          'rel_type': 'm.in_reply_to',
          'event_id': widget.event.eventId,
        },
      });
    } catch (e, s) {
      Logs().w('Unable to send bot card action $actionId', e, s);
    } finally {
      if (mounted) setState(() => _sendingActionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    if (card == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          BotCard.fallbackOf(widget.event.content),
          style: TextStyle(color: widget.textColor, fontSize: widget.fontSize),
        ),
      );
    }

    final theme = Theme.of(context);
    final enabled = card.canInteract() && _sendingActionId == null;
    final status = _statusText(card);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  card.title.isEmpty ? card.id : card.title,
                  style: TextStyle(
                    color: widget.textColor,
                    fontSize: widget.fontSize + 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (card.page != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    card.page!.label,
                    style: TextStyle(
                      color: widget.textColor.withAlpha(160),
                      fontSize: widget.fontSize - 2,
                    ),
                  ),
                ),
            ],
          ),
          if (card.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            _BodyText(
              text: card.body,
              textColor: widget.textColor,
              fontSize: widget.fontSize,
              expanded: _expanded,
              collapsedLines: _collapsedLines,
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
          ],
          if (card.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _actionLayout(
              card.actions
                  .map(
                    (action) => _actionButton(
                      context,
                      label: action.label,
                      id: action.id,
                      style: action.style,
                      enabled: enabled,
                      onPressed: () => _sendAction(card, action.id),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (card.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...card.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: enabled
                        ? () => _sendAction(card, item.id)
                        : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.label, textAlign: TextAlign.center),
                        if (item.hint.isNotEmpty)
                          Text(
                            item.hint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: widget.fontSize - 2,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status == 'expired'
                      ? Icons.timer_off_outlined
                      : Icons.check_circle_outline,
                  size: widget.fontSize,
                  color: widget.textColor.withAlpha(180),
                ),
                const SizedBox(width: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: widget.textColor.withAlpha(180),
                    fontSize: widget.fontSize - 1,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Four or fewer buttons fit in one row, more than four stack vertically.
  Widget _actionLayout(List<Widget> buttons) {
    if (buttons.length > 4) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons
            .map(
              (button) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: button,
              ),
            )
            .toList(),
      );
    }
    return Wrap(spacing: 4, runSpacing: 4, children: buttons);
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required String id,
    required String style,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final busy = _sendingActionId == id;
    final child = busy
        ? SizedBox.square(
            dimension: widget.fontSize,
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    final action = BotCardAction(id: id, label: label, style: style);
    if (action.isDanger) {
      return FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: theme.colorScheme.onError,
          visualDensity: VisualDensity.compact,
        ),
        child: child,
      );
    }
    if (action.isPrimary) {
      return FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
      child: child,
    );
  }

  String? _statusText(BotCard card) {
    if (!card.isPending) return card.state.isEmpty ? 'done' : card.state;
    if (card.isExpired()) return 'expired';
    return null;
  }
}

/// Card body that is truncated after [collapsedLines] lines until expanded.
class _BodyText extends StatelessWidget {
  final String text;
  final Color textColor;
  final double fontSize;
  final bool expanded;
  final int collapsedLines;
  final VoidCallback onToggle;

  const _BodyText({
    required this.text,
    required this.textColor,
    required this.fontSize,
    required this.expanded,
    required this.collapsedLines,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: textColor, fontSize: fontSize, height: 1.3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: style,
              maxLines: expanded ? null : collapsedLines,
              overflow: expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              GestureDetector(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    expanded
                        ? L10n.of(context).showLess
                        : L10n.of(context).showMore,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: fontSize - 1,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
