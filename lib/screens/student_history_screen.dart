import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

class _C {
  static const bg = Color(0xFFFFF8F1);
  static const navy = Color(0xFF0F1B4D);
  static const orange = Color(0xFFFF9800);
  static const grey = Color(0xFF8E94A9);
  static const green = Color(0xFF0E9F6E);
  static const red = Color(0xFFE53935);
  static const blue = Color(0xFF3B6FF5);
}

/// History:
///   Trips Completed  – finished trips on the student's route (`trips`)
///   RFID Attendance  – card taps (`rfid_scans`)
///
/// Both tabs only READ tables. The driver app writes `trips`; the RFID reader
/// hardware writes `rfid_scans`. Nothing here changes when hardware is added.
class StudentHistoryScreen extends StatefulWidget {
  const StudentHistoryScreen({super.key});

  @override
  State<StudentHistoryScreen> createState() => _StudentHistoryScreenState();
}

class _StudentHistoryScreenState extends State<StudentHistoryScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  String? _error;
  bool _hasCard = false;
  List<Map<String, dynamic>> _trips = [];
  Set<String> _boarded = {};
  Set<String> _absentTrips = {}; // trips where the student was marked absent
  List<Map<String, dynamic>> _scans = [];

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
      final ctx = await StudentContext.load();
      final sid = ctx.student['id'].toString();

      var trips = <Map<String, dynamic>>[];
      var boarded = <String>{};
      if (ctx.routeId != null) {
        final rows = await _sb
            .from('trips')
            .select('id, started_at, ended_at, routes(route_name)')
            .eq('route_id', ctx.routeId!)
            .eq('status', 'completed')
            .order('started_at', ascending: false)
            .limit(30);
        trips = List<Map<String, dynamic>>.from(rows);

        final ids = trips.map((t) => t['id'].toString()).toList();
        if (ids.isNotEmpty) {
          final ci = await _sb
              .from('trip_checkins')
              .select('trip_id')
              .eq('student_id', sid)
              .inFilter('trip_id', ids);
          final bo = await _sb
              .from('boardings')
              .select('trip_id')
              .eq('student_id', sid)
              .inFilter('trip_id', ids);
          boarded = {
            ...ci.map<String>((e) => e['trip_id'].toString()),
            ...bo.map<String>((e) => e['trip_id'].toString()),
          };
        }
      }

      // trips where the bus reached the campus and the student had not boarded (after step 30)
      var absent = <String>{};
      if (trips.isNotEmpty) {
        try {
          final ab = await _sb
              .from('trip_absences')
              .select('trip_id')
              .eq('student_id', sid)
              .inFilter('trip_id', trips.map((t) => t['id'].toString()).toList());
          absent = {for (final a in ab) a['trip_id'].toString()};
        } catch (_) {}
      }

      final scans = await _sb
          .from('rfid_scans')
          .select('scanned_at')
          .eq('student_id', sid)
          .order('scanned_at', ascending: false)
          .limit(30);

      if (!mounted) return;
      setState(() {
        _trips = trips;
        _boarded = boarded;
        _absentTrips = absent;
        _scans = List<Map<String, dynamic>>.from(scans);
        _hasCard = ctx.student['rfid_uid'] != null &&
            ctx.student['rfid_uid'].toString().isNotEmpty;
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

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'History',
      subtitle: 'Your trips and card taps',
      child: _loading
          ? const YmSkeletonList(count: 4, height: 96)
          : _error != null
              ? YmEmpty(
                  icon: Icons.error_outline_rounded,
                  color: Ym.red,
                  title: 'Could not load',
                  subtitle: _error,
                  action: YmButton(
                      label: 'Try again',
                      expanded: false,
                      icon: Icons.refresh_rounded,
                      onPressed: _load),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: Row(
                        children: [
                          _stat('${_trips.length}', 'Trips', Icons.check_circle_rounded, Ym.green),
                          const SizedBox(width: 10),
                          _stat('${_boarded.length}', 'Boarded', Icons.how_to_reg_rounded, Ym.blue),
                          const SizedBox(width: 10),
                          _stat('${_scans.length}', 'Card taps', Icons.contactless_rounded, Ym.amberDark),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: Ym.shadow(Ym.navy, 0.06),
                      ),
                      child: TabBar(
                        controller: _tabs,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                              colors: [Ym.amber, Ym.amberDark]),
                        ),
                        labelColor: Ym.navy,
                        unselectedLabelColor: Ym.grey,
                        labelStyle: Ym.h(13, w: FontWeight.w800),
                        unselectedLabelStyle: Ym.t(13, w: FontWeight.w600),
                        tabs: const [
                          Tab(text: 'Trips Completed'),
                          Tab(text: 'RFID Attendance'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [_tripsTab(), _rfidTab()],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _stat(String value, String label, IconData icon, Color color) =>
      Expanded(
        child: YmCard(
          padding: const EdgeInsets.symmetric(vertical: 12),
          radius: 20,
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 6),
              Text(value, style: Ym.h(20)),
              Text(label, style: Ym.t(11, color: Ym.grey)),
            ],
          ),
        ),
      );

  Widget _tripsTab() {
    return RefreshIndicator(
      color: Ym.amber,
      onRefresh: _load,
      child: _trips.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 60),
                YmEmpty(
                    icon: Iconsax.bus,
                    title: 'No completed trips yet',
                    subtitle: 'Trips on your route appear here once they finish.'),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
              itemCount: _trips.length,
              itemBuilder: (_, i) {
                final t = _trips[i];
                final start = parseUtc(t['started_at']);
                final end = parseUtc(t['ended_at']);
                final name =
                    (t['routes'] as Map?)?['route_name']?.toString() ?? 'Trip';
                final mins = (start != null && end != null)
                    ? end.difference(start).inMinutes
                    : null;
                final boarded = _boarded.contains(t['id'].toString());
                final absent = !boarded && _absentTrips.contains(t['id'].toString());
                return YmFadeSlide(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: YmCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          YmIconBadge(
                              icon: Iconsax.bus,
                              color: boarded ? Ym.blue : Ym.green,
                              size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: Ym.h(15)),
                                const SizedBox(height: 3),
                                if (start != null)
                                  Text(
                                    '${fmtDate(start)}  •  ${fmtClock(start)}'
                                    '${end != null ? ' – ${fmtClock(end)}' : ''}',
                                    style: Ym.t(12, color: Ym.grey),
                                  ),
                                if (mins != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: YmChip('$mins min',
                                        color: Ym.navy,
                                        icon: Icons.timer_outlined),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const YmChip('Completed', color: Ym.green),
                              if (boarded) ...[
                                const SizedBox(height: 5),
                                const YmChip('Boarded', color: Ym.blue),
                              ] else if (absent) ...[
                                const SizedBox(height: 5),
                                const YmChip('Absent', color: Ym.red),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _rfidTab() {
    final last = _scans.isNotEmpty ? parseUtc(_scans.first['scanned_at']) : null;

    return RefreshIndicator(
      color: Ym.amber,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
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
                  const Icon(Icons.info_outline_rounded, color: Ym.amberDark, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No RFID card is linked to your account yet. Please contact your institution.',
                      style: Ym.t(12.5),
                    ),
                  ),
                ],
              ),
            ),
          YmCard(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
            ),
            child: Row(
              children: [
                const YmGradientTile(
                    icon: Icons.contactless_rounded, color: Ym.blue, size: 54),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last check-in',
                          style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        last == null
                            ? 'No scans yet'
                            : '${fmtDate(last)}  •  ${fmtClock(last)}',
                        style: Ym.h(16),
                      ),
                    ],
                  ),
                ),
                if (last != null) const YmChip('Checked in', color: Ym.green, solid: true),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const YmSectionTitle('Recent scans'),
          if (_scans.isEmpty)
            YmCard(
                child: Text('Your card taps will appear here.',
                    style: Ym.t(13.5, color: Ym.grey)))
          else
            for (var i = 0; i < _scans.length; i++)
              YmFadeSlide(
                index: i,
                child: Builder(builder: (_) {
                  final at = parseUtc(_scans[i]['scanned_at']);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: YmCard(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      radius: 18,
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Ym.green, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(at == null ? '' : fmtDate(at),
                                style: Ym.h(14)),
                          ),
                          Text(at == null ? '' : fmtClock(at),
                              style: Ym.t(13, color: Ym.grey, w: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
        ],
      ),
    );
  }
}