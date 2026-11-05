import '../models/preferences.dart';

/// A daylight-saving rule expressed in UTC (start/end instants of the year).
///
/// The MVP cannot use the `timezone` package (no new plugin dependencies), so the
/// app carries a tiny explicit rule table for the zones the demo supports. The
/// rules are the real ones: EU (last Sunday of March/October, 01:00 UTC) and
/// US (second Sunday of March 07:00 UTC, first Sunday of November 06:00 UTC).
class DstTransition {
  const DstTransition({
    required this.month,
    required this.weekday,
    required this.occurrence,
    required this.hourUtc,
  });

  final int month;

  /// `DateTime.monday` … `DateTime.sunday`.
  final int weekday;

  /// 1-based occurrence in the month, or -1 for the last one.
  final int occurrence;
  final int hourUtc;

  DateTime instantUtc(int year) {
    if (occurrence > 0) {
      final first = DateTime.utc(year, month, 1);
      final delta = (weekday - first.weekday) % 7;
      final day = 1 + delta + (occurrence - 1) * 7;
      return DateTime.utc(year, month, day, hourUtc);
    }
    final lastDay = DateTime.utc(year, month + 1, 0);
    final back = (lastDay.weekday - weekday) % 7;
    return DateTime.utc(year, month, lastDay.day - back, hourUtc);
  }
}

/// An IANA-ish zone with an explicit daylight rule.
class ZoneSpec {
  const ZoneSpec({
    required this.id,
    required this.standardOffsetMinutes,
    this.daylightOffsetMinutes,
    this.daylightStart,
    this.daylightEnd,
  });

  final String id;
  final int standardOffsetMinutes;
  final int? daylightOffsetMinutes;
  final DstTransition? daylightStart;
  final DstTransition? daylightEnd;

  bool get hasDaylight =>
      daylightOffsetMinutes != null &&
      daylightStart != null &&
      daylightEnd != null;

  static const ZoneSpec utc = ZoneSpec(id: 'UTC', standardOffsetMinutes: 0);

  static const ZoneSpec shanghai = ZoneSpec(
    id: 'Asia/Shanghai',
    standardOffsetMinutes: 480,
  );

  static const ZoneSpec berlin = ZoneSpec(
    id: 'Europe/Berlin',
    standardOffsetMinutes: 60,
    daylightOffsetMinutes: 120,
    daylightStart: DstTransition(
      month: 3,
      weekday: DateTime.sunday,
      occurrence: -1,
      hourUtc: 1,
    ),
    daylightEnd: DstTransition(
      month: 10,
      weekday: DateTime.sunday,
      occurrence: -1,
      hourUtc: 1,
    ),
  );

  static const ZoneSpec newYork = ZoneSpec(
    id: 'America/New_York',
    standardOffsetMinutes: -300,
    daylightOffsetMinutes: -240,
    daylightStart: DstTransition(
      month: 3,
      weekday: DateTime.sunday,
      occurrence: 2,
      hourUtc: 7,
    ),
    daylightEnd: DstTransition(
      month: 11,
      weekday: DateTime.sunday,
      occurrence: 1,
      hourUtc: 6,
    ),
  );

  static const List<ZoneSpec> known = <ZoneSpec>[
    utc,
    shanghai,
    berlin,
    newYork,
  ];

  /// Falls back to the pilot timezone for an unknown name (SPEC §2 default).
  static ZoneSpec byId(String? id) {
    for (final zone in known) {
      if (zone.id == id) return zone;
    }
    return shanghai;
  }

  int offsetMinutesAt(DateTime utc) {
    if (!hasDaylight) return standardOffsetMinutes;
    final instant = utc.toUtc();
    final start = daylightStart!.instantUtc(instant.year);
    final end = daylightEnd!.instantUtc(instant.year);
    final inDaylight = start.isBefore(end)
        ? (!instant.isBefore(start) && instant.isBefore(end))
        : (!instant.isBefore(start) || instant.isBefore(end));
    return inDaylight ? daylightOffsetMinutes! : standardOffsetMinutes;
  }

  /// Wall-clock time in this zone, as a `DateTime` whose fields are local.
  DateTime wallTime(DateTime utc) {
    final shifted = utc.toUtc().add(Duration(minutes: offsetMinutesAt(utc)));
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
    );
  }

  /// Converts a wall-clock time in this zone to a UTC instant.
  ///
  /// Tries every offset the zone can have and keeps the self-consistent one, so a
  /// gap (spring forward) and an overlap (fall back) both resolve deterministically.
  DateTime toUtc(DateTime wall) {
    final naive = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
    );
    final candidates = <int>{standardOffsetMinutes, ?daylightOffsetMinutes};
    for (final offset in candidates) {
      final candidate = naive.subtract(Duration(minutes: offset));
      if (offsetMinutesAt(candidate) == offset) return candidate;
    }
    return naive.subtract(Duration(minutes: standardOffsetMinutes));
  }
}

/// True when `minute` (minutes since local midnight) falls inside `[start, end)`.
///
/// Mirrors the backend `clock.in_window` exactly: an end before the start means
/// the window crosses midnight, and `start == end` means "all day".
bool minutesInWindow(int minute, int start, int end) {
  if (start == end) return true;
  if (start < end) return minute >= start && minute < end;
  return minute >= start || minute < end;
}

String localDateLabel(DateTime wall) {
  final month = wall.month.toString().padLeft(2, '0');
  final day = wall.day.toString().padLeft(2, '0');
  return '${wall.year}-$month-$day';
}

String clockLabel(DateTime wall) {
  final hour = wall.hour.toString().padLeft(2, '0');
  final minute = wall.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// The scheduling-relevant slice of `preferences` plus the runtime gates.
class ReminderSettings {
  const ReminderSettings({
    required this.greetingStartMinute,
    required this.greetingEndMinute,
    required this.quietStartMinute,
    required this.quietEndMinute,
    required this.dailyCap,
    required this.paused,
    required this.consentActive,
    required this.hasActiveSession,
    required this.designatedDeviceOk,
    this.snoozedUntilUtc,
  });

  final int greetingStartMinute;
  final int greetingEndMinute;
  final int quietStartMinute;
  final int quietEndMinute;
  final int dailyCap;
  final bool paused;
  final bool consentActive;
  final bool hasActiveSession;
  final bool designatedDeviceOk;
  final DateTime? snoozedUntilUtc;

  factory ReminderSettings.fromPreferences(
    Preferences preferences, {
    bool consentActive = false,
    bool hasActiveSession = false,
    bool designatedDeviceOk = true,
    DateTime? snoozedUntilUtc,
  }) => ReminderSettings(
    greetingStartMinute: preferences.greetingStartMinute,
    greetingEndMinute: preferences.greetingEndMinute,
    quietStartMinute: preferences.quietStartMinute,
    quietEndMinute: preferences.quietEndMinute,
    dailyCap: preferences.dailyCap,
    paused: preferences.paused,
    consentActive: consentActive,
    hasActiveSession: hasActiveSession,
    designatedDeviceOk: designatedDeviceOk,
    snoozedUntilUtc: snoozedUntilUtc,
  );

  ReminderSettings copyWith({
    int? greetingStartMinute,
    int? greetingEndMinute,
    int? quietStartMinute,
    int? quietEndMinute,
    int? dailyCap,
    bool? paused,
    bool? consentActive,
    bool? hasActiveSession,
    bool? designatedDeviceOk,
    DateTime? snoozedUntilUtc,
    bool clearSnooze = false,
  }) => ReminderSettings(
    greetingStartMinute: greetingStartMinute ?? this.greetingStartMinute,
    greetingEndMinute: greetingEndMinute ?? this.greetingEndMinute,
    quietStartMinute: quietStartMinute ?? this.quietStartMinute,
    quietEndMinute: quietEndMinute ?? this.quietEndMinute,
    dailyCap: dailyCap ?? this.dailyCap,
    paused: paused ?? this.paused,
    consentActive: consentActive ?? this.consentActive,
    hasActiveSession: hasActiveSession ?? this.hasActiveSession,
    designatedDeviceOk: designatedDeviceOk ?? this.designatedDeviceOk,
    snoozedUntilUtc: clearSnooze
        ? null
        : (snoozedUntilUtc ?? this.snoozedUntilUtc),
  );
}

/// One planned proactive invitation.
class ReminderPlan {
  const ReminderPlan({
    required this.localDate,
    required this.wallTime,
    required this.utcInstant,
    required this.title,
    required this.body,
  });

  final String localDate;
  final DateTime wallTime;
  final DateTime utcInstant;
  final String title;
  final String body;

  String get localTimeLabel => clockLabel(wallTime);

  Map<String, Object?> toJson() => <String, Object?>{
    'local_date': localDate,
    'local_time': localTimeLabel,
    'utc': utcInstant.toIso8601String(),
    'title': title,
    'body': body,
  };
}

/// Locally persisted invitation state. Survives an app restart (SPEC §9).
class ReminderState {
  const ReminderState({
    this.attemptsToday = 0,
    this.lastAttemptLocalDate = '',
    this.snoozedUntilUtc,
  });

  final int attemptsToday;
  final String lastAttemptLocalDate;
  final DateTime? snoozedUntilUtc;

  static const ReminderState empty = ReminderState();

  /// Attempts recorded on `localDate`; a stale date counts as zero, which is how
  /// the daily cap resets at local midnight even across a restart.
  int attemptsOn(String localDate) =>
      lastAttemptLocalDate == localDate ? attemptsToday : 0;

  ReminderState recordAttempt(String localDate) {
    final sameDay = lastAttemptLocalDate == localDate;
    return ReminderState(
      attemptsToday: sameDay ? attemptsToday + 1 : 1,
      lastAttemptLocalDate: localDate,
      snoozedUntilUtc: snoozedUntilUtc,
    );
  }

  ReminderState withSnooze(DateTime? untilUtc) => ReminderState(
    attemptsToday: attemptsToday,
    lastAttemptLocalDate: lastAttemptLocalDate,
    snoozedUntilUtc: untilUtc,
  );

  bool isSnoozedAt(DateTime nowUtc) {
    final until = snoozedUntilUtc;
    return until != null && until.isAfter(nowUtc);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'attempts_today': attemptsToday,
    'last_attempt_local_date': lastAttemptLocalDate,
    'snoozed_until': snoozedUntilUtc?.toIso8601String(),
  };

  factory ReminderState.fromJson(Map<String, Object?> json) {
    final snoozed = json['snoozed_until'];
    return ReminderState(
      attemptsToday: json['attempts_today'] is int
          ? json['attempts_today']! as int
          : int.tryParse('${json['attempts_today'] ?? 0}') ?? 0,
      lastAttemptLocalDate: '${json['last_attempt_local_date'] ?? ''}',
      snoozedUntilUtc: snoozed is String
          ? DateTime.tryParse(snoozed)?.toUtc()
          : null,
    );
  }
}
