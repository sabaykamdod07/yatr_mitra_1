import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Estimated time of arrival of the bus at a stop.
///
/// The estimate uses only data that already exists in the database, so it works
/// the same whether the position comes from the GPS device or (on a bus without
/// a device) from the driver's phone:
///
///   * the bus position            -> `live_locations`
///   * the stops of the route      -> `stops` (in route order)
///   * which stop is next          -> `trip_stops`
///   * how fast the bus is moving  -> the last few positions' speed
///
/// Distances are straight lines between stops multiplied by [roadFactor]
/// (roads are longer than straight lines), so treat the result as an estimate.
class EtaResult {
  const EtaResult(this.duration, this.km);

  final Duration duration;
  final double km;

  DateTime get arrivesAt => DateTime.now().add(duration);

  /// "Arriving now", "7 min", "1h 5m"
  String get label {
    final m = (duration.inSeconds / 60).ceil();
    if (m <= 1) return 'Arriving now';
    if (m < 60) return '$m min';
    return '${m ~/ 60}h ${m % 60}m';
  }
}

class Eta {
  Eta._();

  /// straight line -> road distance
  static const double roadFactor = 1.3;

  /// used when the bus has not been moving (or no speed is known yet)
  static const double fallbackKmh = 20;

  /// anything slower than this is treated as "standing still"
  static const double minMovingKmh = 5;

  /// time the bus spends at every stop on the way
  static const int stopDwellSeconds = 30;

  /// Stops in route order: by `stop_order`, then by pickup time.
  static List<Map<String, dynamic>> sortStops(List<dynamic> stops) {
    final list = [for (final s in stops) Map<String, dynamic>.from(s as Map)];
    list.sort((a, b) {
      final byOrder = (num.tryParse('${a['stop_order'] ?? 0}') ?? 0)
          .compareTo(num.tryParse('${b['stop_order'] ?? 0}') ?? 0);
      if (byOrder != 0) return byOrder;
      return (a['timing'] ?? '').toString().compareTo((b['timing'] ?? '').toString());
    });
    return list;
  }

  static LatLng? pointOf(Map<String, dynamic>? s) {
    final lat = double.tryParse('${s?['lat']}');
    final lng = double.tryParse('${s?['lng']}');
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// ETA from [bus] to `stops[targetIndex]`.
  ///
  /// [nextIndex] is the first stop the bus has not reached yet. Returns null when
  /// the bus has already passed the target, the trip is not running, or the
  /// target stop has no coordinates.
  static EtaResult? estimate({
    required LatLng bus,
    required List<Map<String, dynamic>> stops,
    required int nextIndex,
    required int targetIndex,
    double? avgKmh,
  }) {
    if (nextIndex < 0 || targetIndex < nextIndex || targetIndex >= stops.length) {
      return null;
    }
    if (pointOf(stops[targetIndex]) == null) return null;

    const dist = Distance();
    var meters = 0.0;
    var from = bus;
    var hops = 0;
    for (var i = nextIndex; i <= targetIndex; i++) {
      final p = pointOf(stops[i]);
      if (p == null) continue;
      meters += dist.as(LengthUnit.Meter, from, p);
      from = p;
      if (i < targetIndex) hops++;
    }

    final km = meters * roadFactor / 1000;
    final speed = (avgKmh != null && avgKmh >= minMovingKmh) ? avgKmh : fallbackKmh;
    final seconds = km / speed * 3600 + hops * stopDwellSeconds;
    return EtaResult(Duration(seconds: seconds.round()), km);
  }

  /// Average speed (km/h) of the bus over its last few positions, or null if it
  /// has not been moving. `live_locations.speed` is stored in metres per second.
  static Future<double?> recentSpeedKmh(SupabaseClient sb, String busId) async {
    try {
      final since =
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();
      final rows = await sb
          .from('live_locations')
          .select('speed')
          .eq('bus_id', busId)
          .gte('timestamp', since)
          .order('timestamp', ascending: false)
          .limit(10);
      final moving = [
        for (final r in rows) (double.tryParse('${r['speed']}') ?? 0) * 3.6,
      ].where((k) => k >= minMovingKmh).toList();
      if (moving.isEmpty) return null;
      return moving.reduce((a, b) => a + b) / moving.length;
    } catch (_) {
      return null;
    }
  }
}