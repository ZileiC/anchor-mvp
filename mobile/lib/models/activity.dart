import 'parse.dart';

/// One curated activity (SPEC §6.5). `type` ∈ trivia / story / memory.
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.prompt,
    required this.minutes,
    this.options = const <String>[],
    this.answer,
  });

  final String id;
  final String type;
  final String title;
  final String prompt;
  final int minutes;
  final List<String> options;
  final String? answer;

  bool get isTrivia => type == 'trivia';
  bool get isStory => type == 'story';
  bool get isMemory => type == 'memory';

  factory ActivityItem.fromJson(Map<String, Object?> json) => ActivityItem(
    id: asString(json['id']),
    type: asString(json['type'], 'trivia'),
    title: asString(json['title']),
    prompt: asString(json['prompt']),
    minutes: asInt(json['minutes'], 3),
    options: asStringList(json['options']),
    answer: asStringOrNull(json['answer']),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'title': title,
    'prompt': prompt,
    'minutes': minutes,
    if (options.isNotEmpty) 'options': options,
    if (answer != null) 'answer': answer,
  };
}

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
