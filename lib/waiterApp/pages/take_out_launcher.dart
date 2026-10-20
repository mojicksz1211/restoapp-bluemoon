import 'package:flutter/material.dart';

import '../models.dart';
import '../waiter_models.dart';
import 'get_order_page.dart';

/// Starts a take-out order: the Switch Menu opens with a "TAKE OUT #N" header
/// and the order type already set to TAKE_OUT. There is no table, so the
/// placeholder table has id 0 (sent to the server as no table).
Future<void> openNewTakeOut(
  BuildContext context, {
  required List<MenuItem> menuItems,
  required Iterable<WaiterOrder> orders,
}) {
  final n = TakeOutNumbers.nextNumber(orders);
  final table = WaiterTable(
    id: 0,
    number: 'Take Out #$n',
    capacity: 0,
    status: 1,
  );
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GetOrderPage(
        table: table,
        menuItems: menuItems,
        startInSwitchMenu: true,
        initialOrderType: 'TAKE_OUT',
      ),
    ),
  );
}
