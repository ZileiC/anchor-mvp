import 'parse.dart';

/// The five sharing topics from SPEC §5.
abstract final class ShareTopics {
  static const String participation = 'participation';
  static const String activities = 'activities';
  static const String mood = 'mood';
  static const String meals = 'meals';
  static const String wellbeing = 'wellbeing';

  static const List<String> all = <String>[
    participation,
    activities,
    mood,
    meals,
    wellbeing,
  ];
}

/// Capabilities that do not take a topic.
abstract final class Capabilities {
  static const String cloudProcessing = 'cloud_processing';
  static const String proactiveInvitations = 'proactive_invitations';
  static const String saveMemory = 'save_memory';
  static const String recordObservations = 'record_observations';
  static const String shareTopic = 'share_topic';
}

/// One consent row (`{capability, topic, allowed, version, updated_at}`).
class ConsentItem {
  const ConsentItem({
    required this.capability,
    required this.topic,
    required this.allowed,
    required this.version,
    this.updatedAt,
  });

  final String capability;
  final String topic;
  final bool allowed;
  final int version;
  final DateTime? updatedAt;

  String get key => topic.isEmpty ? capability : '$capability:$topic';

  factory ConsentItem.fromJson(Map<String, Object?> json) => ConsentItem(
    capability: asString(json['capability']),
    topic: asString(json['topic']),
    allowed: asBool(json['allowed']),
    version: asInt(json['version'], 1),
    updatedAt: asDateTime(json['updated_at']),
  );
}

/// The whole consent snapshot, private by default (SPEC §5 rule 1).
///
/// A capability or topic missing from the snapshot is **not allowed** — the UI
/// must never assume permission it was not granted.
class ConsentSnapshot {
  const ConsentSnapshot({required this.version, required this.items});

  final int version;
  final List<ConsentItem> items;

  static const ConsentSnapshot privateDefault = ConsentSnapshot(
    version: 1,
    items: <ConsentItem>[],
  );

  factory ConsentSnapshot.fromJson(Map<String, Object?> json) =>
      ConsentSnapshot(
        version: asInt(json['version'], 1),
        items: asList(json['items'])
            .map((item) => ConsentItem.fromJson(asMap(item)))
            .toList(growable: false),
      );

  bool isAllowed(String capability, [String topic = '']) {
    for (final item in items) {
      if (item.capability == capability && item.topic == topic) {
        return item.allowed;
      }
    }
    return false;
  }

  bool get cloudProcessing => isAllowed(Capabilities.cloudProcessing);
  bool get proactiveInvitations => isAllowed(Capabilities.proactiveInvitations);
  bool get saveMemory => isAllowed(Capabilities.saveMemory);
  bool get recordObservations => isAllowed(Capabilities.recordObservations);

  bool shareTopicAllowed(String topic) =>
      isAllowed(Capabilities.shareTopic, topic);

  /// Topics the senior has explicitly allowed for sharing.
  List<String> get allowedShareTopics =>
      ShareTopics.all.where(shareTopicAllowed).toList(growable: false);

  bool get anySharing => allowedShareTopics.isNotEmpty;

  ConsentSnapshot copyWith({int? version, List<ConsentItem>? items}) =>
      ConsentSnapshot(
        version: version ?? this.version,
        items: items ?? this.items,
      );
}

/// One entry of `PUT /consents` `changes[]`.
class ConsentChange {
  const ConsentChange({
    required this.capability,
    this.topic = '',
    required this.allowed,
  });

  final String capability;
  final String topic;
  final bool allowed;

  Map<String, Object?> toJson() => <String, Object?>{
    'capability': capability,
    'topic': topic,
    'allowed': allowed,
  };
}
