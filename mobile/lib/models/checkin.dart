import 'parse.dart';

/// `GET /checkins/eligibility` (SPEC §6.2). Reasons are backend strings.
class CheckinEligibility {
  const CheckinEligibility({
    required this.eligible,
    required this.reasons,
    required this.capRemaining,
    required this.localTime,
    required this.localDate,
    required this.designatedDeviceOk,
    this.windowStart,
    this.windowEnd,
    this.quietStart,
    this.quietEnd,
  });

  final bool eligible;
  final List<String> reasons;
  final int capRemaining;
  final String localTime;
  final String localDate;
  final bool designatedDeviceOk;
  final String? windowStart;
  final String? windowEnd;
  final String? quietStart;
  final String? quietEnd;

  static const CheckinEligibility unknown = CheckinEligibility(
    eligible: false,
    reasons: <String>['unavailable'],
    capRemaining: 0,
    localTime: '',
    localDate: '',
    designatedDeviceOk: false,
  );

  factory CheckinEligibility.fromJson(Map<String, Object?> json) {
    final window = asMap(json['window']);
    final quiet = asMap(json['quiet_hours']);
    return CheckinEligibility(
      eligible: asBool(json['eligible']),
      reasons: asStringList(json['reasons']),
      capRemaining: asInt(json['cap_remaining']),
      localTime: asString(json['local_time']),
      localDate: asString(json['local_date']),
      designatedDeviceOk: asBool(json['designated_device_ok']),
      windowStart: asStringOrNull(window['start']),
      windowEnd: asStringOrNull(window['end']),
      quietStart: asStringOrNull(quiet['start']),
      quietEnd: asStringOrNull(quiet['end']),
    );
  }
}

/// One entry of the next-7-days local notification plan.
class CheckinEntry {
  const CheckinEntry({
    required this.date,
    required this.localTime,
    required this.title,
    required this.body,
  });

  final String date;
  final String localTime;
  final String title;
  final String body;

  factory CheckinEntry.fromJson(Map<String, Object?> json) => CheckinEntry(
    date: asString(json['date']),
    localTime: asString(json['local_time']),
    title: asString(json['title']),
    body: asString(json['body']),
  );
}

/// `GET /checkins/schedule`; `note` explains why a plan is empty.
class CheckinSchedule {
  const CheckinSchedule({required this.entries, required this.note});

  final List<CheckinEntry> entries;
  final String note;

  static const CheckinSchedule empty = CheckinSchedule(
    entries: <CheckinEntry>[],
    note: '',
  );

  bool get isPaused => note == 'paused';
  bool get isSnoozed => note == 'snoozed';
  bool get isCapZero => note == 'daily_cap_zero';
  bool get isConsentOff => note == 'consent_off';

  factory CheckinSchedule.fromJson(Map<String, Object?> json) =>
      CheckinSchedule(
        entries: asList(json['entries'])
            .map((item) => CheckinEntry.fromJson(asMap(item)))
            .toList(growable: false),
        note: asString(json['note']),
      );
}

/// `POST /checkins/attempts` response.
class CheckinAttempt {
  const CheckinAttempt({
    required this.recorded,
    required this.outcome,
    required this.capRemaining,
    this.localDate,
  });

  final bool recorded;
  final String outcome;
  final int capRemaining;
  final String? localDate;

  factory CheckinAttempt.fromJson(Map<String, Object?> json) => CheckinAttempt(
    recorded: asBool(json['recorded']),
    outcome: asString(json['outcome']),
    capRemaining: asInt(json['cap_remaining']),
    localDate: asStringOrNull(json['local_date']),
  );
}

/// A generic notification (never health content, SPEC §6.6).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.readAt,
    this.createdAt,
  });

  final int id;
  final String kind;
  final String title;
  final String body;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, Object?> json) =>
      AppNotification(
        id: asInt(json['id']),
        kind: asString(json['kind']),
        title: asString(json['title']),
        body: asString(json['body']),
        readAt: asDateTime(json['read_at']),
        createdAt: asDateTime(json['created_at']),
      );
}

/// `GET /health`, used as the inexpensive "is the backend up?" probe.
class HealthInfo {
  const HealthInfo({
    required this.status,
    required this.version,
    required this.offlineCapabilities,
  });

  final String status;
  final String version;
  final List<String> offlineCapabilities;

  bool get isOk => status == 'ok';

  factory HealthInfo.fromJson(Map<String, Object?> json) => HealthInfo(
    status: asString(json['status']),
    version: asString(json['version']),
    offlineCapabilities: asStringList(json['offline_capabilities']),
  );
}
