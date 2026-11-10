import 'package:anchor_app/l10n/strings.dart';
import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/screens/senior/activity_screen.dart';
import 'package:anchor_app/services/tts_service.dart';
import 'package:anchor_app/state/app_state.dart';
import 'package:anchor_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Play's interaction contract: one tap answers, the answer is explained and
/// spoken, further taps are locked, and there is no clock anywhere. The old
/// screen printed the same thank-you line for every choice — these tests pin
/// the behaviour the user asked for instead.
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

  ActivityFeed feedOf(ActivityItem item) =>
      ActivityFeed(items: <ActivityItem>[item], rotation: <String>[item.id]);

  Color? feedbackFill(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.byKey(const Key('activity-feedback')),
    );
    return (box.decoration! as BoxDecoration).color;
  }

  SilentSpeaker speakerOf(AppState state) => state.speaker as SilentSpeaker;

  Future<void> openPlay(WidgetTester tester, AppState state) async {
    await pumpSignedIn(tester, state, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('primary-play')));
    await settle(tester);
  }

  Future<void> tapOption(
    WidgetTester tester,
    int index, {
    bool warnIfMissed = true,
  }) async {
    final finder = find.byKey(Key('activity-option-$index'));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder, warnIfMissed: warnIfMissed);
    await settle(tester);
  }

  group('Play answers', () {
    testWidgets('a correct pick shows the teaching sentence in green, speaks '
        'it once and locks the card', (tester) async {
      final api = FakeApi()..feed = feedOf(trivia);
      final state = buildTestState(api);
      await openPlay(tester, state);

      // The card reads its own title and question when it opens.
      final question = '一年有几个月\n一年有多少个月呀？';
      expect(speakerOf(state).spoken, <String>[question]);

      // No countdown, no urgency text, no timer icon.
      expect(find.byKey(const Key('activity-timer')), findsNothing);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      expect(find.textContaining('还有'), findsNothing);

      await tapOption(tester, 2);

      final sentence = '${L.zh.activityCorrect}\n一年有十二个月。';
      expect(find.text(sentence), findsOneWidget);
      expect(feedbackFill(tester), const Color(0xFFE3EFE6));
      expect(speakerOf(state).spoken, <String>[question, sentence]);

      // The card is answered: another tap changes nothing and says nothing.
      await tapOption(tester, 0, warnIfMissed: false);
      expect(find.text(sentence), findsOneWidget);
      expect(speakerOf(state).spoken, <String>[question, sentence]);

      await disposeApp(tester);
    });

    testWidgets('a wrong pick is gentle and marks the right answer', (
      tester,
    ) async {
      final api = FakeApi()..feed = feedOf(trivia);
      final state = buildTestState(api);
      await openPlay(tester, state);

      final question = '一年有几个月\n一年有多少个月呀？';
      await tapOption(tester, 0);

      final sentence =
          '${L.zh.activityWrong}\n'
          '再数一数日历上的月份。\n'
          '一年有十二个月。\n'
          '${L.zh.activityAnswerWas('12')}';
      expect(find.text(sentence), findsOneWidget);
      expect(feedbackFill(tester), const Color(0xFFF8ECD8));
      // The correct option is visibly marked, the wrong pick is not.
      expect(
        find.descendant(
          of: find.byKey(const Key('activity-option-2')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('activity-option-0')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsNothing,
      );
      // The green fill survives the disabled state (a disabled OutlinedButton
      // would otherwise be repainted by the theme).
      final marked = tester.widget<OutlinedButton>(
        find.byKey(const Key('activity-option-2')),
      );
      expect(
        marked.style?.backgroundColor?.resolve(<WidgetState>{
          WidgetState.disabled,
        }),
        const Color(0xFFE3EFE6),
      );
      expect(speakerOf(state).spoken, <String>[question, sentence]);

      // Locked, and never the word "错".
      await tapOption(tester, 2, warnIfMissed: false);
      expect(speakerOf(state).spoken, <String>[question, sentence]);
      expect(find.textContaining('错'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('a memory pick replies warmly, never with a grade', (
      tester,
    ) async {
      final api = FakeApi()..feed = feedOf(memory);
      final state = buildTestState(api);
      await openPlay(tester, state);

      final question = '记一记\n记住这三样：茶杯、钥匙、毛巾。';
      await tapOption(tester, 1);

      final sentence = '${L.zh.activityThanks}\n钥匙在门口的小盘子里。';
      expect(find.text(sentence), findsOneWidget);
      expect(feedbackFill(tester), const Color(0xFFF4EFE5));
      expect(find.textContaining(L.zh.activityCorrect), findsNothing);
      expect(find.textContaining(L.zh.activityWrong), findsNothing);
      expect(speakerOf(state).spoken, <String>[question, sentence]);

      await tapOption(tester, 2, warnIfMissed: false);
      expect(speakerOf(state).spoken, <String>[question, sentence]);

      await disposeApp(tester);
    });

    testWidgets('a story is shown and read aloud once when the card opens', (
      tester,
    ) async {
      final api = FakeApi()..feed = feedOf(story);
      final state = buildTestState(api);
      await openPlay(tester, state);

      expect(find.byKey(const Key('activity-story')), findsOneWidget);
      expect(find.text(story.story!), findsOneWidget);
      expect(find.text(L.zh.activityListen), findsOneWidget);
      // A story card reads the story first, then asks its question.
      final question = '${story.story!}\n${story.prompt}';
      expect(speakerOf(state).spoken, <String>[question]);

      await tapOption(tester, 1);
      final sentence =
          '${L.zh.activityWrong}\n'
          '在树下乘凉，是很安静的夏天。\n'
          '${L.zh.activityAnswerWas('在树下乘凉')}';
      expect(find.text(sentence), findsOneWidget);
      expect(speakerOf(state).spoken, <String>[question, sentence]);

      await disposeApp(tester);
    });

    testWidgets('换一个 opens the next card with the answer lock reset', (
      tester,
    ) async {
      final api = FakeApi()..feed = threeActivityFeed();
      final state = buildTestState(api);
      await openPlay(tester, state);

      await tapOption(tester, 0);
      expect(find.byKey(const Key('activity-feedback')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('activity-next')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('activity-next')));
      await settle(tester);
      expect(find.byKey(const Key('activity-feedback')), findsNothing);

      // The next card is the story in the rotation: it reads itself, then takes
      // its own answer.
      final next = threeActivityFeed().items[1];
      expect(speakerOf(state).spoken.last, '${next.story}\n${next.prompt}');
      await tapOption(tester, 0);
      expect(find.byKey(const Key('activity-feedback')), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('the new answer panel survives 1.3x text on a phone', (
      tester,
    ) async {
      final api = FakeApi()..feed = feedOf(trivia);
      final state = buildTestState(api);
      await pumpSignedIn(
        tester,
        state,
        size: const Size(390, 844),
        textScale: 1.3,
      );
      await tester.tap(find.byKey(const Key('primary-play')));
      await settle(tester);
      expect(tester.takeException(), isNull);

      await tapOption(tester, 0);
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });
  });

  group('silent duration', () {
    testWidgets('time is measured silently and posted on finish', (
      tester,
    ) async {
      var now = DateTime(2026, 3, 10, 9);
      final api = FakeApi()..feed = feedOf(trivia);
      // Signed in as the senior without pumping the login flow: loadActivities
      // is a no-op for anyone else.
      final state = buildTestState(api)..profile = api.profile;
      await tester.pumpWidget(
        MaterialApp(
          theme: AnchorTheme.build(),
          home: ActivityScreen(state: state, clock: () => now),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('activity-title')), findsOneWidget);
      expect(find.textContaining('还有'), findsNothing);

      now = now.add(const Duration(seconds: 125));
      await tester.ensureVisible(find.byKey(const Key('activity-finish')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('activity-finish')));
      await settle(tester);

      expect(find.byKey(const Key('activity-done')), findsOneWidget);
      expect(api.activitySessions, hasLength(1));
      expect(api.activitySessions.single.id, 'trivia-1');
      expect(api.activitySessions.single.completed, isTrue);
      expect(api.activitySessions.single.seconds, 125);

      await disposeApp(tester);
    });
  });

  group('ActivityItem content contract', () {
    test('parses the graded fields of the new JSON', () {
      final item = ActivityItem.fromJson(<String, Object?>{
        'id': 't1',
        'type': 'trivia',
        'title': '一年有几个月',
        'prompt': '几个月？',
        'minutes': 3,
        'options': <Object?>['10', '11', '12'],
        'answer': 2,
        'explanation': '一年有十二个月。',
        'wrong_hint': '再数一数。',
      });
      expect(item.answerIndex, 2);
      expect(item.hasAnswer, isTrue);
      expect(item.correctOption, '12');
      expect(item.isCorrect(2), isTrue);
      expect(item.isCorrect(0), isFalse);
      expect(item.explanation, '一年有十二个月。');
      expect(item.wrongHint, '再数一数。');
      expect(item.story, isNull);
      expect(item.replies, isEmpty);
    });

    test('tolerates old numeric strings, option text and broken indexes', () {
      ActivityItem parse(Object? answer) =>
          ActivityItem.fromJson(<String, Object?>{
            'id': 't1',
            'type': 'trivia',
            'options': <Object?>['a', 'b', 'c'],
            'answer': answer,
          });
      expect(parse('1').answerIndex, 1);
      expect(parse('b').answerIndex, 1);
      expect(parse(null).answerIndex, isNull);
      expect(parse(9).hasAnswer, isFalse);
      expect(parse('nonsense').answerIndex, isNull);
    });

    test('memory replies stay aligned with the options', () {
      final item = ActivityItem.fromJson(<String, Object?>{
        'id': 'm1',
        'type': 'memory',
        'options': <Object?>['a', 'b', 'c'],
        'replies': <Object?>['first', '', 'third'],
      });
      expect(item.hasAnswer, isFalse);
      expect(item.replyFor(0), 'first');
      expect(item.replyFor(1), isEmpty);
      expect(item.replyFor(2), 'third');
      expect(item.replyFor(9), isNull);
    });

    test('toJson round-trips every new field', () {
      final item = ActivityItem.fromJson(<String, Object?>{
        'id': 's1',
        'type': 'story',
        'title': '一个小故事',
        'prompt': '你喜欢什么？',
        'minutes': 4,
        'options': <Object?>['a', 'b'],
        'answer': 0,
        'explanation': '因为这样。',
        'wrong_hint': '再想想。',
        'replies': <Object?>['r0', 'r1'],
        'story': '从前有一个院子。',
      });
      final again = ActivityItem.fromJson(item.toJson());
      expect(again.toJson(), item.toJson());
      expect(again.story, '从前有一个院子。');
      expect(again.answerIndex, 0);
      expect(again.minutes, 4);
    });

    test('a missing field is null or empty, never a crash', () {
      final item = ActivityItem.fromJson(const <String, Object?>{});
      expect(item.id, isEmpty);
      expect(item.type, 'trivia');
      expect(item.minutes, 3);
      expect(item.options, isEmpty);
      expect(item.hasAnswer, isFalse);
      expect(item.story, isNull);
      expect(item.replyFor(0), isNull);
      expect(item.toJson()['answer'], isNull);
    });
  });
}
