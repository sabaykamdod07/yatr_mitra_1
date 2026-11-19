import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Turns the stops of a route into a line that follows the real roads.
///
/// Uses the free OpenStreetMap routing service (OSRM). It needs internet, and it
/// is meant for light use. If anything goes wrong (no internet, the service is
/// busy, the stops are too far apart or have bad coordinates) [fetch] returns
/// null and the screens keep drawing the straight line between stops, exactly
/// as before. Nothing in the app depends on this succeeding.
class RoadRoute {
  RoadRoute._();

  static const _host = 'https://router.project-osrm.org';

  /// A single leg longer than this (straight line) is almost certainly a wrong
  /// coordinate, so we do not ask for a road path at all.
  static const _maxLegMetres = 60000.0;

  static final Map<String, List<LatLng>> _cache = {};

  /// Road path through [stops], in order. null = use the straight line instead.
  static Future<List<LatLng>?> fetch(List<LatLng> stops) async {
    if (stops.length < 2) return null;

    const dist = Distance();
    for (var i = 1; i < stops.length; i++) {
      if (dist(stops[i - 1], stops[i]) > _maxLegMetres) return null;
    }

    final key = stops
        .map((p) =>
            '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
        .join(';');
    final hit = _cache[key];
    if (hit != null) return hit;

    try {
      final coords = stops.map((p) => '${p.longitude},${p.latitude}').join(';');
      final uri = Uri.parse(
          '$_host/route/v1/driving/$coords?overview=full&geometries=geojson');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map || body['code'] != 'Ok') return null;
      final routes = body['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final line = routes[0]['geometry']?['coordinates'];
      if (line is! List) return null;
      final pts = <LatLng>[
        for (final c in line)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (pts.length < 2) return null;
      _cache[key] = pts;
      return pts;
    } catch (e) {
      debugPrint('Road route not available, using straight lines: $e');
      return null;
    }
  }

  /// Index of the point of [path] closest to [target] (used to split a road
  /// path into "already driven" and "still to go").
  static int nearestIndex(List<LatLng> path, LatLng target) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < path.length; i++) {
      final dx = path[i].latitude - target.latitude;
      final dy = path[i].longitude - target.longitude;
      final d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}