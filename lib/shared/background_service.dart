import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../waiterApp/services/socket_service.dart';
import '../waiterApp/services/api_service.dart';
import '../waiterApp/waiter_models.dart';
import 'lan_broadcast_service.dart';
import 'offline_sync_service.dart';

/// Bridges an alert fired by the background isolate to the foreground UI —
/// the two are completely separate Dart isolates with no shared memory, so
/// there's no direct way for cashierApp's home page to know "the background
/// service already rang the wake alert for order X, show your own popup+TTS
/// for it now that the app is open." SharedPreferences is the one thing both
/// isolates can actually see. Written by the background isolate right after
/// it shows the ringtone notification; read (and cleared) by cashierApp on
/// every load so the requested flow — ringtone first while backgrounded,
/// then the normal in-app modal+TTS once the app is opened — actually happens
/// instead of the order just silently appearing with no second alert.
class PendingForegroundAlerts {
  PendingForegroundAlerts._();

  static const String _prefsKey = 'pending_foreground_alert_order_ids';

  static Future<void> add(int orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_prefsKey) ?? <String>[];
    final ids = current.toSet()..add(orderId.toString());
    await prefs.setStringList(_prefsKey, ids.toList());
  }

  /// Returns every pending order id and clears the list in the same call —
  /// callers should treat this as "I'm handling these now", not a peek.
  static Future<Set<int>> takeAll() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_prefsKey) ?? <String>[];
    if (current.isNotEmpty) {
      await prefs.remove(_prefsKey);
    }
    return current.map((s) => int.tryParse(s)).whereType<int>().toSet();
  }
}

/// Thin wrapper around the native battery-optimization-exemption channel
/// (`MainActivity.kt`) — smaller footprint than pulling in a whole permission
/// plugin for one system intent.
class BatteryOptimizationHelper {
  BatteryOptimizationHelper._();

  static const MethodChannel _channel = MethodChannel('com.bluemoon.restoapp/battery');

  /// Whether the app is already exempt from Android's battery optimization.
  /// Android-only; returns true elsewhere so callers don't gate on it.
  static Future<bool> isExempt() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (e) {
      debugPrint('[BATTERY] Failed to check exemption status: $e');
      return false;
    }
  }

  /// Shows the system "ignore battery optimizations" dialog if not already
  /// exempt. No-op on non-Android platforms.
  static Future<void> requestExemption() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('[BATTERY] Failed to request exemption: $e');
    }
  }
}

/// Keeps waiterApp/cashierApp listening for new orders via a real Android
/// foreground service, so alerts still arrive after the app is minimized,
/// swiped from recents, or the screen is off — Socket.IO/LAN listeners in
/// the normal UI isolate stop running the moment Android suspends/kills that
/// isolate, which a foreground service (with its own separate background
/// isolate) is specifically exempt from under Android's background-execution
/// limits.
///
/// Stage 1 only proves the service itself survives — starts, keeps running
/// after the app is swiped away, and can be stopped on logout. It does not
/// yet listen for orders (that's Stage 2) or show the full-screen wake alert
/// (Stage 3).
class BackgroundServiceManager {
  BackgroundServiceManager._();

  static bool _configured = false;

  /// Registers the service configuration. Safe to call multiple times (e.g.
  /// once from main() and defensively again from a home page's initState) —
  /// only the first call actually configures anything.
  static Future<void> initializeAndConfigure() async {
    if (_configured) return;
    _configured = true;

    // The notification channel referenced by AndroidConfiguration below
    // MUST already exist before configure() runs — startForeground() throws
    // CannotPostForegroundServiceNotificationException ("Bad notification")
    // on a channel id Android has never seen, which crash-loops the app.
    // Don't rely on NotificationService.initialize() having already run
    // elsewhere — initialize this plugin instance explicitly too.
    final localNotifications = FlutterLocalNotificationsPlugin();
    await localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    const channel = AndroidNotificationChannel(
      'resto_background_service',
      'Background Service',
      description: 'Keeps listening for new orders while the app is minimized.',
      importance: Importance.low,
    );
    // Separate, high-importance channel for the full-screen wake alert
    // (cashier only) — must exist before first use for the same reason as
    // above, and kept distinct from 'new_orders_channel' since Android
    // freezes a channel's importance/behavior (including sound) after first
    // creation. "_v2" so devices that already created the plain-sound v1
    // channel actually pick up the new ringtone instead of silently keeping
    // the old channel's settings forever.
    const fullScreenChannel = AndroidNotificationChannel(
      'order_alerts_fullscreen_channel_v2',
      'New Order Alerts',
      description: 'Wakes the screen and shows new orders even when the app is closed.',
      importance: Importance.max,
      sound: UriAndroidNotificationSound('content://settings/system/ringtone'),
      playSound: true,
      enableVibration: true,
    );
    final androidPlugin = localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.createNotificationChannel(fullScreenChannel);

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onServiceStart,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: 'resto_background_service',
        initialNotificationTitle: 'Blue Moon Resto',
        initialNotificationContent: 'Waiting for new orders',
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  /// Starts the service if it isn't already running. Call once a user is
  /// actually logged in as waiter/cashier — the service itself also checks
  /// stored login state before doing anything (see Stage 2), but there's no
  /// reason to spin it up at all before that.
  static Future<void> ensureStarted() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await initializeAndConfigure();
        final service = FlutterBackgroundService();
        if (!await service.isRunning()) {
          await service.startService();
        }
      } catch (e) {
        debugPrint('[BG SERVICE] Failed to start: $e');
      }
    }
  }

  /// Tells the background isolate whether the UI is currently visible, so
  /// its wake-alert banner only fires when the app genuinely can't show its
  /// own in-app popup (backgrounded/swiped, or screen off while open).
  /// `flutter_background_service` has no web implementation at all — an
  /// unguarded call throws there — so this stays a plain no-op off Android,
  /// same guard as ensureStarted()/stop() above.
  static void reportUiForeground(bool foreground) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        FlutterBackgroundService().invoke('ui_lifecycle', {'foreground': foreground});
      } catch (e) {
        debugPrint('[BG SERVICE] Failed to report UI lifecycle: $e');
      }
    }
  }

  /// Stops the service — call on logout so a signed-out device doesn't keep
  /// a foreground notification/socket connection alive for no one.
  static Future<void> stop() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (await FlutterBackgroundService().isRunning()) {
          FlutterBackgroundService().invoke('stopService');
        }
      } catch (e) {
        debugPrint('[BG SERVICE] Failed to stop: $e');
      }
    }
  }
}

/// Runs in its own background isolate (a second, headless Flutter engine) —
/// must be a top-level or static function per the plugin's requirement.
/// `SocketService`/`LanBroadcastService` are pure static-member classes with
/// no `BuildContext` dependency, so importing and using them here gets this
/// isolate its own independent connection, entirely separate from whatever
/// the UI isolate is doing — no changes needed to either service file.
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  try {
    await _runService(service);
  } catch (e, st) {
    // Nothing upstream catches an uncaught error in a background isolate's
    // entrypoint — it silently kills the isolate with zero log output,
    // which is exactly what happened before this try/catch existed (the
    // heartbeat below never got a chance to start). Always log instead.
    debugPrint('[BG SERVICE] Fatal error during setup: $e\n$st');
  }
}

/// A plugin instance scoped to this isolate, used only to show the new-order
/// notification — deliberately NOT `NotificationService.initialize()` (that
/// also calls `requestNotificationsPermission()`, which needs a live
/// Activity; calling it from this headless background isolate throws and
/// silently kills the whole isolate before the heartbeat even starts). The
/// permission is already granted or denied at the OS level from whenever the
/// user first opened the app normally — nothing to (re)request here.
final _backgroundNotifications = FlutterLocalNotificationsPlugin();

/// Cashier-only — wakes the screen and shows the alert even over the lock
/// screen, like an incoming-call UI (MainActivity has
/// android:showWhenLocked/turnScreenOn set, so the Activity this notification
/// launches draws over the lock screen automatically). Requires
/// USE_FULL_SCREEN_INTENT (declared in the manifest) and, on Android 13+,
/// the user having that permission enabled — falls back to a normal
/// heads-up notification if the system won't allow a full-screen intent.
// Whether the foreground UI is currently visible/resumed — reported by
// cashierApp/home_page.dart via a WidgetsBindingObserver over the
// 'ui_lifecycle' bridge (see PendingForegroundAlerts for why a bridge is
// needed at all: separate isolates, no shared memory). Defaults to false so
// a cold-started service (app not open at all) still alerts. Flutter's own
// AppLifecycleState already goes non-resumed both when the app is
// backgrounded/swiped AND when the screen turns off while the app is open —
// one flag correctly covers both cases the user wants the banner to skip.
bool _isUiForeground = false;

Future<void> _showBackgroundOrderNotification({
  required String orderNo,
  String? tableNumber,
}) async {
  if (_isUiForeground) {
    debugPrint('[BG SERVICE] UI is foreground — skipping banner (in-app alert already covers it).');
    return;
  }
  // No API in this plugin version to check full-screen-intent permission
  // state ahead of time — just request fullScreenIntent:true and let
  // Android degrade to a normal heads-up notification on its own if the
  // permission isn't granted (Android 14+ may require the user to enable
  // "Full screen notifications" for this app once, in system settings).
  const androidDetails = AndroidNotificationDetails(
    'order_alerts_fullscreen_channel_v2',
    'New Order Alerts',
    channelDescription: 'Wakes the screen and shows new orders even when the app is closed.',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    visibility: NotificationVisibility.public,
    fullScreenIntent: true,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    sound: UriAndroidNotificationSound('content://settings/system/ringtone'),
  );
  await _backgroundNotifications.show(
    id: orderNo.hashCode,
    title: 'New Order Received!',
    body: tableNumber != null ? '$orderNo • Table $tableNumber' : orderNo,
    notificationDetails: NotificationDetails(android: androidDetails),
    payload: orderNo,
  );
}

Future<void> _runService(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('ui_lifecycle').listen((event) {
    _isUiForeground = event?['foreground'] == true;
    debugPrint('[BG SERVICE] UI foreground state: $_isUiForeground');
  });

  await _backgroundNotifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
  final role = (prefs.getString('role') ?? '').toLowerCase();
  final permissionId = int.tryParse(prefs.getString('permissions') ?? '');
  final userId = prefs.getString('user_id');

  final isCashier = permissionId == 15 || role.contains('cashier');
  final isWaiter = permissionId == 14 || role.contains('waiter');

  if (!isLoggedIn || (!isCashier && !isWaiter)) {
    debugPrint('[BG SERVICE] Not logged in as waiter/cashier — stopping.');
    await service.stopSelf();
    return;
  }

  if (isCashier) {
    SocketService.joinCashier();
  } else {
    SocketService.joinWaiter();
  }
  try {
    await LanBroadcastService.instance.initialize();
  } catch (e) {
    debugPrint('[BG SERVICE] LanBroadcastService init error: $e');
  }

  // Per-order dedup, scoped to this isolate's lifetime (matches the pattern
  // already used in each app's foreground alert handlers).
  final alertedOrderIds = <int>{};
  final lastAlertedQty = <int, double>{};

  Map<String, dynamic> orderPayload(Map<String, dynamic> data) {
    final order = data['order'];
    return order is Map ? Map<String, dynamic>.from(order) : data;
  }

  int? orderIdOf(Map<String, dynamic> orderData) {
    final raw = orderData['order_id'] ?? orderData['IDNo'] ?? orderData['id'];
    return raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  }

  double sumQty(Map<String, dynamic> orderData) {
    final items = orderData['items'];
    double qty = 0;
    if (items is List) {
      for (final item in items) {
        if (item is Map) qty += (item['qty'] as num?)?.toDouble() ?? 0;
      }
    }
    return qty;
  }

  // The OS only auto-launches a fullScreenIntent notification's Activity
  // when the screen is off/locked — by design, Android refuses to do that
  // while the screen is already on and unlocked (a heads-up banner shows
  // instead, requiring a tap), to stop apps stealing focus from whatever
  // the user is doing. openApp() is the one thing this plugin exposes that
  // can still try to bring the app forward in that "swiped away, screen
  // still on" case — but it's still subject to Android's own background-
  // activity-launch restrictions, so it isn't guaranteed on every OEM/
  // Android version the way the screen-off path is.
  Future<void> tryOpenApp() async {
    if (service is AndroidServiceInstance) {
      try {
        final opened = await service.openApp();
        debugPrint('[BG SERVICE] openApp() -> $opened');
      } catch (e) {
        debugPrint('[BG SERVICE] openApp() failed: $e');
      }
    }
  }

  void handleOrderCreated(Map<String, dynamic> data, String source) {
    // New-order alerts are cashier-only — waiterApp used to alert on other
    // waiters' new orders too, but that's explicitly not wanted for this
    // background/wake-alert path (and the REST-poll source below has no
    // reliable self-order check, which was firing this on a waiter's own
    // just-placed order).
    if (!isCashier) return;
    final orderData = orderPayload(data);
    final orderId = orderIdOf(orderData);
    if (orderId == null) return;
    // The foreground UI does this for every LAN-received order so its own
    // offline order list (and this same handoff, once the app reopens) can
    // see it — the background isolate never did, so a purely offline/LAN
    // order would ring the wake alert but then vanish once _loadData() ran
    // its offline fallback and found no trace of it in the shared cache.
    // POLL is excluded: its payload is a minimal synthetic map (id/order_no/
    // table_number/qty only, no table_id/status/full items) built just for
    // the notification text and qty-diff check — caching that would corrupt
    // the shared order cache with an incomplete record. A successful poll
    // also means real internet is up, so the foreground's own fetch will
    // pick this order up directly once opened; no cache workaround needed.
    if (source != 'POLL') {
      unawaited(OfflineSyncService.instance.upsertCachedOrder(orderData));
    }
    final encodedBy = (orderData['encoded_by'] ?? data['encoded_by'])?.toString();
    if (encodedBy != null && userId != null && encodedBy == userId) return; // self-placed
    if (!alertedOrderIds.add(orderId)) return; // already alerted this run
    // Seed the qty baseline now — without this, the next poll tick sees
    // lastAlertedQty[orderId] as unset (null), which never equals the
    // order's real quantity, so it always looked like items were just added
    // and fired a spurious second alert ~15s after every single new order.
    lastAlertedQty[orderId] = sumQty(orderData);
    debugPrint('[BG-$source] order_created — alerting for order $orderId');
    final orderNo = (orderData['order_no'] ?? 'Order #$orderId').toString();
    final tableNumber = orderData['table_number']?.toString();
    if (!_isUiForeground) {
      _showBackgroundOrderNotification(orderNo: orderNo, tableNumber: tableNumber);
      unawaited(PendingForegroundAlerts.add(orderId));
      unawaited(tryOpenApp());
    }
  }

  // waiterApp never alerts on items-added (only a brand-new pending order) —
  // mirrored here so the background isolate matches the foreground behavior
  // exactly. Only cashierApp registers this listener below.
  void handleItemsAdded(Map<String, dynamic> data, String source) {
    final orderData = orderPayload(data);
    final orderId = orderIdOf(orderData);
    if (orderId == null) return;
    if (source != 'POLL') {
      unawaited(OfflineSyncService.instance.upsertCachedOrder(orderData));
    }
    final qty = sumQty(orderData);
    if (lastAlertedQty[orderId] == qty) return; // no real change since last alert
    lastAlertedQty[orderId] = qty;
    debugPrint('[BG-$source] order_items_added — alerting for order $orderId');
    final orderNo = (orderData['order_no'] ?? 'Order #$orderId').toString();
    final tableNumber = orderData['table_number']?.toString();
    if (!_isUiForeground) {
      _showBackgroundOrderNotification(orderNo: orderNo, tableNumber: tableNumber);
      unawaited(PendingForegroundAlerts.add(orderId));
      unawaited(tryOpenApp());
    }
  }

  if (isCashier) {
    SocketService.addOrderCreatedListener((data) => handleOrderCreated(data, 'SOCKET'));
    SocketService.addOrderItemsAddedListener((data) => handleItemsAdded(data, 'SOCKET'));
    // LAN-broadcast alerts are cashier-only, matching cashierApp's
    // foreground behavior — waiterApp's LAN listeners pass allowAlert:false.
    LanBroadcastService.instance.addOrderCreatedListener((data) => handleOrderCreated(data, 'LAN'));
    LanBroadcastService.instance.addOrderItemsAddedListener((data) => handleItemsAdded(data, 'LAN'));
  }

  // REST-poll fallback — the socket has repeatedly proven unreliable in real
  // testing (this test site's connection to the cloud backend times out
  // often), and an order placed while the socket is down would otherwise
  // have no way to reach a backgrounded/killed app at all. Mirrors the
  // foreground UI's own poll fallback (_applyFreshOrders): skip alerting on
  // the very first snapshot (everything looks "new" then), then treat a
  // previously-unseen order id as order_created and a growing item count on
  // an already-known order as order_items_added. Self-order filtering is
  // skipped here (the REST order list has no reliable raw encoded_by field
  // to compare against, only a display name) — same tradeoff the existing
  // foreground poll fallback already accepts.
  bool hasPolledOnce = false;
  Future<void> pollForOrders() async {
    try {
      final result = await ApiService.getWaiterOrders();
      if (result['success'] != true) return;
      final ordersData = List<Map<String, dynamic>>.from(result['data'] ?? []);
      for (final orderJson in ordersData) {
        final order = WaiterOrder.fromApi(orderJson);
        if (order.status != 2 && order.status != 3) continue;
        final wasKnown = alertedOrderIds.contains(order.id);
        if (!hasPolledOnce) {
          alertedOrderIds.add(order.id);
          continue;
        }
        final payload = {
          'order_id': order.id,
          'order_no': order.orderNo,
          'table_number': order.tableNumber,
          'items': order.items.map((it) => {'qty': it.quantity}).toList(),
        };
        if (!wasKnown) {
          handleOrderCreated(payload, 'POLL');
        } else if (isCashier) {
          handleItemsAdded(payload, 'POLL');
        }
      }
      hasPolledOnce = true;
    } catch (e) {
      debugPrint('[BG-POLL] Error polling for orders: $e');
    }
  }

  unawaited(pollForOrders());
  Timer.periodic(const Duration(seconds: 15), (timer) => pollForOrders());

  Timer.periodic(const Duration(seconds: 20), (timer) {
    debugPrint('[BG SERVICE] heartbeat — still alive at ${DateTime.now()}');
  });
}
