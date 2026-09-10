import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';

/// Holds Get Order carts that haven't been placed yet, so a waiter can leave
/// the Get Order screen (Home button, back gesture) — or even close the app —
/// and come back to the same table with the cart still filled in. The Tables
/// dashboard also reads this to flag which tables have a pending order.
///
/// The in-memory map is the source of truth (dashboard reads it synchronously
/// during build); every change is also mirrored to disk via SharedPreferences
/// so it survives the app process being killed. Call [restore] once on startup
/// to pull the saved carts back in.
class WaiterCartStore extends ChangeNotifier {
  WaiterCartStore._();
  static final WaiterCartStore instance = WaiterCartStore._();

  static const String _prefsKey = 'waiter_pending_carts_v1';

  /// A pending cart older than this is treated as abandoned (e.g. left over
  /// from a previous shift) and dropped on [restore] instead of resurfacing.
  static const Duration _maxAge = Duration(hours: 12);

  final Map<String, List<CartItem>> _carts = {};
  final Map<String, DateTime> _savedAt = {};
  bool _restored = false;

  /// A brand-new order for an available table is keyed by the table; an
  /// "additional order" against an existing order is keyed by that order, so
  /// the two never clobber each other.
  static String keyFor({required int tableId, int? existingOrderId}) {
    return existingOrderId != null ? 'order:$existingOrderId' : 'table:$tableId';
  }

  List<CartItem> _copy(List<CartItem> cart) => cart
      .map((ci) => CartItem(item: ci.item, quantity: ci.quantity, remarks: ci.remarks))
      .toList();

  /// A detached copy of the saved cart for [key] (safe to mutate), or an empty
  /// list when nothing is stored.
  List<CartItem> load(String key) {
    final saved = _carts[key];
    return saved == null ? <CartItem>[] : _copy(saved);
  }

  /// Replaces the saved cart for [key]. An empty cart clears the entry.
  void save(String key, List<CartItem> cart) {
    final meaningful = cart.where((ci) => ci.quantity > 0).toList();
    if (meaningful.isEmpty) {
      final removed = _carts.remove(key) != null;
      _savedAt.remove(key);
      if (removed) {
        _flush();
        notifyListeners();
      }
      return;
    }
    _carts[key] = _copy(meaningful);
    _savedAt[key] = DateTime.now();
    _flush();
    notifyListeners();
  }

  void clear(String key) {
    final removed = _carts.remove(key) != null;
    _savedAt.remove(key);
    if (removed) {
      _flush();
      notifyListeners();
    }
  }

  bool hasItems(String key) => _carts[key]?.isNotEmpty ?? false;

  /// Number of pending cart units for an available table's new-order cart
  /// (0 when there is none). Used by the Tables dashboard card badge.
  int pendingItemCountForTable(int tableId) {
    final cart = _carts['table:$tableId'];
    if (cart == null) return 0;
    return cart.fold<int>(0, (sum, ci) => sum + ci.quantity);
  }

  /// Peso value of that same pending new-order cart.
  double pendingTotalForTable(int tableId) {
    final cart = _carts['table:$tableId'];
    if (cart == null) return 0;
    return cart.fold<double>(0, (sum, ci) => sum + ci.item.price * ci.quantity);
  }

  /// Pulls carts saved to disk on a previous run back into memory. Safe to
  /// call more than once — only the first call does any work.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final now = DateTime.now();
      var prunedSomething = false;

      decoded.forEach((dynamic key, dynamic value) {
        if (value is! Map) return;
        final savedAtRaw = value['savedAt'];
        final savedAt =
            savedAtRaw is String ? DateTime.tryParse(savedAtRaw) : null;
        if (savedAt == null || now.difference(savedAt) > _maxAge) {
          prunedSomething = true;
          return;
        }
        final itemsRaw = value['items'];
        if (itemsRaw is! List) return;
        final items = <CartItem>[];
        for (final it in itemsRaw) {
          if (it is Map) {
            try {
              items.add(CartItem.fromJson(Map<String, dynamic>.from(it)));
            } catch (_) {}
          }
        }
        if (items.isEmpty) {
          prunedSomething = true;
          return;
        }
        _carts[key.toString()] = items;
        _savedAt[key.toString()] = savedAt;
      });

      if (prunedSomething) _flush();
      if (_carts.isNotEmpty) notifyListeners();
    } catch (e) {
      debugPrint('WaiterCartStore.restore failed: $e');
    }
  }

  void _flush() {
    unawaited(_writeToDisk());
  }

  Future<void> _writeToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_carts.isEmpty) {
        await prefs.remove(_prefsKey);
        return;
      }
      final map = <String, dynamic>{};
      _carts.forEach((key, cart) {
        map[key] = {
          'savedAt': (_savedAt[key] ?? DateTime.now()).toIso8601String(),
          'items': cart.map((ci) => ci.toJson()).toList(),
        };
      });
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (e) {
      debugPrint('WaiterCartStore persist failed: $e');
    }
  }
}
