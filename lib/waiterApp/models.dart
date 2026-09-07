import 'package:flutter/material.dart';

String formatPrice(num value) {
  final s = value.toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final decPart = parts[1];
  final withCommas = intPart.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  return '$withCommas.$decPart';
}

class MenuItem {
  final int? id;
  final String name;
  final String description;
  final double price;
  final String category;
  final String? categoryName;
  final int? categoryId; // Add categoryId field
  final IconData icon;
  final String? imageUrl;
  final bool isAvailable;
  final int salesQty;
  final double totalRevenue;

  MenuItem({
    this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    this.categoryName,
    this.categoryId, // Add categoryId parameter
    required this.icon,
    this.imageUrl,
    this.isAvailable = true,
    this.salesQty = 0,
    this.totalRevenue = 0.0,
  });

  // Factory constructor to create MenuItem from API data
  factory MenuItem.fromApi(Map<String, dynamic> data) {
    // Ensure category_id is properly converted to int
    int? categoryId;
    if (data['category_id'] != null) {
      if (data['category_id'] is int) {
        categoryId = data['category_id'] as int;
      } else if (data['category_id'] is String) {
        categoryId = int.tryParse(data['category_id'] as String);
      } else {
        categoryId = (data['category_id'] as num?)?.toInt();
      }
    }

    final rawSalesQty = data['sales_qty'] ?? data['total_qty'];
    final rawTotalRevenue = data['total_revenue'];
    
    return MenuItem(
      id: data['id'] is int ? data['id'] as int : (data['id'] as num?)?.toInt(),
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      category: data['category_name'] ?? '',
      categoryName: data['category_name'],
      categoryId: categoryId, // Store category_id from API (properly converted to int)
      icon: Icons.restaurant_menu,
      imageUrl: data['image'],
      isAvailable: data['is_available'] ?? true,
      salesQty: rawSalesQty is int
          ? rawSalesQty
          : (rawSalesQty is num)
              ? rawSalesQty.toInt()
              : int.tryParse(rawSalesQty?.toString() ?? '0') ?? 0,
      totalRevenue: rawTotalRevenue is num
          ? rawTotalRevenue.toDouble()
          : double.tryParse(rawTotalRevenue?.toString() ?? '0') ?? 0.0,
    );
  }
}

class CartItem {
  final MenuItem item;
  int quantity;
  String? remarks;

  CartItem({required this.item, this.quantity = 1, this.remarks});

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'item': {
        'id': item.id,
        'name': item.name,
        'description': item.description,
        'price': item.price,
        'category': item.category,
        'categoryName': item.categoryName,
        'categoryId': item.categoryId,
        'imageUrl': item.imageUrl,
        'isAvailable': item.isAvailable,
      },
      'quantity': quantity,
      'remarks': remarks,
    };
  }

  // Create from JSON
  factory CartItem.fromJson(Map<String, dynamic> json) {
    final itemData = json['item'] as Map<String, dynamic>;
    return CartItem(
      item: MenuItem(
        id: itemData['id'],
        name: itemData['name'],
        description: itemData['description'],
        price: (itemData['price'] ?? 0).toDouble(),
        category: itemData['category'] ?? '',
        categoryName: itemData['categoryName'],
        categoryId: itemData['categoryId'],
        icon: Icons.restaurant_menu,
        imageUrl: itemData['imageUrl'],
        isAvailable: itemData['isAvailable'] ?? true,
      ),
      quantity: json['quantity'] ?? 1,
      remarks: json['remarks'] as String?,
    );
  }
}

enum OrderStatus {
  waitingForAssistance,
  orderConfirmed,
  preparingOrder,
  ordersReady,
}

class Order {
  final String id;
  final List<CartItem> items;
  final double totalPrice;
  final DateTime orderTime;
  OrderStatus status;
  final int? orderId; // Backend order ID from API
  final int? backendStatus; // Raw backend status (1=SETTLED, 2=CONFIRMED, 3=PENDING, -1=CANCELLED)
  final String? orderType; // Order type (DINE_IN, TAKE_OUT, etc.)
  final int? tableId; // Table ID if it's a table order

  Order({
    required this.id,
    required List<CartItem> items,
    required this.totalPrice,
    required this.orderTime,
    this.status = OrderStatus.waitingForAssistance,
    this.orderId,
    this.backendStatus,
    this.orderType,
    this.tableId,
  }) : items = consolidateCartItems(items);

  /// Consolidates duplicate cart items by menu ID or name, summing quantities and combining remarks.
  static List<CartItem> consolidateCartItems(List<CartItem> rawItems) {
    if (rawItems.length <= 1) return rawItems;
    final List<CartItem> consolidated = [];

    for (final cartItem in rawItems) {
      final nameNorm = cartItem.item.name.trim().toLowerCase();
      final hasMenuId = cartItem.item.id != null && cartItem.item.id! > 0;

      final existingIndex = consolidated.indexWhere((existing) {
        if (hasMenuId && existing.item.id != null && existing.item.id! > 0) {
          if (existing.item.id == cartItem.item.id) return true;
        }
        if (nameNorm.isNotEmpty && existing.item.name.trim().toLowerCase() == nameNorm) {
          return true;
        }
        return false;
      });

      if (existingIndex >= 0) {
        final existing = consolidated[existingIndex];
        final newQty = existing.quantity + cartItem.quantity;
        String? combinedRemarks = existing.remarks;
        if (cartItem.remarks != null && cartItem.remarks!.trim().isNotEmpty) {
          if (combinedRemarks == null || combinedRemarks.trim().isEmpty) {
            combinedRemarks = cartItem.remarks;
          } else if (!combinedRemarks.toLowerCase().contains(cartItem.remarks!.trim().toLowerCase())) {
            combinedRemarks = '$combinedRemarks, ${cartItem.remarks}';
          }
        }
        consolidated[existingIndex] = CartItem(
          item: existing.item,
          quantity: newQty,
          remarks: combinedRemarks,
        );
      } else {
        consolidated.add(cartItem);
      }
    }
    return consolidated;
  }

  String get statusText {
    switch (status) {
      case OrderStatus.waitingForAssistance:
        return 'Waiting for Assistance';
      case OrderStatus.orderConfirmed:
        return 'Order Confirmed';
      case OrderStatus.preparingOrder:
        return 'Preparing Order';
      case OrderStatus.ordersReady:
        return 'Orders Ready';
    }
  }

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'items': items.map((item) => item.toJson()).toList(),
      'totalPrice': totalPrice,
      'orderTime': orderTime.toIso8601String(),
      'status': status.index,
      'backendStatus': backendStatus,
      'orderType': orderType,
      'tableId': tableId,
    };
  }

  // Create from JSON
  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'],
      orderId: json['orderId'],
      items: (json['items'] as List)
          .map((item) => CartItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalPrice: (json['totalPrice'] ?? 0).toDouble(),
      orderTime: DateTime.parse(json['orderTime']),
      status: OrderStatus.values[json['status'] ?? 0],
      backendStatus: json['backendStatus'] is int ? json['backendStatus'] : (json['backendStatus'] is String ? int.tryParse(json['backendStatus']) : null),
      orderType: json['orderType'],
      tableId: json['tableId'] is int ? json['tableId'] : (json['tableId'] is String ? int.tryParse(json['tableId']) : null),
    );
  }
}
