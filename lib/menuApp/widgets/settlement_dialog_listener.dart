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
  BuildContext? _context;

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

    // Use currentContext from navigatorKey (has proper MaterialLocalizations)
    // Fallback to stored context if currentContext is not available
    final context = widget.navigatorKey.currentContext ?? _context;
    if (context == null || !mounted) {
      _isDialogShowing = false;
      return;
    }

    // Use SchedulerBinding to ensure we're in the right frame
    await Future.delayed(Duration.zero);
    
    if (!mounted) {
      _isDialogShowing = false;
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        return SettlementDialog(
          order: order,
          onDismiss: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
        );
      },
    );

    if (mounted) {
      _isDialogShowing = false;
    }

    SettlementDialogService.instance.emitDismissed(order);
  }

  @override
  Widget build(BuildContext context) {
    // Store context for dialog usage
    _context = context;
    return widget.child;
  }
}

