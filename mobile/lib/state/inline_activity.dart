import '../models/activity.dart';
import '../models/conversation.dart';

/// An activity offered inside the chat, plus the answer the senior gave.
///
/// The backend decides when a card appears (`ActivityEngine.offer_for_turn`)
/// and never offers the same item twice in one conversation; this object only
/// carries the live card: which turn offered it, when it appeared, and where the
/// senior's finger landed. It deliberately does not grade — the words come from
/// `gradeActivity`, which the Play screen uses too.
class InlineActivity {
  const InlineActivity({
    required this.offer,
    required this.offeredAt,
    this.chosenIndex,
  });

  /// Upper bound on a reported duration, same as the Play screen: a suspended
  /// machine can never post a nonsense number (a card is a few minutes).
  static const int maxReportedSeconds = 7200;

  final TurnActivity offer;

  /// When the card was shown. The posted duration is the time actually spent on
  /// it, measured silently — there is no clock on screen.
  final DateTime offeredAt;

  /// Index of the option the senior picked; null while the card is still open.
  /// Non-null is also the lock: no second answer can change it.
  final int? chosenIndex;

  ActivityItem get item => offer.item;

  bool get answered => chosenIndex != null;

  /// The chosen option's own words, or null before the answer (or when the pack
  /// has no options at all).
  String? get chosenOption {
    final index = chosenIndex;
    if (index == null || index < 0 || index >= item.options.length) return null;
    return item.options[index];
  }

  InlineActivity withAnswer(int index) =>
      InlineActivity(offer: offer, offeredAt: offeredAt, chosenIndex: index);

  /// Seconds spent on the card, clamped to a sane range (never negative).
  int durationSeconds(DateTime now) {
    final measured = now.difference(offeredAt).inSeconds;
    if (measured < 0) return 0;
    return measured > maxReportedSeconds ? maxReportedSeconds : measured;
  }
}
