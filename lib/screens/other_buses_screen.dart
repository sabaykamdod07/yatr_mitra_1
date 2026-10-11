import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import 'live_bus_screen.dart';

class _C {
  static const bg = Color(0xFFFFF8F1);
  static const navy = Color(0xFF0F1B4D);
  static const orange = Color(0xFFFF9800);
  static const orangeSoft = Color(0xFFFFEFD9);
  static const grey = Color(0xFF8E94A9);
  static const green = Color(0xFF0E9F6E);
  static const red = Color(0xFFE53935);
  static const blue = Color(0xFF3B6FF5);
}

BoxDecoration _deco() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3)),
      ],
    );

Widget _chip(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );

// ═════════════════════════════════════════════════════════════════
// OTHER BUSES  (tabs: All Routes | My Route)
// ═════════════════════════════════════════════════════════════════

class OtherBusesScreen extends StatefulWidget {
  const OtherBusesScreen({super.key, this.faculty = false});

  /// true when a faculty member opens it (the ride request is then saved for the faculty member)
  final bool faculty;

  @override
  State<OtherBusesScreen> createState() => _OtherBusesScreenState();
}

class _OtherBusesScreenState extends State<OtherBusesScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  String? _error;
  String? _myRouteId;
  List<Map<String, dynamic>> _routes = [];
  Set<String> _live = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ctx = await StudentContext.load(faculty: widget.faculty);
      final inst = ctx.student['institution_id'];

      var routes = <Map<String, dynamic>>[];
      var live = <String>{};
      if (inst != null) {
        final rows = await _sb
            .from('routes')
            .select('id, route_name, start_point, end_point, bus_id')
            .eq('institution_id', inst)
            .order('route_name', ascending: true);
        routes = List<Map<String, dynamic>>.from(rows);

        final ids = routes.map((r) => r['id'].toString()).toList();
        if (ids.isNotEmpty) {
          final trips = await _sb
              .from('trips')
              .select('route_id')
              .eq('status', 'in_progress')
              .inFilter('route_id', ids);
          live = trips.map<String>((t) => t['route_id'].toString()).toSet();
        }
      }

      if (!mounted) return;
      setState(() {
        _myRouteId = ctx.routeId;
        _routes = routes;
        _live = live;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        size: 20, color: _C.navy),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text('Other Buses / Routes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _C.navy)),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: _C.blue,
              unselectedLabelColor: _C.grey,
              indicatorColor: _C.blue,
              tabs: const [Tab(text: 'All Routes'), Tab(text: 'My Route')],
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _C.orange))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _C.grey)),
                          ),
                        )
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            _allRoutes(),
                            _myRouteId == null
                                ? const Center(
                                    child: Text('No route assigned yet',
                                        style: TextStyle(color: _C.grey)))
                                : RouteDetailsView(
                                    routeId: _myRouteId!, faculty: widget.faculty),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allRoutes() {
    return RefreshIndicator(
      color: _C.orange,
      onRefresh: _load,
      child: _routes.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(
                    child: Text('No routes found',
                        style: TextStyle(color: _C.grey))),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _routes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = _routes[i];
                final id = r['id'].toString();
                final live = _live.contains(id);
                final mine = id == _myRouteId;
                final from = r['start_point']?.toString() ?? '';
                final to = r['end_point']?.toString() ?? '';
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RouteDetailsScreen(
                        routeId: id,
                        routeName: r['route_name'].toString(),
                        faculty: widget.faculty),
                  )),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: _deco(),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                              color: _C.orangeSoft,
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Iconsax.bus, color: _C.orange),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(r['route_name'].toString(),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: _C.navy)),
                                  ),
                                  if (mine) ...[
                                    const SizedBox(width: 8),
                                    _chip('My route', _C.blue),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (from.isNotEmpty || to.isNotEmpty)
                                    ? '$from → $to'
                                    : '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: _C.grey, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(live ? 'Live now' : 'Not running',
                                  style: TextStyle(
                                      color: live ? _C.green : _C.grey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: _C.grey),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// ROUTE DETAILS  (screen wrapper + reusable view)
// ═════════════════════════════════════════════════════════════════

class RouteDetailsScreen extends StatelessWidget {
  const RouteDetailsScreen(
      {super.key,
      required this.routeId,
      required this.routeName,
      this.faculty = false});

  final String routeId;
  final String routeName;
  final bool faculty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        size: 20, color: _C.navy),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(routeName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _C.navy)),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(child: RouteDetailsView(routeId: routeId, faculty: faculty)),
          ],
        ),
      ),
    );
  }
}

class RouteDetailsView extends StatefulWidget {
  const RouteDetailsView({super.key, required this.routeId, this.faculty = false});

  final String routeId;
  final bool faculty;

  @override
  State<RouteDetailsView> createState() => _RouteDetailsViewState();
}

class _RouteDetailsViewState extends State<RouteDetailsView> {
  final _sb = Supabase.instance.client;

  StudentContext? _ctx;
  List<Map<String, dynamic>> _stops = [];
  Map<String, String> _stopStatus = {}; // stop_id -> reached / pending
  bool _tripActive = false;

  bool _loading = true;
  String? _error;
  bool _sending = false;
  DateTime _rideDate = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RouteDetailsView old) {
    super.didUpdateWidget(old);
    if (old.routeId != widget.routeId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ctx = await StudentContext.load(
          forRouteId: widget.routeId, faculty: widget.faculty);

      final stopRows = await _sb
          .from('stops')
          .select('id, stop_name, timing, stop_order')
          .eq('route_id', widget.routeId)
          .order('stop_order', ascending: true);

      final trip = await _sb
          .from('trips')
          .select('id')
          .eq('route_id', widget.routeId)
          .eq('status', 'in_progress')
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final status = <String, String>{};
      if (trip != null) {
        final ts = await _sb
            .from('trip_stops')
            .select('stop_id, status')
            .eq('trip_id', trip['id']);
        for (final r in ts) {
          status[r['stop_id'].toString()] = r['status'].toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _stops = List<Map<String, dynamic>>.from(stopRows);
        _stopStatus = status;
        _tripActive = trip != null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtTime(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _rideDate.isBefore(now) ? now : _rideDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (d != null) setState(() => _rideDate = d);
  }

  Future<void> _notify(String target) async {
    final ctx = _ctx;
    if (ctx == null) return;
    setState(() => _sending = true);
    try {
      await _sb.from('one_day_requests').insert({
        'institution_id': ctx.student['institution_id'],
        if (ctx.isFaculty) 'faculty_id': ctx.student['id'] else 'student_id': ctx.student['id'],
        'route_id': widget.routeId,
        'ride_date': dateKey(_rideDate),
        'target': target,
      });
      if (!mounted) return;
      _snack(target == 'driver'
          ? 'Driver notified for ${fmtDate(_rideDate)}.'
          : 'Incharge notified for ${fmtDate(_rideDate)}.');
    } catch (e) {
      if (mounted) _snack('Could not send: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _C.red : _C.navy,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _C.orange));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _C.grey)),
        ),
      );
    }

    final ctx = _ctx!;
    final routeName = ctx.route?['route_name']?.toString() ?? 'Route';
    final from = ctx.route?['start_point']?.toString() ?? '';
    final to = ctx.route?['end_point']?.toString() ?? '';
    final busNumber = ctx.bus?['bus_number']?.toString();

    // The first stop that is not reached yet is the "current / next" stop.
    final currentIdx = _tripActive
        ? _stops.indexWhere((s) => _stopStatus[s['id'].toString()] != 'reached')
        : -1;

    return RefreshIndicator(
      color: _C.orange,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _deco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(routeName,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: _C.navy)),
                    ),
                    _chip(_tripActive ? 'Live now' : 'Not running',
                        _tripActive ? _C.green : _C.grey),
                  ],
                ),
                if (from.isNotEmpty || to.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$from → $to',
                        style: const TextStyle(color: _C.grey, fontSize: 13)),
                  ),
                if (busNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Bus $busNumber'
                        '${ctx.driverName != null ? '  •  Driver ${ctx.driverName}' : ''}',
                        style: const TextStyle(color: _C.grey, fontSize: 13)),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LiveBusScreen(
                            routeId: widget.routeId,
                            title: routeName,
                            faculty: widget.faculty),
                      ),
                    ),
                    icon: const Icon(Iconsax.map_1, size: 18),
                    label: const Text('View Live Map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Stops (${_stops.length})',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _C.navy)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _deco(),
            child: _stops.isEmpty
                ? const Text('No stops added for this route yet',
                    style: TextStyle(color: _C.grey))
                : Column(
                    children: [
                      for (var i = 0; i < _stops.length; i++)
                        _stopRow(i, currentIdx),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          const Text('Ride this route on a particular day',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _C.navy)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _deco(),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: _C.grey.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 18, color: _C.navy),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(fmtDate(_rideDate),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _C.navy)),
                        ),
                        const Text('Change',
                            style: TextStyle(color: _C.blue, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _sending ? null : () => _notify('driver'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _C.navy,
                          side: const BorderSide(color: _C.orange),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Notify Driver'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _sending ? null : () => _notify('incharge'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _C.navy,
                          side: const BorderSide(color: _C.orange),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Notify Incharge'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopRow(int i, int currentIdx) {
    final s = _stops[i];
    final id = s['id'].toString();
    final reached = _stopStatus[id] == 'reached';
    final isCurrent = i == currentIdx;

    String? label;
    Color color = _C.grey;
    if (_tripActive) {
      if (reached) {
        label = 'Reached';
        color = _C.green;
      } else if (isCurrent) {
        label = 'Next';
        color = _C.blue;
      } else {
        label = 'Pending';
      }
    }

    final time = _fmtTime(s['timing']);
    final isLast = i == _stops.length - 1;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: reached || isCurrent ? color : Colors.white,
              border: Border.all(color: color, width: 2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Stop ${i + 1}  •  ${s['stop_name']}',
                style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    color: _C.navy)),
          ),
          if (time.isNotEmpty)
            Text(time, style: const TextStyle(color: _C.grey, fontSize: 12)),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}