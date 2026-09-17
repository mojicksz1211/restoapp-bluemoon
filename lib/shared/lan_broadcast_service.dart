import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// LAN-local fallback for real-time order notifications when the cloud
/// backend is unreachable but the tablets are still on the same WiFi (the
/// two are different things — internet can drop while the local network
/// stays up). Broadcasts a plain UDP packet to the subnet whenever an order
/// is created/updated offline; every other tablet listening picks it up
/// directly, with no server involved.
///
/// Deliberately shaped like [SocketService] (same `addXListener`/disposer
/// pattern, same payload shape) so a LAN event can be fed straight into the
/// exact same `_handleSocketOrderEvent` handlers each app already has for
/// real socket events — no separate alert/dedup/branch-filter logic needed.
///
/// Uses `dart:io`'s `RawDatagramSocket` directly — UDP broadcast needs no
/// extra package. Sent to the standard "limited broadcast" address
/// (255.255.255.255) so there's no need to compute the device's actual
/// subnet either.
class LanBroadcastService {
  LanBroadcastService._();
  static final LanBroadcastService instance = LanBroadcastService._();

  // Arbitrary fixed app-specific port. `_magic` guards against parsing
  // unrelated UDP traffic that happens to land on the same port — this is
  // a noise filter, not authentication; see the offline-mode plan's "Known
  // limitations" for why that's an acceptable tradeoff here.
  static const int _port = 47872;
  static const String _magic = 'bluemoon_resto_lan_v1';

  RawDatagramSocket? _socket;
  bool _initializing = false;

  final List<void Function(Map<String, dynamic>)> _orderCreatedListeners = [];
  final List<void Function(Map<String, dynamic>)> _orderItemsAddedListeners = [];

  Future<void> initialize() async {
    // Raw UDP sockets aren't available on Flutter Web (dart:io throws
    // UnsupportedError at runtime there) — this fallback is Android/iOS
    // tablet-only by nature anyway, so just no-op rather than logging a
    // bind failure on every web launch.
    if (kIsWeb) return;
    if (_socket != null || _initializing) return;
    _initializing = true;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port, reuseAddress: true);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        _handleDatagram(datagram.data);
      });
      _socket = socket;
      final targets = await _broadcastTargets();
      debugPrint('[LAN BROADCAST] Listening on UDP port $_port. Broadcast targets: $targets');
    } catch (e) {
      // Most likely another process already bound the port, or the platform
      // doesn't support it. Not fatal — this is a best-effort fallback on
      // top of the cloud socket, not a required capability.
      debugPrint('[LAN BROADCAST] Failed to bind: $e');
    } finally {
      _initializing = false;
    }
  }

  void _handleDatagram(List<int> bytes) {
    debugPrint('[LAN BROADCAST] Received ${bytes.length} byte datagram');
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || decoded['magic'] != _magic) {
        debugPrint('[LAN BROADCAST] Ignored datagram (not ours or malformed)');
        return;
      }
      final data = Map<String, dynamic>.from(decoded);
      switch (data['type']) {
        case 'order_created':
          for (final cb in List.of(_orderCreatedListeners)) {
            cb(data);
          }
          break;
        case 'order_items_added':
          for (final cb in List.of(_orderItemsAddedListeners)) {
            cb(data);
          }
          break;
      }
    } catch (e) {
      debugPrint('[LAN BROADCAST] Failed to parse incoming datagram: $e');
    }
  }

  // Plain UDP broadcast has no delivery guarantee, and WiFi broadcast frames
  // in particular are more prone to being dropped than unicast (lower PHY
  // rate, no retry at the radio level, easy for a busy AP to deprioritize).
  // Firing the same packet a few times a beat apart costs almost nothing and
  // meaningfully raises the odds at least one copy lands — the receiving
  // side's existing dedup (an order already in `_orders` doesn't re-alert)
  // makes redelivery harmless.
  // Kept modest — each attempt fans out to every _broadcastTargets() address,
  // so this multiplies total packets sent. Combined with periodic
  // re-announcement (see OfflineSyncService's rebroadcast timer) across
  // several queued orders, a higher value here was observed producing a
  // sustained packet burst that a WiFi AP silently throttled under load.
  static const int _sendAttempts = 2;
  static const Duration _sendGap = Duration(milliseconds: 200);

  /// Every address worth broadcasting to: the standard "limited broadcast"
  /// (255.255.255.255) plus the actual subnet broadcast address of each
  /// WiFi/LAN interface (e.g. 192.168.1.255). Some Android network stacks
  /// handle one more reliably than the other, so this sends to both rather
  /// than guessing which — cheap, since it's still just a handful of local
  /// UDP sends. Assumes a /24 subnet (true for the overwhelming majority of
  /// home/small-business routers); a wrong guess here is harmless, it just
  /// reaches no one, same as not sending it at all.
  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String, InternetAddress>{
      '255.255.255.255': InternetAddress('255.255.255.255'),
    };
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            targets[subnetBroadcast] = InternetAddress(subnetBroadcast);
          }
        }
      }
    } catch (e) {
      debugPrint('[LAN BROADCAST] Failed to enumerate network interfaces: $e');
    }
    return targets.values.toList();
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    if (kIsWeb) return;
    final socket = _socket;
    if (socket == null) {
      debugPrint('[LAN BROADCAST] Not sending "${payload['type']}" — socket never bound.');
      return;
    }
    try {
      final targets = await _broadcastTargets();
      final bytes = utf8.encode(jsonEncode({'magic': _magic, ...payload}));
      debugPrint('[LAN BROADCAST] Sending "${payload['type']}" to $targets ($_sendAttempts attempts each)');
      for (var attempt = 0; attempt < _sendAttempts; attempt++) {
        if (attempt > 0) await Future.delayed(_sendGap);
        for (final target in targets) {
          socket.send(bytes, target, _port);
        }
      }
    } catch (e) {
      // Broadcasting is best-effort — a device with no WiFi at all (e.g.
      // fully airplane-mode) will fail here, which is fine, it just means
      // no peer could have received it either.
      debugPrint('[LAN BROADCAST] Failed to send: $e');
    }
  }

  Future<void> broadcastOrderCreated(Map<String, dynamic> payload) =>
      _send({'type': 'order_created', ...payload});

  Future<void> broadcastOrderItemsAdded(Map<String, dynamic> payload) =>
      _send({'type': 'order_items_added', ...payload});

  VoidCallback addOrderCreatedListener(void Function(Map<String, dynamic>) callback) {
    _orderCreatedListeners.add(callback);
    return () => _orderCreatedListeners.remove(callback);
  }

  VoidCallback addOrderItemsAddedListener(void Function(Map<String, dynamic>) callback) {
    _orderItemsAddedListeners.add(callback);
    return () => _orderItemsAddedListeners.remove(callback);
  }

  void dispose() {
    _socket?.close();
    _socket = null;
  }
}
