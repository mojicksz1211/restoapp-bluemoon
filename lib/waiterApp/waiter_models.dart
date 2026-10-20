import '../shared/floor_utils.dart';

class WaiterTable {
  final int id;
  final String number;
  final int capacity;
  final int status;
  // Fixed charge for VIP / KTV rooms. 0 (or null in the DB) means this is a
  // regular table with no room charge. When set, the backend merges it into
  // the order's SERVICE_CHARGE (see orderModel.resolveServiceChargeWithRoomCharge).
  final double roomCharge;

  WaiterTable({
    required this.id,
    required this.number,
    required this.capacity,
    required this.status,
    this.roomCharge = 0,
  });

  bool get hasRoomCharge => roomCharge > 0;

  WaiterTable withStatus(int status) => WaiterTable(
        id: id,
        number: number,
        capacity: capacity,
        status: status,
        roomCharge: roomCharge,
      );

  factory WaiterTable.fromApi(Map<String, dynamic> data) {
    final rawRoomCharge = data['room_charge'] ?? data['ROOM_CHARGE'];
    return WaiterTable(
      id: data['id'] is int ? data['id'] : (data['id'] as num?)?.toInt() ?? 0,
      number: data['table_number']?.toString() ?? '',
      capacity: data['capacity'] is int
          ? data['capacity']
          : (data['capacity'] as num?)?.toInt() ?? 0,
      status: data['status'] is int
          ? data['status']
          : (data['status'] as num?)?.toInt() ?? 0,
      roomCharge: rawRoomCharge is num
          ? rawRoomCharge.toDouble()
          : double.tryParse(rawRoomCharge?.toString() ?? '') ?? 0,
    );
  }
}

/// The table statuses an order change implies, for when the server's own
/// `table_updated` event is missed (socket down, event lost): the table
/// [before] was on goes back to Available (1) once the order left it —
/// moved, settled or cancelled — and no other open order is there; the table
/// [after] is on becomes Occupied (2). Only flips Occupied ↔ Available, never
/// a table set to Not Available / Reserved. [orders] is the list after the
/// change.
List<WaiterTable> applyOrderTableChange(
  List<WaiterTable> tables,
  Iterable<WaiterOrder> orders,
  WaiterOrder? before,
  WaiterOrder after,
) {
  bool isOpen(WaiterOrder o) => o.status == 2 || o.status == 3;
  final freeId = before != null &&
          before.tableId != null &&
          isOpen(before) &&
          (!isOpen(after) || after.tableId != before.tableId) &&
          !orders.any((o) => o.id != after.id && o.tableId == before.tableId && isOpen(o))
      ? before.tableId
      : null;
  final takeId = isOpen(after) ? after.tableId : null;
  if (freeId == null && takeId == null) return tables;
  return [
    for (final t in tables)
      if (t.id == freeId && t.status == 2)
        t.withStatus(1)
      else if (t.id == takeId && t.status == 1)
        t.withStatus(2)
      else
        t,
  ];
}

class WaiterOrder {
  final int id;
  final String? orderNo;
  final int? tableId;
  final String? tableNumber;
  // Base per-session room charge of this order's table (restaurant_tables.
  // ROOM_CHARGE), 0 for regular tables. The backend merges one or more units
  // of this into `serviceCharge`, so it lets the UI show the breakdown
  // (e.g. ₱1,500 × 4) instead of a bare, surprising total.
  final double roomCharge;
  final int status;
  final double grandTotal;
  // GRAND_TOTAL = SUBTOTAL (sum of items) + TAX_AMOUNT + SERVICE_CHARGE -
  // DISCOUNT_AMOUNT. SERVICE_CHARGE in particular can include a KTV room's
  // ROOM_CHARGE merged in on the backend (see orderModel.js), so grandTotal
  // legitimately runs higher than the sum of visible items — these are kept
  // so the UI can show that breakdown instead of looking like a bad total.
  final double subtotal;
  final double taxAmount;
  final double serviceCharge;
  final double discountAmount;
  /// Items merged per menu item (one line each) — what most screens show.
  final List<WaiterOrderItem> items;
  /// The order's lines as stored, one per send, each with its own time — see
  /// [itemBatches].
  final List<WaiterOrderItem> rawItems;
  final String? paymentMethod;
  final String? orderType;
  final DateTime? encodedDt;
  final double amountPaid;
  final String? paymentRef;
  final String? encodedByName;
  // Floor of the account that created the order ('gf' / '2f', from
  // user_info.FLOOR). Null for older orders or an unscoped creator — callers
  // then fall back to the table-name heuristic.
  final String? floor;
  /// Which room(s) the room charge was made in, oldest first (one per room
  /// the order used; the last is the room it's in now). Empty for regular
  /// tables and for older orders — screens then fall back to [roomCharge].
  final List<RoomChargeSegment> roomCharges;

  WaiterOrder({
    required this.id,
    required this.orderNo,
    required this.tableId,
    required this.tableNumber,
    required this.status,
    required this.grandTotal,
    this.roomCharge = 0,
    this.subtotal = 0,
    this.taxAmount = 0,
    this.serviceCharge = 0,
    this.discountAmount = 0,
    required List<WaiterOrderItem> items,
    List<WaiterOrderItem>? rawItems,
    this.paymentMethod,
    this.orderType,
    this.encodedDt,
    this.amountPaid = 0,
    this.paymentRef,
    this.encodedByName,
    this.floor,
    List<RoomChargeSegment>? roomCharges,
  })  : rawItems = List.unmodifiable(rawItems ?? items),
        items = consolidateItems(items),
        roomCharges = List.unmodifiable(roomCharges ?? const []);

  /// The room the order is in now, from [roomCharges]; null when there is no
  /// room-charge history.
  RoomChargeSegment? get currentRoomCharge {
    for (final s in roomCharges.reversed) {
      if (s.isActive) return s;
    }
    return null;
  }

  /// Total room charge across every room in [roomCharges].
  double get roomChargesTotal =>
      roomCharges.fold(0.0, (sum, s) => sum + s.amount);

  /// SERVICE_CHARGE not explained by [roomCharges] (an extra fee); 0 when
  /// there is no history.
  double get otherServiceCharge {
    if (roomCharges.isEmpty) return 0;
    final rest = serviceCharge - roomChargesTotal;
    return rest > 0.005 ? rest : 0;
  }

  /// The order's room hours in total (all rooms), or null without history.
  double? get totalRoomHours => roomCharges.isEmpty
      ? null
      : roomCharges.fold<double>(0.0, (sum, s) => sum + s.hours);

  /// Items grouped by when they were sent: the first order, then each later
  /// additional order (order_items.ENCODED_DT — the server stamps one time per
  /// batch). A single batch when nothing was added, or when the item times
  /// are unknown (older server, offline-only order).
  List<OrderItemBatch> get itemBatches {
    if (rawItems.isEmpty || rawItems.every((i) => i.encodedDt == null)) {
      return [OrderItemBatch(items: items, isInitial: true)];
    }
    final sorted = [...rawItems]..sort((a, b) {
        final at = a.encodedDt, bt = b.encodedDt;
        if (at == null) return bt == null ? 0 : -1; // unknown time → first order
        if (bt == null) return 1;
        return at.compareTo(bt);
      });
    final groups = <List<WaiterOrderItem>>[];
    final starts = <DateTime?>[];
    for (final item in sorted) {
      final t = item.encodedDt;
      final start = starts.isEmpty ? null : starts.last;
      // A few seconds of slack: lines of one send share a timestamp, separate
      // sends are a waiter round trip apart.
      final sameBatch = groups.isNotEmpty &&
          (t == null ||
              start == null ||
              t.difference(start).inSeconds.abs() <= _batchGapSeconds);
      if (sameBatch) {
        groups.last.add(item);
      } else {
        groups.add([item]);
        starts.add(t);
      }
    }
    return [
      for (var i = 0; i < groups.length; i++)
        OrderItemBatch(
          items: consolidateItems(groups[i]),
          at: starts[i] == null ? null : _toGmt8(starts[i]!),
          isInitial: i == 0,
        ),
    ];
  }

  static const int _batchGapSeconds = 10;

  /// What [after] has that [before] didn't: per menu item, the quantity that
  /// grew (an item added again shows only the extra). Used for the cashier's
  /// "items added" notice, so it lists just the new lines.
  static List<WaiterOrderItem> addedItemsBetween(
    WaiterOrder? before,
    WaiterOrder after,
  ) {
    if (before == null) {
      final batches = after.itemBatches;
      return batches.length > 1 ? batches.last.items : const [];
    }
    String keyOf(WaiterOrderItem i) => (i.menuId != null && i.menuId! > 0)
        ? 'id:${i.menuId}'
        : 'n:${i.name.trim().toLowerCase()}';
    final previousQty = <String, double>{};
    for (final item in before.items) {
      previousQty[keyOf(item)] = (previousQty[keyOf(item)] ?? 0) + item.quantity;
    }
    final added = <WaiterOrderItem>[];
    for (final item in after.items) {
      final extra = item.quantity - (previousQty[keyOf(item)] ?? 0);
      if (extra <= 0.0001) continue;
      final unitPrice = item.unitPrice > 0
          ? item.unitPrice
          : (item.quantity > 0 ? item.lineTotal / item.quantity : 0.0);
      added.add(WaiterOrderItem(
        id: item.id,
        menuId: item.menuId,
        name: item.name,
        quantity: extra,
        unitPrice: unitPrice,
        lineTotal: unitPrice * extra,
        status: item.status,
        remarks: item.remarks,
        encodedDt: item.encodedDt,
      ));
    }
    return added;
  }

  /// Same Asia/Manila conversion as [gmt8DateTime]'s encoded_dt fallback.
  static DateTime _toGmt8(DateTime dt) {
    if (!dt.isUtc && dt.timeZoneOffset == const Duration(hours: 8)) return dt;
    return dt.toUtc().add(const Duration(hours: 8));
  }

  /// Consolidates items by menuId or trimmed name so multiple entries of the same item
  /// (such as additional orders or repeated adds) are summed into a single line with total quantity.
  static List<WaiterOrderItem> consolidateItems(List<WaiterOrderItem> rawItems) {
    if (rawItems.length <= 1) return rawItems;
    final List<WaiterOrderItem> consolidated = [];

    for (final item in rawItems) {
      final nameNorm = item.name.trim().toLowerCase();
      final hasMenuId = item.menuId != null && item.menuId! > 0;

      final existingIndex = consolidated.indexWhere((existing) {
        // Match by menuId if both have it
        if (hasMenuId && existing.menuId != null && existing.menuId! > 0) {
          if (existing.menuId == item.menuId) return true;
        }
        // Match by normalized name if non-empty
        if (nameNorm.isNotEmpty && existing.name.trim().toLowerCase() == nameNorm) {
          return true;
        }
        return false;
      });

      if (existingIndex >= 0) {
        final existing = consolidated[existingIndex];
        final newQty = existing.quantity + item.quantity;
        final newLineTotal = existing.lineTotal + item.lineTotal;

        String? combinedRemarks = existing.remarks;
        if (item.remarks != null && item.remarks!.trim().isNotEmpty) {
          if (combinedRemarks == null || combinedRemarks.trim().isEmpty) {
            combinedRemarks = item.remarks;
          } else if (!combinedRemarks.toLowerCase().contains(item.remarks!.trim().toLowerCase())) {
            combinedRemarks = '$combinedRemarks, ${item.remarks}';
          }
        }

        consolidated[existingIndex] = WaiterOrderItem(
          id: existing.id ?? item.id,
          menuId: (existing.menuId != null && existing.menuId! > 0) ? existing.menuId : item.menuId,
          name: existing.name.trim().isNotEmpty ? existing.name : item.name,
          quantity: newQty,
          unitPrice: existing.unitPrice > 0 ? existing.unitPrice : item.unitPrice,
          lineTotal: newLineTotal,
          status: existing.status,
          remarks: combinedRemarks,
          encodedDt: existing.encodedDt ?? item.encodedDt,
        );
      } else {
        consolidated.add(item);
      }
    }
    return consolidated;
  }

  factory WaiterOrder.fromApi(Map<String, dynamic> data) {
    final itemsRaw = (data['items'] ?? data['ITEMS']) as List<dynamic>? ?? [];
    DateTime? parsedDt;
    final rawDt = data['encoded_dt'] ?? data['ENCODED_DT'];
    if (rawDt != null) {
      parsedDt = DateTime.tryParse(rawDt.toString());
    }
    final rawId = data['order_id'] ?? data['orderId'] ?? data['IDNo'] ?? data['id'];
    final rawTableId = data['table_id'] ?? data['tableId'] ?? data['TABLE_ID'];
    final rawStatus = data['status'] ?? data['STATUS'];
    return WaiterOrder(
      id: rawId is int ? rawId : (rawId as num?)?.toInt() ?? int.tryParse(rawId?.toString() ?? '') ?? 0,
      orderNo: (data['order_no'] ?? data['orderNo'] ?? data['ORDER_NO'])?.toString(),
      tableId: rawTableId is int ? rawTableId : (rawTableId as num?)?.toInt() ?? int.tryParse(rawTableId?.toString() ?? ''),
      tableNumber: (data['table_number'] ?? data['tableNumber'] ?? data['TABLE_NUMBER'])?.toString(),
      roomCharge: _parseDouble(data['room_charge'] ?? data['roomCharge'] ?? data['ROOM_CHARGE']),
      status: rawStatus is int ? rawStatus : (rawStatus as num?)?.toInt() ?? int.tryParse(rawStatus?.toString() ?? '') ?? 0,
      grandTotal: _parseDouble(data['grand_total'] ?? data['grandTotal'] ?? data['GRAND_TOTAL']),
      subtotal: _parseDouble(data['subtotal'] ?? data['SUBTOTAL']),
      taxAmount: _parseDouble(data['tax_amount'] ?? data['taxAmount'] ?? data['TAX_AMOUNT']),
      serviceCharge: _parseDouble(data['service_charge'] ?? data['serviceCharge'] ?? data['SERVICE_CHARGE']),
      discountAmount: _parseDouble(data['discount_amount'] ?? data['discountAmount'] ?? data['DISCOUNT_AMOUNT']),
      items: itemsRaw
          .map((item) => WaiterOrderItem.fromApi(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      paymentMethod: (data['payment_method'] ?? data['paymentMethod'] ?? data['PAYMENT_METHOD'])?.toString(),
      orderType: (data['order_type'] ?? data['orderType'] ?? data['ORDER_TYPE'])?.toString(),
      encodedDt: parsedDt,
      amountPaid: _parseDouble(data['amount_paid'] ?? data['amountPaid'] ?? data['AMOUNT_PAID']),
      paymentRef: (data['payment_ref'] ?? data['paymentRef'] ?? data['PAYMENT_REF'])?.toString(),
      encodedByName: (data['encoded_by_name'] ?? data['encodedByName'] ?? data['ENCODED_BY_NAME'])?.toString(),
      floor: normalizeFloor(data['floor'] ?? data['FLOOR']),
      roomCharges: data['room_charges'] is List
          ? (data['room_charges'] as List)
              .whereType<Map>()
              .map((s) => RoomChargeSegment.fromApi(Map<String, dynamic>.from(s)))
              .toList()
          : null,
    );
  }

  WaiterOrder copyWith({
    int? status,
    double? roomCharge,
    double? grandTotal,
    double? subtotal,
    double? taxAmount,
    double? serviceCharge,
    double? discountAmount,
    List<WaiterOrderItem>? items,
    String? paymentMethod,
    String? orderType,
    DateTime? encodedDt,
    double? amountPaid,
    String? paymentRef,
    String? encodedByName,
    List<RoomChargeSegment>? roomCharges,
  }) {
    return WaiterOrder(
      id: id,
      orderNo: orderNo,
      tableId: tableId,
      tableNumber: tableNumber,
      roomCharge: roomCharge ?? this.roomCharge,
      status: status ?? this.status,
      grandTotal: grandTotal ?? this.grandTotal,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      serviceCharge: serviceCharge ?? this.serviceCharge,
      discountAmount: discountAmount ?? this.discountAmount,
      items: items ?? this.items,
      // The only caller passing items (cashier socket merge) builds them from
      // a payload that already carried the full stored list.
      rawItems: rawItems,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      orderType: orderType ?? this.orderType,
      encodedDt: encodedDt ?? this.encodedDt,
      amountPaid: amountPaid ?? this.amountPaid,
      paymentRef: paymentRef ?? this.paymentRef,
      encodedByName: encodedByName ?? this.encodedByName,
      floor: floor,
      roomCharges: roomCharges ?? this.roomCharges,
    );
  }

  /// [incoming] parsed from a socket payload, keeping this order's room-charge
  /// history when the payload didn't carry one (only some events do).
  WaiterOrder keepRoomChargesIn(WaiterOrder incoming, Map<String, dynamic> payload) {
    if (payload.containsKey('room_charges') || roomCharges.isEmpty) return incoming;
    return incoming.copyWith(roomCharges: roomCharges);
  }

  /// Returns the order timestamp guaranteed in GMT+8 (Asia/Manila time).
  DateTime get gmt8DateTime {
    // 1. If orderNo has an ORD-YYYYMMDD-HHMMSS pattern, it encodes the exact local GMT+8 time.
    if (orderNo != null) {
      final match = RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})').firstMatch(orderNo!);
      if (match != null) {
        final y = int.tryParse(match.group(1)!);
        final m = int.tryParse(match.group(2)!);
        final d = int.tryParse(match.group(3)!);
        final h = int.tryParse(match.group(4)!);
        final min = int.tryParse(match.group(5)!);
        final s = int.tryParse(match.group(6)!);
        if (y != null && m != null && d != null && h != null && min != null && s != null) {
          return DateTime(y, m, d, h, min, s);
        }
      }
    }

    // 2. If encodedDt is provided, convert from UTC to GMT+8 (+8 hours).
    if (encodedDt != null) {
      if (encodedDt!.isUtc) {
        return encodedDt!.toUtc().add(const Duration(hours: 8));
      } else {
        if (encodedDt!.timeZoneOffset == const Duration(hours: 8)) {
          return encodedDt!;
        }
        return encodedDt!.toUtc().add(const Duration(hours: 8));
      }
    }

    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  /// Formatted date string in GMT+8 (e.g. "2026-09-04 02:54 PM" or "2026-09-04 14:54")
  String formatGmt8DateTime({bool includeSeconds = false, bool use12Hour = true}) {
    final dt = gmt8DateTime;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');

    if (!use12Hour) {
      final h24 = dt.hour.toString().padLeft(2, '0');
      return includeSeconds ? '$y-$m-$d $h24:$min:$sec' : '$y-$m-$d $h24:$min';
    }

    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final h12Str = h12.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return includeSeconds ? '$y-$m-$d $h12Str:$min:$sec $period' : '$y-$m-$d $h12Str:$min $period';
  }

  static double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

class WaiterOrderItem {
  final int? id;
  final int? menuId;
  final String name;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final int status;
  final String? remarks;
  /// When this line was sent (order_items.ENCODED_DT), as parsed — convert
  /// with [WaiterOrder] helpers before showing it.
  final DateTime? encodedDt;

  WaiterOrderItem({
    required this.id,
    required this.menuId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.status,
    this.remarks,
    this.encodedDt,
  });

  factory WaiterOrderItem.fromApi(Map<String, dynamic> data) {
    final rawId = data['item_id'] ?? data['itemId'] ?? data['IDNo'] ?? data['id'];
    final rawMenuId = data['menu_id'] ?? data['menuId'] ?? data['MENU_ID'];
    final rawStatus = data['status'] ?? data['STATUS'];
    return WaiterOrderItem(
      id: rawId is int ? rawId : (rawId as num?)?.toInt() ?? int.tryParse(rawId?.toString() ?? ''),
      menuId: rawMenuId is int ? rawMenuId : (rawMenuId as num?)?.toInt() ?? int.tryParse(rawMenuId?.toString() ?? ''),
      name: (data['menu_name'] ?? data['menuName'] ?? data['MENU_NAME'] ?? data['name'] ?? '').toString(),
      quantity: WaiterOrder._parseDouble(data['qty'] ?? data['QTY'] ?? data['quantity']),
      unitPrice: WaiterOrder._parseDouble(data['unit_price'] ?? data['unitPrice'] ?? data['UNIT_PRICE'] ?? data['price']),
      lineTotal: WaiterOrder._parseDouble(data['line_total'] ?? data['lineTotal'] ?? data['LINE_TOTAL']),
      status: rawStatus is int ? rawStatus : (rawStatus as num?)?.toInt() ?? int.tryParse(rawStatus?.toString() ?? '') ?? 0,
      remarks: (data['remarks'] ?? data['REMARKS'] ?? data['notes'])?.toString(),
      encodedDt: DateTime.tryParse(
        (data['encoded_dt'] ?? data['ENCODED_DT'] ?? '').toString(),
      ),
    );
  }
}

/// One send of items on an order: the first order, or a later addition.
class OrderItemBatch {
  final List<WaiterOrderItem> items;
  /// Asia/Manila time of the send; null when unknown.
  final DateTime? at;
  final bool isInitial;

  const OrderItemBatch({required this.items, this.at, this.isInitial = false});

  double get subtotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get quantity => items.fold(0.0, (sum, i) => sum + i.quantity);

  /// "12:45 AM", or null when the time is unknown.
  String? get timeLabel {
    final t = at;
    if (t == null) return null;
    final h12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final min = t.minute.toString().padLeft(2, '0');
    return '$h12:$min ${t.hour >= 12 ? 'PM' : 'AM'}';
  }
}

/// One room an order's room charge was made in (order_room_charges): the
/// room's hourly rate, the hours billed there and when the order was in it.
/// One session = 1 hour; hours go in 0.5 steps.
class RoomChargeSegment {
  final int? tableId;
  final String? tableNumber;
  final double rate;
  final double hours;
  final double amount;
  /// Asia/Manila wall-clock times (as sent by the server); [endedAt] is null
  /// while the order is still in this room.
  final DateTime? startedAt;
  final DateTime? endedAt;
  /// Minutes in this room as of the server's response.
  final int minutesUsed;
  final bool isActive;

  const RoomChargeSegment({
    required this.tableId,
    required this.tableNumber,
    required this.rate,
    required this.hours,
    required this.amount,
    this.startedAt,
    this.endedAt,
    this.minutesUsed = 0,
    this.isActive = false,
  });

  factory RoomChargeSegment.fromApi(Map<String, dynamic> data) {
    final rawTableId = data['table_id'];
    final ended = DateTime.tryParse((data['ended_at'] ?? '').toString());
    return RoomChargeSegment(
      tableId: rawTableId is int ? rawTableId : int.tryParse(rawTableId?.toString() ?? ''),
      tableNumber: data['table_number']?.toString(),
      rate: WaiterOrder._parseDouble(data['rate']),
      hours: WaiterOrder._parseDouble(data['hours']),
      amount: WaiterOrder._parseDouble(data['amount']),
      startedAt: DateTime.tryParse((data['started_at'] ?? '').toString()),
      endedAt: ended,
      minutesUsed: (data['minutes_used'] as num?)?.toInt() ?? 0,
      isActive: data['active'] is bool ? data['active'] as bool : ended == null,
    );
  }

  Map<String, dynamic> toApi() => {
        'table_id': tableId,
        'table_number': tableNumber,
        'rate': rate,
        'hours': hours,
        'amount': amount,
        'started_at': startedAt == null ? null : formatManilaSql(startedAt!),
        'ended_at': endedAt == null ? null : formatManilaSql(endedAt!),
        'minutes_used': minutesUsed,
        'active': isActive,
      };

  /// Minutes spent in this room — live for the room the order is in now.
  int get liveMinutesUsed {
    final start = startedAt;
    if (start == null) return minutesUsed;
    final end = endedAt ?? (isActive ? manilaNow() : null);
    if (end == null) return minutesUsed;
    final m = end.difference(start).inMinutes;
    return m < 0 ? 0 : m;
  }

  /// "ROOM 5" (falls back to "Room").
  String get roomLabel {
    final name = (tableNumber ?? '').trim();
    return name.isEmpty ? 'Room' : name;
  }

  /// "8:10 PM – 8:47 PM", or "since 8:47 PM" for the current room.
  String? get timeRangeLabel {
    final start = startedAt;
    if (start == null) return null;
    final end = endedAt;
    if (end == null) return isActive ? 'since ${formatClock(start)}' : formatClock(start);
    return '${formatClock(start)} – ${formatClock(end)}';
  }
}

/// The rooms [order]'s room charge was made in. Without a recorded history
/// (older orders) it is rebuilt as one room — the order's table at
/// [fallbackRate] per hour since the order was opened — so every screen shows
/// hours the same way. Empty when there is no room charge.
List<RoomChargeSegment> roomChargeSegmentsOf(WaiterOrder order, {double fallbackRate = 0}) {
  if (order.roomCharges.isNotEmpty) return order.roomCharges;
  final rate = fallbackRate > 0 ? fallbackRate : order.roomCharge;
  if (rate <= 0) return const [];
  return [
    RoomChargeSegment(
      tableId: order.tableId,
      tableNumber: order.tableNumber,
      rate: rate,
      hours: (order.serviceCharge / rate * 2).round() / 2,
      amount: order.serviceCharge,
      startedAt: order.gmt8DateTime,
      isActive: order.status == 2 || order.status == 3,
    ),
  ];
}

/// "30 mins", "1 hr", "1.5 hrs", "2 hrs" (one session = 1 hour).
String formatRoomHours(double hours) {
  if (hours <= 0) return '0 hrs';
  if (hours == 0.5) return '30 mins';
  final n = hours % 1 == 0 ? hours.toInt().toString() : hours.toStringAsFixed(1);
  return hours == 1 ? '1 hr' : '$n hrs';
}

/// "45m", "1h 25m".
String formatMinutesUsed(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Hours billed for a room the guest is leaving: whole half-hours of the time
/// spent there (37 minutes → 0.5). Mirrors the server's
/// OrderRoomChargeModel.billableHoursForMinutes.
double billableRoomHours(int minutes) => (minutes < 0 ? 0 : minutes ~/ 30) * 0.5;

/// Moving room-to-room before this many minutes carries the time over: the
/// old room is billed nothing and the new room continues the same clock and
/// booked hours at its own rate. Mirrors OrderRoomChargeModel.CARRY_OVER_MINUTES.
const int kRoomCarryOverMinutes = 30;

/// Whether room [i] of [segments] had its time carried over to the next room
/// (billed nothing there, and the next room's clock starts when its did).
bool roomTimeCarriedOver(List<RoomChargeSegment> segments, int i) {
  if (i < 0 || i + 1 >= segments.length) return false;
  final s = segments[i];
  final next = segments[i + 1];
  return !s.isActive &&
      s.hours <= 0 &&
      s.startedAt != null &&
      next.startedAt != null &&
      next.startedAt!.difference(s.startedAt!).inSeconds.abs() < 60;
}

/// Current Asia/Manila wall-clock time (naive DateTime), whatever the tablet's
/// own timezone.
DateTime manilaNow() {
  final n = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime(n.year, n.month, n.day, n.hour, n.minute, n.second);
}

/// "8:47 PM".
String formatClock(DateTime t) {
  final h12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  return '$h12:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

/// "2026-10-19 20:47:00" — the shape the server sends room-charge times in.
String formatManilaSql(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

class EditableOrderItem {
  int? menuId;
  String name;
  double quantity;
  double unitPrice;
  final int status;
  String? remarks;

  EditableOrderItem({
    required this.menuId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.status,
    this.remarks,
  });

  double get lineTotal => quantity * unitPrice;
}

/// Take-out orders have no table. They are numbered per day ("Take Out #3") in
/// the order they were placed, so every device shows the same label for the
/// same order. [refresh] is called with the loaded order list whenever it
/// changes.
class TakeOutNumbers {
  TakeOutNumbers._();

  static final Map<int, int> _byOrderId = {};

  static void refresh(Iterable<WaiterOrder> orders) {
    final byDay = <String, List<WaiterOrder>>{};
    for (final o in orders) {
      if (!o.isTakeOut) continue;
      final d = o.gmt8DateTime;
      byDay.putIfAbsent('${d.year}-${d.month}-${d.day}', () => []).add(o);
    }
    _byOrderId.clear();
    for (final list in byDay.values) {
      list.sort((a, b) {
        final c = a.gmt8DateTime.compareTo(b.gmt8DateTime);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
      for (var i = 0; i < list.length; i++) {
        _byOrderId[list[i].id] = i + 1;
      }
    }
  }

  static int? numberOf(WaiterOrder o) => _byOrderId[o.id];

  /// The number the next take-out placed today will get.
  static int nextNumber(Iterable<WaiterOrder> orders) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    var count = 0;
    for (final o in orders) {
      if (!o.isTakeOut) continue;
      final d = o.gmt8DateTime;
      if (d.year == now.year && d.month == now.month && d.day == now.day) count++;
    }
    return count + 1;
  }
}

extension WaiterOrderTakeOut on WaiterOrder {
  /// A table-less order placed as TAKE_OUT.
  bool get isTakeOut =>
      tableId == null &&
      (tableNumber ?? '').trim().isEmpty &&
      (orderType ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '') == 'TAKEOUT';

  /// "Take Out #3".
  String get takeOutLabel {
    final n = TakeOutNumbers.numberOf(this);
    return n == null ? 'Take Out' : 'Take Out #$n';
  }
}
