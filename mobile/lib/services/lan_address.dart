/// The line the phone needs: which address this computer is reachable on.
///
/// Added 2026-11-12 (B). Before this, nothing on the computer said where it was:
/// the family had to guess (or ask someone) what to type on the phone. The answer
/// is one line in the corner of the Home screen.
///
/// Which address: the LAN one a phone can dial (192.168.x / 10.x), never
/// 127.0.0.1 (that is the computer talking to itself) and never an unreachable
/// 169.254.x. When there are several (Wi-Fi + Ethernet + WSL), the first usable
/// one wins; a second choice is not offered because a family setting up a phone
/// should not have to pick between networks.
library;

import 'dart:io';

/// The port the packaged backend listens on (`ANCHOR_PORT` overrides it there).
const int anchorBackendPort = 8077;

/// Env override for the address to print (a demo on a fixed machine, or a backend
/// on another host).
const String _overrideName = 'ANCHOR_PUBLIC_HOST';

String? backendAddressForDisplay({int port = anchorBackendPort}) {
  final override = Platform.environment[_overrideName];
  if (override != null && override.trim().isNotEmpty) {
    final value = override.trim();
    return value.startsWith('http') ? value : 'http://$value:$port';
  }
  // Looked up once by the caller at startup, so it is safe to read the cached
  // answer here; the async probe in firstLanAddress() is what fills it in.
  final address = currentLanAddress;
  if (address == null) return null;
  return 'http://$address:$port';
}

/// Filled in by [probeLanAddress] at startup; null until then.
String? currentLanAddress;

/// Looks the LAN address up once and remembers it.
Future<String?> probeLanAddress() async {
  currentLanAddress = await firstLanAddress();
  return currentLanAddress;
}

/// The first IPv4 address a device on the same network could reach, or null.
Future<String?> firstLanAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final text = address.address;
        if (text.startsWith('169.254.')) continue; // link-local: not routable
        if (text.startsWith('127.')) continue;
        return text;
      }
    }
  } on Object {
    // A machine with no network at all is a normal state, not an error.
    return null;
  }
  return null;
}
