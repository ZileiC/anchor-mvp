/// Remembers the backend address typed in on the phone — and only on the phone.
///
/// The computer's LAN address changes with the Wi-Fi (10.4.x at home, 10.2.x on
/// campus, 192.168.43.x on a hotspot), so compiling it in with `--dart-define`
/// meant rebuilding the APK for every network. The family picks the address once
/// on the login screen instead, and this file keeps it across app restarts.
///
/// **The appliance never reads this file** (2026-11-14): a Windows build talks to
/// the backend bundled next to it, over loopback, and a stored LAN address there
/// is always wrong. That distinction cost a demo: a widget test discovered
/// `192.168.43.57`, wrote it here, and the next desktop launch pointed at an
/// address that did not exist on the machine.
///
/// Which is also why the cache is per instance and the directory is injectable:
/// a test may never touch the real file. `InMemoryAddressStore` in the test
/// support code is what tests use.
///
/// Location: `%LOCALAPPDATA%\Anchor\backend_address.txt` (or the mobile support
/// directory). Only an address — never a token or a key (see [CredentialStore]
/// for why nothing secret is written to disk).
library;

import 'dart:io';

/// Reads and writes `<app support dir>/backend_address.txt`.
class BackendAddressStore {
  const BackendAddressStore({this.directory});

  /// Overrides where the file lives. Null means the real support directory; a
  /// test passes a temp directory (or uses an in-memory subclass).
  final String? directory;

  static const String fileName = 'backend_address.txt';

  static String? _lastWritten;

  /// The address this process last loaded or saved, for `addressChosenHere`.
  ///
  /// Kept as one value rather than per instance because the app has exactly one
  /// address; it is reset by [clearCache].
  static String? get current => _lastWritten;

  static void clearCache() => _lastWritten = null;

  bool get hasSaved => (_lastWritten ?? '').trim().isNotEmpty;

  File get file =>
      File('${directory ?? _supportDir()}${Platform.pathSeparator}$fileName');

  /// The saved address, or null when the family never changed it.
  Future<String?> load() async {
    if (_lastWritten != null) return _lastWritten;
    try {
      final target = file;
      if (!await target.exists()) return null;
      final text = (await target.readAsString()).trim();
      if (text.isEmpty) return null;
      _lastWritten = text;
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
    _lastWritten = text;
    try {
      final target = file;
      await target.parent.create(recursive: true);
      await target.writeAsString(text, flush: true);
      return true;
    } on Object {
      // Still usable for this run; only the persistence failed.
      return false;
    }
  }

  /// Forgets the saved address on disk and in memory (a wrong address left the
  /// appliance unreachable once; the family gets a clean slate the same way).
  Future<void> forget() async {
    _lastWritten = null;
    try {
      final target = file;
      if (await target.exists()) await target.delete();
    } on Object {
      // Nothing to do: forgetting in memory is the important half.
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

/// In-memory store: what every widget test uses, so a test can never rewrite the
/// machine's real address file.
class InMemoryAddressStore extends BackendAddressStore {
  InMemoryAddressStore([String? initial]) : _value = initial;

  String? _value;

  int saves = 0;

  @override
  bool get hasSaved => (_value ?? '').trim().isNotEmpty;

  @override
  File get file => File('${Directory.systemTemp.path}/anchor-in-memory.txt');

  @override
  Future<String?> load() async => _value;

  @override
  Future<bool> save(String address) async {
    final text = address.trim();
    if (text.isEmpty) return false;
    _value = text;
    saves++;
    return true;
  }

  @override
  Future<void> forget() async {
    _value = null;
  }
}
