import 'dart:convert';

import 'parse.dart';

/// One highlight of a weekly digest: plain language, one topic, evidence refs.
class DigestItem {
  const DigestItem({
    required this.topic,
    required this.text,
    this.evidenceIds = const <int>[],
  });

  final String topic;
  final String text;
  final List<int> evidenceIds;

  factory DigestItem.fromJson(Map<String, Object?> json) => DigestItem(
    topic: asString(json['topic'], 'wellbeing'),
    text: asString(json['text']),
    evidenceIds: asList(json['evidence_ids'])
        .map((value) => asInt(value))
        .toList(growable: false),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'topic': topic,
    'text': text,
    'evidence_ids': evidenceIds,
  };
}

/// A weekly digest row (SPEC §6.6). At most three items — a maximum, not a quota.
class Digest {
  const Digest({
    required this.id,
    required this.status,
    this.periodStart,
    this.periodEnd,
    this.items = const <DigestItem>[],
    this.message,
    this.consentVersion,
  });

  final int id;
  final String status;
  final String? periodStart;
  final String? periodEnd;
  final List<DigestItem> items;
  final String? message;
  final int? consentVersion;

  bool get isInsufficientData =>
      status == 'insufficient_data' || status == 'insufficient_information';
  bool get isAwaitingApproval => status == 'awaiting_senior_approval';
  bool get isDraft => status == 'draft';
  bool get isApproved => status == 'approved' || status == 'delivered';
  bool get canApprove => isAwaitingApproval || isDraft;

  /// The UI never renders more than three highlights, even if a payload has more.
  List<DigestItem> get highlights =>
      items.length > 3 ? items.sublist(0, 3) : items;

  factory Digest.fromJson(Map<String, Object?> json) {
    // Some responses carry `items_json` as a string (database row) and some as a
    // list (serialized payload). Accept both.
    Object? rawItems = json['items'];
    if (rawItems is String) {
      rawItems = _tryDecode(rawItems);
    }
    return Digest(
      id: asInt(json['id']),
      status: asString(json['status'], 'draft'),
      periodStart: asStringOrNull(json['period_start']),
      periodEnd: asStringOrNull(json['period_end']),
      items: asList(rawItems)
          .map((item) => DigestItem.fromJson(asMap(item)))
          .toList(growable: false),
      message: asStringOrNull(json['message']),
      consentVersion: json['consent_version'] == null
          ? null
          : asInt(json['consent_version']),
    );
  }

  static Object? _tryDecode(String raw) {
    if (raw.trim().isEmpty) return const <Object?>[];
    try {
      return jsonDecode(raw);
    } on FormatException {
      return const <Object?>[];
    }
  }
}

/// Tolerant parser for `GET /digests`, whose shape is shared by two roles.
class DigestList {
  const DigestList(this.digests, {this.note = ''});

  final List<Digest> digests;

  /// Backend note when the list is empty (`insufficient_information`, ...).
  final String note;

  static const DigestList empty = DigestList(<Digest>[]);

  bool get insufficientInformation => note == 'insufficient_information';

  Digest? get latest => digests.isEmpty ? null : digests.first;

  /// Accepts `{items:[digest...]}`, `{digests:[...]}` and a single digest object
  /// in which `items` are highlights (the insufficient-data shape in SPEC §6.6).
  factory DigestList.fromResponse(Object? payload) {
    final json = asMap(payload);
    final list = asList(json['digests']).isNotEmpty
        ? asList(json['digests'])
        : asList(json['items']);
    final digests = <Digest>[];
    for (final entry in list) {
      final map = asMap(entry);
      final looksLikeDigest =
          map.containsKey('period_start') ||
          map.containsKey('status') ||
          map.containsKey('items_json');
      if (looksLikeDigest) {
        digests.add(Digest.fromJson(map));
      }
    }
    if (digests.isEmpty &&
        (list.isNotEmpty ||
            json.containsKey('status') ||
            json.containsKey('message') ||
            json.containsKey('id'))) {
      // The whole payload is one digest whose `items` are highlights.
      digests.add(Digest.fromJson(json));
    }
    return DigestList(
      List<Digest>.unmodifiable(digests),
      note: asString(json['note']),
    );
  }
}
