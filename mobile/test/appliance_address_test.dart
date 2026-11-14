import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/services/backend_address_store.dart';
import 'package:anchor_app/services/backend_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Two defects from 2026-11-14, both of which produced "the computer cannot reach
/// its own backend":
///
/// 1. the appliance read the phone's saved address file, so a LAN address left
///    there made the desktop app dial a machine that was not itself;
/// 2. a widget test discovered an address and (through the real store) wrote it
///    into the machine's live `%LOCALAPPDATA%` file.
///
/// The fix is pinned here: the appliance always uses its compiled-in loopback,
/// and a test's store is in memory only.
class _CountingDiscovery extends BackendDiscovery {
  _CountingDiscovery({this.found, this.healthy = true});

  final DiscoveredBackend? found;

  /// Whether the current address already answers (a phone that is bound).
  final bool healthy;
  int searches = 0;

  @override
  Future<bool> healthOf(String baseUrl) async => healthy;

  @override
  Future<DiscoveredBackend?> discover({
    Duration budget = const Duration(seconds: 6),
    Future<bool> Function(String baseUrl)? verify,
  }) async {
    searches++;
    return found;
  }
}

void main() {
  test(
    'the appliance ignores a stored LAN address and uses loopback',
    () async {
      final discovery = _CountingDiscovery();
      final store = InMemoryAddressStore('http://192.168.43.57:8077');
      final state = buildTestState(
        FakeApi(),
        discovery: discovery,
        addressStore: store,
      )..api.retarget('http://192.168.43.57:8077');

      expect(await state.autoBind(), isTrue);
      expect(state.api.baseUrl, contains('127.0.0.1'));
      expect(discovery.searches, 0, reason: 'the appliance never searches');
      expect(store.saves, 0, reason: 'nothing is written on the appliance');
    },
  );

  test(
    'the appliance does not report success when its backend is down',
    () async {
      final state = buildTestState(
        FakeApi(),
        discovery: _DownDiscovery(),
        addressStore: InMemoryAddressStore(),
      );

      expect(await state.autoBind(), isFalse);
      // The address is still repaired: the next retry has a working target.
      expect(state.api.baseUrl, contains('127.0.0.1'));
    },
  );

  test('the phone writes to its own store, never the machine file', () async {
    final store = InMemoryAddressStore();
    final state = buildTestState(
      FakeApi(),
      policy: const PlatformPolicy.setupApp(),
      discovery: _CountingDiscovery(
        healthy: false, // nothing answers yet: this phone must search
        found: const DiscoveredBackend(
          baseUrl: 'http://192.168.43.57:8077',
          host: '192.168.43.57',
          via: 'beacon',
        ),
      ),
      addressStore: store,
    );

    expect(await state.autoBind(), isTrue);
    expect(store.saves, 1);
    expect(store.hasSaved, isTrue);
  });
}

class _DownDiscovery extends BackendDiscovery {
  const _DownDiscovery();

  @override
  Future<bool> healthOf(String baseUrl) async => false;

  @override
  Future<DiscoveredBackend?> discover({
    Duration budget = const Duration(seconds: 6),
    Future<bool> Function(String baseUrl)? verify,
  }) async => null;
}
