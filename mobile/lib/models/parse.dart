/// Small tolerant JSON helpers shared by the model layer.
///
/// The backend is the source of truth (SPEC §6); parsing must never crash the UI
/// on a missing optional field, so every accessor has a documented fallback.
library;

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double asDouble(Object? value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String asString(Object? value, [String fallback = '']) {
  if (value is String) return value;
  if (value == null) return fallback;
  return '$value';
}

String? asStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return '$value';
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lowered = value.toLowerCase();
    if (lowered == 'true' || lowered == '1') return true;
    if (lowered == 'false' || lowered == '0') return false;
  }
  return fallback;
}

Map<String, Object?> asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  return const <String, Object?>{};
}

List<Object?> asList(Object? value) {
  if (value is List) return value;
  return const <Object?>[];
}

List<String> asStringList(Object? value) =>
    asList(value)
        .map((item) => asString(item))
        .where((item) => item.isNotEmpty)
        .toList();

DateTime? asDateTime(Object? value) {
  final text = asString(value);
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc();
}
