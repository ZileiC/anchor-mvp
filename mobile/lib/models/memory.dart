import 'parse.dart';

/// An explicitly approved (or proposed) remembered fact (SPEC §6.4).
class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.fact,
    required this.approvalState,
    this.approvedAt,
    this.createdAt,
  });

  final int id;
  final String fact;
  final String approvalState;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  bool get isApproved => approvalState == 'approved';
  bool get isProposed => approvalState == 'proposed';

  factory MemoryItem.fromJson(Map<String, Object?> json) => MemoryItem(
    id: asInt(json['id']),
    fact: asString(json['fact']),
    approvalState: asString(json['approval_state'], 'proposed'),
    approvedAt: asDateTime(json['approved_at']),
    createdAt: asDateTime(json['created_at']),
  );
}
