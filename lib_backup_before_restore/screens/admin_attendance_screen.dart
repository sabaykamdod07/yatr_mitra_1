import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// Admin: attendance for any day, every route at a glance.
///
/// Boarded comes from the QR scans (the driver's or in-charge's Scan Pass).
/// Absent is marked when the first trip of the day reaches the campus and the student
/// (who has a valid, paid pass) did not board. On leave means they told the app in advance.
class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  final _sb = Supabase.instance.client;

  DateTime _day = DateTime.now();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _routes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dateParam => dateKey(_day);

  bool get _isToday => dateKey(_day) == dateKey(DateTime.now());

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _sb.rpc('admin_attendance_summary', params: {'p_date': _dateParam}) as List;
      if (!mounted) return;
      setState(() {
        _routes = [for (final r in rows) Map<String, dynamic>.from(r as Map)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() => _day = d);
      _load();
    }
  }

  int _sum(String key) =>
      _routes.fold<int>(0, (a, r) => a + ((r[key] as num?)?.toInt() ?? 0));

  @override
  Widget build(BuildContext context) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final isYesterday = dateKey(_day) == dateKey(yesterday);

    return YmPage(
      title: 'Attendance',
      subtitle: 'Who boarded and who was absent',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                _chip('Today', _isToday, () {
                  setState(() => _day = DateTime.now());
                  _load();
                }),
                const SizedBox(width: 8),
                _chip('Yesterday', isYesterday, () {
                  setState(() => _day = yesterday);
                  _load();
                }),
                const SizedBox(width: 8),
                _chip(
                  (!_isToday && !isYesterday) ? fmtDate(_day) : 'Pick a date',
                  !_isToday && !isYesterday,
                  _pickDate,
                  icon: Icons.event_rounded,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 4, height: 110),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load attendance',
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
                            _totals(),
                            const SizedBox(height: 20),
                            const YmSectionTitle('Routes'),
                            if (_routes.isEmpty)
                              YmCard(
                                child: Text('No routes yet.',
                                    style: Ym.t(13, color: Ym.grey)),
                              )
                            else
                              for (var i = 0; i < _routes.length; i++)
                                YmFadeSlide(
                                    index: i > 6 ? 6 : i, child: _routeCard(_routes[i])),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, bool on, VoidCallback onTap, {IconData? icon}) => YmPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: on ? const LinearGradient(colors: [Ym.amber, Ym.amberDark]) : null,
            color: on ? null : Colors.white,
            boxShadow: Ym.shadow(Ym.navy, 0.06),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: on ? Ym.navy : Ym.grey),
                const SizedBox(width: 6),
              ],
              Text(text,
                  style: Ym.t(12.5, color: on ? Ym.navy : Ym.grey, w: FontWeight.w800)),
            ],
          ),
        ),
      );

  Widget _totals() {
    final expected = _sum('expected');
    final boarded = _sum('boarded');
    final absent = _sum('absent');
    final leave = _sum('on_leave');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Ym.amber.withOpacity(0.45)),
        boxShadow: Ym.shadow(Ym.amberDark, 0.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isToday ? 'Today' : fmtDate(_day),
              style: Ym.t(12, color: Ym.amberDark, w: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('$boarded of $expected boarded', style: Ym.h(22)),
          const SizedBox(height: 4),
          Text('Students with a valid, paid pass', style: Ym.t(12, color: Ym.grey)),
          const SizedBox(height: 14),
          Row(
            children: [
              _count('$boarded', 'Boarded', Ym.green),
              _count('$absent', 'Absent', Ym.red),
              _count('$leave', 'On leave', Ym.amberDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _count(String n, String label, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n, style: Ym.h(24, color: color)),
            Text(label, style: Ym.t(11.5, color: Ym.grey)),
          ],
        ),
      );

  Widget _routeCard(Map<String, dynamic> r) {
    final expected = (r['expected'] as num?)?.toInt() ?? 0;
    final boarded = (r['boarded'] as num?)?.toInt() ?? 0;
    final absent = (r['absent'] as num?)?.toInt() ?? 0;
    final leave = (r['on_leave'] as num?)?.toInt() ?? 0;
    final trips = (r['trips'] as num?)?.toInt() ?? 0;
    final frac = expected == 0 ? 0.0 : (boarded / expected).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AttendanceRouteScreen(
            routeId: r['route_id'].toString(),
            routeName: (r['route_name'] ?? 'Route').toString(),
            day: _day,
          ),
        )),
        padding: const EdgeInsets.all(16),
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const YmIconBadge(icon: Icons.alt_route_rounded, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((r['route_name'] ?? 'Route').toString(), style: Ym.h(15.5)),
                      Text(
                        trips == 0 ? 'No trip on this day' : '$trips trip${trips == 1 ? '' : 's'}',
                        style: Ym.t(12, color: Ym.grey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Ym.grey),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(height: 9, color: Ym.line),
                  FractionallySizedBox(
                    widthFactor: frac,
                    child: Container(
                      height: 9,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Ym.green, Color(0xFF34D399)]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              YmChip('$boarded boarded of $expected', color: Ym.green, icon: Icons.login_rounded),
              if (absent > 0)
                YmChip('$absent absent', color: Ym.red, icon: Icons.event_busy_rounded),
              if (leave > 0)
                YmChip('$leave on leave', color: Ym.amberDark, icon: Icons.beach_access_rounded),
            ]),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── one route, one day ─────────────────────────

/// Every student of a route with their status for the day. The in-charge's own route
/// can be opened the same way.
class AttendanceRouteScreen extends StatefulWidget {
  const AttendanceRouteScreen({
    super.key,
    required this.routeId,
    required this.routeName,
    required this.day,
  });

  final String routeId;
  final String routeName;
  final DateTime day;

  @override
  State<AttendanceRouteScreen> createState() => _AttendanceRouteScreenState();
}

class _AttendanceRouteScreenState extends State<AttendanceRouteScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _filter = 'all'; // all | boarded | absent | on_leave | other
  String _q = '';

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
      final rows = await _sb.rpc('attendance_route_day', params: {
        'p_route': widget.routeId,
        'p_date': dateKey(widget.day),
      }) as List;
      if (!mounted) return;
      setState(() {
        _rows = [for (final r in rows) Map<String, dynamic>.from(r as Map)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  bool _isOther(String s) => s == 'not_marked' || s == 'no_pass';

  int _n(String f) => _rows.where((r) {
        final s = (r['status'] ?? '').toString();
        return f == 'other' ? _isOther(s) : s == f;
      }).length;

  ({String label, Color color, IconData icon}) _look(String s) {
    switch (s) {
      case 'boarded':
        return (label: 'Boarded', color: Ym.green, icon: Icons.login_rounded);
      case 'absent':
        return (label: 'Absent', color: Ym.red, icon: Icons.event_busy_rounded);
      case 'on_leave':
        return (label: 'On leave', color: Ym.amberDark, icon: Icons.beach_access_rounded);
      case 'no_pass':
        return (label: 'No valid pass', color: Ym.grey, icon: Icons.block_rounded);
      default:
        return (label: 'Not marked', color: Ym.grey, icon: Icons.hourglass_empty_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = _rows.where((r) {
      final s = (r['status'] ?? '').toString();
      final okFilter = _filter == 'all' ||
          (_filter == 'other' ? _isOther(s) : s == _filter);
      final okSearch = q.isEmpty ||
          [r['student_name'], r['enrollment_no'], r['stop_name']]
              .any((v) => (v ?? '').toString().toLowerCase().contains(q));
      return okFilter && okSearch;
    }).toList();

    return YmPage(
      title: widget.routeName,
      subtitle: fmtDate(widget.day),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: Ym.t(14),
              decoration: InputDecoration(
                hintText: 'Search by name, ID or stop',
                hintStyle: Ym.t(13, color: Ym.grey),
                prefixIcon: const Icon(Icons.search_rounded, color: Ym.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _fchip('all', 'All (${_rows.length})'),
                _fchip('boarded', 'Boarded (${_n('boarded')})'),
                _fchip('absent', 'Absent (${_n('absent')})'),
                _fchip('on_leave', 'On leave (${_n('on_leave')})'),
                _fchip('other', 'Other (${_n('other')})'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 5, height: 80),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load the list',
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
                        child: list.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 50),
                                  YmEmpty(
                                    icon: Icons.groups_rounded,
                                    color: Ym.amberDark,
                                    title: 'No students here',
                                    subtitle: 'Try another filter.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                                itemCount: list.length,
                                itemBuilder: (_, i) => _tile(list[i]),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _fchip(String key, String text) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: YmPressable(
          onTap: () => setState(() => _filter = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient:
                  _filter == key ? const LinearGradient(colors: [Ym.amber, Ym.amberDark]) : null,
              color: _filter == key ? null : Colors.white,
              boxShadow: Ym.shadow(Ym.navy, 0.05),
            ),
            child: Text(text,
                style: Ym.t(12,
                    color: _filter == key ? Ym.navy : Ym.grey, w: FontWeight.w800)),
          ),
        ),
      );

  Widget _tile(Map<String, dynamic> r) {
    final s = (r['status'] ?? 'not_marked').toString();
    final look = _look(s);
    final bAt = parseUtc(r['boarded_at']);
    final oAt = parseUtc(r['alighted_at']);
    final name = (r['student_name'] ?? 'Student').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        child: Row(
          children: [
            YmIconBadge(icon: look.icon, color: look.color, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Ym.h(14.5)),
                  Text(
                    [
                      if ((r['enrollment_no'] ?? '').toString().isNotEmpty)
                        r['enrollment_no'].toString(),
                      if ((r['stop_name'] ?? '').toString().isNotEmpty)
                        r['stop_name'].toString(),
                    ].join('  •  '),
                    style: Ym.t(11.5, color: Ym.grey),
                  ),
                  if (bAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Boarded ${fmtClock(bAt)}${oAt != null ? '  •  Got off ${fmtClock(oAt)}' : ''}',
                      style: Ym.t(11.5, color: Ym.grey),
                    ),
                  ],
                ],
              ),
            ),
            YmChip(look.label, color: look.color),
          ],
        ),
      ),
    );
  }
}