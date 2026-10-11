import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// A child's bus attendance, trip by trip:
///   Boarded the bus  - from the RFID tap (`boardings`) or the driver's check-in
///   Reached campus   - when the trip was finished
///   Absences         - days marked absent
///
/// It only READS tables. The RFID reader and the driver app write them, so
/// nothing here changes when the hardware is connected.
class ParentAttendanceScreen extends StatefulWidget {
  const ParentAttendanceScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.routeId,
  });

  final String studentId;
  final String studentName;
  final String? routeId;

  @override
  State<ParentAttendanceScreen> createState() => _ParentAttendanceScreenState();
}

class _ParentAttendanceScreenState extends State<ParentAttendanceScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _trips = [];
  final Map<String, DateTime?> _boardedAt = {}; // trip id -> when
  final Map<String, String?> _boardedStop = {}; // trip id -> stop name
  final Map<String, DateTime?> _alightedAt = {}; // trip id -> when the child got off
  final Map<String, String?> _alightedStop = {}; // trip id -> stop name
  final Map<String, String> _absentTrip = {}; // trip id -> did_not_board | on_leave
  List<Map<String, dynamic>> _absences = [];
  bool _hasCard = false;

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
      final sid = widget.studentId;

      final student = await _sb
          .from('students')
          .select('rfid_uid')
          .eq('id', sid)
          .maybeSingle();

      var trips = <Map<String, dynamic>>[];
      if (widget.routeId != null) {
        final rows = await _sb
            .from('trips')
            .select('id, status, started_at, ended_at, routes(route_name)')
            .eq('route_id', widget.routeId!)
            .order('started_at', ascending: false)
            .limit(40);
        trips = List<Map<String, dynamic>>.from(rows);
      }

      final boardings = await _sb
          .from('boardings')
          .select('trip_id, boarded_at, status, stop_id')
          .eq('student_id', sid)
          .order('boarded_at', ascending: false)
          .limit(80);
      // the check-ins now also carry "got off" (after step 29). If that is not set up
      // yet, fall back to the plain list so this screen keeps working.
      List<dynamic> checkins;
      try {
        checkins = await _sb
            .from('trip_checkins')
            .select('trip_id, checked_in_at, alighted_at, boarded_stop, alighted_stop')
            .eq('student_id', sid)
            .order('checked_in_at', ascending: false)
            .limit(80);
      } catch (_) {
        checkins = await _sb
            .from('trip_checkins')
            .select('trip_id, checked_in_at')
            .eq('student_id', sid)
            .order('checked_in_at', ascending: false)
            .limit(80);
      }

      // stop names (looked up separately so this works whatever the table links are)
      final stopIds = <String>{
        for (final b in boardings)
          if (b['stop_id'] != null) b['stop_id'].toString(),
      }.toList();
      final stopNames = <String, String>{};
      if (stopIds.isNotEmpty) {
        final st = await _sb
            .from('stops')
            .select('id, stop_name')
            .inFilter('id', stopIds);
        for (final r in st) {
          stopNames[r['id'].toString()] = (r['stop_name'] ?? '').toString();
        }
      }

      _boardedAt.clear();
      _boardedStop.clear();
      for (final b in boardings) {
        if ((b['status'] ?? '').toString() != 'boarded') continue;
        final id = b['trip_id']?.toString();
        if (id == null) continue;
        _boardedAt[id] = parseUtc(b['boarded_at']);
        _boardedStop[id] = stopNames[b['stop_id']?.toString()];
      }
      // trips where the child was marked absent when the bus reached the campus (after step 30)
      _absentTrip.clear();
      try {
        final ab = await _sb
            .from('trip_absences')
            .select('trip_id, reason')
            .eq('student_id', sid);
        for (final a in ab) {
          final id = a['trip_id']?.toString();
          if (id != null) _absentTrip[id] = (a['reason'] ?? 'did_not_board').toString();
        }
      } catch (_) {
        // not set up yet: the screen works as before
      }

      _alightedAt.clear();
      _alightedStop.clear();
      for (final c in checkins) {
        final id = c['trip_id']?.toString();
        if (id == null) continue;
        if (!_boardedAt.containsKey(id)) {
          _boardedAt[id] = parseUtc(c['checked_in_at']);
          _boardedStop[id] = (c['boarded_stop'] ?? '').toString().isEmpty
              ? null
              : c['boarded_stop'].toString();
        }
        if (c['alighted_at'] != null) {
          _alightedAt[id] = parseUtc(c['alighted_at']);
          _alightedStop[id] = (c['alighted_stop'] ?? '').toString().isEmpty
              ? null
              : c['alighted_stop'].toString();
        }
      }

      final abs = await _sb
          .from('attendance_notifications')
          .select('absent_date, reason, status')
          .eq('student_id', sid)
          .order('absent_date', ascending: false)
          .limit(30);

      if (!mounted) return;
      setState(() {
        _trips = trips;
        _absences = [
          for (final a in abs)
            if ((a['status'] ?? 'absent').toString() == 'absent')
              Map<String, dynamic>.from(a),
        ];
        _hasCard = (student?['rfid_uid'] ?? '').toString().isNotEmpty;
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

  int get _daysBoarded {
    // a day counts once, even if there was more than one trip
    final days = <String>{};
    for (final t in _trips) {
      final id = t['id'].toString();
      if (!_boardedAt.containsKey(id)) continue;
      final at = parseUtc(t['started_at']);
      if (at != null) days.add(dateKey(at));
    }
    return days.length;
  }

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Attendance',
      subtitle: widget.studentName,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: YmSkeletonList(count: 4, height: 96),
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
                      if (!_hasCard)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Ym.amber.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: Ym.amberDark, size: 19),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Boarding and getting off are recorded when the driver or the '
                                  'in-charge scans ${widget.studentName}\'s bus pass QR. '
                                  'An RFID card can be added later.',
                                  style: Ym.t(12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          _stat('$_daysBoarded', 'Days boarded',
                              Icons.directions_bus_rounded, Ym.green),
                          const SizedBox(width: 10),
                          _stat(
                              '${_absences.length + _absentTrip.values.where((r) => r == 'did_not_board').length}',
                              'Absences',
                              Icons.event_busy_rounded, Ym.amberDark),
                          const SizedBox(width: 10),
                          _stat(
                              '${_trips.where((t) => (t['status'] ?? '').toString() == 'completed').length}',
                              'Trips run',
                              Icons.route_rounded,
                              Ym.blue),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const YmSectionTitle('Trips'),
                      if (_trips.isEmpty)
                        YmCard(
                          child: Text('No trips have run on this route yet.',
                              style: Ym.t(13, color: Ym.grey)),
                        )
                      else
                        for (var i = 0; i < _trips.length; i++)
                          YmFadeSlide(
                              index: i > 6 ? 6 : i, child: _tripCard(_trips[i])),
                      if (_absences.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const YmSectionTitle('Marked absent'),
                        for (final a in _absences) _absenceTile(a),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _stat(String value, String label, IconData icon, Color color) =>
      Expanded(
        child: YmCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          radius: 20,
          child: Column(
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(height: 6),
              Text(value, style: Ym.h(20)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Ym.t(10.5, color: Ym.grey)),
            ],
          ),
        ),
      );

  Widget _tripCard(Map<String, dynamic> t) {
    final id = t['id'].toString();
    final start = parseUtc(t['started_at']);
    final end = parseUtc(t['ended_at']);
    final done = (t['status'] ?? '').toString() == 'completed';
    final running = (t['status'] ?? '').toString() == 'in_progress';
    final boarded = _boardedAt.containsKey(id);
    final bAt = _boardedAt[id];
    final stop = _boardedStop[id];
    final offAt = _alightedAt[id];
    final offStop = _alightedStop[id];
    final absentReason = _absentTrip[id];
    final route = (t['routes'] as Map?)?['route_name']?.toString() ?? 'Trip';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(start == null ? route : fmtDate(start),
                      style: Ym.h(14.5)),
                ),
                if (running)
                  const YmChip('On the way', color: Ym.blue)
                else if (done)
                  const YmChip('Completed', color: Ym.green),
              ],
            ),
            const SizedBox(height: 2),
            Text(route, style: Ym.t(12, color: Ym.grey)),
            const SizedBox(height: 12),
            _line(
              boarded
                  ? Icons.check_circle_rounded
                  : (absentReason != null ? Icons.event_busy_rounded : Icons.cancel_rounded),
              boarded ? Ym.green : (absentReason != null ? Ym.red : Ym.grey),
              boarded
                  ? 'Boarded the bus'
                  : (absentReason != null ? 'Absent' : 'Did not board'),
              boarded
                  ? [
                      if (bAt != null) fmtClock(bAt),
                      if (stop != null && stop.isNotEmpty) stop,
                    ].join('  •  ')
                  : (absentReason == 'on_leave'
                      ? 'Told in advance'
                      : (absentReason != null ? 'Did not board the bus' : null)),
            ),
            if (boarded && offAt != null) ...[
              const SizedBox(height: 8),
              _line(
                Icons.logout_rounded,
                Ym.blue,
                'Got off the bus',
                [
                  fmtClock(offAt),
                  if (offStop != null && offStop.isNotEmpty) offStop,
                ].join('  •  '),
              ),
            ],
            const SizedBox(height: 8),
            _line(
              done ? Icons.school_rounded : Icons.hourglass_bottom_rounded,
              done ? Ym.blue : Ym.grey,
              done ? 'Bus reached the campus' : 'Not at the campus yet',
              done && end != null ? fmtClock(end) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, Color color, String title, String? sub) => Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: Ym.t(13, w: FontWeight.w700)),
          ),
          if (sub != null && sub.isNotEmpty)
            Flexible(
              child: Text(sub,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: Ym.t(12, color: Ym.grey)),
            ),
        ],
      );

  Widget _absenceTile(Map<String, dynamic> a) {
    final d = DateTime.tryParse('${a['absent_date']}');
    final reason = (a['reason'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: YmCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 18,
        child: Row(
          children: [
            const YmIconBadge(
                icon: Icons.event_busy_rounded, color: Ym.amberDark, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d == null ? '${a['absent_date']}' : fmtDate(d),
                      style: Ym.h(13.5)),
                  if (reason.isNotEmpty)
                    Text(reason, style: Ym.t(12, color: Ym.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}