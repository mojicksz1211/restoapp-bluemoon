class WaiterTable {
  final int id;
  final String number;
  final int capacity;
  final int status;

  WaiterTable({
    required this.id,
    required this.number,
    required this.capacity,
    required this.status,
  });

  factory WaiterTable.fromApi(Map<String, dynamic> data) {
    return WaiterTable(
      id: data['id'] is int ? data['id'] : (data['id'] as num?)?.toInt() ?? 0,
      number: data['table_number']?.toString() ?? '',
      capacity: data['capacity'] is int
          ? data['capacity']
          : (data['capacity'] as num?)?.toInt() ?? 0,
      status: data['status'] is int
          ? data['status']
          : (data['status'] as num?)?.toInt() ?? 0,
    );
  }
}

class WaiterOrder {
  final int id;
  final String? orderNo;
  final int? tableId;
  final String? tableNumber;
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

  WaiterOrder({
    required this.id,
    required this.orderNo,
    required this.tableId,
    required this.tableNumber,
    required this.status,
    required this.grandTotal,
    this.subtotal = 0,
    this.taxAmount = 0,
    this.serviceCharge = 0,
    this.discountAmount = 0,
    required this.items,
    this.paymentMethod,
  });

  factory WaiterOrder.fromApi(Map<String, dynamic> data) {
    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return WaiterOrder(
      id: data['order_id'] is int
          ? data['order_id']
          : (data['order_id'] as num?)?.toInt() ?? 0,
      orderNo: data['order_no']?.toString(),
      tableId: data['table_id'] is int
          ? data['table_id']
          : (data['table_id'] as num?)?.toInt(),
      tableNumber: data['table_number']?.toString(),
      status: data['status'] is int
          ? data['status']
          : (data['status'] as num?)?.toInt() ?? 0,
      grandTotal: _parseDouble(data['grand_total']),
      subtotal: _parseDouble(data['subtotal']),
      taxAmount: _parseDouble(data['tax_amount']),
      serviceCharge: _parseDouble(data['service_charge']),
      discountAmount: _parseDouble(data['discount_amount']),
      items: itemsRaw
          .map((item) => WaiterOrderItem.fromApi(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      paymentMethod: data['payment_method']?.toString(),
    );
  }

  WaiterOrder copyWith({
    int? status,
    double? grandTotal,
    double? subtotal,
    double? taxAmount,
    double? serviceCharge,
    double? discountAmount,
    List<WaiterOrderItem>? items,
    String? paymentMethod,
  }) {
    return WaiterOrder(
      id: id,
      orderNo: orderNo,
      tableId: tableId,
      tableNumber: tableNumber,
      status: status ?? this.status,
      grandTotal: grandTotal ?? this.grandTotal,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      serviceCharge: serviceCharge ?? this.serviceCharge,
      discountAmount: discountAmount ?? this.discountAmount,
      items: items ?? this.items,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
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
    return WaiterOrderItem(
      id: data['item_id'] is int ? data['item_id'] : (data['item_id'] as num?)?.toInt(),
      menuId: data['menu_id'] is int ? data['menu_id'] : (data['menu_id'] as num?)?.toInt(),
      name: data['menu_name']?.toString() ?? '',
      quantity: WaiterOrder._parseDouble(data['qty']),
      unitPrice: WaiterOrder._parseDouble(data['unit_price']),
      lineTotal: WaiterOrder._parseDouble(data['line_total']),
      status: data['status'] is int
          ? data['status']
          : (data['status'] as num?)?.toInt() ?? 0,
      remarks: data['remarks']?.toString(),
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

