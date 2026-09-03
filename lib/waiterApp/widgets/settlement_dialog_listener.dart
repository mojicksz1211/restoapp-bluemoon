import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/settlement_dialog_service.dart';
import 'settlement_dialog.dart';

class SettlementDialogListener extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const SettlementDialogListener({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<SettlementDialogListener> createState() => _SettlementDialogListenerState();
}

class _SettlementDialogListenerState extends State<SettlementDialogListener> {
  StreamSubscription<Order>? _subscription;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _subscription = SettlementDialogService.instance.events.listen(_handleEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _handleEvent(Order order) async {
    if (!mounted || _isDialogShowing) return;
    _isDialogShowing = true;

    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) {
      _isDialogShowing = false;
      return;
    }

    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) {
        return SettlementDialog(
          order: order,
          onDismiss: () => Navigator.of(context).pop(),
        );
      },
    );

    if (mounted) {
      _isDialogShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

