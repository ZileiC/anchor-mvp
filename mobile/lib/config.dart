/// Build-time configuration for the Anchor app.
///
/// The API base can be overridden without touching code:
///
///   flutter run --dart-define=ANCHOR_API_BASE=http://192.168.1.20:8077
class AnchorConfig {
  const AnchorConfig._();

  /// Backend origin, e.g. `http://127.0.0.1:8077`. No trailing slash.
  ///
  /// Two builds, two truths (2026-11-12):
  ///
  /// * the **appliance** always talks to the backend bundled next to it, so its
  ///   address is the compiled-in loopback and nothing else can be right;
  /// * the **phone** cannot know the computer's address at build time — the LAN
  ///   address changes with the Wi-Fi (10.4.x at home, 10.2.x on campus). So the
  ///   compiled-in value is only a sign-in default; the login screen shows it,
  ///   offers 换一个地址, and the chosen address is saved and wins
  ///   (`services/backend_address_store.dart`). `--dart-define=ANCHOR_API_BASE=…`
  ///   still overrides this default for a fixed setup.
  static const String apiBase = String.fromEnvironment(
    'ANCHOR_API_BASE',
    defaultValue: 'http://127.0.0.1:8077',
  );

  /// Versioned API prefix from SPEC §6.
  static const String apiPrefix = '/api/v1';

  /// Full HTTP timeout for one request.
  ///
  /// 90 s, not 15 s: a spoken turn is upload → cloud ASR (0.6–10 s, provider
  /// latency varies a lot) → LLM (2–5 s), so a 15 s budget made a perfectly
  /// healthy backend look offline on any longer sentence ("The server took too
  /// long to answer" was this constant, measured 2026-11-10). The startup probe
  /// in `backend_bootstrapper.dart` keeps its own short timeout, so a dead
  /// backend is still detected quickly.
  static const Duration requestTimeout = Duration(seconds: 90);

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
