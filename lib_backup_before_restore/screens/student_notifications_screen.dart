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

/// Two categories, as in the design:
///   1. Geofence Alerts  – notifications.type = 'geofence', last 24 hours only
///   2. Announcements    – announcements for students + other app updates
///                         (route request replies etc. that are type 'general')
class StudentNotificationsScreen extends StatefulWidget {
  const StudentNotificationsScreen({super.key});

  @override
  State<StudentNotificationsScreen> createState() =>
      _StudentNotificationsScreenState();
}

class _StudentNotificationsScreenState extends State<StudentNotificationsScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _announcements = [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
  }

  @override
  void dispose() {
    if (_channel != null) _sb.removeChannel(_channel!);
    _tabs.dispose();
    super.dispose();
  }

  void _listen() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    _channel = _sb
        .channel('student_notifications_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (_) => _load(silent: true),
        )
        .subscribe();
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

      final cutoff =
          DateTime.now().toUtc().subtract(const Duration(hours: 24));

      final alerts = await _sb
          .from('notifications')
          .select()
          .eq('recipient_id', uid)
          .eq('type', 'geofence')
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at', ascending: false);

      final general = await _sb
          .from('notifications')
          .select()
          .eq('recipient_id', uid)
          .neq('type', 'geofence')
          .order('created_at', ascending: false)
          .limit(20);

      // Same query the dashboard uses for its single latest announcement.
      final anns = await _sb
          .from('announcements')
          .select()
          .inFilter('target_role', ['all', 'student'])
          .order('created_at', ascending: false)
          .limit(30);

      final merged = <Map<String, dynamic>>[
        for (final a in anns)
          {
            'kind': 'Announcement',
            'title': a['title'],
            'body': a['body'],
            'at': parseUtc(a['created_at']),
          },
        for (final n in general)
          {
            'kind': 'Update',
            'title': n['title'],
            'body': n['message'],
            'at': parseUtc(n['created_at']),
          },
      ]..sort((a, b) {
          final x = a['at'] as DateTime?;
          final y = b['at'] as DateTime?;
          if (x == null || y == null) return 0;
          return y.compareTo(x);
        });

      if (!mounted) return;
      setState(() {
        _alerts = List<Map<String, dynamic>>.from(alerts);
        _announcements = merged;
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

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _expires(DateTime? d) {
    if (d == null) return '';
    final left = d.add(const Duration(hours: 24)).difference(DateTime.now());
    if (left.isNegative) return 'Expired';
    return 'Expires in ${left.inHours}h ${left.inMinutes % 60}m';
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Notifications',
      subtitle: 'Alerts and announcements',
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
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
                        tabs: [
                          Tab(text: 'Geofence (${_alerts.length})'),
                          Tab(text: 'Announcements (${_announcements.length})'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [_alertsTab(), _announcementsTab()],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _scroll(List<Widget> items, IconData icon, String empty, String sub) {
    return RefreshIndicator(
      color: Ym.amber,
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                YmEmpty(icon: icon, title: empty, subtitle: sub),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
              children: items,
            ),
    );
  }

  Widget _alertsTab() {
    return _scroll(
      [
        for (var i = 0; i < _alerts.length; i++)
          YmFadeSlide(
            index: i,
            child: Builder(builder: (_) {
              final n = _alerts[i];
              final msg = n['message']?.toString() ?? '';
              final exited = msg.contains('exited');
              final color = exited ? Ym.blue : Ym.green;
              final at = parseUtc(n['created_at']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: Ym.shadow(),
                    border: Border(left: BorderSide(color: color, width: 5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      YmGradientTile(
                          icon: exited ? Icons.logout_rounded : Icons.login_rounded,
                          color: color,
                          size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(exited ? 'Bus left your area' : 'Bus is near you',
                                style: Ym.h(15)),
                            const SizedBox(height: 3),
                            Text(msg, style: Ym.t(12.5, color: Ym.grey)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (at != null)
                                  YmChip(fmtClock(at),
                                      color: color, icon: Icons.access_time_rounded),
                                if (at != null)
                                  YmChip(_expires(at),
                                      color: Ym.grey, icon: Icons.hourglass_bottom_rounded),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
      ],
      Icons.notifications_none_rounded,
      'No alerts in the last 24 hours',
      'Alerts about your bus arriving or leaving appear here for 24 hours.',
    );
  }

  Widget _announcementsTab() {
    return _scroll(
      [
        for (var i = 0; i < _announcements.length; i++)
          YmFadeSlide(
            index: i,
            child: Builder(builder: (_) {
              final a = _announcements[i];
              final isUpdate = a['kind'] == 'Update';
              final color = isUpdate ? Ym.amberDark : Ym.blue;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: YmCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      YmIconBadge(
                          icon: isUpdate
                              ? Icons.notifications_active_outlined
                              : Icons.campaign_rounded,
                          color: color,
                          size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: Text(a['title']?.toString() ?? '',
                                        style: Ym.h(14.5))),
                                YmChip(a['kind']?.toString() ?? '', color: color),
                              ],
                            ),
                            if ((a['body'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(a['body'].toString(),
                                    style: Ym.t(12.5, color: Ym.grey)),
                              ),
                            const SizedBox(height: 6),
                            Text(_ago(a['at'] as DateTime?),
                                style: Ym.t(11, color: Ym.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
      ],
      Icons.campaign_outlined,
      'No announcements yet',
      'Announcements and updates from your institution appear here.',
    );
  }
}