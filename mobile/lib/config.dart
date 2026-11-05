/// Build-time configuration for the Anchor app.
///
/// The API base can be overridden without touching code:
///
///   flutter run --dart-define=ANCHOR_API_BASE=http://192.168.1.20:8077
class AnchorConfig {
  const AnchorConfig._();

  /// Backend origin, e.g. `http://127.0.0.1:8077`. No trailing slash.
  static const String apiBase = String.fromEnvironment(
    'ANCHOR_API_BASE',
    defaultValue: 'http://127.0.0.1:8077',
  );

  /// Versioned API prefix from SPEC §6.
  static const String apiPrefix = '/api/v1';

  /// Full HTTP timeout for one request. Generous: the demo backend is local but
  /// a slow ASR provider must not look like an offline device.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Dev-only demo identities from the seed (SPEC §4, scripts/seed_demo.py).
  static const DemoAccount seniorDemo = DemoAccount(
    userId: 1,
    nameZh: '林秀兰',
    nameEn: 'Lin Xiulan',
    role: 'senior',
  );
  static const DemoAccount caregiverDemo = DemoAccount(
    userId: 2,
    nameZh: 'Mei（家人）',
    nameEn: 'Mei (family)',
    role: 'caregiver',
  );

  /// Stable id of this installation, used for the "designated device" rule
  /// (one proactive invitation per day, on one device only).
  static const String deviceId = 'anchor-win-demo-1';
}

/// A demo login from `POST /api/v1/dev/login`.
class DemoAccount {
  const DemoAccount({
    required this.userId,
    required this.nameZh,
    required this.nameEn,
    required this.role,
  });

  final int userId;
  final String nameZh;
  final String nameEn;
  final String role;

  String displayName({required bool english}) => english ? nameEn : nameZh;
}
