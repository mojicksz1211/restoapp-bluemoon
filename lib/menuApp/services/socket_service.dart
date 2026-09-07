import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class SocketService {
  static IO.Socket? _socket;
  static bool _isConnected = false;
  static final Set<int> _desiredOrderRooms = <int>{};
  static bool _shouldBeInKitchen = false;
  static bool _shouldBeInCashier = false;
  static bool _shouldBeInWaiter = false;

  // Get socket instance
  static IO.Socket? get socket => _socket;

  // Check if connected
  static bool get isConnected => _isConnected;

  // Initialize socket connection
  static Future<void> initialize() async {
    if (_socket != null && _isConnected) {
      // Already connected, no need to re-initialize
      return;
    }

    try {
      // Get base URL from ApiService
      final baseUrl = await ApiService.baseUrl;
      
      // Parse URL to get host and port
      final uri = Uri.parse(baseUrl);
      // Socket.io typically uses the same host but may need explicit port
      // For HTTPS, use wss://, for HTTP use ws://
      final scheme = uri.scheme == 'https' ? 'https' : 'http';
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socketUrl = '$scheme://${uri.host}:$port';

      debugPrint('[SOCKET] Connecting to: $socketUrl');

      _socket = IO.io(
        socketUrl,
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .build(),
      );

      // Connection event handlers
      _socket!.onConnect((_) {
        _isConnected = true;
        debugPrint('[SOCKET] Connected: ${_socket!.id}');
        
        // Re-join role rooms if needed
        if (_shouldBeInKitchen) {
          _socket!.emit('join_kitchen');
          debugPrint('[SOCKET] Re-joined kitchen room');
        }
        if (_shouldBeInCashier) {
          _socket!.emit('join_cashier');
          debugPrint('[SOCKET] Re-joined cashier room');
        }
        if (_shouldBeInWaiter) {
          _socket!.emit('join_waiter');
          debugPrint('[SOCKET] Re-joined waiter room');
        }

        // Re-join desired rooms after (re)connect.
        for (final orderId in _desiredOrderRooms) {
          _socket!.emit('join_order', orderId);
          debugPrint('[SOCKET] Joined order room: order_$orderId');
        }
      });

      _socket!.onDisconnect((_) {
        _isConnected = false;
        debugPrint('[SOCKET] Disconnected');
      });

      _socket!.onConnectError((error) {
        _isConnected = false;
        debugPrint('[SOCKET] Connection error: $error');
      });

      _socket!.onError((error) {
        debugPrint('[SOCKET] Error: $error');
      });

      // Wait for connection
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('[SOCKET] Initialization error: $e');
      _isConnected = false;
    }
  }

  // Join order room
  static void joinOrder(int orderId) {
    _desiredOrderRooms.add(orderId);
    if (_socket == null) {
      // Fire and forget; onConnect will re-join desired rooms.
      initialize();
      debugPrint('[SOCKET] Socket not initialized yet, queued join for order_$orderId');
      return;
    }

    if (!_isConnected) {
      debugPrint('[SOCKET] Socket not connected yet, queued join for order_$orderId');
      return;
    }

    _socket!.emit('join_order', orderId);
    debugPrint('[SOCKET] Joined order room: order_$orderId');
  }

  // Leave order room
  static void leaveOrder(int orderId) {
    _desiredOrderRooms.remove(orderId);
    if (_socket == null || !_isConnected) {
      debugPrint('[SOCKET] Cannot leave order: Socket not connected');
      return;
    }

    _socket!.emit('leave_order', orderId);
    debugPrint('[SOCKET] Left order room: order_$orderId');
  }

  // Join kitchen room
  static void joinKitchen() {
    _shouldBeInKitchen = true;
    if (_socket == null) {
      initialize();
      return;
    }
    if (!_isConnected) return;
    _socket!.emit('join_kitchen');
    debugPrint('[SOCKET] Joined kitchen room');
  }

  // Leave kitchen room
  static void leaveKitchen() {
    _shouldBeInKitchen = false;
    if (_socket == null || !_isConnected) return;
    _socket!.emit('leave_kitchen');
    debugPrint('[SOCKET] Left kitchen room');
  }

  // Join cashier room
  static void joinCashier() {
    _shouldBeInCashier = true;
    if (_socket == null) {
      initialize();
      return;
    }
    if (!_isConnected) return;
    _socket!.emit('join_cashier');
    debugPrint('[SOCKET] Joined cashier room');
  }

  // Leave cashier room
  static void leaveCashier() {
    _shouldBeInCashier = false;
    if (_socket == null || !_isConnected) return;
    _socket!.emit('leave_cashier');
    debugPrint('[SOCKET] Left cashier room');
  }

  // Join waiter room
  static void joinWaiter() {
    _shouldBeInWaiter = true;
    if (_socket == null) {
      initialize();
      return;
    }
    if (!_isConnected) return;
    _socket!.emit('join_waiter');
    debugPrint('[SOCKET] Joined waiter room');
  }

  // Leave waiter room
  static void leaveWaiter() {
    _shouldBeInWaiter = false;
    if (_socket == null || !_isConnected) return;
    _socket!.emit('leave_waiter');
    debugPrint('[SOCKET] Left waiter room');
  }

  // Add listener for order_updated; returns disposer
  static VoidCallback addOrderUpdateListener(Function(Map<String, dynamic>) callback) {
    if (_socket == null) {
      debugPrint('[SOCKET] Cannot listen: Socket not initialized');
      return () {};
    }

    void listener(dynamic data) {
      if (data is Map) {
        callback(Map<String, dynamic>.from(data));
      }
    }

    _socket!.on('order_updated', listener);
    return () => _socket?.off('order_updated', listener);
  }

  // Add listener for order_created; returns disposer
  static VoidCallback addOrderCreatedListener(Function(Map<String, dynamic>) callback) {
    if (_socket == null) {
      debugPrint('[SOCKET] Cannot listen: Socket not initialized');
      return () {};
    }

    void listener(dynamic data) {
      if (data is Map) {
        callback(Map<String, dynamic>.from(data));
      }
    }

    _socket!.on('order_created', listener);
    return () => _socket?.off('order_created', listener);
  }

  // Add listener for order_items_added; returns disposer
  static VoidCallback addOrderItemsAddedListener(Function(Map<String, dynamic>) callback) {
    if (_socket == null) {
      debugPrint('[SOCKET] Cannot listen: Socket not initialized');
      return () {};
    }

    void listener(dynamic data) {
      if (data is Map) {
        callback(Map<String, dynamic>.from(data));
      }
    }

    _socket!.on('order_items_added', listener);
    return () => _socket?.off('order_items_added', listener);
  }

  // Disconnect socket
  static void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
      _desiredOrderRooms.clear();
      debugPrint('[SOCKET] Disconnected and disposed');
    }
  }
}

