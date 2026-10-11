import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/eta.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import '../widgets/parent_child_picker.dart';
import 'live_bus_screen.dart';

/// The child's route: the bus, the driver, every stop in order with its pickup
/// time, and a marker on the stop where the child boards.
class ParentRouteScreen extends StatefulWidget {
  const ParentRouteScreen({
    super.key,
    required this.children,
    required this.selected,
    this.faculty = false,
  });

  final List<Map<String, dynamic>> children;
  final int selected;

  /// true when a faculty member looks at their own route (children then holds just them)
  final bool faculty;

  @override
  State<ParentRouteScreen> createState() => _ParentRouteScreenState();
}

class _ParentRouteScreenState extends State<ParentRouteScreen> {
  final _sb = Supabase.instance.client;

  late int _sel = widget.selected;
  bool _loading = true;
  String? _error;
  StudentContext? _ctx;
  List<Map<String, dynamic>> _stops = [];

  String get _childId => widget.children[_sel]['id'].toString();
  String get _childName =>
      (widget.children[_sel]['student_name'] ?? 'Your child').toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ctx = await StudentContext.load(
          studentId: widget.faculty ? null : _childId, faculty: widget.faculty);
      var stops = <Map<String, dynamic>>[];
      if (ctx.routeId != null) {
        final rows = await _sb
            .from('stops')
            .select('id, stop_name, timing, lat, lng, stop_order')
            .eq('route_id', ctx.routeId!);
        stops = Eta.sortStops(rows);
      }
      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _stops = stops;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Route & Timings',
      subtitle: _childName,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: YmSkeletonList(count: 4, height: 80),
            )
          : _error != null
              ? YmEmpty(
                  icon: Icons.cloud_off_rounded,
                  color: Ym.red,
                  title: 'Could not load the route',
                  subtitle: _error,
                  action: YmButton(
                      label: 'Try again',
                      icon: Icons.refresh_rounded,
                      expanded: false,
                      onPressed: _load),
                )
              : RefreshIndicator(
                  color: Ym.amber,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                    children: [
                      ParentChildPicker(
                        children: widget.children,
                        selected: _sel,
                        onChanged: (i) {
                          setState(() => _sel = i);
                          _load();
                        },
                      ),
                      if (_ctx?.routeId == null)
                        const YmEmpty(
                          icon: Icons.alt_route_rounded,
                          color: Ym.amberDark,
                          title: 'No route yet',
                          subtitle:
                              'A bus route has not been assigned to this child. The school will add it.',
                        )
                      else ...[
                        _summary(),
                        const SizedBox(height: 22),
                        const YmSectionTitle('Stops'),
                        if (_stops.isEmpty)
                          YmCard(
                            child: Text('No stops have been added to this route yet.',
                                style: Ym.t(13, color: Ym.grey)),
                          )
                        else
                          _timeline(),
                        const SizedBox(height: 18),
                        YmButton(
                          label: 'See the bus live',
                          icon: Icons.directions_bus_rounded,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LiveBusScreen(
                                  studentId: widget.faculty ? null : _childId,
                                  faculty: widget.faculty,
                                  title: widget.faculty ? 'My bus' : "$_childName's bus"),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _summary() {
    final r = _ctx?.route ?? {};
    final bus = _ctx?.bus?['bus_number']?.toString();
    // where the route starts and ends: taken from the first and last stop of the route,
    // so nobody has to type it in separately
    var start = (r['start_point'] ?? '').toString();
    var end = (r['end_point'] ?? '').toString();
    if (start.isEmpty && _stops.isNotEmpty) start = (_stops.first['stop_name'] ?? '').toString();
    if (end.isEmpty && _stops.length > 1) end = (_stops.last['stop_name'] ?? '').toString();
    final timings = (r['timings'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Ym.amber.withOpacity(0.45)),
        boxShadow: Ym.shadow(Ym.amberDark, 0.22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((r['route_name'] ?? 'Route').toString(), style: Ym.h(22)),
          if (start.isNotEmpty || end.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.trip_origin_rounded, size: 14, color: Ym.green),
              const SizedBox(width: 6),
              Flexible(child: Text(start, style: Ym.t(12.5, color: Ym.grey))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 14, color: Ym.grey),
              ),
              Flexible(child: Text(end, style: Ym.t(12.5, color: Ym.grey))),
            ]),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (bus != null && bus.isNotEmpty)
              YmChip(bus, color: Ym.navy, icon: Icons.directions_bus_rounded),
            if ((_ctx?.driverName ?? '').isNotEmpty)
              YmChip(_ctx!.driverName!, color: Ym.navy, icon: Icons.person_rounded),
            if (timings.isNotEmpty)
              YmChip(timings, color: Ym.amberDark, icon: Icons.schedule_rounded),
          ]),
        ],
      ),
    );
  }

  Widget _timeline() {
    final mine = _ctx?.student['stop_id']?.toString();
    return Column(
      children: [
        for (var i = 0; i < _stops.length; i++)
          _stopRow(
            _stops[i],
            first: i == 0,
            last: i == _stops.length - 1,
            isMine: _stops[i]['id'].toString() == mine,
          ),
      ],
    );
  }

  Widget _stopRow(Map<String, dynamic> s,
      {required bool first, required bool last, required bool isMine}) {
    final color = isMine ? Ym.amberDark : Ym.grey;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2.5,
                    color: first ? Colors.transparent : Ym.line,
                  ),
                ),
                Container(
                  width: isMine ? 18 : 12,
                  height: isMine ? 18 : 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isMine ? Ym.amber : Colors.white,
                    border: Border.all(color: color, width: 2.5),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2.5,
                    color: last ? Colors.transparent : Ym.line,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isMine ? Ym.amber.withOpacity(0.16) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: isMine ? Ym.amber : Ym.line, width: isMine ? 1.4 : 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((s['stop_name'] ?? '').toString(),
                              style: Ym.h(14)),
                          if (isMine)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text('$_childName boards here',
                                  style: Ym.t(11.5,
                                      color: Ym.amberDark, w: FontWeight.w800)),
                            ),
                        ],
                      ),
                    ),
                    if ((s['timing'] ?? '').toString().isNotEmpty)
                      Text(_clock(s['timing']),
                          style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "07:50:00" -> "07:50"
  String _clock(dynamic t) {
    final s = t.toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }
}