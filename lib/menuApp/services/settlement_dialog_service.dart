import 'dart:async';

import '../models.dart';

class SettlementDialogService {
  SettlementDialogService._();

  static final SettlementDialogService instance = SettlementDialogService._();

  final StreamController<Order> _controller = StreamController<Order>.broadcast();
  final StreamController<Order> _dismissedController =
      StreamController<Order>.broadcast();

  Stream<Order> get events => _controller.stream;
  Stream<Order> get dismissed => _dismissedController.stream;

  void emit(Order order) {
    _controller.add(order);
  }

  void emitDismissed(Order order) {
    _dismissedController.add(order);
  }
}

