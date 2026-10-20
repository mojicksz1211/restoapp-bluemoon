import 'package:bluemoon_resto_app/waiterApp/services/room_time_alerts.dart';
import 'package:bluemoon_resto_app/waiterApp/waiter_models.dart';
import 'package:flutter_test/flutter_test.dart';

WaiterOrder roomOrder({
  required int minutesAgo,
  double hours = 1,
  int status = 2,
  bool active = true,
}) {
  final started = manilaNow().subtract(Duration(minutes: minutesAgo));
  return WaiterOrder.fromApi({
    'order_id': 7,
    'order_no': 'ORD-TEST',
    'table_id': 26,
    'table_number': 'ROOM 2',
    'status': status,
    'grand_total': 1400 * hours,
    'service_charge': 1400 * hours,
    'room_charge': 1400,
    'items': [],
    'room_charges': [
      {
        'table_id': 26,
        'table_number': 'ROOM 2',
        'rate': 1400,
        'hours': hours,
        'amount': 1400 * hours,
        'started_at': formatManilaSql(started),
        'ended_at': null,
        'minutes_used': minutesAgo,
        'active': active,
      },
    ],
  });
}

void main() {
  test('plenty of time left: counts down, no warning', () {
    final c = RoomCountdown.of(roomOrder(minutesAgo: 20))!;
    expect(c.label, '40m left');
    expect(c.isEndingSoon, isFalse);
    expect(c.shouldWarn, isFalse);
  });

  test('15 minutes or less left: warns', () {
    final c = RoomCountdown.of(roomOrder(minutesAgo: 50))!;
    expect(c.label, '10m left');
    expect(c.shouldWarn, isTrue);
    expect(c.isOver, isFalse);
    expect(c.alertKey, endsWith('|soon'));
  });

  test('time is up: warns again with its own key', () {
    final c = RoomCountdown.of(roomOrder(minutesAgo: 70))!;
    expect(c.isOver, isTrue);
    expect(c.label, '+10m over');
    expect(c.shouldWarn, isTrue);
    expect(c.alertKey, endsWith('|over'));
  });

  test('long past the end: no popup any more', () {
    final c = RoomCountdown.of(roomOrder(minutesAgo: 100))!;
    expect(c.shouldWarn, isFalse);
  });

  test('extending moves the end time and so the alert key', () {
    final before = RoomCountdown.of(roomOrder(minutesAgo: 50))!;
    final after = RoomCountdown.of(roomOrder(minutesAgo: 50, hours: 2))!;
    expect(after.alertKey, isNot(before.alertKey));
    expect(after.label, '1h 10m left');
  });

  test('waived room, settled order: no countdown', () {
    expect(RoomCountdown.of(roomOrder(minutesAgo: 10, hours: 0)), isNull);
    expect(RoomCountdown.of(roomOrder(minutesAgo: 10, status: 1)), isNull);
  });

  test('older order without history: clock from the order time, hours from the charge', () {
    final opened = manilaNow().subtract(const Duration(minutes: 110));
    String two(int v) => v.toString().padLeft(2, '0');
    final orderNo =
        'ORD-${opened.year}${two(opened.month)}${two(opened.day)}-${two(opened.hour)}${two(opened.minute)}${two(opened.second)}';
    final order = WaiterOrder.fromApi({
      'order_id': 8,
      'order_no': orderNo,
      'table_id': 27,
      'table_number': 'ROOM 3',
      'status': 2,
      'service_charge': 1200,
      'grand_total': 1200,
      'items': [],
    });
    final c = RoomCountdown.of(order, fallbackRate: 600)!;
    expect(c.room.hours, 2);
    expect(c.label, '10m left');
  });

  test('billing helpers', () {
    expect(billableRoomHours(37), 0.5);
    expect(billableRoomHours(29), 0);
    expect(formatRoomHours(0.5), '30 mins');
    expect(formatRoomHours(1.5), '1.5 hrs');
  });
}
