/// Remembers the backend address typed in on the phone.
///
/// The computer's LAN address changes with the Wi-Fi (10.4.x at home, 10.2.x on
/// campus, 192.168.x elsewhere), so compiling it in with `--dart-define` meant
/// rebuilding the APK for every network. The family picks the address once on the
/// login screen instead, and this file keeps it across app restarts.
///
/// Location: `%LOCALAPPDATA%\Anchor\backend_address.txt` (or the mobile support
/// directory). Only an address — never a token or a key (see [CredentialStore]
/// for why nothing secret is written to disk).
library;

import 'dart:io';

/// Reads and writes `<app support dir>/backend_address.txt`.
class BackendAddressStore {
  const BackendAddressStore();

  static String? _cached;

  File get _file =>
      File('${_supportDir()}${Platform.pathSeparator}backend_address.txt');

  /// The saved address, or null when the family never changed it.
  Future<String?> load() async {
    if (_cached != null) return _cached;
    try {
      final file = _file;
      if (!await file.exists()) return null;
      final text = (await file.readAsString()).trim();
      if (text.isEmpty) return null;
      _cached = text;
      return text;
    } on Object {
      // An unreadable file is not an error worth bothering the family with: the
      // compiled-in default is still there.
      return null;
    }
  }

  Future<bool> save(String address) async {
    final text = address.trim();
    if (text.isEmpty) return false;
    try {
      final file = _file;
      await file.parent.create(recursive: true);
      await file.writeAsString(text, flush: true);
      _cached = text;
      return true;
    } on Object {
      // Still usable for this run; only the persistence failed.
      _cached = text;
      return false;
    }
  }

  /// The per-user writable directory. LOCALAPPDATA on Windows, the app data dir
  /// everywhere else; created lazily by [save].
  String _supportDir() {
    final fromEnv = _env('LOCALAPPDATA') ?? _env('XDG_DATA_HOME');
    final base =
        fromEnv ??
        _env('HOME') ??
        _env('USERPROFILE') ??
        Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}Anchor';
  }

  String? _env(String name) => Platform.environment[name];
}
