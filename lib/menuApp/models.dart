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

int? normalizeBackendStatus(int? status) {
  if (status == 1 || status == -1) {
    return status;
  }
  return null;
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
    );
  }
}

class CartItem {
  final MenuItem item;
  int quantity;

  CartItem({required this.item, this.quantity = 1});

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
    );
  }
}

class Order {
  final String id;
  final List<CartItem> items;
  final double totalPrice;
  final DateTime orderTime;
  final int? orderId; // Backend order ID from API
  final int? backendStatus; // 1=SETTLED, -1=CANCELLED, null=ACTIVE
  final String? orderType; // Order type (DINE_IN, TAKE_OUT, etc.)
  final int? tableId; // Table ID if it's a table order

  Order({
    required this.id,
    required this.items,
    required this.totalPrice,
    required this.orderTime,
    this.orderId,
    this.backendStatus,
    this.orderType,
    this.tableId,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'items': items.map((item) => item.toJson()).toList(),
      'totalPrice': totalPrice,
      'orderTime': orderTime.toIso8601String(),
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
      backendStatus: json['backendStatus'] is int ? json['backendStatus'] : (json['backendStatus'] is String ? int.tryParse(json['backendStatus']) : null),
      orderType: json['orderType'],
      tableId: json['tableId'] is int ? json['tableId'] : (json['tableId'] is String ? int.tryParse(json['tableId']) : null),
    );
  }
}
