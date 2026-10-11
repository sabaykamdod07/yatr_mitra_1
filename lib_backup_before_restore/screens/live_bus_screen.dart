import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax/iconsax.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/eta.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import 'geofence_settings_screen.dart';

class _C {
  static const bg = Color(0xFFFFF8F1);
  static const navy = Color(0xFF0F1B4D);
  static const orange = Color(0xFFFF9800);
  static const orangeSoft = Color(0xFFFFEFD9);
  static const grey = Color(0xFF8E94A9);
  static const green = Color(0xFF0E9F6E);
  static const red = Color(0xFFE53935);
  static const blue = Color(0xFF3B6FF5);
  static const border = Color(0xFFF6E3C6);
}

/// Student's live bus view.
///
/// DATA SOURCE (hardware ready): this screen only READS `live_locations`.
/// Today the driver's phone writes there; later the GPS device writes there.
/// Nothing in this file changes when the hardware is connected.
class LiveBusScreen extends StatefulWidget {
  const LiveBusScreen({super.key, this.routeId, this.title, this.studentId, this.faculty = false});

  /// null = the student's own route. Set it to watch another route (Other Buses).
  final String? routeId;
  final String? title;

  /// Set by the parent app: follow this child's bus instead of the logged-in student's.
  final String? studentId;

  /// Set by the faculty app: follow the logged-in FACULTY member's own bus.
  final bool faculty;

  @override
  State<LiveBusScreen> createState() => _LiveBusScreenState();
}

class _LiveBusScreenState extends State<LiveBusScreen> {
  final _sb = Supabase.instance.client;
  final _map = MapController();

  StudentContext? _ctx;
  List<Map<String, dynamic>> _routeStops = [];

  LatLng? _busPos;
  DateTime? _busTime;
  double? _speed;
  bool _tripActive = false;
  String? _lastStop;
  String? _nextStop;
  String? _nextStopId;
  double? _avgKmh;
  DateTime? _avgAt;
  EtaResult? _etaMine; // to the student's own boarding stop
  EtaResult? _etaNext; // to the next stop of the trip

  bool _loading = true;
  String? _error;
  bool _follow = true;

  RealtimeChannel? _channel;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_channel != null) _sb.removeChannel(_channel!);
    super.dispose();
  }

  // ───────────────────────── DATA ─────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ctx = await StudentContext.load(
          forRouteId: widget.routeId,
          studentId: widget.studentId,
          faculty: widget.faculty);

      var stops = <Map<String, dynamic>>[];
      if (ctx.routeId != null) {
        final rows = await _sb
            .from('stops')
            .select('id, stop_name, timing, lat, lng, stop_order')
            .eq('route_id', ctx.routeId!)
            .order('stop_order', ascending: true);
        stops = Eta.sortStops(rows);
      }

      if (!mounted) return;
      _ctx = ctx;
      _routeStops = stops;
      await _refreshLive();

      if (!mounted) return;
      setState(() => _loading = false);

      _subscribe();
      _poll?.cancel();
      // Safety net in case a realtime message is missed.
      _poll = Timer.periodic(
          const Duration(seconds: 15), (_) => _refreshLive(rebuild: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshLive({bool rebuild = false}) async {
    final ctx = _ctx;
    if (ctx == null) return;
    try {
      if (ctx.busId != null) {
        final rows = await _sb
            .from('live_locations')
            .select('lat, lng, speed, timestamp')
            .eq('bus_id', ctx.busId!)
            .order('timestamp', ascending: false)
            .limit(1);
        if (rows.isNotEmpty) _applyLocation(Map<String, dynamic>.from(rows.first));
      }

      if (ctx.routeId != null) {
        final trip = await _sb
            .from('trips')
            .select('id')
            .eq('route_id', ctx.routeId!)
            .eq('status', 'in_progress')
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (trip == null) {
          _tripActive = false;
          _lastStop = null;
          _nextStop = null;
          _nextStopId = null;
        } else {
          _tripActive = true;
          final ts = await _sb
              .from('trip_stops')
              .select('status, stop_order, stop_id, stops(stop_name)')
              .eq('trip_id', trip['id'])
              .order('stop_order', ascending: true);
          String? last;
          String? next;
          String? nextId;
          for (final r in ts) {
            final name = (r['stops'] as Map?)?['stop_name']?.toString();
            if (r['status'] == 'reached') {
              last = name;
            } else if (next == null) {
              next = name;
              nextId = r['stop_id']?.toString();
            }
          }
          _lastStop = last;
          _nextStop = next;
          _nextStopId = nextId;
        }
      }

      // average speed of the bus (refreshed at most every 20 seconds)
      if (ctx.busId != null &&
          (_avgAt == null ||
              DateTime.now().difference(_avgAt!).inSeconds > 20)) {
        _avgKmh = await Eta.recentSpeedKmh(_sb, ctx.busId!);
        _avgAt = DateTime.now();
      }
      _recomputeEta();
    } catch (e) {
      debugPrint('Live bus refresh failed: $e');
    }
    if (rebuild && mounted) setState(() {});
  }

  /// ETA to the student's stop and to the next stop of the running trip.
  void _recomputeEta() {
    final bus = _busPos;
    final ctx = _ctx;
    final nextId = _nextStopId;
    if (bus == null || ctx == null || !_tripActive || nextId == null) {
      _etaMine = null;
      _etaNext = null;
      return;
    }
    final nextIdx = _routeStops.indexWhere((s) => s['id'].toString() == nextId);
    if (nextIdx < 0) {
      _etaMine = null;
      _etaNext = null;
      return;
    }
    _etaNext = Eta.estimate(
        bus: bus,
        stops: _routeStops,
        nextIndex: nextIdx,
        targetIndex: nextIdx,
        avgKmh: _avgKmh);
    final mineId = ctx.stop?['id']?.toString();
    final mineIdx =
        mineId == null ? -1 : _routeStops.indexWhere((s) => s['id'].toString() == mineId);
    _etaMine = mineIdx < 0
        ? null
        : Eta.estimate(
            bus: bus,
            stops: _routeStops,
            nextIndex: nextIdx,
            targetIndex: mineIdx,
            avgKmh: _avgKmh);
  }

  void _applyLocation(Map<String, dynamic> r) {
    final lat = double.tryParse('${r['lat']}');
    final lng = double.tryParse('${r['lng']}');
    if (lat == null || lng == null) return;
    _busPos = LatLng(lat, lng);
    _busTime = parseUtc(r['timestamp']);
    _speed = double.tryParse('${r['speed']}');
  }

  void _subscribe() {
    final busId = _ctx?.busId;
    if (busId == null) return;
    _channel = _sb
        .channel('live_bus_$busId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'bus_id',
            value: busId,
          ),
          callback: (payload) {
            if (!mounted) return;
            setState(() {
              _applyLocation(payload.newRecord);
              _recomputeEta();
            });
            _followBus();
          },
        )
        .subscribe();
  }

  void _followBus() {
    if (!_follow || _busPos == null) return;
    try {
      _map.move(_busPos!, _map.camera.zoom);
    } catch (_) {
      // map not on screen yet
    }
  }

  void _recenter() {
    final target = _busPos ?? _stopPoint;
    if (target == null) return;
    setState(() => _follow = true);
    try {
      _map.move(target, 15);
    } catch (_) {}
  }

  LatLng? get _stopPoint {
    final c = _ctx;
    if (c?.stopLat == null || c?.stopLng == null) return null;
    return LatLng(c!.stopLat!, c.stopLng!);
  }

  Future<void> _callDriver() async {
    final phone = _ctx?.driverPhone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver phone number is not available yet.'),
          backgroundColor: _C.navy,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return YmPage(
        title: widget.title ?? 'Live Bus',
        child: const YmSkeletonList(count: 3, height: 150),
      );
    }
    if (_error != null) {
      return YmPage(
        title: widget.title ?? 'Live Bus',
        child: YmEmpty(
          icon: Iconsax.warning_2,
          color: Ym.red,
          title: 'Could not load the live map',
          subtitle: _error,
          action: YmButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              expanded: false,
              onPressed: _load),
        ),
      );
    }
    final ctx = _ctx!;
    if (ctx.busId == null) {
      return YmPage(
        title: widget.title ?? 'Live Bus',
        child: const YmEmpty(
          icon: Iconsax.bus,
          title: 'No bus assigned yet',
          subtitle: 'Your route does not have a bus yet.\nPlease contact your institution.',
        ),
      );
    }
    return Scaffold(
      backgroundColor: Ym.creamTop,
      body: Stack(
        children: [
          Positioned.fill(child: _map_(ctx)),
          Positioned(top: 0, left: 0, right: 0, child: _topBar()),
          Align(alignment: Alignment.bottomCenter, child: _panel(ctx)),
        ],
      ),
    );
  }

  bool get _running {
    final fresh =
        _busTime != null && DateTime.now().difference(_busTime!).inMinutes < 3;
    return _tripActive || fresh;
  }

  Widget _topBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            YmRoundButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: Ym.shadow(Ym.navy, 0.12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_running) ...[
                      const YmPulse(color: Ym.green, size: 7),
                      const SizedBox(width: 2),
                    ],
                    Flexible(
                      child: Text(widget.title ?? 'Live Bus',
                          overflow: TextOverflow.ellipsis,
                          style: Ym.h(16)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            widget.routeId == null && widget.studentId == null && !widget.faculty
                ? YmRoundButton(
                    icon: Icons.tune_rounded,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const GeofenceSettingsScreen()),
                    ),
                  )
                : const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }

  Widget _map_(StudentContext ctx) {
    final stopPoint = _stopPoint;
    final center =
        _busPos ?? stopPoint ?? const LatLng(12.9716, 77.5946); // Bengaluru
    final routePoints = <LatLng>[
      for (final s in _routeStops)
        if (s['lat'] != null && s['lng'] != null)
          LatLng(double.parse('${s['lat']}'), double.parse('${s['lng']}')),
    ];
    final lastIdx = _lastStop == null
        ? -1
        : _routeStops.indexWhere((s) => s['stop_name']?.toString() == _lastStop);

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.yatramitra.app',
            ),
            if (routePoints.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                  points: routePoints,
                  color: Ym.blue.withOpacity(0.75),
                  strokeWidth: 5,
                  borderColor: Colors.white,
                  borderStrokeWidth: 2,
                ),
              ]),
            MarkerLayer(markers: [
              for (var i = 0; i < _routeStops.length; i++)
                if (_routeStops[i]['lat'] != null &&
                    _routeStops[i]['lng'] != null)
                  Marker(
                    point: LatLng(double.parse('${_routeStops[i]['lat']}'),
                        double.parse('${_routeStops[i]['lng']}')),
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: i <= lastIdx ? Ym.green : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: i <= lastIdx ? Colors.white : Ym.grey,
                            width: 2.5),
                        boxShadow: Ym.shadow(Ym.navy, 0.2),
                      ),
                    ),
                  ),
              if (stopPoint != null)
                Marker(
                  point: stopPoint,
                  width: 150,
                  height: 74,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Ym.green,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: Ym.shadow(Ym.green, 0.35),
                        ),
                        child: Text(
                          ctx.stop?['stop_name']?.toString() ?? 'Your stop',
                          overflow: TextOverflow.ellipsis,
                          style: Ym.t(11,
                              color: Colors.white, w: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.location_on, color: Ym.green, size: 38),
                    ],
                  ),
                ),
              if (_busPos != null)
                Marker(
                  point: _busPos!,
                  width: 84,
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const YmPulse(color: Ym.blue, size: 18),
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Ym.blue, Color(0xFF1E3AD8)]),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: Ym.shadow(Ym.blue, 0.45),
                        ),
                        child: const Icon(Iconsax.bus,
                            color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                ),
            ]),
          ],
        ),
        if (_busPos == null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 70, 24, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: Ym.shadow(Ym.navy, 0.1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded,
                          color: Ym.amberDark, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Waiting for the bus to share its location…',
                            style: Ym.t(12.5, color: Ym.grey)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statTile(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.14), color.withOpacity(0.04)],
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ym.h(14.5)),
            const SizedBox(height: 2),
            Text(label, style: Ym.t(10.5, color: Ym.grey)),
          ],
        ),
      ),
    );
  }

  Widget _panel(StudentContext ctx) {
    final stopPoint = _stopPoint;
    String away = '--';
    if (_busPos != null && stopPoint != null) {
      final km = const Distance(roundResult: false)
          .as(LengthUnit.Kilometer, _busPos!, stopPoint);
      away = km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
    }
    final speed = (_speed != null && _running)
        ? '${(_speed! * 3.6).round()} km/h'
        : '--';
    final busNumber = ctx.bus?['bus_number']?.toString() ?? 'Bus';
    final lastIdx = _lastStop == null
        ? -1
        : _routeStops.indexWhere((s) => s['stop_name']?.toString() == _lastStop);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                  color: Ym.navy.withOpacity(0.16),
                  blurRadius: 30,
                  offset: const Offset(0, -8)),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4.5,
                    decoration: BoxDecoration(
                        color: Ym.line, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const YmIconBadge(icon: Iconsax.bus, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(busNumber, style: Ym.h(17)),
                          Text(ctx.route?['route_name']?.toString() ?? '',
                              style: Ym.t(12.5, color: Ym.grey)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        YmChip(_running ? 'On Route' : 'Not running',
                            color: _running ? Ym.green : Ym.grey,
                            icon: Icons.circle),
                        if (ctx.rescueActive) ...[
                          const SizedBox(height: 4),
                          const YmChip('Rescue bus', color: Ym.red),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (ctx.stop != null) ...[
                      _statTile(Iconsax.location, away, 'Away', Ym.green),
                      const SizedBox(width: 10),
                    ],
                    _statTile(Icons.speed_rounded, speed, 'Speed', Ym.blue),
                    const SizedBox(width: 10),
                    _statTile(
                        Icons.schedule_rounded,
                        (ctx.stop != null ? _etaMine : _etaNext)?.label ?? '--',
                        ctx.stop != null ? 'Arrives at you' : 'Next stop ETA',
                        Ym.amberDark),
                  ],
                ),
                if (_nextStop != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.near_me_rounded,
                            size: 16, color: Ym.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Next stop: $_nextStop'
                            '${_etaNext != null ? '  •  ${_etaNext!.label}' : ''}',
                            style: Ym.t(12.5, w: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_etaMine != null && ctx.stop != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 16, color: Ym.green),
                        const SizedBox(width: 8),
                        Text(
                            'Expected at your stop around ${fmtClock(_etaMine!.arrivesAt)}',
                            style: Ym.t(12.5,
                                color: Ym.green, w: FontWeight.w700)),
                      ],
                    ),
                  ),
                if (_routeStops.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _routeStops.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final name = _routeStops[i]['stop_name']?.toString() ?? '';
                        final reached = i <= lastIdx;
                        final isNext = name == _nextStop;
                        final isMine = name == ctx.stop?['stop_name']?.toString();
                        final color = reached
                            ? Ym.green
                            : (isNext ? Ym.blue : Ym.grey);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: color.withOpacity(isNext ? 0.16 : 0.1),
                            borderRadius: BorderRadius.circular(18),
                            border: isMine
                                ? Border.all(color: Ym.amber, width: 1.8)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                reached
                                    ? Icons.check_circle_rounded
                                    : (isMine
                                        ? Icons.location_on
                                        : Icons.circle_outlined),
                                size: 14,
                                color: color,
                              ),
                              const SizedBox(width: 6),
                              Text(name,
                                  style: Ym.t(12,
                                      color: color, w: FontWeight.w700)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Ym.creamTop,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Ym.amber.withOpacity(0.25),
                        child: const Icon(Iconsax.user,
                            color: Ym.amberDark, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Driver', style: Ym.t(11.5, color: Ym.grey)),
                            Text(ctx.driverName ?? 'Not assigned yet',
                                style: Ym.h(14.5)),
                          ],
                        ),
                      ),
                      YmPressable(
                        onTap: _callDriver,
                        child: const YmGradientTile(
                            icon: Icons.call_rounded,
                            color: Ym.green,
                            size: 44),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: -24,
          right: 18,
          child: YmPressable(
            onTap: _recenter,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: Ym.shadow(Ym.navy, 0.2),
              ),
              child: Icon(Icons.my_location_rounded,
                  color: _follow ? Ym.blue : Ym.navy, size: 21),
            ),
          ),
        ),
      ],
    );
  }
}