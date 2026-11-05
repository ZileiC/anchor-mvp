import 'parse.dart';

/// `GET/PATCH /preferences` (SPEC §6.1). Times are local `HH:MM` strings.
class Preferences {
  const Preferences({
    required this.greetingStart,
    required this.greetingEnd,
    required this.quietStart,
    required this.quietEnd,
    required this.dailyCap,
    required this.paused,
    required this.voicePace,
    required this.shortReplies,
    required this.language,
    required this.interests,
    required this.observationTopics,
    required this.digestRetentionDays,
    this.snoozedUntil,
    this.designatedDeviceId,
  });

  final String greetingStart;
  final String greetingEnd;
  final String quietStart;
  final String quietEnd;
  final int dailyCap;
  final bool paused;
  final String voicePace;
  final bool shortReplies;
  final String language;
  final List<String> interests;
  final List<String> observationTopics;
  final int digestRetentionDays;
  final String? snoozedUntil;
  final String? designatedDeviceId;

  static const Preferences defaults = Preferences(
    greetingStart: '09:00',
    greetingEnd: '11:00',
    quietStart: '21:00',
    quietEnd: '08:00',
    dailyCap: 1,
    paused: false,
    voicePace: 'slow',
    shortReplies: true,
    language: 'zh-CN',
    interests: <String>[],
    observationTopics: <String>[
      'participation',
      'activities',
      'mood',
      'meals',
      'wellbeing',
    ],
    digestRetentionDays: 365,
  );

  factory Preferences.fromJson(Map<String, Object?> json) => Preferences(
    greetingStart: asString(json['greeting_start'], '09:00'),
    greetingEnd: asString(json['greeting_end'], '11:00'),
    quietStart: asString(json['quiet_start'], '21:00'),
    quietEnd: asString(json['quiet_end'], '08:00'),
    dailyCap: asInt(json['daily_cap'], 1),
    paused: asBool(json['paused']),
    voicePace: asString(json['voice_pace'], 'slow'),
    shortReplies: asBool(json['short_replies'], true),
    language: asString(json['language'], 'zh-CN'),
    interests: asStringList(json['interests']),
    observationTopics: asStringList(json['observation_topics']),
    digestRetentionDays: asInt(json['digest_retention_days'], 365),
    snoozedUntil: asStringOrNull(json['snoozed_until']),
    designatedDeviceId: asStringOrNull(json['designated_device_id']),
  );

  bool get isSlowPace => voicePace == 'slow';

  Preferences copyWith({
    String? greetingStart,
    String? greetingEnd,
    String? quietStart,
    String? quietEnd,
    int? dailyCap,
    bool? paused,
    String? voicePace,
    bool? shortReplies,
    String? language,
    List<String>? interests,
    List<String>? observationTopics,
    int? digestRetentionDays,
    String? snoozedUntil,
    bool clearSnooze = false,
    String? designatedDeviceId,
    bool clearDesignatedDevice = false,
  }) => Preferences(
    greetingStart: greetingStart ?? this.greetingStart,
    greetingEnd: greetingEnd ?? this.greetingEnd,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
    dailyCap: dailyCap ?? this.dailyCap,
    paused: paused ?? this.paused,
    voicePace: voicePace ?? this.voicePace,
    shortReplies: shortReplies ?? this.shortReplies,
    language: language ?? this.language,
    interests: interests ?? this.interests,
    observationTopics: observationTopics ?? this.observationTopics,
    digestRetentionDays: digestRetentionDays ?? this.digestRetentionDays,
    snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
    designatedDeviceId: clearDesignatedDevice
        ? null
        : (designatedDeviceId ?? this.designatedDeviceId),
  );

  /// Minutes since local midnight, for window arithmetic (`HH:MM`).
  static int minuteOfDay(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return (hour.clamp(0, 23)) * 60 + (minute.clamp(0, 59));
  }

  static String formatMinuteOfDay(int minutes) {
    final normalised = minutes % (24 * 60);
    final hour = (normalised ~/ 60).toString().padLeft(2, '0');
    final minute = (normalised % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  int get greetingStartMinute => minuteOfDay(greetingStart);
  int get greetingEndMinute => minuteOfDay(greetingEnd);
  int get quietStartMinute => minuteOfDay(quietStart);
  int get quietEndMinute => minuteOfDay(quietEnd);
}
