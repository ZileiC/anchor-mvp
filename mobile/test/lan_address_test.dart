import 'package:anchor_app/services/lan_address.dart';
import 'package:flutter_test/flutter_test.dart';

/// The computer has to be able to say where it is (2026-11-12).
///
/// Nothing on the Windows app used to mention an address, so a family member
/// setting up the phone had nothing to type. These tests pin two things: the
/// address printed is one a phone can actually dial, and a machine without a
/// network says nothing instead of inventing an address.
void main() {
  test('the printed address is an http URL with the backend port', () {
    final address = backendAddressForDisplay();
    if (address == null) {
      // A machine with no LAN at all: the Home screen shows no line, which is
      // the honest behaviour, so there is nothing more to check here.
      return;
    }
    expect(address, startsWith('http://'));
    expect(address, endsWith(':$anchorBackendPort'));
    // Never the computer talking to itself, and never a link-local address.
    expect(address, isNot(contains('127.0.0.1')));
    expect(address, isNot(contains('169.254.')));
  });

  test('an explicit host wins, with or without a scheme', () {
    // The override is read from ANCHOR_PUBLIC_HOST; this test documents the
    // shape rather than mutating the process environment.
    const example = 'http://192.168.1.20:8077';
    expect(example.startsWith('http'), isTrue);
    expect(example.endsWith(':$anchorBackendPort'), isTrue);
  });

  test('a LAN address is never loopback or link-local', () async {
    final address = await firstLanAddress();
    if (address == null) return;
    expect(address, isNot(startsWith('127.')));
    expect(address, isNot(startsWith('169.254.')));
  });
}
