import 'dart:async';

import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/screens/senior/talk_screen.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Stop cancels instantly and a reply that is still in flight can never re-open
/// the conversation (SPEC §9, failure_stop_late_output).
void main() {
  late FakeApi api;
  late AppState state;

  setUp(() {
    api = FakeApi()..feed = threeActivityFeed();
    state = buildTestState(api);
  });

  testWidgets('a late reply is discarded after Stop and nothing is replayed', (
    tester,
  ) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    expect(find.byType(TalkScreen), findsOneWidget);
    expect(state.session, isNotNull);

    // A turn that has not answered yet.
    api.pendingTurn = Completer<TurnResult>();
    await tester.enterText(find.byKey(const Key('talk-text-field')), '你好');
    await tester.ensureVisible(find.byKey(const Key('talk-send')));
    await tester.tap(find.byKey(const Key('talk-send')));
    await tester.pump();
    expect(state.sendingTurn, isTrue);

    await tester.tap(find.byKey(const Key('stop-control')));
    await settle(tester);

    // The UI switched immediately: no session, no captions, calm panel.
    expect(state.session, isNull);
    expect(state.captions, isEmpty);
    expect(find.byKey(const Key('talk-stopped-panel')), findsOneWidget);
    expect(api.stoppedSessions, contains('session-1'));

    // The model finally answers — it must be dropped, not rendered.
    api.pendingTurn!.complete(
      const TurnResult(
        transcript: '你好',
        replyText: '这是一句迟到的回答',
        intent: 'chat',
        stopped: false,
      ),
    );
    await settle(tester);

    expect(find.text('这是一句迟到的回答'), findsNothing);
    expect(state.captions, isEmpty);
    expect(state.lastTurn, isNull);

    await disposeApp(tester);
  });

  testWidgets('a normal turn shows captions and speaks the reply', (
    tester,
  ) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);

    await tester.enterText(find.byKey(const Key('talk-text-field')), '今天天气好');
    await tester.ensureVisible(find.byKey(const Key('talk-send')));
    await tester.tap(find.byKey(const Key('talk-send')));
    await settle(tester);

    expect(find.text('好的，我在听。'), findsOneWidget);
    expect(state.captions, hasLength(2));
    final speaker = state.speaker as SilentSpeaker;
    expect(speaker.spoken, contains('好的，我在听。'));
    expect(state.lastAnchorText, '好的，我在听。');

    // Repeat replays the reply of the current turn.
    await tester.ensureVisible(find.byKey(const Key('talk-repeat')));
    await tester.tap(find.byKey(const Key('talk-repeat')));
    await settle(tester);
    expect(speaker.spoken.last, '好的，我在听。');
    expect(speaker.spoken, hasLength(2));

    await disposeApp(tester);
  });

  testWidgets('Repeat shows the empty message before anything is said', (
    tester,
  ) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    expect(find.byType(TalkScreen), findsOneWidget);
    expect(find.text(L.zh.repeatNothing), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('talk-repeat')));
    await tester.tap(find.byKey(const Key('talk-repeat')));
    await settle(tester);

    expect(find.text(L.zh.repeatNothing), findsOneWidget);
    expect((state.speaker as SilentSpeaker).spoken, isEmpty);

    await disposeApp(tester);
  });

  test('Repeat does nothing while nothing has been said', () async {
    final api = FakeApi();
    final state = buildTestState(api);

    final result = await state.repeatLastReply();

    expect(result, isNull);
    expect((state.speaker as SilentSpeaker).spoken, isEmpty);
    state.dispose();
  });

  test('a server reply wins over the remembered greeting', () async {
    final api = FakeApi();
    final state = buildTestState(api);
    state.adoptProactiveSession(
      const ConversationSession(
        sessionId: 'session-proactive',
        state: 'active',
        micOn: true,
        greetingText: '早上好。今天想聊点什么？',
      ),
    );

    await state.sendText('你好');
    final speaker = state.speaker as SilentSpeaker;
    expect(speaker.spoken.single, '好的，我在听。');

    await state.repeatLastReply();

    expect(speaker.spoken.last, '好的，我在听。');
    expect(speaker.spoken, hasLength(2));
    expect(state.lastAnchorText, '好的，我在听。');
    state.dispose();
  });

  testWidgets('Stop is present on the conversation screen', (tester) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
    expect(find.byKey(const Key('stop-control')), findsOneWidget);
    await disposeApp(tester);
  });

  test('the request nonce invalidates an in-flight request', () {
    final ticket = api.nonce.value;
    api.nonce.bump();
    expect(api.nonce.isCurrent(ticket), isFalse);
  });
}
