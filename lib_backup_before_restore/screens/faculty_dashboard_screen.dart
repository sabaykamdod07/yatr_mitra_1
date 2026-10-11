import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/eta.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import 'faculty_alerts_screen.dart';
import 'faculty_complaints_screen.dart';
import 'faculty_profile_screen.dart';
import 'incharge_ride_requests_screen.dart';
import 'incharge_route_students_screen.dart';
import 'live_bus_screen.dart';
import 'other_buses_screen.dart';
import 'parent_announcements_screen.dart';
import 'parent_route_screen.dart';
import 'role_selection_screen.dart';
import 'scan_pass_screen.dart';

/// The faculty member's home.
///
/// Everyone gets: their bus live, alerts, other buses (ride a different bus for a
/// day), the complaints students send to faculty, route and timings, announcements.
/// The faculty member the admin chose as IN-CHARGE of a route also gets: scan bus
/// passes, ride requests for their bus, and the students of their route.
/// It is the same login. The in-charge tools simply appear.
class FacultyDashboardScreen extends StatefulWidget {
  const FacultyDashboardScreen({super.key});

  @override
  State<FacultyDashboardScreen> createState() => _FacultyDashboardScreenState();
}

class _FacultyDashboardScreenState extends State<FacultyDashboardScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  StudentContext? _ctx;
  Map<String, dynamic>? _institution;
  Map<String, dynamic>? _incharge; // the route they are in-charge of, if any

  bool _tripLive = false;
  String? _busAt;
  String? _busNext;
  EtaResult? _eta;
  Map<String, dynamic>? _announcement;
  int _alertCount = 0;
  int _openComplaintCount = 0;

  RealtimeChannel? _chan;
  Timer? _tick;

  Map<String, dynamic> get _me => _ctx?.student ?? {};
  String get _name => (_me['faculty_name'] ?? 'Faculty').toString();
  bool get _isIncharge => _incharge != null;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _chan?.unsubscribe();
    super.dispose();
  }

  // ───────────────────────── data ─────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _ctx == null;
        _refreshing = _ctx != null;
        _error = null;
      });
    }
    try {
      final uid = _sb.auth.currentUser!.id;
      final ctx = await StudentContext.load(faculty: true);
      final me = ctx.student;

      Map<String, dynamic>? institution = _institution;
      if (institution == null && me['institution_id'] != null) {
        institution = await _sb
            .from('institutions')
            .select('name, city')
            .eq('id', me['institution_id'])
            .maybeSingle();
      }

      // are they the in-charge of a route?
      Map<String, dynamic>? incharge;
      try {
        final rows = await _sb.rpc('my_incharge_route') as List;
        if (rows.isNotEmpty) incharge = Map<String, dynamic>.from(rows.first as Map);
      } catch (_) {}

      // is the bus running, and when does it reach their stop?
      var live = false;
      String? at;
      String? next;
      String? nextId;
      EtaResult? eta;
      final routeId = ctx.routeId;
      final busId = ctx.busId;
      if (routeId != null) {
        final trip = await _sb
            .from('trips')
            .select('id')
            .eq('route_id', routeId)
            .eq('status', 'in_progress')
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (trip != null) {
          live = true;
          final ts = await _sb
              .from('trip_stops')
              .select('status, stop_order, stop_id, stops(stop_name)')
              .eq('trip_id', trip['id'])
              .order('stop_order', ascending: true);
          for (final r in ts) {
            final nm = (r['stops'] as Map?)?['stop_name']?.toString();
            if (r['status'] == 'reached') {
              at = nm;
            } else if (next == null) {
              next = nm;
              nextId = r['stop_id']?.toString();
            }
          }
          if (busId != null && nextId != null) {
            final loc = await _sb
                .from('live_locations')
                .select('lat, lng')
                .eq('bus_id', busId)
                .order('timestamp', ascending: false)
                .limit(1);
            final stopRows = await _sb
                .from('stops')
                .select('id, lat, lng, timing, stop_order')
                .eq('route_id', routeId);
            final sorted = Eta.sortStops(stopRows);
            final mineId = me['stop_id']?.toString();
            final nextIdx = sorted.indexWhere((x) => x['id'].toString() == nextId);
            final mineIdx = sorted.indexWhere((x) => x['id'].toString() == mineId);
            final la = loc.isEmpty ? null : double.tryParse('${loc.first['lat']}');
            final lo = loc.isEmpty ? null : double.tryParse('${loc.first['lng']}');
            if (la != null && lo != null && nextIdx >= 0 && mineIdx >= 0) {
              final avg = await Eta.recentSpeedKmh(_sb, busId);
              eta = Eta.estimate(
                  bus: LatLng(la, lo),
                  stops: sorted,
                  nextIndex: nextIdx,
                  targetIndex: mineIdx,
                  avgKmh: avg);
            }
          }
        }
      }

      // newest announcement of the last 24 hours for faculty / their bus / route
      final since = DateTime.now().toUtc().subtract(const Duration(hours: 24));
      var q = _sb.from('announcements').select().inFilter('target_role', [
        'all',
        'faculty',
        if (routeId != null) 'route_$routeId',
        if (busId != null) 'bus_$busId',
      ]).gte('created_at', since.toIso8601String());
      if (me['institution_id'] != null) q = q.eq('institution_id', me['institution_id']);
      final ann = await q.order('created_at', ascending: false).limit(1);

      final notifs = await _sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .gte('created_at', since.toIso8601String());

      var open = 0;
      try {
        final cs = await _sb.rpc('faculty_inbox_complaints') as List;
        open = cs.where((c) => (c as Map)['status'] != 'resolved').length;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _institution = institution;
        _incharge = incharge;
        _tripLive = live;
        _busAt = at;
        _busNext = next;
        _eta = eta;
        _announcement = ann.isNotEmpty ? Map<String, dynamic>.from(ann.first) : null;
        _alertCount = notifs.length;
        _openComplaintCount = open;
        _loading = false;
        _refreshing = false;
      });
      _subscribe();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _subscribe() {
    if (_chan != null) return;
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    _chan = _sb
        .channel('faculty_notif_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: 'recipient_id', value: uid),
          callback: (payload) {
            if (!mounted) return;
            final n = payload.newRecord;
            setState(() => _alertCount += 1);
            _banner((n['title'] ?? 'Alert').toString(), (n['message'] ?? '').toString(),
                (n['type'] ?? '').toString());
            _load(silent: true);
          },
        )
        .subscribe();
  }

  // ───────────────────────── actions ─────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _banner(String title, String message, String type) {
    final urgent = type == 'emergency';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: urgent ? Ym.red : Ym.navy,
        duration: Duration(seconds: urgent ? 10 : 5),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Ym.t(13.5, color: Colors.white, w: FontWeight.w800)),
            if (message.isNotEmpty) Text(message, style: Ym.t(12.5, color: Colors.white)),
          ],
        ),
      ));
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load(silent: true);
  }

  void _openLive() => _push(const LiveBusScreen(faculty: true, title: 'My bus'));
  void _openAlerts() => _push(const FacultyAlertsScreen());
  void _openOtherBuses() => _push(const OtherBusesScreen(faculty: true));
  void _openComplaints() => _push(FacultyComplaintsScreen(isIncharge: _isIncharge));
  void _openRoute() => _push(ParentRouteScreen(
        children: [
          {'id': _me['id'], 'student_name': _name}
        ],
        selected: 0,
        faculty: true,
      ));
  void _openAnnouncements() =>
      _push(ParentAnnouncementsScreen(children: [_me], audience: 'faculty'));
  void _openScan() => _push(const ScanPassScreen());
  void _openRequests() => _push(const InchargeRideRequestsScreen());
  void _openStudents() => _push(const InchargeRouteStudentsScreen());

  void _openProfile() => _push(FacultyProfileScreen(
        me: _me,
        route: _ctx?.route,
        stop: _ctx?.stop,
        institution: _institution,
        inchargeRoute: _incharge,
        onLogout: _logout,
      ));

  Future<void> _callDriver() async {
    final phone = _ctx?.driverPhone;
    if (phone == null || phone.isEmpty) {
      _snack("The driver's phone number is not available.");
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _logout() async {
    await _sb.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Log out?', style: Ym.h(18)),
        content: Text('You will need to sign in again.', style: Ym.t(13.5, color: Ym.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Log out', style: Ym.t(14, color: Ym.red, w: FontWeight.w800))),
        ],
      ),
    );
    if (ok == true) await _logout();
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ym.creamTop,
      body: YmBackground(
        child: SafeArea(
          bottom: false,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: YmSkeletonList(count: 4, height: 110),
                )
              : _error != null
                  ? _errorView()
                  : RefreshIndicator(
                      color: Ym.amber,
                      onRefresh: () => _load(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                        children: [
                          YmFadeSlide(index: 0, child: _topBar()),
                          const SizedBox(height: 22),
                          YmFadeSlide(index: 1, child: _greeting()),
                          const SizedBox(height: 18),
                          YmFadeSlide(index: 2, child: _heroCard()),
                          const SizedBox(height: 24),
                          const YmFadeSlide(index: 3, child: YmSectionTitle('Overview')),
                          YmFadeSlide(index: 3, child: _overview()),
                          const SizedBox(height: 24),
                          const YmFadeSlide(index: 4, child: YmSectionTitle('Quick Access')),
                          YmFadeSlide(index: 4, child: _quickAccess()),
                          if (_isIncharge) ...[
                            const SizedBox(height: 24),
                            YmFadeSlide(
                                index: 5,
                                child: YmSectionTitle(
                                    'In-charge tools, ${_incharge!['route_name'] ?? ''}')),
                            YmFadeSlide(index: 5, child: _inchargeTools()),
                          ],
                          const SizedBox(height: 24),
                          const YmFadeSlide(
                              index: 6, child: YmSectionTitle('Latest Announcement')),
                          YmFadeSlide(index: 6, child: _announcementCard()),
                        ],
                      ),
                    ),
        ),
      ),
      bottomNavigationBar: (_loading || _error != null) ? null : _bottomNav(),
    );
  }

  Widget _errorView() => YmEmpty(
        icon: Icons.badge_outlined,
        color: Ym.red,
        title: 'We could not open your account',
        subtitle: _error,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YmButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                expanded: false,
                onPressed: () => _load()),
            const SizedBox(height: 10),
            YmButton(label: 'Log out', outline: true, expanded: false, onPressed: _logout),
          ],
        ),
      );

  Widget _topBar() {
    final initial = _name.isEmpty ? 'F' : _name[0].toUpperCase();
    return Row(
      children: [
        YmPressable(
          onTap: _openProfile,
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
              boxShadow: Ym.shadow(Ym.amberDark, 0.3),
            ),
            child: CircleAvatar(
              radius: 21,
              backgroundColor: Colors.white,
              child: Text(initial, style: Ym.h(18, color: Ym.amberDark)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(children: [
                  TextSpan(text: 'YATRA ', style: Ym.h(16)),
                  TextSpan(text: 'MITRA', style: Ym.h(16, color: Ym.green)),
                ]),
              ),
              Text(_isIncharge ? 'Faculty, in-charge' : 'Faculty',
                  style: Ym.t(11.5, color: Ym.grey, w: FontWeight.w600)),
            ],
          ),
        ),
        YmRoundButton(
            icon: Iconsax.notification, badge: _alertCount, onTap: _openAlerts),
        const SizedBox(width: 10),
        YmRoundButton(icon: Iconsax.logout, color: Ym.red, onTap: _confirmLogout),
      ],
    );
  }

  String _hello() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Widget _greeting() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_hello(), style: Ym.t(15, color: Ym.grey)),
          const SizedBox(height: 3),
          Text(_name.trim().split(' ').first, style: Ym.h(32)),
          if (_isIncharge) ...[
            const SizedBox(height: 8),
            YmChip('In-charge of ${_incharge!['route_name'] ?? 'a route'}',
                color: Ym.green, icon: Icons.verified_user_rounded),
          ],
        ],
      );

  // ── hero ──

  Widget _heroCard() {
    final hasBus = _ctx?.routeId != null;
    final stopName = _ctx?.stop?['stop_name']?.toString();
    final instName = _institution?['name']?.toString() ?? '';
    final dept = (_me['department'] ?? '').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Ym.amber.withOpacity(0.45), width: 1.2),
        boxShadow: Ym.shadow(Ym.amberDark, 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmPulse(color: Ym.green, size: 7),
              const SizedBox(width: 8),
              Text('YOUR BUS',
                  style: Ym.t(10.5, color: Ym.amberDark, w: FontWeight.w800)
                      .copyWith(letterSpacing: 0.8)),
              const Spacer(),
              if (_refreshing)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Ym.amberDark)),
            ],
          ),
          const SizedBox(height: 10),
          Text(instName.isEmpty ? 'Faculty transport' : instName, style: Ym.h(21)),
          if (dept.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(dept, style: Ym.t(12.5, color: Ym.grey)),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
            ),
            child: !hasBus
                ? Row(children: [
                    const Icon(Icons.info_outline_rounded, color: Ym.grey, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('No bus route is assigned to you yet. The admin will add it.',
                          style: Ym.t(12.5, color: Ym.grey)),
                    ),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        YmChip(
                          _tripLive ? 'Bus is on the way' : 'Bus is not running',
                          color: _tripLive ? Ym.green : Ym.grey,
                          icon: _tripLive
                              ? Icons.directions_bus_rounded
                              : Icons.pause_circle_outline_rounded,
                        ),
                        if (_ctx?.rescueActive == true) ...[
                          const SizedBox(width: 6),
                          const YmChip('Rescue bus',
                              color: Ym.amberDark, icon: Icons.build_rounded),
                        ],
                      ]),
                      if (_tripLive) ...[
                        const SizedBox(height: 10),
                        if (_eta != null)
                          Text(
                            'Reaches ${stopName ?? "your stop"} in ${_eta!.label}'
                            ' (around ${fmtClock(_eta!.arrivesAt)})',
                            style: Ym.h(14.5),
                          ),
                        if (_busAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Last stop reached: $_busAt',
                                style: Ym.t(12.5, color: Ym.grey)),
                          ),
                        if (_busNext != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('Next stop: $_busNext',
                                style: Ym.t(12.5, color: Ym.grey)),
                          ),
                      ] else if (stopName != null) ...[
                        const SizedBox(height: 8),
                        Text('Boarding stop: $stopName', style: Ym.t(12.5, color: Ym.grey)),
                      ],
                    ],
                  ),
          ),
          if (hasBus) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: YmButton(label: 'Live Bus', icon: Iconsax.bus, onPressed: _openLive),
                ),
                const SizedBox(width: 10),
                YmPressable(
                  onTap: _callDriver,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: Ym.shadow(Ym.navy, 0.1),
                    ),
                    child: const Icon(Icons.call_rounded, color: Ym.green, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── overview ──

  Widget _overview() {
    final busNo = _ctx?.bus?['bus_number']?.toString() ?? 'Not assigned';
    final route = _ctx?.route?['route_name']?.toString() ?? 'Not assigned';
    final driver = _ctx?.driverName ?? 'Not assigned';
    final stop = _ctx?.stop?['stop_name']?.toString() ??
        ((_me['boarding_point'] ?? '').toString().isEmpty
            ? 'Not set'
            : _me['boarding_point'].toString());

    Widget mini(IconData icon, Color color, String label, String value) => Expanded(
          child: YmCard(
            padding: const EdgeInsets.all(14),
            radius: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YmIconBadge(icon: icon, color: color, size: 40),
                const SizedBox(height: 12),
                Text(label, style: Ym.t(11.5, color: Ym.grey)),
                const SizedBox(height: 3),
                Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: Ym.h(14.5)),
              ],
            ),
          ),
        );

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              mini(Iconsax.bus, Ym.green, 'Bus', busNo),
              const SizedBox(width: 12),
              mini(Icons.alt_route_rounded, Ym.blue, 'Route', route),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              mini(Icons.person_rounded, Ym.purple, 'Driver', driver),
              const SizedBox(width: 12),
              mini(Icons.pin_drop_outlined, Ym.amberDark, 'Boarding stop', stop),
            ],
          ),
        ),
      ],
    );
  }

  // ── quick access ──

  Widget _action(Widget tile, String label, VoidCallback onTap) => Expanded(
        child: YmPressable(
          onTap: onTap,
          child: Column(
            children: [
              tile,
              const SizedBox(height: 9),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: Ym.t(11.5, w: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _badged(Widget tile, int count) => Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Ym.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.8),
                ),
                child: Text(count > 9 ? '9+' : '$count',
                    style: Ym.t(10.5, color: Colors.white, w: FontWeight.w800)),
              ),
            ),
        ],
      );

  Widget _quickAccess() {
    return YmCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _action(const YmGradientTile(icon: Iconsax.bus, color: Ym.green), 'Live Bus',
                  _openLive),
              _action(
                  _badged(
                      const YmGradientTile(icon: Iconsax.notification, color: Ym.red),
                      _alertCount),
                  'Alerts',
                  _openAlerts),
              _action(
                  const YmGradientTile(icon: Icons.swap_horiz_rounded, color: Ym.blue),
                  'Other Buses',
                  _openOtherBuses),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _action(
                  _badged(
                      const YmGradientTile(
                          icon: Icons.mail_outline_rounded, color: Ym.amberDark),
                      _openComplaintCount),
                  'Complaints',
                  _openComplaints),
              _action(
                  const YmGradientTile(
                      icon: Icons.alt_route_rounded, color: Color(0xFF0D9488)),
                  'Route & Timings',
                  _openRoute),
              _action(
                  const YmGradientTile(
                      icon: Icons.campaign_rounded, color: Color(0xFFE11D48)),
                  'Announcements',
                  _openAnnouncements),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inchargeTools() {
    return YmCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _action(
              const YmGradientTile(icon: Icons.qr_code_scanner_rounded, color: Ym.purple),
              'Scan Pass',
              _openScan),
          _action(
              const YmGradientTile(icon: Icons.event_available_rounded, color: Ym.blue),
              'Ride Requests',
              _openRequests),
          _action(
              const YmGradientTile(icon: Icons.groups_rounded, color: Ym.green),
              'Route Students',
              _openStudents),
        ],
      ),
    );
  }

  // ── announcement ──

  Widget _announcementCard() {
    final a = _announcement;
    if (a == null) {
      return YmCard(
        onTap: _openAnnouncements,
        child: Row(
          children: [
            const YmIconBadge(icon: Icons.campaign_outlined, color: Ym.grey),
            const SizedBox(width: 14),
            Expanded(
              child: Text('No announcements in the last 24 hours.',
                  style: Ym.t(13, color: Ym.grey)),
            ),
          ],
        ),
      );
    }
    final at = parseUtc(a['created_at']);
    return YmCard(
      onTap: _openAnnouncements,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmIconBadge(icon: Icons.campaign_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text((a['title'] ?? 'Announcement').toString(), style: Ym.h(15))),
              if (at != null) Text(fmtClock(at), style: Ym.t(11.5, color: Ym.grey)),
            ],
          ),
          const SizedBox(height: 10),
          Text((a['body'] ?? '').toString(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5)),
          const SizedBox(height: 8),
          Text('View all announcements',
              style: Ym.t(12, color: Ym.amberDark, w: FontWeight.w800)),
        ],
      ),
    );
  }

  // ── bottom navigation ──

  Widget _bottomNav() {
    const items = <(IconData, String)>[
      (Iconsax.home_2, 'Home'),
      (Iconsax.bus, 'Live Bus'),
      (Iconsax.notification, 'Alerts'),
      (Iconsax.user, 'Profile'),
    ];
    const current = 0;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(34),
          boxShadow: Ym.shadow(Ym.navy, 0.18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              YmPressable(
                onTap: () {
                  if (i == 1) _openLive();
                  if (i == 2) _openAlerts();
                  if (i == 3) _openProfile();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.symmetric(
                      horizontal: current == i ? 18 : 14, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: current == i
                        ? const LinearGradient(colors: [Ym.amber, Ym.amberDark])
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(items[i].$1,
                          size: 22, color: current == i ? Ym.navy : Ym.grey),
                      if (current == i) ...[
                        const SizedBox(width: 7),
                        Text(items[i].$2, style: Ym.h(13, w: FontWeight.w800)),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}