import 'activity.dart';
import 'parse.dart';

/// One caption line from a session (`{role, text, at}`).
class Caption {
  const Caption({required this.role, required this.text, this.at});

  final String role;
  final String text;
  final DateTime? at;

  bool get isSenior => role == 'senior';

  factory Caption.fromJson(Map<String, Object?> json) => Caption(
    role: asString(json['role'], 'anchor'),
    text: asString(json['text']),
    at: asDateTime(json['at']),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'text': text,
    'at': at?.toIso8601String(),
  };
}

/// `POST /sessions` response, and also `GET /sessions/{id}`.
class ConversationSession {
  const ConversationSession({
    required this.sessionId,
    required this.state,
    required this.micOn,
    this.startedAt,
    this.greetingText,
    this.captions = const <Caption>[],
  });

  final String sessionId;
  final String state;
  final bool micOn;
  final DateTime? startedAt;
  final String? greetingText;
  final List<Caption> captions;

  bool get isActive => state == 'active';

  factory ConversationSession.fromJson(Map<String, Object?> json) =>
      ConversationSession(
        sessionId: asString(json['session_id']),
        state: asString(json['state'], 'active'),
        micOn: asBool(json['mic_on'], true),
        startedAt: asDateTime(json['started_at']),
        greetingText: asStringOrNull(json['greeting_text']),
        captions: asList(json['captions'])
            .map((item) => Caption.fromJson(asMap(item)))
            .toList(growable: false),
      );
}

/// `action` inside a turn result. Only `stop`, `activity` and `dial` exist.
class TurnAction {
  const TurnAction({
    required this.type,
    this.activityId,
    this.activity,
    this.contactId,
    this.label,
    this.phone,
    this.contactActionId,
    this.requiresConfirmation = false,
  });

  final String type;
  final String? activityId;
  final ActivityItem? activity;
  final int? contactId;
  final String? label;
  final String? phone;
  final int? contactActionId;
  final bool requiresConfirmation;

  bool get isStop => type == 'stop';
  bool get isActivity => type == 'activity';
  bool get isDial => type == 'dial';

  factory TurnAction.fromJson(Map<String, Object?> json) => TurnAction(
    type: asString(json['type']),
    activityId: asStringOrNull(json['activity_id']),
    activity: json['activity'] == null
        ? null
        : ActivityItem.fromJson(asMap(json['activity'])),
    contactId: json['contact_id'] == null ? null : asInt(json['contact_id']),
    label: asStringOrNull(json['label']),
    phone: asStringOrNull(json['phone']),
    contactActionId: json['contact_action_id'] == null
        ? null
        : asInt(json['contact_action_id']),
    requiresConfirmation: asBool(json['requires_confirmation']),
  );
}

/// A single clarifying question (`{kind, options}`), never more than one.
class TurnAsk {
  const TurnAsk({required this.kind, required this.options});

  final String kind;
  final List<String> options;

  factory TurnAsk.fromJson(Map<String, Object?> json) => TurnAsk(
    kind: asString(json['kind'], 'clarify'),
    options: asStringList(json['options']),
  );
}

/// `POST /sessions/{id}/turns` response (SPEC §6.3).
class TurnResult {
  const TurnResult({
    required this.transcript,
    required this.replyText,
    required this.intent,
    required this.stopped,
    this.turnId,
    this.action,
    this.ask,
    this.captions = const <Caption>[],
  });

  final int? turnId;
  final String transcript;
  final String replyText;
  final String intent;
  final bool stopped;
  final TurnAction? action;
  final TurnAsk? ask;
  final List<Caption> captions;

  factory TurnResult.fromJson(Map<String, Object?> json) => TurnResult(
    turnId: json['turn_id'] == null ? null : asInt(json['turn_id']),
    transcript: asString(json['transcript']),
    replyText: asString(json['reply_text']),
    intent: asString(json['intent'], 'chat'),
    stopped: asBool(json['stopped']),
    action: json['action'] == null
        ? null
        : TurnAction.fromJson(asMap(json['action'])),
    ask: json['ask'] == null ? null : TurnAsk.fromJson(asMap(json['ask'])),
    captions: asList(json['captions'])
        .map((item) => Caption.fromJson(asMap(item)))
        .toList(growable: false),
  );
}
