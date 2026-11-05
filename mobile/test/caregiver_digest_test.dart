import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/screens/caregiver/digest_screen.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Caregiver digest contract (SPEC §6.6, S10/S11): at most three highlights —
/// a maximum, not a quota — and a single call-to-check-in action.
void main() {
  late FakeApi api;
  late AppState state;

  Digest approvedDigest({int itemCount = 3}) => Digest(
    id: 1,
    status: 'approved',
    periodStart: '2026-03-02',
    periodEnd: '2026-03-09',
    items: <DigestItem>[
      for (var index = 0; index < itemCount; index++)
        DigestItem(
          topic: ShareTopics.all[index % ShareTopics.all.length],
          text: '第${index + 1}条：这周提到的小事。',
          evidenceIds: <int>[index + 1],
        ),
    ],
  );

  setUp(() {
    api = FakeApi()..asCaregiver();
    api.contactList = <Contact>[
      const Contact(id: 1, label: '林秀兰', phone: '13900000000'),
    ];
    state = buildTestState(api);
  });

  testWidgets('three highlights render with a call to check in', (
    tester,
  ) async {
    api.digestList = DigestList(<Digest>[approvedDigest()]);
    await pumpSignedIn(
      tester,
      state,
      caregiver: true,
      size: const Size(390, 844),
    );

    await tester.tap(find.byKey(const Key('caregiver-digest')));
    await settle(tester);

    expect(find.byType(DigestScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('highlight-0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('highlight-2')), findsOneWidget);
    expect(find.byKey(const Key('caregiver-call-checkin')), findsOneWidget);
    expect(find.textContaining('第3条'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a payload with more than three items is capped at three', (
    tester,
  ) async {
    api.digestList = DigestList(<Digest>[approvedDigest(itemCount: 5)]);
    await pumpSignedIn(
      tester,
      state,
      caregiver: true,
      size: const Size(390, 844),
    );

    await tester.tap(find.byKey(const Key('caregiver-digest')));
    await settle(tester);

    expect(find.byKey(const ValueKey<String>('highlight-2')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('highlight-3')), findsNothing);
    expect(find.textContaining('第4条'), findsNothing);
    expect(find.textContaining('第5条'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('the call action asks for confirmation before dialling', (
    tester,
  ) async {
    api.digestList = DigestList(<Digest>[approvedDigest()]);
    final dialer = FakeDialer();
    state = buildTestState(api, dialer: dialer);
    await pumpSignedIn(
      tester,
      state,
      caregiver: true,
      size: const Size(390, 844),
    );

    await tester.tap(find.byKey(const Key('caregiver-digest')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('caregiver-call-checkin')));
    await tester.tap(find.byKey(const Key('caregiver-call-checkin')));
    await settle(tester);

    expect(find.byKey(const Key('confirm-dial-yes')), findsOneWidget);
    expect(find.byKey(const Key('confirm-dial-number')), findsOneWidget);
    expect(dialer.dialled, isEmpty);

    await tester.tap(find.byKey(const Key('confirm-dial-yes')));
    await settle(tester);
    expect(dialer.dialled, <String>['13900000000']);

    await disposeApp(tester);
  });

  testWidgets('insufficient data shows the honest message, not filler', (
    tester,
  ) async {
    api.digestList = DigestList(<Digest>[
      const Digest(id: 2, status: 'insufficient_data'),
    ]);
    await pumpSignedIn(
      tester,
      state,
      caregiver: true,
      size: const Size(390, 844),
    );

    await tester.tap(find.byKey(const Key('caregiver-digest')));
    await settle(tester);

    expect(find.textContaining('还不够'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('highlight-0')), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('an insufficient-information note is shown honestly', (
    tester,
  ) async {
    api.digestList = const DigestList(
      <Digest>[],
      note: 'insufficient_information',
    );
    await pumpSignedIn(
      tester,
      state,
      caregiver: true,
      size: const Size(390, 844),
    );

    await tester.tap(find.byKey(const Key('caregiver-digest')));
    await settle(tester);

    expect(find.textContaining('还不够'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a missing digest endpoint degrades to a friendly note', (
    tester,
  ) async {
    api.digestMissing = true;
    await pumpSignedIn(
      tester,
      state,
      caregiver: true,
      size: const Size(390, 844),
    );

    expect(state.digestFeatureMissing, isTrue);

    await tester.tap(find.byKey(const Key('caregiver-digest')));
    await settle(tester);

    expect(find.byType(DigestScreen), findsOneWidget);
    expect(find.textContaining('还没接通'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });
}
