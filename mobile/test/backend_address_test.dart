import 'package:anchor_app/app.dart';
import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The phone's backend address is a runtime choice (2026-11-12).
///
/// It used to be compiled in with `--dart-define`, which tied the APK to one
/// network: the computer's LAN address moves with the Wi-Fi, so the app went
/// offline every time it moved. These tests pin the two halves of the fix: the
/// client can be repointed, and the login screen is where the family does it.
void main() {
  group('ApiClient.retarget', () {
    test('accepts an http(s) address and drops the trailing slash', () {
      final api = ApiClient(baseUrl: 'http://127.0.0.1:8077');

      expect(api.retarget('http://10.206.99.14:8077/'), isTrue);
      expect(api.baseUrl, 'http://10.206.99.14:8077');

      expect(api.retarget('https://example.test/anchor'), isTrue);
      expect(api.baseUrl, 'https://example.test/anchor');
    });

    test('refuses anything that is not an http(s) origin', () {
      final api = ApiClient(baseUrl: 'http://127.0.0.1:8077');

      for (final bad in <String>[
        '',
        '   ',
        'not an address',
        'ftp://x',
        '10.0.0.5:8077',
      ]) {
        expect(api.retarget(bad), isFalse, reason: bad);
        // A refused value leaves the working address alone.
        expect(api.baseUrl, 'http://127.0.0.1:8077');
      }
    });
  });

  testWidgets('the phone can retype the address and it takes effect at once', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(780, 1688);
    addTearDown(tester.view.reset);

    final api = FakeApi()..asCaregiver();
    final state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    // A session exists before the change, so we can prove it is dropped.
    state.credentials.save(token: 'old', userId: 2, role: 'caregiver');

    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);

    final button = find.byKey(const Key('backend-change'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);

    await tester.enterText(
      find.byKey(const Key('backend-address-field')),
      'http://10.206.99.14:8077',
    );
    await tester.tap(find.byKey(const Key('backend-address-save')));
    await settle(tester);

    // The client the whole app shares now points at the computer, and the token
    // issued by the old backend is gone (it would only produce 401s). The
    // SnackBar itself is not asserted on: settle() advances eight seconds, which
    // is exactly how long it lives.
    expect(state.api.baseUrl, 'http://10.206.99.14:8077');
    expect(state.credentials.isSignedIn, isFalse);
    expect(find.textContaining('10.206.99.14'), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('a refused address is reported and changes nothing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(780, 1688);
    addTearDown(tester.view.reset);

    final api = FakeApi()..asCaregiver();
    final state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    final before = state.api.baseUrl;

    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);

    await tester.ensureVisible(find.byKey(const Key('backend-change')));
    await tester.tap(find.byKey(const Key('backend-change')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('backend-address-field')),
      'my laptop',
    );
    await tester.tap(find.byKey(const Key('backend-address-save')));
    await settle(tester);

    expect(state.api.baseUrl, before);
    // (No snackbar assertion: settle() advances the eight seconds it lives.)

    await disposeApp(tester);
  });

  testWidgets('the Windows appliance has no address control at all', (
    tester,
  ) async {
    final state = buildTestState(FakeApi());
    await tester.pumpWidget(AnchorApp(state: state));
    await settle(tester);

    expect(find.byKey(const Key('backend-change')), findsNothing);

    await disposeApp(tester);
  });
}
