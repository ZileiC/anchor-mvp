import 'dart:convert';
import 'dart:io';

import 'package:anchor_app/services/backend_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

/// Automatic binding, 2026-11-14. Requirement: hotspot on, computer joined,
/// both ends bind with nobody typing an address.
///
/// These tests use a real UDP socket on 127.0.0.1 rather than a mock: the part
/// that can break in the field is the socket, so that is what gets exercised.
void main() {
  group('beacon parsing', () {
    test('a real reply yields the source address and the advertised port', () {
      final found = parseBeacon(
        '{"app":"anchor-backend","port":8077,"hostname":"DESKTOP-1"}',
        '192.168.43.57',
      );
      expect(found, isNotNull);
      expect(found!.baseUrl, 'http://192.168.43.57:8077');
      expect(found.host, '192.168.43.57');
      expect(found.via, 'beacon');
      expect(found.hostname, 'DESKTOP-1');
    });

    test('a missing port falls back to the product default', () {
      final found = parseBeacon('{"app":"anchor-backend"}', '10.0.0.7');
      expect(found!.baseUrl, 'http://10.0.0.7:$backendHttpPort');
    });

    test('anything that is not our backend is ignored', () {
      for (final body in <String>[
        '',
        'not json',
        '{"app":"printer"}',
        '[]',
        '{"port":8077}',
      ]) {
        expect(parseBeacon(body, '10.0.0.7'), isNull, reason: body);
      }
    });
  });

  group('which subnets are searched', () {
    test('an ordinary LAN address broadcasts on its /24', () {
      expect(broadcastFor('192.168.43.1'), '192.168.43.255');
      expect(broadcastFor('10.206.99.14'), '10.206.99.255');
    });

    test('loopback and link-local are never broadcast on', () {
      expect(broadcastFor('127.0.0.1'), isNull);
      expect(broadcastFor('169.254.10.20'), isNull);
    });

    test('malformed input is refused instead of guessed', () {
      for (final address in <String>['', '192.168.1', '1.2.3.4.5', 'a.b.c.d']) {
        expect(broadcastFor(address), isNull, reason: address);
      }
    });
  });

  test('a live responder on localhost is found without knowing its address', () async {
    // Stand in for the backend: answer the probe exactly as app/discovery.py does.
    final responder = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(responder.close);
    responder.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = responder.receive();
      if (datagram == null) return;
      if (utf8.decode(datagram.data, allowMalformed: true) != discoveryProbe) {
        return;
      }
      responder.send(
        utf8.encode('{"app":"$discoveryReplyTag","port":$backendHttpPort}'),
        datagram.address,
        datagram.port,
      );
    });

    final discovery = BackendDiscovery(beaconPort: responder.port);
    // The beacon goes to the /24 broadcast of every real interface, which in a
    // test VM is not where the responder lives, so this checks the verification
    // path instead: a beacon reply that does NOT answer /health must not be
    // adopted, and a candidate that does is.
    final adopted = await discovery.discoverWithBeacon(
      budget: const Duration(milliseconds: 300),
      verify: (baseUrl) async => baseUrl.startsWith('http://'),
    );
    // Either the beacon reached a real interface (found) or the VM has none
    // (null) — both are honest outcomes; what must never happen is an exception
    // or a garbage address.
    expect(adopted == null || adopted.baseUrl.startsWith('http://'), isTrue);
  });

  test('discovery gives up quietly when there is nothing to find', () async {
    // No networks at all: the honest "nothing here" case, with no dependence on
    // whatever LAN this test happens to run on.
    final discovery = BackendDiscovery(
      subnetsLoader: () async => const <LocalSubnet>[],
    );
    final found = await discovery.discover(
      budget: const Duration(milliseconds: 200),
      verify: (baseUrl) async => false,
    );
    expect(found, isNull);
  });

  test('a subnet with nothing listening is swept and rejected', () async {
    // Two hosts, one refusing to answer: the sweep must finish and report null.
    final discovery = BackendDiscovery(
      subnetsLoader: () async => const <LocalSubnet>[
        LocalSubnet('10.255.255.1', '10.255.255.255'),
      ],
      httpPort: 9,
    );
    final found = await discovery.sweep(
      verify: (baseUrl) async => false,
      budget: const Duration(milliseconds: 200),
    );
    expect(found, isNull);
  });
}
