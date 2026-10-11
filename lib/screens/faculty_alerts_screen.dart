import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// Everything the faculty member has been told, newest first:
///   SOS       an emergency on their bus (in-charge)
///   Bus       the bus started, came near their stop or left it
///   Requests  ride requests and complaints for them to look at
/// These are rows of the `notifications` table, filled in by the database.
class FacultyAlertsScreen extends StatefulWidget {
  const FacultyAlertsScreen({super.key});

  @override
  State<FacultyAlertsScreen> createState() => _FacultyAlertsScreenState();
}

class _FacultyAlertsScreenState extends State<FacultyAlertsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _filter = 'all'; // all | sos | bus | requests
  RealtimeChannel? _chan;

  @override
  void initState() {
    super.initState();
    _load();
    final uid = _sb.auth.currentUser?.id;
    if (uid != null) {
      _chan = _sb
          .channel('faculty_alerts_$uid')
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
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in.');
      final since = DateTime.now().toUtc().subtract(const Duration(days: 30));
      final rows = await _sb
          .from('notifications')
          .select()
          .eq('recipient_id', uid)
          .gte('created_at', since.toIso8601String())
          .order('created_at', ascending: false)
          .limit(150);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
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

  String _cat(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString();
    final title = (n['title'] ?? '').toString().toLowerCase();
    if (type == 'emergency') return 'sos';
    if (type == 'geofence') return 'bus';
    if (title.contains('complaint') || title.contains('ride') || title.contains('request')) {
      return 'requests';
    }
    if (title.contains('bus')) return 'bus';
    return 'other';
  }

  ({IconData icon, Color color}) _look(Map<String, dynamic> n) {
    switch (_cat(n)) {
      case 'sos':
        return (icon: Icons.sos_rounded, color: Ym.red);
      case 'bus':
        return (icon: Icons.directions_bus_rounded, color: Ym.blue);
      case 'requests':
        return (icon: Icons.mail_outline_rounded, color: Ym.amberDark);
      default:
        return (icon: Icons.notifications_rounded, color: Ym.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list =
        _filter == 'all' ? _items : _items.where((n) => _cat(n) == _filter).toList();

    return YmPage(
      title: 'Alerts',
      subtitle: 'Bus, requests and complaints',
      child: Column(
        children: [
          _chips(),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 5, height: 84),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load alerts',
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
                        child: list.isEmpty ? _empty() : _list(list),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    const tabs = <(String, String, IconData)>[
      ('all', 'All', Icons.apps_rounded),
      ('bus', 'Bus', Icons.directions_bus_rounded),
      ('requests', 'Requests', Icons.mail_outline_rounded),
      ('sos', 'SOS', Icons.sos_rounded),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: YmPressable(
                onTap: () => setState(() => _filter = t.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: _filter == t.$1
                        ? const LinearGradient(colors: [Ym.amber, Ym.amberDark])
                        : null,
                    color: _filter == t.$1 ? null : Colors.white,
                    boxShadow: Ym.shadow(Ym.navy, 0.06),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.$3, size: 15, color: _filter == t.$1 ? Ym.navy : Ym.grey),
                      const SizedBox(width: 6),
                      Text(t.$2,
                          style: Ym.t(12.5,
                              color: _filter == t.$1 ? Ym.navy : Ym.grey,
                              w: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 60),
          YmEmpty(
            icon: Icons.notifications_none_rounded,
            color: Ym.amberDark,
            title: 'You are all caught up',
            subtitle: 'New alerts will appear here.',
          ),
        ],
      );

  Widget _list(List<Map<String, dynamic>> list) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final n = list[i];
        final look = _look(n);
        final at = parseUtc(n['created_at']);
        final isSos = _cat(n) == 'sos';
        return YmFadeSlide(
          index: i > 8 ? 8 : i,
          child: YmCard(
            padding: const EdgeInsets.all(14),
            radius: 20,
            color: isSos ? const Color(0xFFFFF5F4) : Colors.white,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YmIconBadge(icon: look.icon, color: look.color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((n['title'] ?? 'Alert').toString(),
                          style: Ym.h(14, color: isSos ? Ym.red : Ym.navy)),
                      const SizedBox(height: 4),
                      Text((n['message'] ?? '').toString(),
                          style: Ym.t(12.5, color: const Color(0xFF4B5563))
                              .copyWith(height: 1.45)),
                      if (at != null) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.schedule_rounded, size: 13, color: Ym.grey),
                          const SizedBox(width: 4),
                          Text('${fmtDate(at)}  •  ${fmtClock(at)}',
                              style: Ym.t(11, color: Ym.grey)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}