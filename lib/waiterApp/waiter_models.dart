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
  final List<WaiterOrderItem> items;
  final String? paymentMethod;
  final String? orderType;
  final DateTime? encodedDt;
  final double amountPaid;
  final String? paymentRef;
  final String? encodedByName;

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
    this.paymentMethod,
    this.orderType,
    this.encodedDt,
    this.amountPaid = 0,
    this.paymentRef,
    this.encodedByName,
  }) : items = consolidateItems(items);

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
      paymentMethod: paymentMethod ?? this.paymentMethod,
      orderType: orderType ?? this.orderType,
      encodedDt: encodedDt ?? this.encodedDt,
      amountPaid: amountPaid ?? this.amountPaid,
      paymentRef: paymentRef ?? this.paymentRef,
      encodedByName: encodedByName ?? this.encodedByName,
    );
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

  WaiterOrderItem({
    required this.id,
    required this.menuId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.status,
    this.remarks,
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
    );
  }
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

