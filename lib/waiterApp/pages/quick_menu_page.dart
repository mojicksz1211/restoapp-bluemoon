import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../waiter_models.dart';
import '../services/api_service.dart';
import '../services/waiter_cart_store.dart';
import '../widgets/fire_glow_background.dart';
import '../widgets/item_note_modal.dart';
import '../../menuApp/widgets/category_icons.dart';
import '../../shared/widgets/offline_sync_banner.dart';
import '../../shared/widgets/blurred_dialog.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/floating_result.dart';
import '../../shared/widgets/sliding_segments.dart';

// Switch Menu — a fast, board-style ordering screen for waiters. It mirrors the
// printed Blue Moon menu boards (chalkboard look, accent headings, same
// category names/order, Foods vs Drinks) with a tap-to-add +/- stepper on
// every item, best sellers first.
//
// It shares the Get Order cart through WaiterCartStore (same key), so items
// added here show up in Get Order and vice versa. It has its own cart sheet
// and places the order itself; on success it pops with the result 'placed'
// (the classic button pops with 'classic').

class _QM {
  // Same palette as the waiter dashboard: cream page, navy cards, champagne gold.
  static const cream = Color(0xFFF5F6F0);
  static const creamMuted = Color(0xFF6B6F80);
  static const line = Color(0xFFDDDED3);
  static const navy = Color(0xFF0C0E2B);
  static const navy2 = Color(0xFF1B1E4A);
  static const gold = Color(0xFFE8C468);
  static const goldDeep = Color(0xFFB8902F); // gold text on cream

  // Tokens used on navy surfaces (item cards, preview dialog).
  static const accent = gold;
  static const accentLine = gold;
  static const accentSoft = gold;
  static const text = Colors.white;
  static const muted = Color(0xFFB7BBD0);
}

enum _Group { foods, drinks, more }

class _CatDef {
  final _Group group;
  final int order;
  final String label;
  const _CatDef(this.group, this.order, this.label);
}

// Category names/order follow the printed menu boards (Bluemoon-menu1..5).
// Keys are normalised category names (lowercase, '&' -> 'and', letters/digits
// only). Anything not listed falls back to a keyword guess, see _defFor().
const Map<String, _CatDef> _catDefs = {
  // Foods (menu4 + menu5)
  'salad': _CatDef(_Group.foods, 10, 'Salad'),
  'fries': _CatDef(_Group.foods, 20, 'Fries'),
  'chicken': _CatDef(_Group.foods, 30, 'Chicken'),
  'steak': _CatDef(_Group.foods, 40, 'Steak'),
  'shrimp': _CatDef(_Group.foods, 50, 'Shrimp'),
  'pasta': _CatDef(_Group.foods, 60, 'Pasta'),
  'pizza': _CatDef(_Group.foods, 70, 'Pizza'),
  'platter': _CatDef(_Group.foods, 80, 'Platter'),
  'rice': _CatDef(_Group.foods, 90, 'Rice'),
  'filipinofood': _CatDef(_Group.foods, 100, 'Filipino Food'),
  'noodleandsoup': _CatDef(_Group.foods, 110, 'Noodle & Soup'),
  'noodlesoup': _CatDef(_Group.foods, 110, 'Noodle & Soup'),
  'dessert': _CatDef(_Group.foods, 120, 'Dessert'),
  'desserts': _CatDef(_Group.foods, 120, 'Dessert'),
  'setmenu': _CatDef(_Group.foods, 130, 'Set Menu'),
  // Drinks (menu1 + menu2 + menu3)
  'coffee': _CatDef(_Group.drinks, 10, 'Coffee'),
  'ade': _CatDef(_Group.drinks, 20, 'Ade'),
  'sodaincan': _CatDef(_Group.drinks, 30, 'Soda in Can'),
  'soda': _CatDef(_Group.drinks, 30, 'Soda in Can'),
  'fruitshakes': _CatDef(_Group.drinks, 40, 'Fruit Shakes'),
  'fruitshake': _CatDef(_Group.drinks, 40, 'Fruit Shakes'),
  'frappe': _CatDef(_Group.drinks, 50, 'Frappe'),
  'others': _CatDef(_Group.drinks, 60, 'Others'),
  'localbeer': _CatDef(_Group.drinks, 70, 'Local Beer'),
  'importedbeer': _CatDef(_Group.drinks, 80, 'Imported Beer'),
  'draftbeer': _CatDef(_Group.drinks, 85, 'Draft Beer'),
  'soju': _CatDef(_Group.drinks, 90, 'Soju'),
  'cocktailsoju': _CatDef(_Group.drinks, 100, 'Cocktail Soju'),
  'cocktailmenu': _CatDef(_Group.drinks, 110, 'Cocktail Menu'),
  'cocktail': _CatDef(_Group.drinks, 110, 'Cocktail Menu'),
  'cocktails': _CatDef(_Group.drinks, 110, 'Cocktail Menu'),
  'wineandchampagne': _CatDef(_Group.drinks, 120, 'Wine & Champagne'),
  'wine': _CatDef(_Group.drinks, 120, 'Wine & Champagne'),
  'whiskey': _CatDef(_Group.drinks, 130, 'Whiskey'),
  'whisky': _CatDef(_Group.drinks, 130, 'Whiskey'),
  'tequila': _CatDef(_Group.drinks, 140, 'Tequila'),
  'liquorpershot': _CatDef(_Group.drinks, 150, 'Liquor Per Shot'),
  'additional': _CatDef(_Group.drinks, 160, 'Additional'),
  // Not part of the printed menu (services / extras)
  'games': _CatDef(_Group.more, 10, 'Games'),
  'roomcharge': _CatDef(_Group.more, 20, 'Room Charge'),
  'service': _CatDef(_Group.more, 30, 'Service'),
};

const List<String> _drinkWords = [
  'beer',
  'wine',
  'whisk',
  'vodka',
  'rum',
  'gin',
  'tequila',
  'soju',
  'cocktail',
  'drink',
  'juice',
  'coffee',
  'tea',
  'soda',
  'shake',
  'liquor',
  'champagne',
  'mocktail',
  'beverage',
  'cognac',
  'bourbon',
  '주류',
  '음료',
];

String _normKey(String raw) {
  final k = raw
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  return k.isEmpty ? raw.trim().toLowerCase() : k;
}

class _Section {
  final String key;
  final String label;
  final _Group group;
  final int order;
  final List<MenuItem> items;
  _Section(this.key, this.label, this.group, this.order) : items = [];
}

// ── Size ("ml" / "oz" / "L") extraction ─────────────────────────────────────
// Drinks carry their volume in the description ("•750 ml", "3 Litters") or in
// the name ("Johnnie Walker Black 700ML"). It is pulled out into an accent badge
// so the waiter always sees the bottle size.
final RegExp _sizeRe = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(ml|cl|fl\.?\s?oz|oz|liters?|litters?|litres?|ltrs?|lt|l|kg|grams?|gm|g)\b',
  caseSensitive: false,
);

String _trimJunk(String s) => s
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'^[\s•·\-–—,:;|()]+|[\s•·\-–—,:;|()]+$'), '')
    .trim();

String _sizeLabel(String rawNum, String rawUnit) {
  final u = rawUnit.toLowerCase().replaceAll(RegExp(r'[.\s]'), '');
  final value = double.tryParse(rawNum.replaceAll(',', '.')) ?? 0;
  String n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  if (u == 'ml') {
    // A bottle entered as "1.75 ml" is really 1.75 litres — guard the typo.
    if (value > 0 && value < 10) {
      return '${n(value)} ${value == 1 ? 'LITER' : 'LITERS'}';
    }
    return '${n(value)} ML';
  }
  if (u == 'cl') return '${n(value)} CL';
  if (u == 'oz' || u == 'floz') return '${n(value)} OZ';
  if (u == 'kg') return '${n(value)} KG';
  if (u == 'g' || u == 'gm' || u.startsWith('gram')) return '${n(value)} G';
  return '${n(value)} ${value == 1 ? 'LITER' : 'LITERS'}';
}

class _ItemView {
  final String name;
  final String? size;
  final String? detail;
  const _ItemView(this.name, this.size, this.detail);

  factory _ItemView.of(MenuItem item) {
    var name = item.name.trim();
    var desc = item.description.trim().replaceAll(RegExp(r'[\r\n]+'), ' · ');
    String? size;

    final dm = _sizeRe.firstMatch(desc);
    if (dm != null) {
      size = _sizeLabel(dm.group(1)!, dm.group(2)!);
      desc = desc.replaceRange(dm.start, dm.end, '');
    }
    final nm = _sizeRe.firstMatch(name);
    if (nm != null) {
      size ??= _sizeLabel(nm.group(1)!, nm.group(2)!);
      final stripped = _trimJunk(name.replaceRange(nm.start, nm.end, ''));
      if (stripped.isNotEmpty) name = stripped;
    }
    final detail = _trimJunk(desc);
    return _ItemView(name, size, detail.isEmpty ? null : detail);
  }
}

String _peso(double v) {
  final whole = v == v.roundToDouble();
  final s = v.toStringAsFixed(whole ? 0 : 2);
  final parts = s.split('.');
  final whole3 = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return '₱$whole3${parts.length > 1 ? '.${parts[1]}' : ''}';
}

class QuickMenuPage extends StatefulWidget {
  final WaiterTable table;
  final List<MenuItem> menuItems;
  final WaiterOrder? existingOrder;

  /// Key into WaiterCartStore shared with Get Order for this table/order.
  final String cartKey;

  /// Same best-seller figure Get Order ranks by, so both screens agree.
  final int Function(MenuItem item) salesQtyOf;

  /// 'DINE_IN' (default) or 'TAKE_OUT'.
  final String? initialOrderType;

  const QuickMenuPage({
    super.key,
    required this.table,
    required this.menuItems,
    required this.cartKey,
    required this.salesQtyOf,
    this.existingOrder,
    this.initialOrderType,
  });

  @override
  State<QuickMenuPage> createState() => _QuickMenuPageState();
}

class _QuickMenuPageState extends State<QuickMenuPage> {
  final List<CartItem> _cart = [];
  final ScrollController _scroll = ScrollController();
  final Map<String, _ItemView> _views = {};
  final Map<String, int> _sales = {};

  final Map<_Group, List<_Section>> _sections = {};
  final Map<_Group, Map<String, int>> _rank = {};
  final Map<_Group, List<MenuItem>> _best = {};

  _Group _group = _Group.foods;
  String? _selectedKey; // null = All
  bool _chipsExpanded = false;
  String _orderType = 'DINE_IN';
  bool _submitting = false;
  String? _cartError;

  /// Room-charge sessions for a new order on a KTV room (see [_hasRoomCharge]).
  double _roomQty = 1;

  static String _itemKey(MenuItem m) =>
      m.id != null ? 'id:${m.id}' : 'n:${m.name.toLowerCase()}';

  @override
  void initState() {
    super.initState();
    _cart.addAll(WaiterCartStore.instance.load(widget.cartKey));
    _roomQty = WaiterCartStore.instance.roomChargeQty(widget.cartKey);
    _orderType = widget.initialOrderType ?? 'DINE_IN';
    _buildSections();
    // Open on whichever side actually has items.
    if ((_sections[_Group.foods] ?? const []).isEmpty &&
        (_sections[_Group.drinks] ?? const []).isNotEmpty) {
      _group = _Group.drinks;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ── data ──────────────────────────────────────────────────────────────────

  int _salesOf(MenuItem m) =>
      _sales.putIfAbsent(_itemKey(m), () => widget.salesQtyOf(m));

  _ItemView _viewOf(MenuItem m) =>
      _views.putIfAbsent(_itemKey(m), () => _ItemView.of(m));

  int _compare(MenuItem a, MenuItem b) {
    final c = _salesOf(b).compareTo(_salesOf(a));
    if (c != 0) return c;
    final r = b.totalRevenue.compareTo(a.totalRevenue);
    if (r != 0) return r;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  _CatDef _defFor(String rawName) {
    final key = _normKey(rawName);
    final known = _catDefs[key];
    if (known != null) return known;
    final lower = rawName.toLowerCase();
    final isDrink = _drinkWords.any(lower.contains);
    final label = rawName.trim().replaceFirst(RegExp(r'^\d+\.\s*'), '');
    return _CatDef(
      isDrink ? _Group.drinks : _Group.foods,
      1000,
      label.isEmpty ? 'Other Items' : label,
    );
  }

  void _buildSections() {
    final byKey = <String, _Section>{};
    for (final item in widget.menuItems) {
      final raw = (item.categoryName ?? item.category).trim();
      final key = _normKey(raw.isEmpty ? 'other' : raw);
      final section = byKey.putIfAbsent(key, () {
        final def = _defFor(raw);
        return _Section(key, def.label, def.group, def.order);
      });
      section.items.add(item);
    }

    for (final g in _Group.values) {
      // Best-selling categories first (units sold, then revenue). Categories
      // with no sales yet keep the printed-menu order from _catDefs.
      int unitsOf(_Section s) => s.items.fold(0, (sum, m) => sum + _salesOf(m));
      double revenueOf(_Section s) =>
          s.items.fold(0.0, (sum, m) => sum + m.totalRevenue);
      final list = byKey.values.where((s) => s.group == g).toList()
        ..sort((a, b) {
          final u = unitsOf(b).compareTo(unitsOf(a));
          if (u != 0) return u;
          final r = revenueOf(b).compareTo(revenueOf(a));
          if (r != 0) return r;
          final o = a.order.compareTo(b.order);
          return o != 0
              ? o
              : a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
      for (final s in list) {
        s.items.sort(_compare);
      }
      _sections[g] = list;

      // Best sellers = the group's top 10 by units sold (only items that sold).
      final all = [for (final s in list) ...s.items]..sort(_compare);
      final top = all.where((m) => _salesOf(m) > 0).take(10).toList();
      _best[g] = top;
      _rank[g] = {for (var i = 0; i < top.length; i++) _itemKey(top[i]): i + 1};
    }
  }

  // ── cart ──────────────────────────────────────────────────────────────────

  int _indexOf(MenuItem m) => _cart.indexWhere((c) {
    if (m.id != null && c.item.id != null) return c.item.id == m.id;
    return c.item.name.toLowerCase() == m.name.toLowerCase();
  });

  int _qty(MenuItem m) {
    final i = _indexOf(m);
    return i >= 0 ? _cart[i].quantity : 0;
  }

  int get _totalCount => _cart.fold(0, (s, c) => s + c.quantity);
  double get _totalPrice =>
      _cart.fold(0.0, (s, c) => s + c.item.price * c.quantity);

  /// A new order on a room with a room charge starts with that charge already
  /// in the cart (1 session), so the cart shows before any item is added and a
  /// room-only order can be sent. The waiter can lower it to 0 (waived).
  bool get _hasRoomCharge =>
      widget.existingOrder == null &&
      widget.table.id != 0 &&
      widget.table.roomCharge > 0;

  double get _roomChargeTotal =>
      _hasRoomCharge ? _roomQty * widget.table.roomCharge : 0;

  double get _orderTotal => _totalPrice + _roomChargeTotal;

  bool get _hasCartContent => _totalCount > 0 || _hasRoomCharge;

  void _setRoomQty(double qty) {
    final next = ((qty.clamp(0, 20)) * 2).round() / 2;
    if (next == _roomQty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _roomQty = next;
      _cartError = null;
    });
    WaiterCartStore.instance.setRoomChargeQty(widget.cartKey, next);
  }

  static String _fmtQty(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  void _add(MenuItem m) {
    HapticFeedback.selectionClick();
    setState(() {
      final i = _indexOf(m);
      if (i >= 0) {
        if (_cart[i].quantity < 99) _cart[i].quantity++;
      } else {
        _cart.add(CartItem(item: m, quantity: 1));
      }
    });
    WaiterCartStore.instance.save(widget.cartKey, _cart);
  }

  void _remove(MenuItem m) {
    HapticFeedback.selectionClick();
    setState(() {
      final i = _indexOf(m);
      if (i < 0) return;
      if (_cart[i].quantity > 1) {
        _cart[i].quantity--;
      } else {
        _cart.removeAt(i);
      }
    });
    WaiterCartStore.instance.save(widget.cartKey, _cart);
  }

  // ── navigation / ui state ─────────────────────────────────────────────────

  void _setGroup(_Group g) {
    if (g == _group) {
      // Tapping the active tab again drops the category filter ("All").
      if (_selectedKey != null) _setSection(null);
      return;
    }
    setState(() {
      _group = g;
      _selectedKey = null;
      _chipsExpanded = false;
    });
    _scrollTop();
  }

  void _setSection(String? key) {
    setState(() => _selectedKey = key);
    _scrollTop();
  }

  void _scrollTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String get _tableLabel {
    final no = widget.table.number.trim();
    return RegExp(r'^[A-Za-z]').hasMatch(no) ? no : 'Table $no';
  }

  // ── own cart sheet ────────────────────────────────────────────────────────

  Future<void> _openCart() async {
    if (!_hasCartContent) return;
    _cartError = null;
    await showBlurredBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => _buildCartSheet(ctx, setSheet),
      ),
    );
    if (mounted) setState(() {});
  }

  void _bump(BuildContext ctx, StateSetter setSheet, VoidCallback op) {
    op(); // _add/_remove update the page + cart store themselves
    setSheet(() => _cartError = null);
    if (!_hasCartContent && ctx.mounted) Navigator.of(ctx).pop();
  }

  Future<void> _submitOrder(BuildContext sheetCtx, StateSetter setSheet) async {
    if (!_hasCartContent || _submitting) return;
    if (_cart.isEmpty && _roomChargeTotal <= 0) {
      setSheet(
        () => _cartError =
            'Add at least one item, or set the room charge above 0.',
      );
      return;
    }
    setSheet(() {
      _submitting = true;
      _cartError = null;
    });

    String? error;
    try {
      final items = _cart.map((c) {
        if (c.item.id == null) {
          throw Exception('Menu item ID is missing for ${c.item.name}');
        }
        return {
          'menu_id': c.item.id,
          'qty': c.quantity,
          'unit_price': c.item.price,
          'status': 3, // PENDING
          if (c.remarks != null && c.remarks!.trim().isNotEmpty)
            'remarks': c.remarks!.trim(),
        };
      }).toList();
      final itemCount = _cart.length;
      final existing = widget.existingOrder;

      String orderNo = '';
      if (existing == null) {
        final now = DateTime.now();
        String two(int v) => v.toString().padLeft(2, '0');
        orderNo =
            'ORD-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
      }

      // Branded loading card for the whole create/add + confirm round trip.
      final result = await runWithLoader<Map<String, dynamic>>(
        context,
        message: existing != null ? 'Adding items…' : 'Placing order…',
        task: () async {
          Map<String, dynamic> r;
          if (existing != null) {
            r = await ApiService.addItemsToOrder(
              orderId: existing.id,
              items: items,
            );
          } else {
            final subtotal = _totalPrice;
            // The server adds one room-charge session by itself (same as the
            // admin's Manual Order), so send the difference: -rate when waived,
            // 0 for one session, +rate per extra session.
            final roomRate = _hasRoomCharge ? widget.table.roomCharge : 0.0;
            r = await ApiService.createOrder(
              orderNo: orderNo,
              tableId: widget.table.id == 0 ? null : widget.table.id,
              tableNumber: widget.table.number,
              orderType: _orderType,
              subtotal: subtotal,
              taxAmount: 0.0,
              serviceCharge: _hasRoomCharge ? (_roomQty - 1) * roomRate : 0.0,
              discountAmount: 0.0,
              grandTotal: _orderTotal,
              items: items,
              roomChargeRate: roomRate,
            );
            if (r['success'] == true) {
              final raw = r['data']?['order_id'] ?? r['data']?['orderId'];
              final orderId = raw is int
                  ? raw
                  : int.tryParse(raw?.toString() ?? '');
              if (orderId != null) {
                final status = await ApiService.updateWaiterOrderStatus(
                  orderId: orderId,
                  status: 2, // CONFIRMED
                );
                if (status['unauthorized'] == true) r = status;
              }
            }
          }
          return r;
        },
      );
      if (!mounted) return;

      if (result['unauthorized'] == true) {
        error = 'Session expired. Please login again.';
      } else if (result['success'] == true) {
        final isOffline = result['is_offline'] == true;
        WaiterCartStore.instance.clear(widget.cartKey);
        if (!mounted) return;
        setState(_cart.clear);
        showFloatingResult(
          context,
          warning: isOffline,
          duration: const Duration(milliseconds: 2400),
          title: existing != null
              ? (isOffline
                    ? 'Items Added Locally (Offline)'
                    : 'Items Added Successfully!')
              : (isOffline
                    ? 'Order Saved Locally (Offline)'
                    : 'Order Placed Successfully!'),
          subtitle: existing != null
              ? (isOffline
                    ? '$itemCount item(s) saved locally to order. Will auto-sync when online.'
                    : '$itemCount item(s) added to order #${existing.orderNo ?? existing.id}')
              : (isOffline
                    ? 'Order #${result['data']?['order_no'] ?? orderNo} saved to device. Will auto-sync once WiFi has internet.'
                    : 'Order #${result['data']?['order_no'] ?? orderNo}'),
        );
        if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        if (mounted) Navigator.of(context).pop('placed');
        return;
      } else {
        error = (result['error'] ?? 'Failed to place order').toString();
      }
    } catch (e) {
      error = 'Error placing order: $e';
    }

    _submitting = false;
    if (sheetCtx.mounted) setSheet(() => _cartError = error);
  }

  // Same look as the waiter's Order Details sheet: navy header, cream body
  // with a white card per line, white "Total Amount" bar, navy buttons.
  static const _sheetBg = Color(0xFFF5F6F0);
  static const _amount = Color(0xFFD97706);

  Widget _buildCartSheet(BuildContext ctx, StateSetter setSheet) {
    final mq = MediaQuery.of(ctx);
    final isMobile = mq.size.width < 600;
    final isNew = widget.existingOrder == null;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: mq.size.height * 0.85,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: _sheetBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 20,
                  vertical: isMobile ? 14 : 16,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_QM.navy, _QM.navy2]),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      color: _QM.gold,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.existingOrder != null
                                ? 'Additional Order'
                                : 'Your Order',
                            style: GoogleFonts.urbanist(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '$_tableLabel  •  $_totalCount ${_totalCount == 1 ? 'item' : 'items'}${_hasRoomCharge ? ' + room' : ''}',
                            style: GoogleFonts.urbanist(
                              fontSize: isMobile ? 13 : 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),

              // Lines
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(14),
                  children: [
                    if (_hasRoomCharge) _roomChargeLine(setSheet, isMobile),
                    for (final c in _cart)
                      _cartLine(ctx, setSheet, c, isMobile),
                  ],
                ),
              ),

              // Total
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 18 : 22,
                  vertical: isMobile ? 14 : 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Total Amount',
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 17 : 19,
                            fontWeight: FontWeight.w800,
                            color: _QM.navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Items ($_totalCount)${_hasRoomCharge ? ' + Room' : ''}',
                          style: GoogleFonts.urbanist(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _peso(_orderTotal),
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 22 : 25,
                        fontWeight: FontWeight.w900,
                        color: _amount,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Order type, errors, Place Order
              Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, isMobile ? 16 : 20),
                color: _sheetBg,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isNew) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _OrderTypePill(
                                label: 'Dine In',
                                icon: Icons.restaurant_rounded,
                                selected: _orderType == 'DINE_IN',
                                onTap: () =>
                                    setSheet(() => _orderType = 'DINE_IN'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _OrderTypePill(
                                label: 'Take Out',
                                icon: Icons.shopping_bag_outlined,
                                selected: _orderType == 'TAKE_OUT',
                                onTap: () =>
                                    setSheet(() => _orderType = 'TAKE_OUT'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_cartError != null) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFDC2626),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _cartError!,
                                style: GoogleFonts.urbanist(
                                  color: const Color(0xFFDC2626),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [_QM.navy, _QM.navy2],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _QM.navy.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _submitting
                                ? null
                                : () => _submitOrder(ctx, setSheet),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: isMobile ? 14 : 16,
                              ),
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.transparent,
                              disabledForegroundColor: Colors.white70,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    widget.existingOrder != null
                                        ? 'Add to Order'
                                        : 'Place Order',
                                    style: GoogleFonts.urbanist(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isMobile ? 15 : 16.5,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// White card per line, like the Order Details sheet.
  BoxDecoration get _lineCard => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ],
  );

  /// First line of a new room order's cart: the room charge, in hours.
  Widget _roomChargeLine(StateSetter setSheet, bool isMobile) {
    final rate = widget.table.roomCharge;
    final waived = _roomQty <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _amount.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Room Charge',
                  style: GoogleFonts.urbanist(
                    fontSize: isMobile ? 15 : 16,
                    fontWeight: FontWeight.bold,
                    color: _QM.navy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  waived
                      ? 'Waived — 100% less'
                      : '${_fmtQty(_roomQty)} × ${_peso(rate)} per hour',
                  style: GoogleFonts.urbanist(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: waived
                        ? const Color(0xFF059669)
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _peso(_roomChargeTotal),
                  style: GoogleFonts.urbanist(
                    fontSize: isMobile ? 16.5 : 18,
                    fontWeight: FontWeight.w900,
                    color: _amount,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _RoomStepper(
            light: true,
            qty: _roomQty,
            label: _fmtQty(_roomQty),
            onAdd: () {
              _setRoomQty(_roomQty + 0.5);
              setSheet(() {});
            },
            onRemove: () {
              _setRoomQty(_roomQty - 0.5);
              setSheet(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _cartLine(
    BuildContext ctx,
    StateSetter setSheet,
    CartItem c,
    bool isMobile,
  ) {
    final view = _viewOf(c.item);
    final note = (c.remarks ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _lineCard,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  view.size == null ? view.name : '${view.name} (${view.size})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.urbanist(
                    fontSize: isMobile ? 15 : 16,
                    fontWeight: FontWeight.bold,
                    color: _QM.navy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${c.quantity} × ${_peso(c.item.price)}',
                  style: GoogleFonts.urbanist(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showItemNoteModal(
                    context: ctx,
                    cartItem: c,
                    onSaved: () {
                      WaiterCartStore.instance.save(widget.cartKey, _cart);
                      setSheet(() {});
                    },
                  ),
                  child: note.isEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 16,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Add note',
                              style: GoogleFonts.urbanist(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _QM.gold.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _QM.gold.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            '📝 $note',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.urbanist(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFB45309),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _peso(c.item.price * c.quantity),
                style: GoogleFonts.urbanist(
                  fontSize: isMobile ? 16.5 : 18,
                  fontWeight: FontWeight.w900,
                  color: _amount,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              _Stepper(
                light: true,
                qty: c.quantity,
                onAdd: () => _bump(ctx, setSheet, () => _add(c.item)),
                onRemove: () => _bump(ctx, setSheet, () => _remove(c.item)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _preview(MenuItem m) {
    final url = m.imageUrl;
    if (url == null || url.isEmpty) return;
    final view = _viewOf(m);
    // White card over a blurred, dimmed screen, like the app's other popups.
    showBlurredDialog<void>(
      context,
      useRootNavigator: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(19),
                ),
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: _NetImage(
                    url: url,
                    fit: BoxFit.contain,
                    fallback: const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: _QM.creamMuted,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            view.name.toUpperCase(),
                            style: GoogleFonts.urbanist(
                              color: _QM.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: 0.4,
                            ),
                          ),
                          if (view.size != null || view.detail != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                [
                                  view.size,
                                  view.detail,
                                ].whereType<String>().join(' · '),
                                style: GoogleFonts.urbanist(
                                  color: _QM.creamMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _peso(m.price),
                      style: GoogleFonts.urbanist(
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final clampedScale = TextScaler.linear(
      mq.textScaler.scale(1).clamp(1.0, 1.15).toDouble(),
    );
    final width = mq.size.width;
    final gutter = width >= 900 ? 24.0 : 14.0;
    final sections = _sections[_group] ?? const <_Section>[];

    return MediaQuery(
      data: mq.copyWith(textScaler: clampedScale),
      child: Scaffold(
        backgroundColor: _QM.cream,
        // Same floating gold "View Order" pill as the classic Get Order screen.
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _hasCartContent ? _buildCartFab() : null,
        body: Stack(
          children: [
            const Positioned.fill(child: _BoardBackground()),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(gutter),
                  const OfflineSyncBanner(),
                  _buildGroupTabs(gutter),
                  _buildChips(gutter, sections),
                  Expanded(child: _buildBody(gutter, sections)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double gutter) {
    return Padding(
      // Extra top margin: in immersive fullscreen on tablets SafeArea reports no
      // inset, which pins the header buttons to the very top edge of the screen.
      padding: EdgeInsets.fromLTRB(gutter - 4, 26, gutter, 6),
      child: SizedBox(
        height: 58,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Logo + title centred on the screen. The side padding equals the
            // wider button group so it stays centred and never runs under the
            // buttons; FittedBox shrinks it on narrow phones.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 100),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: QuickMenuBrand(
                  tableLabel: quickMenuTableLabel(widget.table.number),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: _QM.gold,
                style: IconButton.styleFrom(
                  backgroundColor: _QM.navy,
                  minimumSize: const Size(44, 44),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Classic menu',
                    onPressed: () => Navigator.of(context).pop('classic'),
                    icon: const Icon(Icons.grid_view_rounded, size: 21),
                    color: _QM.accentSoft,
                    style: IconButton.styleFrom(
                      backgroundColor: _QM.navy,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _CartButton(
                    count: _totalCount,
                    onTap: _hasCartContent ? _openCart : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupTabs(double gutter) {
    final tabs = <(_Group, String, IconData)>[
      (_Group.foods, 'Foods', Icons.restaurant_rounded),
      (_Group.drinks, 'Drinks', Icons.local_bar_rounded),
      if ((_sections[_Group.more] ?? const []).isNotEmpty)
        (_Group.more, 'More', Icons.more_horiz_rounded),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 8),
      child: SlidingSegments(
        selectedIndex: tabs.indexWhere((t) => t.$1 == _group),
        onChanged: (i) => _setGroup(tabs[i].$1),
        segments: [
          for (final t in tabs)
            SegmentLabel(
              label: t.$2,
              icon: t.$3,
              count: (_sections[t.$1] ?? const <_Section>[]).fold<int>(
                0,
                (s, sec) => s + sec.items.length,
              ),
            ),
        ],
      ),
    );
  }

  // Category pill cards, wrapped [_chipCols] per row. Collapsed it shows only
  // the first [_chipCollapsed]; a toggle underneath reveals the rest. ("All"
  // lives in the Foods/Drinks tab row.)
  static const int _chipCols = 4;
  static const int _chipCollapsed = 8;
  static const double _pillH = 54;
  static const double _pillGap = 8;

  Widget _buildChips(double gutter, List<_Section> sections) {
    final collapsible = sections.length > _chipCollapsed;
    final expanded = !collapsible || _chipsExpanded;
    final visibleCount = expanded ? sections.length : _chipCollapsed;
    final hidden = sections.length - _chipCollapsed;

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 6),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final pillW =
                  (c.maxWidth - (_chipCols - 1) * _pillGap) / _chipCols;
              return AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Wrap(
                    spacing: _pillGap,
                    runSpacing: _pillGap,
                    children: [
                      for (final s in sections.take(visibleCount))
                        SizedBox(
                          width: pillW,
                          height: _pillH,
                          child: _CategoryPill(
                            label: s.label,
                            icon: _chipIcon(s.label),
                            count: s.items.length,
                            selected: _selectedKey == s.key,
                            onTap: () => _setSection(
                              _selectedKey == s.key ? null : s.key,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (collapsible || _selectedKey != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_selectedKey != null)
                    _chipAction(
                      label: 'Clear',
                      icon: Icons.close_rounded,
                      filled: true,
                      onTap: () => _setSection(null),
                    ),
                  if (_selectedKey != null && collapsible)
                    const SizedBox(width: 24),
                  if (collapsible)
                    _chipAction(
                      label: expanded
                          ? 'SHOW LESS'
                          : 'SHOW $hidden MORE CATEGORIES',
                      icon: expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      iconAfter: true,
                      onTap: () =>
                          setState(() => _chipsExpanded = !_chipsExpanded),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chipAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool iconAfter = false,
    bool filled = false,
  }) {
    final text = Text(
      label,
      style: GoogleFonts.urbanist(
        color: _QM.navy,
        fontWeight: FontWeight.w900,
        fontSize: 14.5,
      ),
    );
    final ic = Icon(icon, color: _QM.navy, size: 22);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: filled
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
            : const EdgeInsets.symmetric(vertical: 2),
        decoration: filled
            ? BoxDecoration(
                color: _QM.gold,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _QM.goldDeep.withValues(alpha: 0.8)),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconAfter
              ? [text, const SizedBox(width: 4), ic]
              : [ic, const SizedBox(width: 4), text],
        ),
      ),
    );
  }

  Widget _buildBody(double gutter, List<_Section> sections) {
    final slivers = <Widget>[];

    void addSection({
      required String title,
      required List<MenuItem> items,
      required _Group group,
      bool best = false,
      bool cocktail = false,
    }) {
      if (items.isEmpty) return;
      slivers.add(
        SliverToBoxAdapter(
          child: _SectionHeader(
            title: title,
            group: group,
            best: best,
            cocktail: cocktail,
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 6),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 520,
              mainAxisExtent: 128,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final item = items[i];
              final rank =
                  (_rank[group] ?? const <String, int>{})[_itemKey(item)];
              return _QuickItemCard(
                key: ValueKey('${title}_${_itemKey(item)}'),
                item: item,
                view: _viewOf(item),
                qty: _qty(item),
                rank: rank,
                bestRow: best,
                cocktail: cocktail,
                group: group,
                onAdd: () => _add(item),
                onRemove: () => _remove(item),
                onPreview: () => _preview(item),
              );
            }, childCount: items.length),
          ),
        ),
      );
    }

    if (_selectedKey == null) {
      final best = _best[_group] ?? const <MenuItem>[];
      addSection(title: 'Best Sellers', items: best, group: _group, best: true);
      for (final s in sections) {
        addSection(
          title: s.label,
          items: s.items,
          group: s.group,
          cocktail: s.key.startsWith('cocktail') && s.key != 'cocktailsoju',
        );
      }
    } else {
      final s = sections.firstWhere(
        (s) => s.key == _selectedKey,
        orElse: () => sections.first,
      );
      addSection(
        title: s.label,
        items: s.items,
        group: s.group,
        cocktail: s.key.startsWith('cocktail') && s.key != 'cocktailsoju',
      );
    }

    if (slivers.isEmpty) {
      return const _EmptyState(message: 'No items in this menu yet');
    }

    // Room so the floating cart button never covers the last row.
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 110)));
    return CustomScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: slivers,
    );
  }

  Widget _buildCartFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FireGlowBackground(
        child: Material(
          color: _QM.gold,
          borderRadius: BorderRadius.circular(32),
          elevation: 8,
          shadowColor: _QM.navy.withValues(alpha: 0.55),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: _openCart,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 20, 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cart icon + count in a dark disc so it reads on the gold.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: _QM.navy,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          color: _QM.gold,
                          size: 22,
                        ),
                      ),
                      if (_totalCount > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: _QM.gold, width: 2),
                            ),
                            child: Text(
                              '$_totalCount',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.urbanist(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: _QM.navy,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'View Order',
                    style: GoogleFonts.urbanist(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: _QM.navy,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 1.4,
                    height: 20,
                    color: _QM.navy.withValues(alpha: 0.25),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '₱${formatPrice(_orderTotal)}',
                    style: GoogleFonts.urbanist(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _QM.navy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── pieces ──────────────────────────────────────────────────────────────────

class _BoardBackground extends StatelessWidget {
  const _BoardBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: _QM.cream),
        Image.asset(
          'assets/images/menubackground.png',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CartButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _CartButton({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Review order',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _QM.navy,
                ),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: count > 0 ? _QM.accentSoft : _QM.muted,
                  size: 23,
                ),
              ),
              if (count > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _QM.gold,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _QM.cream, width: 2),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: GoogleFonts.urbanist(
                        color: _QM.navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? _QM.navy : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? _QM.navy : _QM.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: selected ? _QM.gold : _QM.navy),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.urbanist(
                  color: selected ? _QM.gold : _QM.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 17.5,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: GoogleFonts.urbanist(
                color: selected
                    ? _QM.gold.withValues(alpha: 0.8)
                    : _QM.creamMuted,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared keyword icon, plus the Switch Menu sections it doesn't cover.
IconData _chipIcon(String label) {
  final n = label.toLowerCase();
  if (n.contains('steak') || n.contains('beef') || n.contains('pork')) {
    return Icons.kebab_dining_outlined;
  }
  return getCategoryIcon(label);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final _Group group;
  final bool best;
  final bool cocktail;

  const _SectionHeader({
    required this.title,
    required this.group,
    this.best = false,
    this.cocktail = false,
  });

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.of(context).size.width >= 900 ? 24.0 : 14.0;

    // Mirrors the boards: drinks sections use an accent script heading, the
    // cocktail board a bold condensed one, food sections bold caps + underline.
    final Widget heading;
    if (best) {
      heading = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: _QM.goldDeep,
            size: 36,
          ),
          const SizedBox(width: 8),
          Text(
            'Best Sellers',
            style: GoogleFonts.yellowtail(
              color: _QM.navy,
              fontSize: 46,
              height: 1.1,
            ),
          ),
        ],
      );
    } else if (cocktail) {
      heading = Text(
        title.toUpperCase(),
        style: GoogleFonts.oswald(
          color: _QM.navy,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      );
    } else if (group == _Group.drinks) {
      heading = Text(
        title,
        style: GoogleFonts.yellowtail(
          color: _QM.navy,
          fontSize: 46,
          height: 1.1,
        ),
      );
    } else {
      heading = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: _QM.navy,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 84,
            height: 3.5,
            decoration: BoxDecoration(
              color: _QM.gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      );
    }

    Widget rule({required bool leading}) => Expanded(
      child: Container(
        height: 1.4,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _QM.goldDeep.withValues(alpha: leading ? 0.0 : 0.55),
              _QM.goldDeep.withValues(alpha: leading ? 0.55 : 0.0),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 12),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            rule(leading: true),
            const SizedBox(width: 16),
            // Heading scales down only if a long category name would crowd
            // the rules.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.7),
              child: FittedBox(fit: BoxFit.scaleDown, child: heading),
            ),
            const SizedBox(width: 16),
            rule(leading: false),
          ],
        ),
      ),
    );
  }
}

class _QuickItemCard extends StatelessWidget {
  final MenuItem item;
  final _ItemView view;
  final int qty;
  final int? rank;
  final bool bestRow;
  final bool cocktail;
  final _Group group;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  const _QuickItemCard({
    super.key,
    required this.item,
    required this.view,
    required this.qty,
    required this.rank,
    required this.bestRow,
    required this.cocktail,
    required this.group,
    required this.onAdd,
    required this.onRemove,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    final available = item.isAvailable;
    final nameStyle = group == _Group.drinks
        ? GoogleFonts.alegreyaSc(
            color: _QM.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            height: 1.12,
          )
        : GoogleFonts.montserrat(
            color: _QM.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            height: 1.2,
          );
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_QM.navy, _QM.navy2],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? _QM.gold : Colors.white.withValues(alpha: 0.06),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Opacity(
        opacity: available ? 1 : 0.5,
        child: Row(
          children: [
            GestureDetector(
              onTap: hasImage ? onPreview : null,
              child: _Thumb(
                url: item.imageUrl,
                group: group,
                rank: rank,
                bestRow: bestRow,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    view.name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                  if (view.size != null || view.detail != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (view.size != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _QM.accentLine.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _QM.accentLine.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              view.size!,
                              style: GoogleFonts.urbanist(
                                color: _QM.accentSoft,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        if (view.size != null && view.detail != null)
                          const SizedBox(width: 6),
                        if (view.detail != null)
                          Expanded(
                            child: Text(
                              view.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.urbanist(
                                color: _QM.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 5),
                  _PriceTag(price: item.price, cocktail: cocktail),
                ],
              ),
            ),
            const SizedBox(width: 6),
            available
                ? _Stepper(qty: qty, onAdd: onAdd, onRemove: onRemove)
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      'SOLD OUT',
                      style: GoogleFonts.urbanist(
                        color: _QM.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  final double price;
  final bool cocktail;
  const _PriceTag({required this.price, required this.cocktail});

  @override
  Widget build(BuildContext context) {
    if (cocktail) {
      // Ribbon-style tag, as on the cocktail board (gold to match the theme).
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
        decoration: BoxDecoration(
          color: _QM.gold,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(3),
            right: Radius.circular(10),
          ),
          border: Border.all(color: _QM.goldDeep.withValues(alpha: 0.8)),
        ),
        child: Text(
          _peso(price),
          style: GoogleFonts.urbanist(
            color: _QM.navy,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      );
    }
    return Text(
      _peso(price),
      style: GoogleFonts.urbanist(
        color: _QM.accentSoft,
        fontWeight: FontWeight.w900,
        fontSize: 21,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  final _Group group;
  final int? rank;
  final bool bestRow;

  const _Thumb({
    required this.url,
    required this.group,
    required this.rank,
    required this.bestRow,
  });

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    final placeholder = Container(
      color: Colors.white.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: Icon(
        group == _Group.drinks
            ? Icons.local_bar_rounded
            : Icons.restaurant_rounded,
        color: _QM.accentSoft.withValues(alpha: 0.55),
        size: 26,
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: (url == null || url!.isEmpty)
                  ? placeholder
                  : _NetImage(
                      url: url!,
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                      fallback: placeholder,
                    ),
            ),
          ),
          if (rank != null)
            Positioned(
              left: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: rank! <= 3 ? _QM.accent : _QM.navy,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: rank! <= 3
                        ? _QM.accentLine
                        : _QM.accentLine.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 11,
                      color: rank! <= 3 ? _QM.navy : _QM.accentSoft,
                    ),
                    Text(
                      '$rank',
                      style: GoogleFonts.urbanist(
                        color: rank! <= 3 ? _QM.navy : _QM.accentSoft,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Network image on a white backdrop (product photos are shot on white / have
/// transparency, which reads black on the dark board). Uses Image.network on
/// web — same as the classic menu card — since CachedNetworkImage is unreliable
/// there.
class _NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget fallback;

  const _NetImage({
    required this.url,
    required this.fit,
    required this.fallback,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final Widget image = kIsWeb
        ? Image.network(
            url,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : fallback,
          )
        : CachedNetworkImage(
            imageUrl: url,
            fit: fit,
            memCacheWidth: cacheWidth,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
          );
    return ColoredBox(color: Colors.white, child: image);
  }
}

/// Dine In / Take Out choice in the cart sheet — styled like the Order
/// Details buttons: navy when selected, navy outline otherwise.
class _OrderTypePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _OrderTypePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 46,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [_QM.navy, _QM.navy2])
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _QM.navy, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? _QM.gold : _QM.navy),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.urbanist(
                color: selected ? Colors.white : _QM.navy,
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  /// For white surfaces (the cart sheet); navy item cards use the default.
  final bool light;

  const _Stepper({
    required this.qty,
    required this.onAdd,
    required this.onRemove,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerRight,
      child: qty == 0
          ? _RoundBtn(
              icon: Icons.add_rounded,
              filled: true,
              size: 42,
              onTap: onAdd,
              label: 'Add',
            )
          : Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: light
                    ? Colors.white
                    : Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(21),
                border: Border.all(
                  color: light
                      ? _QM.navy.withValues(alpha: 0.15)
                      : _QM.accentLine.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RoundBtn(
                    icon: Icons.remove_rounded,
                    filled: false,
                    light: light,
                    size: 34,
                    onTap: onRemove,
                    label: 'Remove one',
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 28),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Text(
                        '$qty',
                        key: ValueKey(qty),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.urbanist(
                          color: light ? _QM.navy : _QM.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  _RoundBtn(
                    icon: Icons.add_rounded,
                    filled: true,
                    light: light,
                    size: 34,
                    onTap: onAdd,
                    label: 'Add one',
                  ),
                ],
              ),
            ),
    );
  }
}

/// − qty + for the room-charge line. Goes down to 0 (waived), in 0.5 steps.
class _RoomStepper extends StatelessWidget {
  final double qty;
  final String label;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  /// For white surfaces (the cart sheet).
  final bool light;

  const _RoomStepper({
    required this.qty,
    required this.label,
    required this.onAdd,
    required this.onRemove,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final canRemove = qty > 0;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: light ? Colors.white : Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: light
              ? _QM.navy.withValues(alpha: 0.15)
              : _QM.accentLine.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: canRemove ? 1 : 0.3,
            child: _RoundBtn(
              icon: Icons.remove_rounded,
              filled: false,
              light: light,
              size: 34,
              onTap: canRemove ? onRemove : () {},
              label: 'Less room charge',
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 34),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.urbanist(
                color: light ? _QM.navy : _QM.text,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          _RoundBtn(
            icon: Icons.add_rounded,
            filled: true,
            light: light,
            size: 34,
            onTap: onAdd,
            label: 'More room charge',
          ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final bool filled;
  // On a white surface (the cart sheet): navy circle, white icon.
  final bool light;
  final double size;
  final VoidCallback onTap;
  final String label;

  const _RoundBtn({
    required this.icon,
    required this.filled,
    this.light = false,
    required this.size,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: light
                ? _QM.navy
                : (filled ? _QM.accent : Colors.transparent),
            border: filled && !light
                ? Border.all(
                    color: _QM.accentLine.withValues(alpha: 0.75),
                    width: 1.2,
                  )
                : null,
            boxShadow: filled && !light && size > 36
                ? [
                    BoxShadow(
                      color: _QM.accentLine.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: size > 36 ? 24 : 21,
            color: light ? Colors.white : (filled ? _QM.navy : _QM.text),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 46,
            color: _QM.creamMuted.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(
              color: _QM.creamMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header button for Get Order that opens the Switch Menu, sitting next to the
/// Home button. Collapses to icon-only on narrow phones.
/// Blue Moon logo + title, shared by the Switch Menu and classic Get Order
/// headers so both read as the same app.
class QuickMenuBrand extends StatelessWidget {
  /// Text shown after the title, separated by a bullet (e.g. the table).
  final String? tableLabel;

  const QuickMenuBrand({super.key, this.tableLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _QM.accentLine.withValues(alpha: 0.7),
              width: 1.6,
            ),
          ),
          child: ClipOval(
            child: Image.asset('assets/images/logo1.png', fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'BLUE MOON',
          maxLines: 1,
          style: GoogleFonts.cormorantGaramond(
            color: _QM.navy,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            height: 1.0,
          ),
        ),
        if (tableLabel != null) ...[
          const SizedBox(width: 12),
          Text(
            '•',
            style: GoogleFonts.urbanist(
              color: _QM.goldDeep,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            tableLabel!,
            maxLines: 1,
            style: GoogleFonts.urbanist(
              color: _QM.goldDeep,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

/// "TABLE 5" for numbered tables, the bare name ("BAR") for lettered ones.
String quickMenuTableLabel(String number) {
  final no = number.trim();
  return (RegExp(r'^[A-Za-z]').hasMatch(no) ? no : 'Table $no').toUpperCase();
}

class QuickMenuButton extends StatelessWidget {
  final VoidCallback onPressed;

  const QuickMenuButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Same round navy icon button as the Switch Menu header's buttons.
    return IconButton(
      tooltip: 'Switch Menu',
      onPressed: onPressed,
      icon: const Icon(Icons.view_agenda_rounded, size: 21),
      color: _QM.accentSoft,
      style: IconButton.styleFrom(
        backgroundColor: _QM.navy,
        minimumSize: const Size(44, 44),
      ),
    );
  }
}
