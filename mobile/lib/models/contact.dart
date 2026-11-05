import 'parse.dart';

/// A saved family contact. The dialer never needs the server, so contacts can be
/// kept locally when the contact endpoint is unavailable (SPEC §9 offline rule).
class Contact {
  const Contact({
    required this.id,
    required this.label,
    required this.phone,
    this.isFamily = true,
  });

  final int id;
  final String label;
  final String phone;
  final bool isFamily;

  factory Contact.fromJson(Map<String, Object?> json) => Contact(
    id: asInt(json['id']),
    label: asString(json['label']),
    phone: asString(json['phone']),
    isFamily: asBool(json['is_family'], true),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'phone': phone,
    'is_family': isFamily,
  };
}

/// `POST /contact-actions` — recorded initiation, plus the dial URI to open.
class ContactAction {
  const ContactAction({
    required this.id,
    required this.label,
    required this.phone,
    required this.dialUri,
  });

  final int id;
  final String label;
  final String phone;
  final String dialUri;

  factory ContactAction.fromJson(Map<String, Object?> json) => ContactAction(
    id: asInt(json['contact_action_id']),
    label: asString(json['label']),
    phone: asString(json['phone']),
    dialUri: asString(json['dial_uri']),
  );
}
