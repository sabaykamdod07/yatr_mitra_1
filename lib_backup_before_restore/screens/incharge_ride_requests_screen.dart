import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// For the IN-CHARGE: who is going to board your bus on a day that is not their
/// usual route (students and faculty who pressed "Notify in-charge" on Other
/// Buses), from which stop, and on which day.
class InchargeRideRequestsScreen extends StatefulWidget {
  const InchargeRideRequestsScreen({super.key});

  @override
  State<InchargeRideRequestsScreen> createState() => _InchargeRideRequestsScreenState();
}

class _InchargeRideRequestsScreenState extends State<InchargeRideRequestsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _tab = 'today'; // today | later | earlier
  RealtimeChannel? _chan;

  @override
  void initState() {
    super.initState();
    _load();
    final uid = _sb.auth.currentUser?.id;
    if (uid != null) {
      _chan = _sb
          .channel('incharge_rides_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq, column: 'recipient_id', value: uid),
            callback: (_) {
              if (mounted) _load(silent: true);
            },
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _chan?.unsubscribe();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _sb.rpc('incharge_ride_requests') as List;
      if (!mounted) return;
      setState(() {
        _items = [for (final r in rows) Map<String, dynamic>.from(r as Map)];
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

  DateTime? _day(Map<String, dynamic> r) => DateTime.tryParse('${r['ride_date']}');

  String get _todayKey => dateKey(DateTime.now());

  List<Map<String, dynamic>> get _shown {
    return _items.where((r) {
      final d = _day(r);
      if (d == null) return false;
      final k = dateKey(d);
      if (_tab == 'today') return k == _todayKey;
      if (_tab == 'later') return k.compareTo(_todayKey) > 0;
      return k.compareTo(_todayKey) < 0;
    }).toList();
  }

  int _count(String tab) {
    final t = _tab;
    _tab = tab;
    final n = _shown.length;
    _tab = t;
    return n;
  }

  Future<void> _call(String? phone) async {
    final p = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: p));
  }

  @override
  Widget build(BuildContext context) {
    final list = _shown;
    return YmPage(
      title: 'Ride Requests',
      subtitle: 'Who boards your bus from other routes',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                _chip('Today (${_count('today')})', 'today'),
                const SizedBox(width: 8),
                _chip('Upcoming (${_count('later')})', 'later'),
                const SizedBox(width: 8),
                _chip('Earlier', 'earlier'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 4, height: 100),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load ride requests',
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
                                children: [
                                  const SizedBox(height: 50),
                                  YmEmpty(
                                    icon: Icons.event_available_rounded,
                                    color: Ym.green,
                                    title: _tab == 'today'
                                        ? 'Nobody extra today'
                                        : 'Nothing here',
                                    subtitle:
                                        'When someone from another route plans to ride your bus, they appear here.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                                itemCount: list.length,
                                itemBuilder: (_, i) => YmFadeSlide(
                                    index: i > 6 ? 6 : i, child: _tile(list[i])),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, String key) => YmPressable(
        onTap: () => setState(() => _tab = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: _tab == key
                ? const LinearGradient(colors: [Ym.amber, Ym.amberDark])
                : null,
            color: _tab == key ? null : Colors.white,
            boxShadow: Ym.shadow(Ym.navy, 0.06),
          ),
          child: Text(text,
              style: Ym.t(12, color: _tab == key ? Ym.navy : Ym.grey, w: FontWeight.w800)),
        ),
      );

  Widget _tile(Map<String, dynamic> r) {
    final d = _day(r);
    final isFaculty = r['kind'] == 'Faculty';
    final phone = (r['phone'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        radius: 22,
        child: Row(
          children: [
            YmIconBadge(
                icon: isFaculty ? Icons.badge_outlined : Icons.school_rounded,
                color: isFaculty ? Ym.blue : Ym.green,
                size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((r['who'] ?? 'Someone').toString(), style: Ym.h(14.5)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ((r['from_stop'] ?? '').toString().isNotEmpty)
                        'Boards at ${r['from_stop']}',
                      if ((r['from_route'] ?? '').toString().isNotEmpty)
                        'from ${r['from_route']}',
                    ].join('  '),
                    style: Ym.t(12, color: Ym.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    YmChip(isFaculty ? 'Faculty' : 'Student',
                        color: isFaculty ? Ym.blue : Ym.green),
                    if (d != null)
                      YmChip(fmtDate(d), color: Ym.amberDark, icon: Icons.event_rounded),
                  ]),
                ],
              ),
            ),
            if (phone.isNotEmpty)
              YmPressable(
                onTap: () => _call(phone),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: Ym.green.withOpacity(0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.call_rounded, color: Ym.green, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}