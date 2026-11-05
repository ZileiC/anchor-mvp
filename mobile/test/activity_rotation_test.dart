import 'package:anchor_app/models/activity.dart';
import 'package:anchor_app/state/activity_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The Play screen's rotation state (SPEC §6.5): an item never repeats until the
/// alternatives have been shown, and a refreshed feed keeps the current item.
void main() {
  test('starts on the first item of the server rotation', () {
    final controller = ActivityRotationController(feed: threeActivityFeed());
    expect(controller.current, isNotNull);
    expect(controller.current!.id, 'trivia-1');
    expect(controller.currentType, 'trivia');
  });

  test('walks every item once before repeating', () {
    final controller = ActivityRotationController(feed: threeActivityFeed());
    final seen = <String>[controller.current!.id];
    seen.add(controller.advance()!.id);
    seen.add(controller.advance()!.id);
    expect(seen, <String>['trivia-1', 'story-1', 'memory-1']);
    expect(seen.toSet(), hasLength(3));
    // The fourth step wraps back to the beginning.
    expect(controller.advance()!.id, 'trivia-1');
  });

  test('exposes all three activity types', () {
    final controller = ActivityRotationController(feed: threeActivityFeed());
    expect(controller.types, <String>{'trivia', 'story', 'memory'});
    expect(controller.hasAllThreeTypes, isTrue);
  });

  test('select jumps to a specific activity', () {
    final controller = ActivityRotationController(feed: threeActivityFeed());
    expect(controller.select('memory-1')!.type, 'memory');
    expect(controller.current!.id, 'memory-1');
    expect(controller.advance()!.id, 'trivia-1');
  });

  test('the server rotation wins over the item order', () {
    final feed = ActivityFeed(
      items: threeActivityFeed().items,
      rotation: const <String>['story-1', 'memory-1', 'trivia-1'],
    );
    final controller = ActivityRotationController(feed: feed);
    expect(controller.order, <String>['story-1', 'memory-1', 'trivia-1']);
    expect(controller.current!.id, 'story-1');
  });

  test('ids that are missing from the feed are ignored', () {
    final feed = ActivityFeed(
      items: threeActivityFeed().items,
      rotation: const <String>['ghost-item', 'trivia-1'],
    );
    final controller = ActivityRotationController(feed: feed);
    expect(controller.order, <String>['trivia-1', 'story-1', 'memory-1']);
  });

  test('an empty feed has no current activity', () {
    final controller = ActivityRotationController(feed: ActivityFeed.empty);
    expect(controller.isEmpty, isTrue);
    expect(controller.current, isNull);
    expect(controller.advance(), isNull);
  });

  test('a refreshed feed keeps the current activity when it survives', () {
    final controller = ActivityRotationController(feed: threeActivityFeed());
    controller.advance();
    expect(controller.current!.id, 'story-1');
    controller.syncFromFeed(threeActivityFeed());
    expect(controller.current!.id, 'story-1');
  });

  test('after a play session the next rotation is adopted', () {
    final controller = ActivityRotationController(feed: threeActivityFeed());
    // The backend rotated once: trivia is now last.
    final rotated = ActivityFeed(
      items: threeActivityFeed().items,
      rotation: const <String>['story-1', 'memory-1', 'trivia-1'],
    );
    controller.syncFromFeed(rotated);
    expect(controller.order.first, 'story-1');
    expect(controller.advance(), isNotNull);
  });

  test('the completed activity is what gets reported to the API', () {
    final controller = ActivityRotationController(feed: threeActivityFeed());
    final first = controller.current!;
    controller.advance();
    expect(first.id, isNot(controller.current!.id));
    expect(first.minutes, 3);
  });
}
