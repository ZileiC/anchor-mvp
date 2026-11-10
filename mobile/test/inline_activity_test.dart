import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:anchor_app/state/inline_activity.dart';
import 'package:anchor_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The activity card inside the conversation (product decision 2026-11-10):
/// Play is no longer a separate world. A chat turn may carry one card, it is
/// rendered in the caption stream with per-kind identity, one tap grades it in
/// place, and the answer becomes an ordinary chat turn.
void main() {
  const trivia = ActivityItem(
    id: 'trivia-1',
    type: 'trivia',
    title: '一年有几个月',
    prompt: '一年有多少个月呀？',
    minutes: 3,
    options: <String>['10', '11', '12'],
    answerIndex: 2,
    explanation: '一年有十二个月。',
    wrongHint: '再数一数日历上的月份。',
  );

  const memory = ActivityItem(
    id: 'memory-1',
    type: 'memory',
    title: '记一记',
    prompt: '记住这三样：茶杯、钥匙、毛巾。',
    minutes: 3,
    options: <String>['茶杯', '钥匙', '毛巾'],
    replies: <String>['茶杯在桌上。', '钥匙在门口的小盘子里。', '毛巾在柜子里。'],
  );

  const story = ActivityItem(
    id: 'story-1',
    type: 'story',
    title: '一个小故事',
    prompt: '小时候的院子里，你最喜欢做什么？',
    minutes: 3,
    story: '小时候的院子有一棵枣树。夏天你常在树下坐着。',
    options: <String>['在树下乘凉', '在门口等信'],
    answerIndex: 0,
    explanation: '在树下乘凉，是很安静的夏天。',
  );

  const intro = '对了，我这儿有个小问题想问问你——';

  TurnActivity offered(ActivityItem item, {String bridge = intro}) =>
      TurnActivity(activityId: item.id, intro: bridge, item: item);

  SilentSpeaker speakerOf(AppState state) => state.speaker as SilentSpeaker;

  Future<void> openTalk(WidgetTester tester, AppState state) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);
  }

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('talk-text-field')), text);
    await tester.ensureVisible(find.byKey(const Key('talk-send')));
    await tester.tap(find.byKey(const Key('talk-send')));
    await settle(tester);
  }

  Future<void> tapOption(WidgetTester tester, int index) async {
    final finder = find.byKey(Key('inline-activity-option-$index'));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Color? feedbackFill(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.byKey(const Key('inline-activity-feedback')),
    );
    return (box.decoration! as BoxDecoration).color;
  }

  testWidgets('a turn that offers an activity renders the card in the stream', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await openTalk(tester, state);

    api
      ..replyText = '好呀，早上吃了什么？\n$intro'
      ..nextTurnActivity = offered(trivia);
    await say(tester, '今天早上吃了面条');

    // The assistant's own sentence bridges into the card; the question itself
    // is only in the card, never written into the chat sentence.
    expect(find.text('好呀，早上吃了什么？\n$intro'), findsOneWidget);
    expect(find.text(trivia.prompt), findsOneWidget);

    // The card is part of the chat: no separate screen, no route change.
    expect(find.byKey(const Key('inline-activity-card')), findsOneWidget);
    expect(find.byKey(const Key('inline-activity-hero')), findsOneWidget);
    expect(find.byKey(const Key('inline-activity-hero-strip')), findsOneWidget);
    expect(find.text(trivia.title), findsOneWidget);
    expect(find.text(L.zh.activityTrivia), findsOneWidget);
    expect(find.text(L.zh.activityChoose), findsOneWidget);

    // Generous type on the thing the senior must read.
    final prompt = tester.widget<Text>(
      find.byKey(const Key('inline-activity-prompt')),
    );
    expect(prompt.style?.fontSize, AnchorTheme.baseTextSize);

    // Three kind dots for the app's small activity set — never a score.
    expect(find.byKey(const Key('inline-activity-dots')), findsOneWidget);
    expect(find.textContaining('分'), findsNothing);
    expect(find.byIcon(Icons.timer_outlined), findsNothing);

    // Every option is a big, labelled button.
    for (var index = 0; index < trivia.options.length; index++) {
      expect(find.byKey(Key('inline-activity-option-$index')), findsOneWidget);
    }

    await disposeApp(tester);
  });

  testWidgets('a story card reads its story before its question', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await openTalk(tester, state);

    api.nextTurnActivity = offered(story, bridge: '对了，我这儿有个小故事——');
    await say(tester, '今天天气不错');

    expect(find.byKey(const Key('inline-activity-story')), findsOneWidget);
    expect(find.text(story.story!), findsOneWidget);
    expect(find.text(L.zh.activityStory), findsOneWidget);
    expect(find.text(L.zh.activityListen), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets(
    'a correct pick collapses the card, grades it green and posts the '
    'answer as a chat turn',
    (tester) async {
      final api = FakeApi();
      final state = buildTestState(api);
      await openTalk(tester, state);

      api.nextTurnActivity = offered(trivia);
      await say(tester, '今天天气好');
      expect(api.turnCalls, 1);

      await tapOption(tester, 2);

      // Collapsed in place: the options are gone, one short line remains.
      expect(find.byKey(const Key('inline-activity-card')), findsOneWidget);
      expect(find.byKey(const Key('inline-activity-option-2')), findsNothing);
      expect(find.text('你选了：12'), findsOneWidget);
      expect(find.byKey(const Key('inline-activity-feedback')), findsOneWidget);
      expect(feedbackFill(tester), AnchorTheme.correctFill);
      expect(find.textContaining('一年有十二个月。'), findsOneWidget);

      // The result went through the existing activity-session endpoint.
      expect(api.activitySessions, hasLength(1));
      expect(api.activitySessions.single.id, 'trivia-1');
      expect(api.activitySessions.single.completed, isTrue);
      expect(api.activitySessions.single.seconds, greaterThanOrEqualTo(0));

      // The choice became an ordinary turn, and the model answered it.
      expect(api.turnCalls, 2);
      expect(api.lastTurnText, '我选了：12');
      expect(find.text('我选了：12'), findsOneWidget);

      // The graded sentence is spoken after the conversational reply.
      final spoken = speakerOf(state).spoken;
      expect(spoken.last, '${L.zh.activityCorrect}\n一年有十二个月。');

      await disposeApp(tester);
    },
  );

  testWidgets('a wrong pick is gentle, amber, and shows the right answer', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await openTalk(tester, state);

    api.nextTurnActivity = offered(trivia);
    await say(tester, '今天天气好');
    await tapOption(tester, 0);

    expect(find.text('你选了：10'), findsOneWidget);
    expect(feedbackFill(tester), AnchorTheme.wrongFill);
    expect(find.textContaining(trivia.wrongHint!), findsOneWidget);
    expect(find.textContaining('对的是：12'), findsOneWidget);
    expect(api.activitySessions.single.completed, isTrue);

    await disposeApp(tester);
  });

  testWidgets('a memory card gets a warm reply, never a verdict', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await openTalk(tester, state);

    api.nextTurnActivity = offered(memory, bridge: '对了，我这儿有件小事——');
    await say(tester, '今天天气好');
    await tapOption(tester, 1);

    expect(find.text('你选了：钥匙'), findsOneWidget);
    expect(feedbackFill(tester), AnchorTheme.openFill);
    expect(find.textContaining(L.zh.activityThanks), findsOneWidget);
    expect(find.textContaining('钥匙在门口的小盘子里。'), findsOneWidget);
    expect(find.textContaining(L.zh.activityWrong), findsNothing);
    expect(find.textContaining(L.zh.activityCorrect), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('a card belongs to its turn: the answer keeps it, the next turn '
      'ends it', (tester) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await openTalk(tester, state);

    api.nextTurnActivity = offered(trivia);
    await say(tester, '今天天气好');
    expect(find.byKey(const Key('inline-activity-card')), findsOneWidget);

    await tapOption(tester, 2);
    expect(find.byKey(const Key('inline-activity-chosen')), findsOneWidget);

    // The fake consumes the offer, like the backend: this turn has no card.
    await say(tester, '再聊点别的');
    expect(find.byKey(const Key('inline-activity-card')), findsNothing);
    // The record stays in the conversation as captions.
    expect(find.text('我选了：12'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a second answer can never be recorded or posted twice', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await openTalk(tester, state);

    api.nextTurnActivity = offered(trivia);
    await say(tester, '今天天气好');
    await tapOption(tester, 2);
    expect(api.turnCalls, 2);
    expect(api.activitySessions, hasLength(1));

    // The card is locked, and the state refuses an out-of-band second answer.
    await state.answerInlineActivity(0);
    expect(api.turnCalls, 2);
    expect(api.activitySessions, hasLength(1));
    expect(find.text('你选了：12'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('Stop removes the card with the conversation', (tester) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await openTalk(tester, state);

    api.nextTurnActivity = offered(trivia);
    await say(tester, '今天天气好');
    expect(find.byKey(const Key('inline-activity-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stop-control')));
    await settle(tester);

    expect(find.byKey(const Key('inline-activity-card')), findsNothing);
    expect(state.inlineActivity, isNull);

    await disposeApp(tester);
  });

  test(
    'answering records the activity and posts the choice as a turn',
    () async {
      final api = FakeApi();
      final state = buildTestState(api);
      await state.startConversation();
      api.nextTurnActivity = offered(trivia);
      await state.sendText('你好');

      expect(state.inlineActivity, isNotNull);
      await state.answerInlineActivity(2);

      expect(state.inlineActivity!.answered, isTrue);
      expect(api.activitySessions, hasLength(1));
      expect(api.activitySessions.single.id, 'trivia-1');
      expect(api.turnCalls, 2);
      expect(api.lastTurnText, '我选了：12');
      state.dispose();
    },
  );

  testWidgets('the card survives large text without overflowing', (
    tester,
  ) async {
    final api = FakeApi();
    final state = buildTestState(api);
    await pumpSignedIn(
      tester,
      state,
      size: const Size(390, 844),
      textScale: 1.3,
    );
    await tester.tap(find.byKey(const Key('primary-talk')));
    await settle(tester);

    api.nextTurnActivity = offered(trivia);
    await say(tester, '今天天气好');
    expect(find.byKey(const Key('inline-activity-card')), findsOneWidget);

    await tapOption(tester, 2);
    expect(find.byKey(const Key('inline-activity-chosen')), findsOneWidget);
    expect(find.byKey(const Key('inline-activity-feedback')), findsOneWidget);

    await disposeApp(tester);
  });

  test('the measured duration is clamped and never negative', () {
    final start = DateTime.utc(2026, 3, 10, 1, 30);
    final activity = InlineActivity(offer: offered(trivia), offeredAt: start);

    expect(activity.durationSeconds(start), 0);
    expect(
      activity.durationSeconds(start.subtract(const Duration(seconds: 5))),
      0,
    );
    expect(activity.durationSeconds(start.add(const Duration(seconds: 9))), 9);
    expect(
      activity.durationSeconds(start.add(const Duration(days: 3))),
      InlineActivity.maxReportedSeconds,
    );
    expect(activity.answered, isFalse);
    expect(activity.withAnswer(1).answered, isTrue);
    expect(activity.withAnswer(1).chosenOption, '11');
  });
}
