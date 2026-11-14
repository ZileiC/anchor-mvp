import 'dart:async';

import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/platform_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class DelayedApi extends FakeApi {
  Completer<ConversationSession>? opening;
  Completer<HealthInfo>? reconnecting;
  Completer<DigestList>? checkingDigest;
  int healthCalls = 0;

  @override
  Future<ConversationSession> openSession({
    String origin = 'voluntary',
    String? deviceId,
  }) {
    return opening?.future ??
        super.openSession(origin: origin, deviceId: deviceId);
  }

  @override
  Future<HealthInfo> health() async {
    healthCalls++;
    return await reconnecting!.future;
  }

  @override
  Future<DigestList> digests() => checkingDigest?.future ?? super.digests();

  @override
  Future<List<AppNotification>> notifications() async => [];
}

void main() {
  const size = Size(390, 844);
  final micButton = find.byKey(const Key('talk-mic'));
  final send = find.byKey(const Key('talk-send'));
  final textField = find.byKey(const Key('talk-text-field'));
  final refresh = find.byKey(const Key('refresh-digests'));

  testWidgets(
    'Talk names startup and the pending reply and leaves Stop usable',
    (tester) async {
      final api = DelayedApi();
      final state = buildTestState(api);
      await pumpSignedIn(tester, state, size: size, textScale: 1.3);
      api.opening = Completer<ConversationSession>();
      await tester.tap(find.byKey(const Key('primary-talk')));
      await settle(tester);
      expect(find.text(L.zh.talkStarting), findsOneWidget);
      expect(tester.widget<FilledButton>(micButton).onPressed, isNull);
      expect(tester.widget<IconButton>(send).onPressed, isNull);

      api.opening!.complete(
        const ConversationSession(
          sessionId: 'ready',
          state: 'active',
          micOn: true,
        ),
      );
      await settle(tester);
      expect(find.text(L.zh.talkStarting), findsNothing);
      api.pendingTurn = Completer<TurnResult>();
      await tester.enterText(textField, '测试一句话');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();
      expect(find.text(L.zh.talkWaiting), findsOneWidget);
      expect(tester.widget<FilledButton>(micButton).onPressed, isNull);
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(api.turnCalls, 1);

      await tester.tap(find.byKey(const Key('stop-control')));
      api.pendingTurn!.complete(
        const TurnResult(
          transcript: '测试一句话',
          replyText: '迟到的回复',
          intent: 'chat',
          stopped: false,
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('talk-stopped-panel')), findsOneWidget);
      expect(find.text(L.zh.talkWaiting), findsNothing);
      expect(find.text('迟到的回复'), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeApp(tester);
    },
  );

  testWidgets('Talk Retry checks the backend and keeps the typed draft', (
    tester,
  ) async {
    final api = DelayedApi();
    final state = buildTestState(api);
    await pumpSignedIn(tester, state, size: size);
    api.offline = true;
    await state.refresh();
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    await tester.enterText(textField, '留在这里的一句话');
    expect(tester.widget<IconButton>(send).onPressed, isNull);

    for (final reachable in [false, true]) {
      api.reconnecting = Completer<HealthInfo>();
      await tester.ensureVisible(find.text(L.zh.retry));
      await tester.tap(find.text(L.zh.retry));
      await tester.pump();
      expect(find.text(L.zh.talkReconnecting), findsWidgets);
      if (reachable) {
        api.offline = false;
        api.reconnecting!.complete(
          const HealthInfo(status: 'ok', version: '1', offlineCapabilities: []),
        );
      } else {
        api.reconnecting!.completeError(api.offlineError);
      }
      await settle(tester);
      expect(find.text('留在这里的一句话'), findsOneWidget);
      expect(state.offline, !reachable);
    }
    expect(api.healthCalls, 2);
    expect(api.openSessionCalls, 1);
    expect(api.turnCalls, 0);
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await settle(tester);
    expect(api.lastTurnText, '留在这里的一句话');
    await disposeApp(tester);
  });

  testWidgets('a failed mic start and an empty clip both offer typing', (
    tester,
  ) async {
    final api = FakeApi();
    api.providerStatusValue = const ProviderStatus(
      llm: ProviderSectionStatus.unknown,
      asr: ProviderSectionStatus(
        configured: true,
        mode: 'offline',
        engine: 'windows-sapi',
      ),
    );
    final mic = FakeMicrophoneInput()..failStartWith = 'permission denied';
    final state = buildTestState(api, microphone: mic);
    await pumpSignedIn(tester, state, size: size, textScale: 1.3);
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    await tester.tap(micButton);
    await settle(tester);
    expect(find.text(L.zh.micUnavailable), findsOneWidget);
    final retry = find.text(L.zh.retryMicrophone);
    final typeInstead = find.byKey(const Key('talk-capture-type-instead'));
    expect(typeInstead, findsOneWidget);

    mic.failStartWith = null;
    mic.captured = null;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await settle(tester);
    expect(state.recording, isTrue);
    await tester.tap(micButton);
    await settle(tester);
    expect(find.text(L.zh.micNoAudio), findsOneWidget);
    expect(api.turnCalls, 0);
    await tester.ensureVisible(typeInstead);
    await tester.tap(typeInstead);
    await settle(tester);
    expect(tester.widget<TextField>(textField).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets(
    'Android hides cached highlights while checking and recovers on Retry',
    (tester) async {
      final api = DelayedApi()..asCaregiver();
      api.digestList = const DigestList([
        Digest(
          id: 1,
          status: 'delivered',
          items: [
            DigestItem(topic: 'mood', text: '之前分享的内容', evidenceIds: [1]),
          ],
        ),
      ]);
      final state = buildTestState(
        api,
        policy: const PlatformPolicy.setupApp(),
      );
      await pumpSignedIn(tester, state, caregiver: true, size: size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      final digestRow = find.byKey(const Key('setup-digest'));
      await tester.ensureVisible(digestRow);
      await tester.tap(digestRow);
      await settle(tester);
      expect(find.text('之前分享的内容'), findsOneWidget);

      api.checkingDigest = Completer<DigestList>();
      await tester.tap(refresh);
      await tester.pump();
      expect(find.byKey(const Key('digest-checking')), findsOneWidget);
      expect(find.text('之前分享的内容'), findsNothing);
      api.checkingDigest!.completeError(api.offlineError);
      await settle(tester);
      expect(find.text('暂时连不上电脑'), findsOneWidget);
      expect(find.text('之前分享的内容'), findsNothing);

      api.checkingDigest = Completer<DigestList>();
      await tester.ensureVisible(find.text(L.zh.retry));
      await tester.tap(find.text(L.zh.retry));
      await tester.pump();
      expect(find.byKey(const Key('digest-checking')), findsOneWidget);
      api.checkingDigest!.complete(
        const DigestList([Digest(id: 1, status: 'delivered')]),
      );
      await settle(tester);
      expect(state.offline, isFalse);
      expect(find.text('暂时连不上电脑'), findsNothing);
      expect(find.text(L.zh.caregiverInsufficient), findsOneWidget);
      expect(find.text('之前分享的内容'), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeApp(tester);
    },
  );
}
