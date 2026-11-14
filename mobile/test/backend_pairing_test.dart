import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/services/backend_discovery.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// A discovery that answers from a script instead of the network.
class _ScriptedDiscovery extends BackendDiscovery {
  _ScriptedDiscovery({this.found, this.healthy = const <String>{}});

  /// What a search returns. Null means "nothing on this network".
  final DiscoveredBackend? found;

  /// Addresses whose /api/v1/health answers.
  final Set<String> healthy;

  int searches = 0;

  @override
  Future<bool> healthOf(String baseUrl) async => healthy.contains(baseUrl);

  @override
  Future<DiscoveredBackend?> discover({
    Duration budget = const Duration(seconds: 6),
    Future<bool> Function(String baseUrl)? verify,
  }) async {
    searches++;
    return found;
  }
}

/// Binding the phone to the computer with nobody typing an address (2026-11-14).
void main() {
  test('a working address is kept: no search, no disruption', () async {
    final discovery = _ScriptedDiscovery(
      healthy: <String>{'http://10.0.0.5:8077'},
    );
    final state = buildTestState(
      FakeApi(),
      policy: const PlatformPolicy.setupApp(),
      discovery: discovery,
    )..api.retarget('http://10.0.0.5:8077');

    expect(await state.autoBind(), isTrue);
    expect(
      discovery.searches,
      0,
      reason: 'a working address must not be hunted',
    );
    expect(state.pairing, PairingState.bound);
    expect(state.api.baseUrl, 'http://10.0.0.5:8077');
  });

  test('a phone with no address finds the computer and adopts it', () async {
    final discovery = _ScriptedDiscovery(
      found: const DiscoveredBackend(
        baseUrl: 'http://192.168.43.57:8077',
        host: '192.168.43.57',
        via: 'beacon',
        hostname: 'DESKTOP-1',
      ),
    );
    final state = buildTestState(
      FakeApi(),
      policy: const PlatformPolicy.setupApp(),
      discovery: discovery,
    );
    state.credentials.save(token: 'old', userId: 1, role: 'senior');

    expect(await state.autoBind(), isTrue);
    expect(discovery.searches, 1);
    expect(state.pairing, PairingState.bound);
    expect(state.api.baseUrl, 'http://192.168.43.57:8077');
    // A token issued by the old address would only produce 401s.
    expect(state.credentials.isSignedIn, isFalse);
    expect(state.pairedBackend?.hostname, 'DESKTOP-1');
    expect(state.addressChosenHere, isTrue);
  });

  test('nothing on the network is reported, not crashed', () async {
    final discovery = _ScriptedDiscovery();
    final state = buildTestState(
      FakeApi(),
      policy: const PlatformPolicy.setupApp(),
      discovery: discovery,
    );
    final before = state.api.baseUrl;

    expect(await state.autoBind(), isFalse);
    expect(state.pairing, PairingState.notFound);
    // The manual address is untouched: the family can still type one.
    expect(state.api.baseUrl, before);
  });

  test('the Windows appliance never searches, and points at loopback', () async {
    final discovery = _ScriptedDiscovery(
      healthy: <String>{'http://127.0.0.1:8077'},
      found: const DiscoveredBackend(
        baseUrl: 'http://192.168.43.57:8077',
        host: '192.168.43.57',
        via: 'beacon',
      ),
    );
    final state = buildTestState(FakeApi(), discovery: discovery)
      ..api.retarget('http://192.168.43.57:8077');

    expect(await state.autoBind(), isTrue);
    expect(discovery.searches, 0, reason: 'the appliance IS the backend');
    // Whatever was in the address file, the appliance talks to its own backend.
    expect(state.api.baseUrl, contains('127.0.0.1'));
  });
}
