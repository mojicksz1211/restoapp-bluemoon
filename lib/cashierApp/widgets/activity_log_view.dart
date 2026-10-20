import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/offline_sync_service.dart';
import '../../waiterApp/models.dart' show formatPrice;
import '../../waiterApp/services/api_service.dart';
import '../../waiterApp/waiter_models.dart' show formatClock, formatRoomHours;

const _navy = Color(0xFF0C0E2B);
const _navy2 = Color(0xFF1B1E4A);
const _gold = Color(0xFFE8C468);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);

/// One thing a waiter / cashier tablet did to an order (server table
/// order_activity_logs).
class ActivityLogEntry {
  final int id;
  final int? orderId;
  final String? orderNo;
  final String? tableNumber;
  final String? floor;
  final String action;
  final String summary;
  final Map<String, dynamic>? details;
  final double? amount;
  final String? username;
  final String? fullname;
  final String? role;

  /// Asia/Manila wall-clock time.
  final DateTime? createdAt;

  /// Done on this tablet while offline and not on the server yet.
  final bool pending;

  /// Done offline on some tablet; logged once it synced (time is the
  /// original one).
  final bool syncedLate;

  const ActivityLogEntry({
    required this.id,
    required this.orderId,
    required this.orderNo,
    required this.tableNumber,
    required this.floor,
    required this.action,
    required this.summary,
    required this.details,
    required this.amount,
    required this.username,
    required this.fullname,
    required this.role,
    required this.createdAt,
    this.pending = false,
    this.syncedLate = false,
  });

  factory ActivityLogEntry.fromApi(Map<String, dynamic> d) {
    final details = d['details'];
    return ActivityLogEntry(
      id: (d['id'] as num?)?.toInt() ?? 0,
      orderId: (d['order_id'] as num?)?.toInt(),
      orderNo: d['order_no']?.toString(),
      tableNumber: d['table_number']?.toString(),
      floor: d['floor']?.toString(),
      action: d['action']?.toString() ?? '',
      summary: d['summary']?.toString() ?? '',
      details: details is Map ? Map<String, dynamic>.from(details) : null,
      amount: (d['amount'] as num?)?.toDouble(),
      username: d['username']?.toString(),
      fullname: d['user_fullname']?.toString(),
      role: d['user_role']?.toString(),
      createdAt: DateTime.tryParse(d['created_at']?.toString() ?? ''),
      syncedLate: d['synced_late'] == true,
    );
  }

  /// "Juan Dela Cruz (Waiter)" / "gf_waiter2".
  String get who {
    final name = (fullname ?? '').trim().isNotEmpty ? fullname!.trim() : (username ?? 'Unknown');
    final r = (role ?? '').trim();
    return r.isEmpty ? name : '$name ($r)';
  }

  String get searchText =>
      [summary, tableNumber, orderNo, fullname, username, role, _ActionMeta.of(action).label]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
}

class _ActionMeta {
  final String label;
  final String chip;
  final IconData icon;
  final Color color;
  const _ActionMeta(this.label, this.chip, this.icon, this.color);

  static const all = <String, _ActionMeta>{
    'order_created': _ActionMeta('New Order', 'New', Icons.receipt_long_rounded, Color(0xFF2563EB)),
    'items_added': _ActionMeta('Items Added', 'Added', Icons.add_shopping_cart_rounded, Color(0xFF16A34A)),
    'items_edited': _ActionMeta('Order Edited', 'Edited', Icons.edit_note_rounded, Color(0xFF7C3AED)),
    'room_charge': _ActionMeta('Room Charge', 'Room', Icons.more_time_rounded, Color(0xFFD97706)),
    'transferred': _ActionMeta('Transferred', 'Transfer', Icons.swap_horiz_rounded, Color(0xFF0891B2)),
    'confirmed': _ActionMeta('Confirmed', 'Confirmed', Icons.check_circle_outline_rounded, Color(0xFF059669)),
    'cancelled': _ActionMeta('Cancelled', 'Cancelled', Icons.delete_outline_rounded, Color(0xFFDC2626)),
    'settled': _ActionMeta('Settled', 'Settled', Icons.payments_rounded, Color(0xFF15803D)),
  };

  static _ActionMeta of(String action) =>
      all[action] ?? const _ActionMeta('Activity', 'Other', Icons.history_rounded, _muted);
}

/// The cashier app's Activity tab: everything the branch's waiter and cashier
/// tablets did to orders on one business day — new orders, items added /
/// edited, room charge, transfers, confirm, cancel, settle — newest first.
class ActivityLogView extends StatefulWidget {
  /// The header search box's text.
  final String searchQuery;

  /// 'gf' / '2f' when the account is locked to one floor (its floor only, no
  /// floor chips); null shows All / Ground / 2nd chips.
  final String? floorScope;

  /// Whether an entry is on the ground floor (same rule as the order cards).
  final bool Function(String? floor, String? tableNumber) isGroundFloor;

  /// Bumped by the home page whenever an order changes, so today's log
  /// refreshes on its own.
  final ValueListenable<int> refreshSignal;

  const ActivityLogView({
    super.key,
    required this.searchQuery,
    required this.floorScope,
    required this.isGroundFloor,
    required this.refreshSignal,
  });

  @override
  State<ActivityLogView> createState() => _ActivityLogViewState();
}

class _ActivityLogViewState extends State<ActivityLogView> {
  List<ActivityLogEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  /// The business day shown ('YYYY-MM-DD'); null until the server says which
  /// day "today" is.
  String? _date;
  String? _today;
  String _action = 'all';
  late String _floor = widget.floorScope ?? 'all';
  final Set<int> _expanded = {};
  Timer? _refreshDebounce;
  Timer? _poll;

  /// This tablet's actions still waiting to sync (shown first, today only).
  List<ActivityLogEntry> _pending = const [];

  /// Set while showing the copy saved on this device because it's offline:
  /// when that copy was loaded.
  DateTime? _offlineCopyAt;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_onSignal);
    OfflineSyncService.instance.pendingCountNotifier.addListener(_onQueueChanged);
    _load();
    _loadPending();
    // Backstop when socket events are missed.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isToday) _load(silent: true);
    });
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_onSignal);
    OfflineSyncService.instance.pendingCountNotifier.removeListener(_onQueueChanged);
    _refreshDebounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  bool get _isToday => _date == null || _date == _today;

  /// The offline queue grew (something done offline) or shrank (it synced).
  void _onQueueChanged() {
    _loadPending();
    _onSignal();
  }

  Future<void> _loadPending() async {
    final pending = await buildPendingActivity();
    if (mounted) setState(() => _pending = pending);
  }

  void _onSignal() {
    if (!_isToday) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 900), () => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final result = await ApiService.getActivityLogs(date: _isToday ? null : _date);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _error = null;
        _offlineCopyAt = result['is_offline'] == true
            ? DateTime.tryParse(result['cached_at']?.toString() ?? '')?.toLocal()
            : null;
        _entries = (result['data'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ActivityLogEntry.fromApi(Map<String, dynamic>.from(e)))
            .toList();
        final day = result['date']?.toString();
        if (_date == null || _isToday) {
          _today = day;
          _date = day;
        }
      } else if (!silent || _entries.isEmpty) {
        _error = result['error']?.toString() ?? 'Failed to load activity log';
      } else if (result['is_offline'] == true) {
        // Went offline with the log already on screen: keep it, say so.
        _offlineCopyAt ??= DateTime.now();
      }
    });
  }

  void _shiftDay(int days) {
    final current = DateTime.tryParse(_date ?? '');
    if (current == null) return;
    final next = current.add(Duration(days: days));
    final today = DateTime.tryParse(_today ?? '');
    if (today != null && next.isAfter(today)) return;
    String two(int v) => v.toString().padLeft(2, '0');
    setState(() {
      _date = '${next.year}-${two(next.month)}-${two(next.day)}';
      _expanded.clear();
    });
    _load();
  }

  String get _dayLabel {
    final d = DateTime.tryParse(_date ?? '');
    if (d == null) return 'Today';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final text = '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
    if (_isToday) return 'Today · $text';
    final today = DateTime.tryParse(_today ?? '');
    if (today != null && today.difference(d).inDays == 1) return 'Yesterday · $text';
    return text;
  }

  bool _onFloor(ActivityLogEntry e) {
    final floor = widget.floorScope ?? _floor;
    if (floor == 'all') return true;
    final gf = widget.isGroundFloor(e.floor, e.tableNumber);
    return floor == 'gf' ? gf : !gf;
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.searchQuery.trim().toLowerCase();
    final all = [if (_isToday) ..._pending, ..._entries];
    final onFloor = all.where(_onFloor).where((e) => query.isEmpty || e.searchText.contains(query)).toList();
    final counts = <String, int>{};
    for (final e in onFloor) {
      counts[e.action] = (counts[e.action] ?? 0) + 1;
    }
    final shown = _action == 'all' ? onFloor : onFloor.where((e) => e.action == _action).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _buildDayBar(),
        ),
        if (widget.floorScope == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('All Floors', _floor == 'all', () => setState(() => _floor = 'all')),
                  _chip('Ground Floor', _floor == 'gf', () => setState(() => _floor = 'gf')),
                  _chip('2nd Floor', _floor == '2f', () => setState(() => _floor = '2f')),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('All', _action == 'all', () => setState(() => _action = 'all'), count: onFloor.length),
                for (final entry in _ActionMeta.all.entries)
                  if ((counts[entry.key] ?? 0) > 0 || _action == entry.key)
                    _chip(
                      entry.value.chip,
                      _action == entry.key,
                      () => setState(() => _action = entry.key),
                      count: counts[entry.key] ?? 0,
                      color: entry.value.color,
                    ),
              ],
            ),
          ),
        ),
        if (_offlineCopyAt != null || (_error != null && _pending.isNotEmpty))
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: _offlineBanner(),
          ),
        const SizedBox(height: 10),
        Expanded(child: _buildList(shown)),
      ],
    );
  }

  Widget _buildDayBar() {
    final canGoForward = !_isToday;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: _date == null ? null : () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left_rounded, color: _navy),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ACTIVITY LOG',
                  style: GoogleFonts.urbanist(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: _muted,
                  ),
                ),
                Text(
                  _dayLabel,
                  style: GoogleFonts.urbanist(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: canGoForward ? () => _shiftDay(1) : null,
            icon: Icon(Icons.chevron_right_rounded, color: canGoForward ? _navy : Colors.grey.shade300),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded, color: _navy),
          ),
        ],
      ),
    );
  }

  Widget _offlineBanner() {
    final at = _offlineCopyAt;
    final text = at == null
        ? 'Offline — only this tablet\'s unsynced actions can be shown.'
        : 'Offline — showing the log as of ${formatClock(at)}.'
            '${_pending.isEmpty ? '' : ' This tablet\'s unsynced actions are listed first.'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFFD97706)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.urbanist(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {int? count, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: selected ? const LinearGradient(colors: [_navy, _navy2]) : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? _navy : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (color != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GoogleFonts.urbanist(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : Colors.grey.shade800,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.urbanist(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: selected ? _gold : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<ActivityLogEntry> shown) {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }
    if (_error != null && _entries.isEmpty && (_pending.isEmpty || !_isToday)) {
      return _empty(Icons.cloud_off_rounded, _error!);
    }
    if (shown.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            _empty(Icons.history_rounded, 'No activity yet'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        itemCount: shown.length,
        itemBuilder: (context, i) => _ActivityCard(
          entry: shown[i],
          expanded: _expanded.contains(shown[i].id),
          onTap: () => setState(() {
            if (!_expanded.remove(shown[i].id)) _expanded.add(shown[i].id);
          }),
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String text) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: _navy.withValues(alpha: 0.2)),
        const SizedBox(height: 12),
        Text(
          text.toUpperCase(),
          textAlign: TextAlign.center,
          style: GoogleFonts.urbanist(
            color: _navy.withValues(alpha: 0.45),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final ActivityLogEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  const _ActivityCard({required this.entry, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = _ActionMeta.of(entry.action);
    final details = _detailLines();
    final table = (entry.tableNumber ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: details.isEmpty ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(meta.icon, size: 21, color: meta.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                table.isEmpty ? (entry.orderNo ?? 'Order') : table,
                                style: GoogleFonts.urbanist(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: meta.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  meta.label.toUpperCase(),
                                  style: GoogleFonts.urbanist(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                    color: meta.color,
                                  ),
                                ),
                              ),
                              if (entry.pending)
                                _badge('NOT SYNCED YET', const Color(0xFFD97706), filled: true)
                              else if (entry.syncedLate)
                                _badge('SYNCED LATER', _muted),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            entry.summary,
                            style: GoogleFonts.urbanist(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: _navy.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              'by ${entry.who}',
                              if ((entry.orderNo ?? '').isNotEmpty && table.isNotEmpty) entry.orderNo!,
                            ].join('  ·  '),
                            style: GoogleFonts.urbanist(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          entry.createdAt == null ? '' : formatClock(entry.createdAt!),
                          style: GoogleFonts.urbanist(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: _navy,
                          ),
                        ),
                        if (entry.amount != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            '₱${formatPrice(entry.amount!)}',
                            style: GoogleFonts.urbanist(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFD97706),
                            ),
                          ),
                        ],
                        if (details.isNotEmpty)
                          Icon(
                            expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            size: 20,
                            color: _muted,
                          ),
                      ],
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topCenter,
                  child: expanded && details.isNotEmpty
                      ? Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 10, left: 52),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: details,
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _badge(String text, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filled ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
            size: 12,
            color: filled ? Colors.white : color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.urbanist(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: filled ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }

  static String _qty(dynamic v) {
    final n = (v as num?)?.toDouble() ?? double.tryParse(v?.toString() ?? '') ?? 0;
    return n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2);
  }

  static double _num(dynamic v) => (v as num?)?.toDouble() ?? double.tryParse(v?.toString() ?? '') ?? 0;

  Widget _row(String left, {String? right, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: GoogleFonts.urbanist(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color ?? _navy,
              ),
            ),
          ),
          if (right != null)
            Text(
              right,
              style: GoogleFonts.urbanist(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color ?? _navy,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _detailLines() {
    final d = entry.details;
    if (d == null) return const [];
    final lines = <Widget>[];
    final items = d['items'];
    if (items is List) {
      for (final it in items.whereType<Map>()) {
        lines.add(_row(
          '${_qty(it['qty'])}× ${it['name'] ?? 'Item'}',
          right: it['line_total'] == null ? null : '₱${formatPrice(_num(it['line_total']))}',
        ));
      }
      final hours = d['room_hours'];
      if (hours != null) lines.add(_row('Room charge', right: formatRoomHours(_num(hours))));
    }
    switch (entry.action) {
      case 'items_edited':
        for (final it in (d['added'] as List? ?? const []).whereType<Map>()) {
          lines.add(_row('+ ${_qty(it['qty'])}× ${it['name']}', color: const Color(0xFF16A34A)));
        }
        for (final it in (d['removed'] as List? ?? const []).whereType<Map>()) {
          lines.add(_row('− ${_qty(it['qty'])}× ${it['name']}', color: const Color(0xFFDC2626)));
        }
        for (final it in (d['changed'] as List? ?? const []).whereType<Map>()) {
          lines.add(_row('${it['name']}', right: '${_qty(it['from'])} → ${_qty(it['to'])}'));
        }
        break;
      case 'settled':
        lines.add(_row('Payment', right: '${d['payment_method'] ?? '—'}'));
        lines.add(_row('Amount paid', right: '₱${formatPrice(_num(d['amount_paid']))}'));
        if (_num(d['discount']) > 0) {
          lines.add(_row('Discount', right: '−₱${formatPrice(_num(d['discount']))}', color: const Color(0xFFDC2626)));
        }
        if (_num(d['change']) > 0) lines.add(_row('Change', right: '₱${formatPrice(_num(d['change']))}'));
        if ((d['payment_ref'] ?? '').toString().isNotEmpty) lines.add(_row('Reference', right: '${d['payment_ref']}'));
        break;
      case 'transferred':
        lines.add(_row('From', right: '${d['from_table'] ?? '—'}'));
        lines.add(_row('To', right: '${d['to_table'] ?? '—'}'));
        if (d['prev_room_hours'] != null) {
          lines.add(_row(
            'Old room billed',
            right: d['carry_over'] == true ? 'time carried over' : formatRoomHours(_num(d['prev_room_hours'])),
          ));
        }
        if (d['new_room_hours'] != null) lines.add(_row('New room', right: formatRoomHours(_num(d['new_room_hours']))));
        if (d['service_charge_from'] != null && d['service_charge_to'] != null) {
          lines.add(_row(
            'Room charge',
            right: '₱${formatPrice(_num(d['service_charge_from']))} → ₱${formatPrice(_num(d['service_charge_to']))}',
          ));
        }
        break;
      case 'room_charge':
        lines.add(_row(
          'Hours',
          right: '${formatRoomHours(_num(d['from_hours']))} → ${formatRoomHours(_num(d['to_hours']))}',
        ));
        if (d['rate'] != null) lines.add(_row('Rate', right: '₱${formatPrice(_num(d['rate']))}/hr'));
        lines.add(_row(
          'Room charge',
          right: '₱${formatPrice(_num(d['service_charge_from']))} → ₱${formatPrice(_num(d['service_charge_to']))}',
        ));
        break;
      case 'cancelled':
        if ((d['remarks'] ?? '').toString().isNotEmpty) lines.add(_row('Note: ${d['remarks']}', color: _muted));
        break;
      case 'order_created':
        if (d['offline'] == true) lines.add(_row('Taken offline, synced later', color: _muted));
        break;
    }
    return lines;
  }
}

/// This tablet's actions that haven't reached the server yet (the offline
/// queue), as log entries — newest first, marked "Not synced yet". Labels
/// come from the data cached on the device (orders, tables, menu).
Future<List<ActivityLogEntry>> buildPendingActivity() async {
  final actions = OfflineSyncService.instance.pendingActions;
  if (actions.isEmpty) return const [];

  final sync = OfflineSyncService.instance;
  final orders = await sync.getCachedOrders() ?? const <Map<String, dynamic>>[];
  final tables = await sync.getCachedTables() ?? const <Map<String, dynamic>>[];
  final menu = await sync.getCachedMenu() ?? const <Map<String, dynamic>>[];
  final user = await ApiService.getUserData();

  int? idOf(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
  double numOf(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  final orderById = <int, Map<String, dynamic>>{};
  for (final o in orders) {
    final id = idOf(o['order_id'] ?? o['IDNo'] ?? o['id']);
    if (id != null) orderById[id] = o;
  }
  final tableName = <int, String>{};
  for (final t in tables) {
    final id = idOf(t['id'] ?? t['IDNo']);
    final name = t['table_number']?.toString();
    if (id != null && name != null) tableName[id] = name;
  }
  final menuName = <int, String>{};
  for (final m in menu) {
    final id = idOf(m['id']);
    final name = m['name']?.toString();
    if (id != null && name != null) menuName[id] = name;
  }

  final fullname = [user['firstname'], user['lastname']]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  String? role = user['role'];
  if (role != null && role.isNotEmpty) role = role[0].toUpperCase() + role.substring(1);

  List<Map<String, dynamic>> itemsOf(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((it) {
      final menuId = idOf(it['menu_id']);
      final qty = numOf(it['qty']);
      return <String, dynamic>{
        'name': it['menu_name'] ?? (menuId == null ? null : menuName[menuId]) ?? 'Item',
        'qty': qty,
        'line_total': qty * numOf(it['unit_price']),
      };
    }).toList();
  }

  String itemsText(List<Map<String, dynamic>> items) {
    final parts = items.take(3).map((i) {
      final q = numOf(i['qty']);
      return '${q % 1 == 0 ? q.toInt() : q}× ${i['name']}';
    }).toList();
    if (items.length > 3) parts.add('+${items.length - 3} more');
    return parts.join(', ');
  }

  final entries = <ActivityLogEntry>[];
  for (var i = 0; i < actions.length; i++) {
    final a = actions[i];
    final p = a.payload;
    final order = orderById[a.orderId];
    final tableId = idOf(p['table_id'] ?? order?['table_id']);
    String? table = order?['table_number']?.toString() ?? (tableId == null ? null : tableName[tableId]);
    final orderNo = (p['order_no'] ?? order?['order_no'])?.toString();
    double? amount = order == null ? null : numOf(order['grand_total']);
    String action;
    String summary;
    Map<String, dynamic>? details;

    switch (a.type) {
      case 'create_order':
        final items = itemsOf(p['items']);
        amount = numOf(p['grand_total']);
        action = 'order_created';
        summary = 'New order · ${items.length} item${items.length == 1 ? '' : 's'} · ₱${formatPrice(amount)}';
        details = {'items': items};
        break;
      case 'add_items':
        final items = itemsOf(p['items']);
        action = 'items_added';
        summary = 'Added ${itemsText(items)}';
        details = {'items': items};
        break;
      case 'update_status':
        final status = idOf(p['status']);
        if (status == 1) {
          action = 'settled';
          if (p['grand_total'] != null) amount = numOf(p['grand_total']);
          summary = 'Settled ₱${formatPrice(amount ?? 0)} · ${p['payment_method'] ?? 'CASH'}';
          details = {
            'payment_method': p['payment_method'] ?? 'CASH',
            'amount_paid': p['amount_paid'] ?? amount,
            'discount': p['discount_amount'] ?? 0,
          };
        } else if (status == -1) {
          action = 'cancelled';
          summary = 'Cancelled order';
        } else {
          action = 'confirmed';
          summary = 'Confirmed order';
        }
        break;
      case 'transfer_table':
        final target = idOf(p['target_table_id']);
        final to = target == null ? 'another table' : (tableName[target] ?? 'table #$target');
        action = 'transferred';
        summary = 'Moved to $to';
        table = to;
        details = {
          'to_table': to,
          if (p['prev_room_hours'] != null) 'prev_room_hours': p['prev_room_hours'],
          if (p['new_room_hours'] != null) 'new_room_hours': p['new_room_hours'],
          if (p['carry_over'] != null) 'carry_over': p['carry_over'],
        };
        break;
      case 'extend_room_charge':
        action = 'room_charge';
        final sessions = p['sessions'];
        summary = sessions != null
            ? 'Room charge → ${formatRoomHours(numOf(sessions))}'
            : 'Room charge +${formatRoomHours(numOf(p['qty'] ?? 1))}';
        break;
      default:
        continue;
    }

    final created = a.createdAt.toUtc().add(const Duration(hours: 8));
    entries.add(ActivityLogEntry(
      id: -(i + 1),
      orderId: a.orderId,
      orderNo: orderNo,
      tableNumber: table,
      floor: order?['floor']?.toString(),
      action: action,
      summary: summary,
      details: details,
      amount: amount,
      username: user['username'],
      fullname: fullname.isEmpty ? null : fullname,
      role: role,
      createdAt: DateTime(created.year, created.month, created.day, created.hour, created.minute, created.second),
      pending: true,
    ));
  }
  return entries.reversed.toList();
}
