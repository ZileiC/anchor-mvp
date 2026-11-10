import 'parse.dart';

/// One curated activity (SPEC §6.5). `type` ∈ trivia / story / memory.
///
/// Content contract (written by the content side, parsed defensively here):
///
/// ```
/// id, type, title, prompt, minutes,
/// options?:     [string]
/// answer?:      int              index into options; only trivia/story
/// explanation?: string           the teaching sentence; required for trivia/story
/// wrong_hint?:  string           one gentle line for a wrong pick (never "错")
/// replies?:     [string]         memory only: one warm reply per option
/// story?:       string           story only: 2-4 sentences to read aloud first
/// ```
///
/// Every optional field may be absent: a missing field becomes null/empty, never
/// a crash. A card without a usable [answerIndex] is simply never graded.
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.prompt,
    required this.minutes,
    this.options = const <String>[],
    this.answerIndex,
    this.explanation,
    this.wrongHint,
    this.replies = const <String>[],
    this.story,
  });

  final String id;
  final String type;
  final String title;
  final String prompt;
  final int minutes;
  final List<String> options;

  /// Index into [options] of the correct choice.
  ///
  /// Null when the card has no single right answer: every `memory` card, and a
  /// `trivia`/`story` card whose content has not been graded yet. The screen
  /// must never say "wrong" when this is null.
  final int? answerIndex;

  /// The teaching sentence shown (and spoken) after a graded answer.
  final String? explanation;

  /// One gentle line for a wrong pick. Never contains the word "错".
  final String? wrongHint;

  /// One warm reply per option for `memory` cards, same order as [options].
  final List<String> replies;

  /// The 2-4 sentences of a `story` card, read aloud before the question.
  final String? story;

  bool get isTrivia => type == 'trivia';
  bool get isStory => type == 'story';
  bool get isMemory => type == 'memory';

  /// True only when [answerIndex] really points at one of [options].
  bool get hasAnswer =>
      answerIndex != null && answerIndex! >= 0 && answerIndex! < options.length;

  /// The correct option, or null when the card cannot be graded.
  String? get correctOption => hasAnswer ? options[answerIndex!] : null;

  /// The warm reply for the option at [index], or null when there is none.
  String? replyFor(int index) =>
      index >= 0 && index < replies.length ? replies[index] : null;

  /// True when the pick at [index] is the graded correct one.
  bool isCorrect(int index) => hasAnswer && answerIndex == index;

  factory ActivityItem.fromJson(Map<String, Object?> json) {
    final options = asStringList(json['options']);
    return ActivityItem(
      id: asString(json['id']),
      type: asString(json['type'], 'trivia'),
      title: asString(json['title']),
      prompt: asString(json['prompt']),
      minutes: asInt(json['minutes'], 3),
      options: options,
      answerIndex: _answerIndex(json['answer'], options),
      explanation: asStringOrNull(json['explanation']),
      wrongHint: asStringOrNull(json['wrong_hint']),
      // Positional, *not* compacted: replies[i] belongs to options[i].
      replies: _replies(json['replies']),
      story: asStringOrNull(json['story']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'title': title,
    'prompt': prompt,
    'minutes': minutes,
    if (options.isNotEmpty) 'options': options,
    if (answerIndex != null) 'answer': answerIndex,
    if (explanation != null && explanation!.isNotEmpty)
      'explanation': explanation,
    if (wrongHint != null && wrongHint!.isNotEmpty) 'wrong_hint': wrongHint,
    if (replies.isNotEmpty) 'replies': replies,
    if (story != null && story!.isNotEmpty) 'story': story,
  };
}

/// Reads the answer index. Tolerates `2`, `"2"` (an older serialisation) and an
/// option's own text (an even older one), and returns null for anything else.
int? _answerIndex(Object? value, List<String> options) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed != null) return parsed;
    final position = options.indexOf(text);
    return position >= 0 ? position : null;
  }
  return null;
}

/// Replies keep their positions so `replies[i]` always matches `options[i]`.
List<String> _replies(Object? value) =>
    asList(value).map((item) => asString(item)).toList(growable: false);

/// `GET /activities` — the pack plus the persisted rotation order.
class ActivityFeed {
  const ActivityFeed({required this.items, required this.rotation});

  final List<ActivityItem> items;
  final List<String> rotation;

  factory ActivityFeed.fromJson(Map<String, Object?> json) => ActivityFeed(
    items: asList(json['items'])
        .map((item) => ActivityItem.fromJson(asMap(item)))
        .toList(growable: false),
    rotation: asStringList(json['rotation']),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'rotation': rotation,
  };

  static const ActivityFeed empty = ActivityFeed(
    items: <ActivityItem>[],
    rotation: <String>[],
  );
}

/// `POST /activity-sessions` response.
class ActivitySessionResult {
  const ActivitySessionResult({
    required this.recorded,
    required this.activityId,
    required this.observationRecorded,
    this.nextActivityId,
  });

  final bool recorded;
  final String activityId;
  final bool observationRecorded;
  final String? nextActivityId;

  factory ActivitySessionResult.fromJson(Map<String, Object?> json) =>
      ActivitySessionResult(
        recorded: asBool(json['recorded']),
        activityId: asString(json['activity_id']),
        observationRecorded: asBool(json['observation_recorded']),
        nextActivityId: asStringOrNull(json['next_activity_id']),
      );
}
