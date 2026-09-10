import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class SocketService {
  static IO.Socket? _socket;
  static bool _isConnected = false;
  static final Set<int> _desiredOrderRooms = <int>{};
  static bool _shouldBeInCashier = false;
  static bool _shouldBeInWaiter = false;
  static bool _shouldBeInKitchen = false;

  // This client's branch id — sent with every join_* so the backend can keep
  // each branch's realtime traffic in its own room. Loaded lazily from prefs.
  static int? _branchId;
  static bool _branchIdLoaded = false;

  static Future<int?> _ensureBranchId() async {
    if (!_branchIdLoaded) {
      _branchId = await ApiService.getBranchId();
      _branchIdLoaded = true;
    }
    return _branchId;
  }

  /// This client's branch id (null until loaded / for multi-branch accounts).
  static int? get branchId => _branchId;

  // Event listeners live here, independent of the underlying IO.Socket
  // instance, so they survive a hard reset (see below) instead of going
  // silent because they were bound to a socket object we just threw away.
  static final List<Function(Map<String, dynamic>)> _orderUpdatedListeners = [];
  static final List<Function(Map<String, dynamic>)> _orderCreatedListeners = [];
  static final List<Function(Map<String, dynamic>)> _orderItemsAddedListeners = [];
  static final List<Function(Map<String, dynamic>)> _tableUpdatedListeners = [];

  // Some networks/devices never complete the socket.io handshake (corporate
  // wifi, MDM-managed tablets, a wedged internal connection pool, ...) and the
  // package's own reconnection loop just keeps retrying the same broken
  // socket object forever. After a run of consecutive failures we throw the
  // whole IO.Socket away and build a fresh one — this is what manually
  // logging out and back in was doing by accident; now it happens on its own.
  static int _consecutiveErrors = 0;
  static const int _hardResetThreshold = 4;

  // Get socket instance
  static IO.Socket? get socket => _socket;

  // Check if connected
  static bool get isConnected => _isConnected;

  // Initialize socket connection
  static Future<void> initialize() async {
    if (_socket != null) {
      // Socket already created — don't spin up a second one, just make sure
      // it's (re)connecting.
      if (!_isConnected) _socket!.connect();
      return;
    }

    try {
      await _ensureBranchId();
      // Get base URL from ApiService
      final baseUrl = await ApiService.baseUrl;

      // Same origin as the API. Uri.origin keeps a non-default port (e.g. the
      // local :2000 backend) but drops :80/:443, which some HTTPS reverse
      // proxies reject on the socket.io handshake.
      final uri = Uri.parse(baseUrl);
      final socketUrl = uri.origin;

      debugPrint('[SOCKET] Connecting to: $socketUrl');

      _socket = IO.io(
        socketUrl,
        IO.OptionBuilder()
            // Polling first: the HTTP handshake works through any reverse
            // proxy, then socket.io upgrades to websocket where the proxy
            // forwards the Upgrade header. Websocket-first stalls with a
            // timeout when the proxy doesn't.
            .setTransports(['polling', 'websocket'])
            .enableReconnection()
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(10000)
            .setTimeout(20000)
            .enableAutoConnect()
            .build(),
      );

      _bindEventForwarding();

      // Connection event handlers
      _socket!.onConnect((_) {
        _isConnected = true;
        _consecutiveErrors = 0;
        debugPrint('[SOCKET] Connected: ${_socket!.id}');

        // Re-join role rooms after (re)connect, scoped to this branch.
        if (_shouldBeInCashier) {
          _socket!.emit('join_cashier', _branchId);
          debugPrint('[SOCKET] Re-joined cashier room (branch $_branchId)');
        }
        if (_shouldBeInWaiter) {
          _socket!.emit('join_waiter', _branchId);
          debugPrint('[SOCKET] Re-joined waiter room (branch $_branchId)');
        }
        if (_shouldBeInKitchen) {
          _socket!.emit('join_kitchen', _branchId);
          debugPrint('[SOCKET] Re-joined kitchen room (branch $_branchId)');
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
        _consecutiveErrors++;
        debugPrint('[SOCKET] Connection error: $error (attempt $_consecutiveErrors)');
        _maybeHardReset();
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

  /// After enough consecutive failures, rebuild the socket from scratch
  /// instead of trusting the package's built-in reconnection to eventually
  /// recover a wedged connection. Registered event listeners are unaffected —
  /// they live in our own lists, not on the socket object.
  static void _maybeHardReset() {
    if (_consecutiveErrors < _hardResetThreshold) return;
    debugPrint('[SOCKET] $_consecutiveErrors consecutive failures — rebuilding socket');
    _consecutiveErrors = 0;
    final old = _socket;
    _socket = null;
    _isConnected = false;
    try {
      old?.dispose();
    } catch (_) {}
    initialize();
  }

  static void _bindEventForwarding() {
    if (_socket == null) return;
    _socket!.on('order_updated', (data) => _forward(_orderUpdatedListeners, data));
    _socket!.on('order_created', (data) => _forward(_orderCreatedListeners, data));
    _socket!.on('order_items_added', (data) => _forward(_orderItemsAddedListeners, data));
    _socket!.on('table_updated', (data) => _forward(_tableUpdatedListeners, data));
  }

  static void _forward(List<Function(Map<String, dynamic>)> listeners, dynamic data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    // Copy the list — a listener could unsubscribe itself mid-iteration.
    for (final callback in List<Function(Map<String, dynamic>)>.from(listeners)) {
      callback(map);
    }
  }

  // Join cashier room
  static void joinCashier() {
    _shouldBeInCashier = true;
    if (_socket == null) {
      initialize();
      return;
    }
    if (_isConnected) {
      _socket!.emit('join_cashier', _branchId);
      debugPrint('[SOCKET] Joined cashier room (branch $_branchId)');
    }
  }

  // Leave cashier room
  static void leaveCashier() {
    _shouldBeInCashier = false;
    if (_socket == null || !_isConnected) return;
    _socket!.emit('leave_cashier', _branchId);
    debugPrint('[SOCKET] Left cashier room');
  }

  // Join waiter room
  static void joinWaiter() {
    _shouldBeInWaiter = true;
    if (_socket == null) {
      initialize();
      return;
    }
    if (_isConnected) {
      _socket!.emit('join_waiter', _branchId);
      debugPrint('[SOCKET] Joined waiter room (branch $_branchId)');
    }
  }

  // Leave waiter room
  static void leaveWaiter() {
    _shouldBeInWaiter = false;
    if (_socket == null || !_isConnected) return;
    _socket!.emit('leave_waiter', _branchId);
    debugPrint('[SOCKET] Left waiter room');
  }

  // Join kitchen room
  static void joinKitchen() {
    _shouldBeInKitchen = true;
    if (_socket == null) {
      initialize();
      return;
    }
    if (_isConnected) {
      _socket!.emit('join_kitchen', _branchId);
      debugPrint('[SOCKET] Joined kitchen room (branch $_branchId)');
    }
  }

  // Leave kitchen room
  static void leaveKitchen() {
    _shouldBeInKitchen = false;
    if (_socket == null || !_isConnected) return;
    _socket!.emit('leave_kitchen', _branchId);
    debugPrint('[SOCKET] Left kitchen room');
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

  // Add listener for order_updated; returns disposer
  static VoidCallback addOrderUpdateListener(Function(Map<String, dynamic>) callback) {
    _orderUpdatedListeners.add(callback);
    return () => _orderUpdatedListeners.remove(callback);
  }

  // Add listener for order_created; returns disposer
  static VoidCallback addOrderCreatedListener(Function(Map<String, dynamic>) callback) {
    _orderCreatedListeners.add(callback);
    return () => _orderCreatedListeners.remove(callback);
  }

  // Add listener for order_items_added; returns disposer
  static VoidCallback addOrderItemsAddedListener(Function(Map<String, dynamic>) callback) {
    _orderItemsAddedListeners.add(callback);
    return () => _orderItemsAddedListeners.remove(callback);
  }

  // Add listener for table_updated; returns disposer
  static VoidCallback addTableUpdateListener(Function(Map<String, dynamic>) callback) {
    _tableUpdatedListeners.add(callback);
    return () => _tableUpdatedListeners.remove(callback);
  }

  /// Full reset — called on logout so a fresh login always starts a brand new
  /// socket (and reloads branch id fresh) rather than reusing whatever state
  /// this static singleton was left in.
  static void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }
    _isConnected = false;
    _consecutiveErrors = 0;
    _desiredOrderRooms.clear();
    _shouldBeInCashier = false;
    _shouldBeInWaiter = false;
    _shouldBeInKitchen = false;
    _branchId = null;
    _branchIdLoaded = false;
    debugPrint('[SOCKET] Disconnected and disposed');
  }
}
