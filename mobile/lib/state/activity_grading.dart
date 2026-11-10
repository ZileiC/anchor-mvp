import '../l10n/strings.dart';
import '../models/activity.dart';

/// How one pick feels: an achievement, a gentle correction, or a reply with no
/// verdict at all.
enum ActivityTone { correct, wrong, open }

/// The feedback for one pick: what is written, what is spoken, and its colour.
///
/// This lives outside both screens because the Play card and the in-chat card
/// must grade **identically** — one rule, two places to show it. [spoken] is
/// exactly the sentence the panel renders, so the voice can never drift from
/// what the senior reads (they are the same string, built once).
class ActivityFeedback {
  const ActivityFeedback({
    required this.title,
    required this.body,
    required this.spoken,
    required this.tone,
  });

  final String title;
  final String body;
  final String spoken;
  final ActivityTone tone;
}

/// Grades the pick at [index]. Pure: the same item and language always produce
/// the same words, whether it was tapped in the Play screen or in the chat.
///
/// A card without a usable answer (every `memory` card) is never called wrong:
/// it gets a warm thank-you and, when the pack has one, the reply that belongs
/// to that option.
ActivityFeedback gradeActivity(L l, ActivityItem item, int index) {
  if (item.hasAnswer) {
    if (item.isCorrect(index)) {
      final body = item.explanation?.trim() ?? '';
      return _compose(l.activityCorrect, body, ActivityTone.correct);
    }
    final hint = item.wrongHint?.trim() ?? '';
    // On a wrong pick the senior gets the gentle line, the teaching sentence
    // and the right option — the card is locked, so "再想想" would be a lie
    // and the explanation is the only thing that actually teaches.
    final explanation = item.explanation?.trim() ?? '';
    final lines = <String>[
      if (hint.isNotEmpty) hint,
      if (explanation.isNotEmpty) explanation,
      l.activityAnswerWas(item.correctOption!),
    ].where((line) => line.isNotEmpty);
    return _compose(l.activityWrong, lines.join('\n'), ActivityTone.wrong);
  }
  // Memory, or any card without a graded answer: a warm reply, never a
  // verdict. A missing reply falls back to the thank-you line already shown.
  return _compose(
    l.activityThanks,
    item.replyFor(index)?.trim() ?? '',
    ActivityTone.open,
  );
}

ActivityFeedback _compose(String title, String body, ActivityTone tone) =>
    ActivityFeedback(
      title: title,
      body: body,
      spoken: body.isEmpty ? title : '$title\n$body',
      tone: tone,
    );
