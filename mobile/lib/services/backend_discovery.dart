/// Finds the computer without anyone typing an IP address, 2026-11-14.
///
/// The requirement was blunt: hotspot on, computer joined, both ends bind on
/// their own. Two mechanisms, because on a real hotspot one of them is usually
/// filtered:
///
/// 1. **UDP beacon** (fast, no dependencies). Broadcast
///    `ANCHOR-DISCOVER-v1` on every local subnet, and take the *source address*
///    of the reply — that address is the computer, by definition. The payload is
///    only used to confirm it is an Anchor and to learn the HTTP port.
/// 2. **HTTP sweep** (fallback). Try every host on each local /24 for
///    `GET /api/v1/health`, with a small concurrency window. Slower, but it
///    survives networks that drop broadcast packets.
///
/// Whatever comes back is verified once more over HTTP before the app adopts it,
/// so a stale or unrelated reply cannot hijack the appliance.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The UDP port the backend answers discovery probes on
/// (`backend/app/discovery.py: DEFAULT_DISCOVERY_PORT`).
const int discoveryPort = 8078;

/// The probe the backend looks for, verbatim.
const String discoveryProbe = 'ANCHOR-DISCOVER-v1';

/// Tag the backend replies with; anything else on that port is ignored.
const String discoveryReplyTag = 'anchor-backend';

/// The HTTP port the packaged backend serves the API on.
const int backendHttpPort = 8077;

/// A computer that answered, plus how it was found (for the UI line).
class DiscoveredBackend {
  const DiscoveredBackend({
    required this.baseUrl,
    required this.host,
    required this.via,
    this.hostname = '',
  });

  final String baseUrl;
  final String host;

  /// `beacon` (UDP broadcast) or `sweep` (HTTP scan). Shown to the user, because
  /// "found it" and "guessed it" are different kinds of reassurance.
  final String via;

  /// The computer's own name, when the beacon carried it.
  final String hostname;

  @override
  String toString() => 'DiscoveredBackend($baseUrl via $via)';
}

/// Parses a beacon reply. Null when the datagram is not one of ours.
///
/// Kept pure so it can be tested without a network: the wild part of this
/// feature is the socket, not the JSON.
DiscoveredBackend? parseBeacon(String body, String sourceHost) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    if (decoded['app'] != discoveryReplyTag) return null;
    final port = decoded['port'];
    final httpPort = port is int && port > 0 ? port : backendHttpPort;
    return DiscoveredBackend(
      baseUrl: 'http://$sourceHost:$httpPort',
      host: sourceHost,
      via: 'beacon',
      hostname: '${decoded['hostname'] ?? ''}',
    );
  } on FormatException {
    return null;
  }
}

/// The broadcast address for an /24 that contains [address], or null when the
/// address is not something we should broadcast on.
///
/// Hotspots are /24 in practice (Android uses 192.168.43.0/24, iOS 172.20.10.0/24)
/// and every home router is too, so assuming /24 is a reasonable trade against
/// implementing DHCP option parsing.
String? broadcastFor(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    octets.add(value);
  }
  if (octets[0] == 127) return null; // loopback: nothing to find there
  if (octets[0] == 169 && octets[1] == 254) return null; // link-local
  return '${octets[0]}.${octets[1]}.${octets[2]}.255';
}

/// Every usable local IPv4 address with the /24 to sweep.
class LocalSubnet {
  const LocalSubnet(this.address, this.broadcast);

  final String address;
  final String broadcast;

  /// The first three octets plus a dot: `192.168.43.`.
  String get prefix => '${broadcast.split('.').take(3).join('.')}.';
}

/// Reads the phone's own addresses. On a hotspot the AP interface shows up here
/// with its own /24 — that is the network the computer joined.
Future<List<LocalSubnet>> localSubnets() async {
  final subnets = <LocalSubnet>[];
  final seen = <String>{};
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final text = address.address;
        final broadcast = broadcastFor(text);
        if (broadcast == null || !seen.add(text)) continue;
        subnets.add(LocalSubnet(text, broadcast));
      }
    }
  } on Object {
    // No network is a normal state; the caller reports "not found".
  }
  return subnets;
}

/// Finds the backend, or null when nothing answered inside [budget].
///
/// [verify] is the HTTP health check. It is a parameter so tests (and a future
/// QR-code path) can supply their own notion of "this is really the appliance".
class BackendDiscovery {
  const BackendDiscovery({
    this.beaconPort = discoveryPort,
    this.httpPort = backendHttpPort,
    this.subnetsLoader = localSubnets,
  });

  final int beaconPort;
  final int httpPort;

  /// Where the candidate networks come from. Injectable so a test can say
  /// "there is nothing to search" instead of sweeping this machine's real /24s
  /// (which is slow and depends on whatever network the developer happens to be
  /// on — a test that does that hangs for minutes on an idle LAN).
  final Future<List<LocalSubnet>> Function() subnetsLoader;

  /// The whole search: beacon first, sweep only if the beacon found nothing.
  Future<DiscoveredBackend?> discover({
    Duration budget = const Duration(seconds: 6),
    Future<bool> Function(String baseUrl)? verify,
  }) async {
    final check = verify ?? (baseUrl) => _healthy(baseUrl);
    final beacon = await discoverWithBeacon(budget: budget ~/ 2, verify: check);
    if (beacon != null) return beacon;
    return sweep(verify: check, budget: budget);
  }

  // -- 1. UDP beacon -------------------------------------------------------
  /// Broadcasts the probe on every local subnet and listens for a reply.
  Future<DiscoveredBackend?> discoverWithBeacon({
    Duration budget = const Duration(seconds: 3),
    Future<bool> Function(String baseUrl)? verify,
  }) async {
    final check = verify ?? (baseUrl) => _healthy(baseUrl);
    final subnets = await subnetsLoader();
    if (subnets.isEmpty) return null;

    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? repeat;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final targets = <String>{
        for (final subnet in subnets) '${subnet.broadcast}:$beaconPort',
        // Some stacks only route the limited broadcast; try it too.
        '255.255.255.255:$beaconPort',
      };
      final payload = utf8.encode(discoveryProbe);
      final deadline = DateTime.now().add(budget);
      final found = Completer<DiscoveredBackend?>();

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final host = datagram.address.address;
        final candidate = parseBeacon(
          utf8.decode(datagram.data, allowMalformed: true),
          host,
        );
        if (candidate == null || found.isCompleted) return;
        found.complete(candidate);
      });

      // Repeat the probe: a first datagram can be lost to ARP or a sleeping radio.
      repeat = Timer.periodic(const Duration(milliseconds: 400), (timer) {
        if (DateTime.now().isAfter(deadline) || found.isCompleted) {
          timer.cancel();
          // The completer has to be closed here too, or a search that found
          // nothing leaves the timer alive for the rest of the app's life.
          if (!found.isCompleted) found.complete(null);
          return;
        }
        for (final target in targets) {
          final parts = target.split(':');
          try {
            socket?.send(
              payload,
              InternetAddress(parts.first),
              int.parse(parts[1]),
            );
          } on Object {
            // One unreachable interface must not abort the others.
          }
        }
      });

      DiscoveredBackend? candidate;
      try {
        candidate = await found.future.timeout(
          budget + const Duration(milliseconds: 200),
        );
      } on TimeoutException {
        candidate = null;
      }
      if (candidate == null) return null;
      // Confirm before trusting it: the beacon proves an Anchor *process* is
      // there; the health check proves its API is actually up.
      return await check(candidate.baseUrl) ? candidate : null;
    } on Object {
      return null;
    } finally {
      repeat?.cancel();
      await subscription?.cancel();
      socket?.close();
    }
  }

  // -- 2. HTTP sweep -------------------------------------------------------
  /// Tries every host on each local /24 for the health endpoint.
  Future<DiscoveredBackend?> sweep({
    Future<bool> Function(String baseUrl)? verify,
    Duration budget = const Duration(seconds: 6),
  }) async {
    final check = verify ?? (baseUrl) => _healthy(baseUrl);
    final subnets = await subnetsLoader();
    for (final subnet in subnets) {
      final hosts = <String>[
        for (var last = 1; last <= 254; last++) '${subnet.prefix}$last',
      ]..shuffle(); // Not always the same order: a stuck host is not hit first.
      const window = 24;
      for (var start = 0; start < hosts.length; start += window) {
        final batch = hosts.skip(start).take(window);
        final results = await Future.wait(
          batch.map((host) async {
            final baseUrl = 'http://$host:$httpPort';
            return await check(baseUrl) ? baseUrl : null;
          }),
        );
        final hit = results.whereType<String>().toList();
        if (hit.isNotEmpty) {
          final baseUrl = hit.first;
          return DiscoveredBackend(
            baseUrl: baseUrl,
            host: Uri.parse(baseUrl).host,
            via: 'sweep',
          );
        }
      }
    }
    return null;
  }

  /// The one question that matters: does this address serve Anchor's health?
  ///
  /// Public because the app asks it before it agrees to search: an address that
  /// already works must never be replaced by a hunt.
  Future<bool> healthOf(String baseUrl) => _healthy(baseUrl);

  Future<bool> _healthy(String baseUrl) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 700);
    try {
      final request = await client
          .getUrl(Uri.parse('$baseUrl/api/v1/health'))
          .timeout(const Duration(milliseconds: 900));
      final response = await request.close().timeout(
        const Duration(milliseconds: 900),
      );
      await response.drain<void>();
      return response.statusCode == 200;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
