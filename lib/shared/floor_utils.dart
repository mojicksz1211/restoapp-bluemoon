/// Floor codes stored in `user_info.FLOOR` and `orders.FLOOR`.
const String kFloorGround = 'gf';
const String kFloorSecond = '2f';

/// Returns [kFloorGround] / [kFloorSecond] for a recognised value
/// (case-insensitive), or null for anything else — null/empty means
/// "no floor", i.e. unscoped.
String? normalizeFloor(dynamic raw) {
  final value = raw?.toString().trim().toLowerCase();
  if (value == kFloorGround || value == kFloorSecond) return value;
  return null;
}
