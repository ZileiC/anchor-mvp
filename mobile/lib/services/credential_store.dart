/// Session credentials for the demo build.
///
/// **Documented limitation (SPEC §9):** the bearer token lives in memory for the
/// duration of one app run. Windows and mobile secure storage is a TODO adapter:
/// nothing is written to disk, so restarting the app requires signing in again.
/// That is deliberate for the MVP — a plaintext token file would be worse.
class CredentialStore {
  String? _token;
  int? _userId;
  String? _role;
  DateTime? _issuedAt;

  String? get token => _token;
  int? get userId => _userId;
  String? get role => _role;
  DateTime? get issuedAt => _issuedAt;

  bool get isSignedIn => _token != null;

  void save({
    required String token,
    required int userId,
    required String role,
  }) {
    _token = token;
    _userId = userId;
    _role = role;
    _issuedAt = DateTime.now().toUtc();
  }

  void clear() {
    _token = null;
    _userId = null;
    _role = null;
    _issuedAt = null;
  }
}
