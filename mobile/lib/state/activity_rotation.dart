import '../models/activity.dart';

/// UI state for the Play screen's deterministic rotation (SPEC §6.5).
///
/// The backend decides the order (`rotation`) and persists it, so the app only
/// walks that order and never repeats an item until the list wraps. Keeping this
/// pure makes the "no repeat until every item was shown" rule unit-testable
/// without a widget tree.
class ActivityRotationController {
  ActivityRotationController({ActivityFeed feed = ActivityFeed.empty}) {
    _items = <ActivityItem>[...feed.items];
    _order = _orderFrom(feed);
  }

  late List<ActivityItem> _items;
  late List<String> _order;
  int _index = 0;

  static List<String> _orderFrom(ActivityFeed feed) {
    final known = <String, ActivityItem>{
      for (final item in feed.items) item.id: item,
    };
    final ordered = <String>[];
    for (final id in feed.rotation) {
      if (known.containsKey(id) && !ordered.contains(id)) ordered.add(id);
    }
    for (final item in feed.items) {
      if (!ordered.contains(item.id)) ordered.add(item.id);
    }
    return ordered;
  }

  List<ActivityItem> get items => List<ActivityItem>.unmodifiable(_items);

  List<String> get order => List<String>.unmodifiable(_order);

  bool get isEmpty => _order.isEmpty;

  ActivityItem? get current {
    if (_order.isEmpty) return null;
    final id = _order[_index % _order.length];
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return _items.isEmpty ? null : _items[_index % _items.length];
  }

  String get currentType => current?.type ?? '';

  /// Distinct activity types available (trivia / story / memory).
  Set<String> get types => _items.map((item) => item.type).toSet();

  bool get hasAllThreeTypes =>
      types.contains('trivia') &&
      types.contains('story') &&
      types.contains('memory');

  int get shownIndex => _index;

  /// Moves to the next item and returns it. Wraps after the last one.
  ActivityItem? advance() {
    if (_order.isEmpty) return null;
    _index = (_index + 1) % _order.length;
    return current;
  }

  ActivityItem? select(String activityId) {
    final position = _order.indexOf(activityId);
    if (position < 0) return current;
    _index = position;
    return current;
  }

  /// Adopts a refreshed feed from the server while staying on the same activity
  /// when it is still present.
  void syncFromFeed(ActivityFeed feed) {
    final previousId = current?.id;
    _items = <ActivityItem>[...feed.items];
    _order = _orderFrom(feed);
    if (_order.isEmpty) {
      _index = 0;
      return;
    }
    final position = previousId == null ? -1 : _order.indexOf(previousId);
    _index = position >= 0 ? position : 0;
    if (_index >= _order.length) _index = 0;
  }
}
