import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/platform_policy.dart';
import 'package:anchor_app/screens/senior/choices_screen.dart';
import 'package:anchor_app/screens/caregiver/digest_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class ReportApi extends FakeApi {
  int generated = 0;
  int published = 0;
  int reads = 0;
  @override
  Future<Digest> generateDigest() async {
    generated++;
    const result = Digest(
      id: 42,
      status: 'draft',
      periodStart: '2026-11-02',
      periodEnd: '2026-11-09',
      items: [
        DigestItem(
          topic: 'activities',
          text: 'Three days of gardening.',
          evidenceIds: [1],
        ),
      ],
    );
    digestList = const DigestList([result]);
    return result;
  }

  @override
  Future<Digest> publishDigest(int id) async {
    published++;
    return Digest(
      id: id,
      status: 'delivered',
      items: digestList.digests.first.items,
    );
  }

  @override
  Future<DigestList> digests() async {
    reads++;
    return super.digests();
  }
}

void main() {
  testWidgets('senior opens personal controls without provider configuration', (
    tester,
  ) async {
    final api = ReportApi();
    final state = buildTestState(api);
    await pumpSignedIn(
      tester,
      state,
      size: const Size(390, 844),
      textScale: 1.3,
    );
    await tester.ensureVisible(find.byKey(const Key('primary-choices')));
    await tester.tap(find.byKey(const Key('primary-choices')));
    await settle(tester);
    expect(find.byType(ChoicesScreen), findsOneWidget);
    expect(find.byKey(const Key('ai-llm-key')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('choice-cloud_processing-')));
    await settle(tester);
    expect(state.consent.cloudProcessing, isTrue);
    await disposeApp(tester);
  });

  testWidgets(
    'draft requires explicit confirmation and sharing can be stopped',
    (tester) async {
      final api = ReportApi();
      final state = buildTestState(api);
      await pumpSignedIn(tester, state, size: const Size(1100, 900));
      await tester.tap(find.byKey(const Key('primary-choices')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('generate-digest')));
      await tester.tap(find.byKey(const Key('generate-digest')));
      await settle(tester);
      expect(api.generated, 1);
      expect(api.published, 0);
      await tester.ensureVisible(
        find.byKey(const ValueKey('publish-digest-42')),
      );
      await tester.tap(find.byKey(const ValueKey('publish-digest-42')));
      await settle(tester);
      expect(api.published, 0);
      await tester.tap(find.widgetWithText(FilledButton, state.l.ok));
      await settle(tester);
      expect(api.published, 1);
      expect(state.digests.single.status, 'delivered');
      await tester.ensureVisible(find.byKey(const Key('stop-all-sharing')));
      await tester.tap(find.byKey(const Key('stop-all-sharing')));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, state.l.ok));
      await settle(tester);
      expect(state.consent.anySharing, isFalse);
      await disposeApp(tester);
    },
  );

  testWidgets('family refresh removes revoked cached highlights', (
    tester,
  ) async {
    final api = ReportApi()..asCaregiver();
    final state = buildTestState(api, policy: const PlatformPolicy.setupApp());
    api.digestList = const DigestList([
      Digest(
        id: 1,
        status: 'delivered',
        items: [DigestItem(topic: 'mood', text: 'Private highlight')],
      ),
    ]);
    await pumpSignedIn(
      tester,
      state,
      caregiver: true,
      size: const Size(390, 844),
    );
    await tester.ensureVisible(find.byKey(const Key('setup-digest')));
    await tester.tap(find.byKey(const Key('setup-digest')));
    await settle(tester);
    expect(find.byType(DigestScreen), findsOneWidget);
    expect(find.text('Private highlight'), findsOneWidget);
    api.digestList = const DigestList([Digest(id: 1, status: 'delivered')]);
    final before = api.reads;
    await tester.tap(find.byKey(const Key('refresh-digests')));
    await settle(tester);
    expect(api.reads, greaterThan(before));
    expect(find.text('Private highlight'), findsNothing);
    await disposeApp(tester);
  });
}
