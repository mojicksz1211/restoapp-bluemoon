class KitchenItemUi {
  final String menuName;
  final double qty;
  final double unitPrice;
  final double lineTotal;

  KitchenItemUi({
    required this.menuName,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory KitchenItemUi.fromMap(Map<String, dynamic> map) {
    return KitchenItemUi(
      menuName: map['menu_name']?.toString() ?? 'N/A',
      qty: (map['qty'] is num) ? (map['qty'] as num).toDouble() : 0.0,
      unitPrice: (map['unit_price'] is num) ? (map['unit_price'] as num).toDouble() : 0.0,
      lineTotal: (map['line_total'] is num) ? (map['line_total'] as num).toDouble() : 0.0,
    );
  }
}

class KitchenOrderUi {
  final int orderId;
  final String orderNo;
  final String? tableNumber;
  final String orderType;
  final int status;
  final double grandTotal;
  final DateTime encodedDt;
  final List<KitchenItemUi> items;

  KitchenOrderUi({
    required this.orderId,
    required this.orderNo,
    this.tableNumber,
    required this.orderType,
    required this.status,
    required this.grandTotal,
    required this.encodedDt,
    required this.items,
  });

  factory KitchenOrderUi.fromMap(Map<String, dynamic> map) {
    final orderId = map['order_id'] is int ? map['order_id'] as int : int.parse(map['order_id'].toString());
    final orderNo = map['order_no']?.toString() ?? 'N/A';
    final tableNumber = map['table_number']?.toString();
    final tableId = map['table_id']?.toString();
    final orderType = map['order_type']?.toString() ?? 'DINE_IN';
    final status = map['status'] is int ? map['status'] as int : int.parse(map['status'].toString());
    final grandTotal = (map['grand_total'] is num) ? (map['grand_total'] as num).toDouble() : 0.0;
    
    final encodedDtRaw = map['encoded_dt']?.toString();
    final encodedDt = encodedDtRaw != null ? DateTime.parse(encodedDtRaw) : DateTime.now();
    
    final itemsRaw = map['items'] as List<dynamic>? ?? [];
    final items = itemsRaw.map((item) => KitchenItemUi.fromMap(Map<String, dynamic>.from(item))).toList();

    return KitchenOrderUi(
      orderId: orderId,
      orderNo: orderNo,
      tableNumber: tableNumber ?? tableId,
      orderType: orderType,
      status: status,
      grandTotal: grandTotal,
      encodedDt: encodedDt,
      items: items,
    );
  }

  String get statusLabel {
    switch (status) {
      case 3:
      case 2:
        return 'Pending';
      case 1:
        return 'Ready';
      case -1:
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }
}
