import 'package:shared_preferences/shared_preferences.dart';

import '../waiter_models.dart';

/// Warn staff this many minutes before a room's booked time runs out, so they
/// can ask the guest whether to extend.
const int kRoomWarnMinutes = 15;

/// Past this many minutes over, a room that was never warned about (app was
/// closed the whole time) no longer pops up — the card already shows it red.
const int kRoomWarnLateLimitMinutes = 30;

/// Countdown of the room an open order is in now: its clock starts when the
/// order was placed (or when it moved there — see the transfer carry-over)
/// and runs for the hours booked. Null for regular tables, waived rooms
/// (0 hrs) and closed orders.
class RoomCountdown {
  final WaiterOrder order;
  final RoomChargeSegment room;

  const RoomCountdown._(this.order, this.room);

  static RoomCountdown? of(WaiterOrder order, {double fallbackRate = 0}) {
    if (order.status != 2 && order.status != 3) return null;
    final rooms = roomChargeSegmentsOf(order, fallbackRate: fallbackRate);
    if (rooms.isEmpty) return null;
    final room = rooms.last;
    if (!room.isActive || room.hours <= 0 || room.startedAt == null) return null;
    return RoomCountdown._(order, room);
  }

  /// When the booked time runs out (Asia/Manila wall clock).
  DateTime get endsAt =>
      room.startedAt!.add(Duration(minutes: (room.hours * 60).round()));

  /// Time left; negative once it's over.
  Duration get remaining => endsAt.difference(manilaNow());

  bool get isOver => remaining.inSeconds <= 0;

  /// Within the warning window (15 minutes or less left).
  bool get isEndingSoon => remaining.inSeconds <= kRoomWarnMinutes * 60;

  /// Time to warn staff now: 15 minutes or less left, and not long past.
  bool get shouldWarn =>
      isEndingSoon && remaining.inMinutes > -kRoomWarnLateLimitMinutes;

  /// Two warnings per booking — "15 minutes left", then "time is up" if it
  /// wasn't extended. Extending moves [endsAt], which makes new keys (so the
  /// next "15 minutes left" warns again).
  String get alertKey => '${order.id}|${formatManilaSql(endsAt)}|${isOver ? 'over' : 'soon'}';

  /// "1h 12m left", "8m left", "Time's up", "+5m over".
  String get label {
    final secs = remaining.inSeconds;
    if (secs > 0) {
      final mins = (secs / 60).ceil();
      return '${formatMinutesUsed(mins)} left';
    }
    final over = (-secs) ~/ 60;
    return over == 0 ? "Time's up" : '+${formatMinutesUsed(over)} over';
  }

  String get roomName => room.roomLabel;
}

/// Room-time warnings already shown, shared by the app and its background
/// service (separate isolates — SharedPreferences is the one thing both see).
/// The app and the background notification keep separate lists, so a
/// notification fired while the app was closed is still followed by the
/// in-app popup once it's opened (same flow as new-order alerts).
class RoomTimeAlertLog {
  RoomTimeAlertLog._();

  static const String _foregroundKey = 'room_time_alerted_fg';
  static const String _backgroundKey = 'room_time_alerted_bg';
  static const int _keep = 200;

  /// Records [alertKey]; true when it wasn't recorded before (i.e. warn now).
  static Future<bool> claim(String alertKey, {bool background = false}) async {
    final prefs = await SharedPreferences.getInstance();
    // The other isolate may have written since this one cached its copy.
    await prefs.reload();
    final key = background ? _backgroundKey : _foregroundKey;
    final list = prefs.getStringList(key) ?? <String>[];
    if (list.contains(alertKey)) return false;
    list.add(alertKey);
    if (list.length > _keep) list.removeRange(0, list.length - _keep);
    await prefs.setStringList(key, list);
    return true;
  }
}
