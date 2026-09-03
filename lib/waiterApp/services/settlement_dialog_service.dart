import 'dart:async';

import '../models.dart';

class SettlementDialogService {
  SettlementDialogService._();

  static final SettlementDialogService instance = SettlementDialogService._();

  final StreamController<Order> _controller = StreamController<Order>.broadcast();

  Stream<Order> get events => _controller.stream;

  void emit(Order order) {
    _controller.add(order);
  }
}

