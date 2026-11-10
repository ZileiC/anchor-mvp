import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/activity.dart';
import '../state/activity_grading.dart';
import '../state/inline_activity.dart';
import '../theme.dart';

/// One activity, rendered **inside the conversation** instead of on the Play
/// screen (product decision 2026-11-10: Play is no longer a separate world).
///
/// The card carries exactly the structured fields the Play screen uses, so it
/// never depends on the model's wording: the assistant's own bridge sentence
/// ("对了，我这儿有个小问题想问问你——") sits in the caption above, and the
/// question lives here.
///
/// Visual identity is asset-free on purpose: a per-kind icon and colour, a thin
/// hero strip over a tinted hero row, and three kind dots (the app's small
/// activity set — not a score, not a step count, and no clock anywhere).
///
/// After the answer the card collapses **in place** into one short line
/// ("你选了：X") plus the graded feedback, so the stream keeps the record without
/// leaving a full card behind.
class InlineActivityCard extends StatelessWidget {
  const InlineActivityCard({
    super.key,
    required this.l,
    required this.activity,
    this.onChoose,
    this.flowers = 0,
    this.awarded = false,
  });

  final L l;
  final InlineActivity activity;

  /// The senior's running flower count, shown after the answer. Encouragement
  /// only: a wrong answer never subtracts and nothing is compared.
  final int flowers;

  /// True when this answer earned a flower (drives the "+1" line).
  final bool awarded;

  /// Called with the option index. Null disables the options (never happens for
  /// a live card; it keeps the widget honest when it is rendered in isolation).
  final ValueChanged<int>? onChoose;

  @override
  Widget build(BuildContext context) {
    final item = activity.item;
    final style = _styleFor(l, item.type);
    return Container(
      key: const Key('inline-activity-card'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AnchorTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: style.ink, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _heroStrip(style),
          _heroRow(style, item),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: activity.answered
                ? _answeredBody(style, item)
                : _openBody(style, item),
          ),
        ],
      ),
    );
  }

  // -- identity -------------------------------------------------------------
  /// A thin band of the kind's ink over the tinted hero row: enough colour to
  /// tell the three kinds apart at a glance, no illustration required.
  Widget _heroStrip(_KindStyle style) {
    return Container(
      key: const Key('inline-activity-hero-strip'),
      height: 8,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: <Color>[style.ink, style.fill]),
      ),
    );
  }

  Widget _heroRow(_KindStyle style, ActivityItem item) {
    return Container(
      key: const Key('inline-activity-hero'),
      color: style.fill,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: style.ink,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(style.icon, size: 38, color: AnchorTheme.surface),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        style.label,
                        key: const Key('inline-activity-kind'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: style.ink,
                          height: 1.2,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _kindDots(style, item.type),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.title,
                  key: const Key('inline-activity-title'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AnchorTheme.ink,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Three dots: where this card sits in the app's small set of activity kinds.
  /// Decorative — the kind is already written out next to them, and nothing here
  /// counts anything the senior did.
  Widget _kindDots(_KindStyle style, String type) {
    const kinds = <String>['trivia', 'story', 'memory'];
    return Row(
      key: const Key('inline-activity-dots'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final kind in kinds)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kind == type ? style.ink : AnchorTheme.surface,
                border: Border.all(color: style.ink, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  // -- open card ------------------------------------------------------------
  Widget _openBody(_KindStyle style, ActivityItem item) {
    final story = item.story?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (story.isNotEmpty) ...<Widget>[
          Container(
            key: const Key('inline-activity-story'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: style.fill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: style.ink, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.menu_book, size: 26, color: style.ink),
                    const SizedBox(width: 8),
                    Text(
                      l.activityListen,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: style.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(story, style: AnchorTheme.reading),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          item.prompt,
          key: const Key('inline-activity-prompt'),
          style: AnchorTheme.reading,
        ),
        const SizedBox(height: 14),
        Text(l.activityChoose, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 8),
        for (var index = 0; index < item.options.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _option(item, index),
          ),
      ],
    );
  }

  /// One big option. Generous height and left-aligned text: the same shape as
  /// the Play screen's options, so the two places answer identically.
  Widget _option(ActivityItem item, int index) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: OutlinedButton(
        key: Key('inline-activity-option-$index'),
        onPressed: onChoose == null ? null : () => onChoose!(index),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: AnchorTheme.surface,
          foregroundColor: AnchorTheme.ink,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: const BorderSide(color: AnchorTheme.border, width: 2),
        ),
        child: Text(
          item.options[index],
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w400,
            color: AnchorTheme.ink,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  // -- collapsed card -------------------------------------------------------
  /// After the answer: the short "你选了：X" line and the graded feedback, in the
  /// same panel the Play screen shows. The card keeps its hero row so the senior
  /// can still see which activity this was.
  Widget _answeredBody(_KindStyle style, ActivityItem item) {
    final feedback = gradeActivity(l, item, activity.chosenIndex!);
    final chosen = activity.chosenOption ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(style.icon, size: 30, color: style.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.inlineChosen(chosen),
                key: const Key('inline-activity-chosen'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AnchorTheme.ink,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _feedbackPanel(feedback),
        if (item.hasAnswer && flowers > 0) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            awarded ? l.flowerEarned : l.flowersTotal(flowers),
            key: const Key('inline-activity-flowers'),
            style: const TextStyle(
              fontSize: 22,
              color: AnchorTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _feedbackPanel(ActivityFeedback feedback) {
    final (fill, border, icon, iconColor) = switch (feedback.tone) {
      ActivityTone.correct => (
        AnchorTheme.correctFill,
        AnchorTheme.primary,
        Icons.check_circle,
        AnchorTheme.primary,
      ),
      ActivityTone.wrong => (
        AnchorTheme.wrongFill,
        AnchorTheme.accent,
        Icons.lightbulb_outline,
        AnchorTheme.accent,
      ),
      ActivityTone.open => (
        AnchorTheme.openFill,
        AnchorTheme.border,
        Icons.favorite_border,
        AnchorTheme.primary,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('inline-activity-feedback'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 32, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: feedback.title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AnchorTheme.ink,
                        height: 1.3,
                      ),
                    ),
                    if (feedback.body.isNotEmpty)
                      TextSpan(
                        text: '\n${feedback.body}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          color: AnchorTheme.ink,
                          height: 1.45,
                        ),
                      ),
                  ],
                ),
                key: const Key('inline-activity-feedback-text'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The per-kind identity: one icon, one dark ink and one pale tint per type.
class _KindStyle {
  const _KindStyle({
    required this.label,
    required this.icon,
    required this.ink,
    required this.fill,
  });

  final String label;
  final IconData icon;
  final Color ink;
  final Color fill;
}

_KindStyle _styleFor(L l, String type) => switch (type) {
  'story' => _KindStyle(
    label: l.activityStory,
    icon: Icons.menu_book,
    ink: AnchorTheme.storyInk,
    fill: AnchorTheme.storyFill,
  ),
  'memory' => _KindStyle(
    label: l.activityMemory,
    icon: Icons.psychology_alt,
    ink: AnchorTheme.accent,
    fill: AnchorTheme.wrongFill,
  ),
  _ => _KindStyle(
    label: l.activityTrivia,
    icon: Icons.quiz_outlined,
    ink: AnchorTheme.primary,
    fill: AnchorTheme.triviaFill,
  ),
};
