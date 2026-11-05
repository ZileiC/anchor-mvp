import 'parse.dart';

/// `GET /me` payload (SPEC §6.1).
class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.displayName,
    required this.timezone,
    required this.locale,
    required this.seniorId,
    required this.relationshipStatus,
  });

  final int id;
  final String role;
  final String displayName;
  final String timezone;
  final String locale;
  final int? seniorId;
  final String? relationshipStatus;

  bool get isSenior => role == 'senior';

  factory Profile.fromJson(Map<String, Object?> json) => Profile(
    id: asInt(json['id']),
    role: asString(json['role'], 'senior'),
    displayName: asString(json['display_name']),
    timezone: asString(json['timezone'], 'Asia/Shanghai'),
    locale: asString(json['locale'], 'zh-CN'),
    seniorId: json['senior_id'] == null ? null : asInt(json['senior_id']),
    relationshipStatus: asStringOrNull(json['relationship_status']),
  );
}

/// One row of `GET /relationships`.
class Relationship {
  const Relationship({
    required this.id,
    required this.seniorId,
    required this.caregiverId,
    required this.status,
    this.counterpartId,
    this.counterpartName,
  });

  final int id;
  final int seniorId;
  final int caregiverId;
  final String status;
  final int? counterpartId;
  final String? counterpartName;

  bool get isAccepted => status == 'accepted';
  bool get isPending => status == 'pending';

  factory Relationship.fromJson(Map<String, Object?> json) => Relationship(
    id: asInt(json['id']),
    seniorId: asInt(json['senior_id']),
    caregiverId: asInt(json['caregiver_id']),
    status: asString(json['status'], 'pending'),
    counterpartId: json['counterpart_id'] == null
        ? null
        : asInt(json['counterpart_id']),
    counterpartName: asStringOrNull(json['counterpart_name']),
  );
}

/// `POST /invitations` response — the token is returned exactly once.
class InvitationToken {
  const InvitationToken({
    required this.id,
    required this.token,
    required this.expiresAt,
  });

  final int id;
  final String token;
  final String expiresAt;

  factory InvitationToken.fromJson(Map<String, Object?> json) =>
      InvitationToken(
        id: asInt(json['id']),
        token: asString(json['token']),
        expiresAt: asString(json['expires_at']),
      );
}

/// Accepted invitation: a pending link only, sharing is still separate.
class InvitationAcceptance {
  const InvitationAcceptance({
    required this.relationshipId,
    required this.status,
  });

  final int relationshipId;
  final String status;

  factory InvitationAcceptance.fromJson(Map<String, Object?> json) =>
      InvitationAcceptance(
        relationshipId: asInt(json['relationship_id']),
        status: asString(json['status'], 'pending'),
      );
}

/// A caregiver's proposed schedule change (`POST /schedule-proposals`).
class ScheduleProposal {
  const ScheduleProposal({
    required this.id,
    required this.status,
    required this.payload,
    this.createdAt,
    this.counterpartName,
  });

  final int id;
  final String status;
  final Map<String, Object?> payload;
  final DateTime? createdAt;
  final String? counterpartName;

  factory ScheduleProposal.fromJson(Map<String, Object?> json) =>
      ScheduleProposal(
        id: asInt(json['id']),
        status: asString(json['status'], 'pending'),
        payload: asMap(json['payload']),
        createdAt: asDateTime(json['created_at']),
        counterpartName: asStringOrNull(json['counterpart_name']),
      );
}
