import 'package:bluemoon_resto_app/waiterApp/waiter_models.dart';
import 'package:flutter_test/flutter_test.dart';

WaiterTable table(int id, int status) =>
    WaiterTable(id: id, number: 'ROOM $id', capacity: 4, status: status, roomCharge: 1000);

WaiterOrder order(int id, int? tableId, int status) => WaiterOrder(
      id: id,
      orderNo: 'ORD-$id',
      tableId: tableId,
      tableNumber: tableId == null ? null : 'ROOM $tableId',
      status: status,
      grandTotal: 0,
      items: const [],
    );

Map<int, int> statuses(List<WaiterTable> tables) => {for (final t in tables) t.id: t.status};

void main() {
  test('transfer frees the old room and occupies the new one', () {
    final before = order(1, 10, 2);
    final after = order(1, 20, 2);
    final result = applyOrderTableChange([table(10, 2), table(20, 1)], [after], before, after);
    expect(statuses(result), {10: 1, 20: 2});
  });

  test('cancel and settle free the room', () {
    for (final status in [-1, 1]) {
      final before = order(1, 10, 2);
      final after = order(1, 10, status);
      final result = applyOrderTableChange([table(10, 2)], [after], before, after);
      expect(statuses(result), {10: 1}, reason: 'status $status');
    }
  });

  test('room stays occupied while another open order is on it', () {
    final before = order(1, 10, 2);
    final after = order(1, 20, 2);
    final other = order(2, 10, 3);
    final result = applyOrderTableChange([table(10, 2), table(20, 1)], [after, other], before, after);
    expect(statuses(result), {10: 2, 20: 2});
  });

  test('never overrides Not Available / Reserved', () {
    final before = order(1, 10, 2);
    final after = order(1, 20, -1);
    final result = applyOrderTableChange([table(10, 3), table(20, 4)], [after], before, after);
    expect(statuses(result), {10: 3, 20: 4});
  });

  test('new order occupies its room', () {
    final created = order(1, 10, 3);
    final result = applyOrderTableChange([table(10, 1)], [created], null, created);
    expect(statuses(result), {10: 2});
  });
}
