import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/eta.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import '../widgets/parent_hero_video.dart';
import 'bus_pass_screen.dart';
import 'live_bus_screen.dart';
import 'parent_alerts_screen.dart';
import 'parent_announcements_screen.dart';
import 'parent_attendance_screen.dart';
import 'parent_complaints_screen.dart';
import 'parent_contact_screen.dart';
import 'parent_geofence_screen.dart';
import 'parent_leave_screen.dart';
import 'parent_payments_screen.dart';
import 'parent_profile_screen.dart';
import 'parent_route_screen.dart';
import 'role_selection_screen.dart';

/// The parent's home.
///
/// A parent is found by the `parent_email` saved on the student's record, so one
/// parent can have more than one child here. Everything shown is read from the
/// same tables the student app uses (trips, live_locations, notifications ...),
/// so the parent always sees exactly what the student sees.
class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _childBusy = false;
  String? _error;

  List<Map<String, dynamic>> _children = [];
  int _sel = 0;
  StudentContext? _ctx;
  Map<String, dynamic>? _institution;

  bool _tripLive = false;
  String? _busAt;
  String? _busNext;
  EtaResult? _eta;
  Map<String, dynamic>? _announcement;
  Map<String, dynamic>? _fee;
  int _alertCount = 0;

  RealtimeChannel? _chan;
  Timer? _tick;

  Map<String, dynamic>? get _child =>
      _children.isEmpty ? null : _children[_sel];

  String get _childId => _child?['id']?.toString() ?? '';
  String get _childName => (_child?['student_name'] ?? 'Your child').toString();

  @override
  void initState() {
    super.initState();
    _loadAll();
    // keep "bus is live / ETA" fresh while the parent has the app open
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading && _child != null) _loadChild(silent: true);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _chan?.unsubscribe();
    super.dispose();
  }

  // ───────────────────────── data ─────────────────────────

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _sb.auth.currentUser;
      final email = user?.email;
      if (user == null || email == null) throw Exception('Not logged in.');

      // ilike treats _ and % as wildcards, so escape them for an exact match
      final pattern = email
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');

      final rows = await _sb
          .from('students')
          .select()
          .ilike('parent_email', pattern)
          .order('student_name');
      if (rows.isEmpty) {
        throw Exception('No student is linked to $email. '
            'Please ask the help desk to check the parent email on the student record.');
      }

      Map<String, dynamic>? institution;
      final instId = rows.first['institution_id'];
      if (instId != null) {
        institution = await _sb
            .from('institutions')
            .select('name, city')
            .eq('id', instId)
            .maybeSingle();
      }

      if (!mounted) return;
      setState(() {
        _children = List<Map<String, dynamic>>.from(rows);
        if (_sel >= _children.length) _sel = 0;
        _institution = institution;
        _loading = false;
      });
      await _loadChild();
      _subscribe();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadChild({bool silent = false}) async {
    final child = _child;
    if (child == null) return;
    if (!silent) setState(() => _childBusy = true);

    try {
      final uid = _sb.auth.currentUser!.id;
      final ctx = await StudentContext.load(studentId: child['id'].toString());

      // Is the bus running? + where is it? + when does it reach the child's stop?
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
            final mineId = ctx.student['stop_id']?.toString();
            final nextIdx =
                sorted.indexWhere((x) => x['id'].toString() == nextId);
            final mineIdx =
                sorted.indexWhere((x) => x['id'].toString() == mineId);
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

      // newest announcement from the last 24 hours meant for parents / this bus / route
      final since = DateTime.now().toUtc().subtract(const Duration(hours: 24));
      var annQuery = _sb
          .from('announcements')
          .select()
          .inFilter('target_role', [
            'all',
            'parent',
            if (routeId != null) 'route_$routeId',
            if (busId != null) 'bus_$busId',
          ])
          .gte('created_at', since.toIso8601String());
      if (child['institution_id'] != null) {
        annQuery = annQuery.eq('institution_id', child['institution_id']);
      }
      final ann = await annQuery.order('created_at', ascending: false).limit(1);

      // fee status for this year (the help desk records payments)
      Map<String, dynamic>? fee;
      try {
        fee = await _sb
            .from('student_fee_status')
            .select()
            .eq('student_id', child['id'])
            .maybeSingle();
      } catch (_) {}

      final notifs = await _sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .gte('created_at', since.toIso8601String());

      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _tripLive = live;
        _busAt = at;
        _busNext = next;
        _eta = eta;
        _announcement = ann.isNotEmpty ? Map<String, dynamic>.from(ann.first) : null;
        _fee = fee;
        _alertCount = notifs.length;
        _childBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _childBusy = false);
      if (!silent) _snack('Could not load $_childName: $e');
    }
  }

  void _subscribe() {
    if (_chan != null) return;
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    _chan = _sb
        .channel('parent_notif_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: uid),
          callback: (payload) {
            if (!mounted) return;
            final n = payload.newRecord;
            setState(() => _alertCount += 1);
            _banner(
              (n['title'] ?? 'Alert').toString(),
              (n['message'] ?? '').toString(),
              (n['type'] ?? '').toString(),
            );
            _loadChild(silent: true);
          },
        )
        .subscribe();
  }

  // ───────────────────────── actions ─────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ));
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
            Text(title,
                style: Ym.t(13.5, color: Colors.white, w: FontWeight.w800)),
            if (message.isNotEmpty)
              Text(message, style: Ym.t(12.5, color: Colors.white)),
          ],
        ),
      ));
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _loadChild(silent: true);
  }

  void _openLive() {
    if (_child == null) return;
    _push(LiveBusScreen(studentId: _childId, title: "$_childName's bus"));
  }

  void _openAlerts() => _push(ParentAlertsScreen(childName: _childName));

  void _openAttendance() {
    if (_child == null) return;
    _push(ParentAttendanceScreen(
      studentId: _childId,
      studentName: _childName,
      routeId: _ctx?.routeId,
    ));
  }

  void _openComplaints() {
    if (_child == null) return;
    _push(ParentComplaintsScreen(children: _children, selected: _sel));
  }

  void _openLeave() {
    if (_child == null) return;
    _push(ParentLeaveScreen(children: _children, selected: _sel));
  }

  void _openRoute() {
    if (_child == null) return;
    _push(ParentRouteScreen(children: _children, selected: _sel));
  }

  void _openPayments() {
    if (_child == null) return;
    _push(ParentPaymentsScreen(children: _children, selected: _sel));
  }

  void _openBusPass() {
    if (_child == null) return;
    _push(BusPassScreen(studentId: _childId));
  }

  void _openAlertDistance() {
    if (_child == null) return;
    _push(ParentGeofenceScreen(children: _children, selected: _sel));
  }

  void _openAnnouncements() => _push(ParentAnnouncementsScreen(children: _children));

  void _openContact() {
    if (_child == null) return;
    _push(ParentContactScreen(
      children: _children,
      selected: _sel,
      onComplaint: _openComplaints,
    ));
  }

  void _openProfile() {
    if (_child == null) return;
    _push(ParentProfileScreen(
      children: _children,
      selected: _sel,
      institution: _institution,
      onLogout: _logout,
    ));
  }

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
        content: Text('You will need to sign in again to see your child\'s bus.',
            style: Ym.t(13.5, color: Ym.grey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
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
              ? _skeleton()
              : _error != null
                  ? _errorView()
                  : RefreshIndicator(
                      color: Ym.amber,
                      onRefresh: _loadAll,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                        children: [
                          YmFadeSlide(index: 0, child: _topBar()),
                          const SizedBox(height: 22),
                          YmFadeSlide(index: 1, child: _greeting()),
                          if (_children.length > 1) ...[
                            const SizedBox(height: 16),
                            YmFadeSlide(index: 1, child: _childPicker()),
                          ],
                          const SizedBox(height: 18),
                          YmFadeSlide(index: 2, child: _heroCard()),
                          const SizedBox(height: 24),
                          const YmFadeSlide(
                              index: 3, child: YmSectionTitle('Overview')),
                          YmFadeSlide(index: 3, child: _overview()),
                          const SizedBox(height: 24),
                          const YmFadeSlide(
                              index: 4, child: YmSectionTitle('Quick Access')),
                          YmFadeSlide(index: 4, child: _quickAccess()),
                          const SizedBox(height: 24),
                          const YmFadeSlide(
                              index: 5,
                              child: YmSectionTitle('Latest Announcement')),
                          YmFadeSlide(index: 5, child: _announcementCard()),
                        ],
                      ),
                    ),
        ),
      ),
      bottomNavigationBar:
          (_loading || _error != null) ? null : _bottomNav(),
    );
  }

  Widget _skeleton() => const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: YmSkeletonList(count: 4, height: 110),
      );

  Widget _errorView() => YmEmpty(
        icon: Icons.family_restroom_rounded,
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
                onPressed: _loadAll),
            const SizedBox(height: 10),
            YmButton(
                label: 'Log out',
                outline: true,
                expanded: false,
                onPressed: _logout),
          ],
        ),
      );

  String get _parentName {
    final n = _child?['parent_name']?.toString().trim() ?? '';
    if (n.isNotEmpty) return n;
    final e = _sb.auth.currentUser?.email ?? '';
    return e.contains('@') ? e.split('@').first : 'Parent';
  }

  Widget _topBar() {
    final initial = _parentName.isEmpty ? 'P' : _parentName[0].toUpperCase();
    return Row(
      children: [
        YmPressable(
          onTap: _openProfile,
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient:
                  const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
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
              Text('Parent',
                  style: Ym.t(11.5, color: Ym.grey, w: FontWeight.w600)),
            ],
          ),
        ),
        YmRoundButton(
            icon: Iconsax.notification, badge: _alertCount, onTap: _openAlerts),
        const SizedBox(width: 10),
        YmRoundButton(
            icon: Iconsax.logout, color: Ym.red, onTap: _confirmLogout),
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
          Text(_parentName.trim().split(' ').first, style: Ym.h(32)),
        ],
      );

  Widget _childPicker() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _children.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: YmPressable(
                  onTap: () {
                    if (i == _sel) return;
                    setState(() => _sel = i);
                    _loadChild();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: i == _sel
                          ? const LinearGradient(
                              colors: [Ym.amber, Ym.amberDark])
                          : null,
                      color: i == _sel ? null : Colors.white,
                      boxShadow: Ym.shadow(Ym.navy, 0.07),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_rounded,
                            size: 16, color: i == _sel ? Ym.navy : Ym.grey),
                        const SizedBox(width: 7),
                        Text(
                          (_children[i]['student_name'] ?? 'Student')
                              .toString()
                              .split(' ')
                              .first,
                          style: Ym.t(13,
                              color: i == _sel ? Ym.navy : Ym.grey,
                              w: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  // ── hero: the child and where the bus is ──

  Widget _heroCard() {
    final c = _child!;
    final dept = c['department']?.toString() ?? '';
    final year = c['year']?.toString() ?? '';
    final enrol = c['enrollment_no']?.toString() ?? '';
    final instName = _institution?['name']?.toString() ?? '';
    final chips = <String>[
      if (dept.isNotEmpty) dept,
      if (year.isNotEmpty) year,
      if (enrol.isNotEmpty) enrol,
    ];

    final hasBus = _ctx?.routeId != null;
    final stopName = _ctx?.stop?['stop_name']?.toString();

    const fade = Color(0xFFFFF5E0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // the top of the card is one flat colour so the picture melts into it
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fade, fade, Color(0xFFFFE6B8)],
          stops: [0.0, 0.36, 1.0],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Ym.amber.withOpacity(0.45), width: 1.2),
        boxShadow: Ym.shadow(Ym.amberDark, 0.25),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: LayoutBuilder(
          builder: (context, box) {
            // height of the picture at this card width
            final vh = box.maxWidth / ParentHeroVideo.ratio;
            return Stack(
              children: [
                const Positioned(
                    top: 0, left: 0, right: 0, child: ParentHeroVideo()),
                // the picture fades softly into the card
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: vh,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00FFF5E0), fade],
                          stops: [0.42, 0.98],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, vh * 0.8, 20, 20),
                  child: _heroContent(
                      chips: chips,
                      instName: instName,
                      hasBus: hasBus,
                      stopName: stopName),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The text, status and buttons of the "Your child" card.
  Widget _heroContent({
    required List<String> chips,
    required String instName,
    required bool hasBus,
    required String? stopName,
  }) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmPulse(color: Ym.green, size: 7),
              const SizedBox(width: 8),
              Text('YOUR CHILD',
                  style: Ym.t(10.5, color: Ym.amberDark, w: FontWeight.w800)
                      .copyWith(letterSpacing: 0.8)),
              const Spacer(),
              if (_childBusy)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Ym.amberDark)),
            ],
          ),
          const SizedBox(height: 10),
          Text(_childName, style: Ym.h(25)),
          if (instName.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(instName, style: Ym.t(12.5, color: Ym.grey)),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in chips) YmChip(t, color: Ym.navy),
            ]),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
            ),
            child: !hasBus
                ? Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Ym.grey, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('No bus route is assigned to $_childName yet.',
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
                            'Reaches ${stopName ?? "the stop"} in ${_eta!.label}'
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
                        Text('Boarding stop: $stopName',
                            style: Ym.t(12.5, color: Ym.grey)),
                      ],
                    ],
                  ),
          ),
          if (hasBus) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: YmButton(
                      label: 'Live Bus',
                      icon: Iconsax.bus,
                      onPressed: _openLive),
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
                    child: const Icon(Icons.call_rounded,
                        color: Ym.green, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
  }

  // ── overview ──

  String _validTill() {
    final v = _fee?['valid_till']?.toString();
    final d = v == null ? null : DateTime.tryParse(v);
    return d == null ? 'Not active' : fmtDate(d);
  }

  Widget _overview() {
    final busNo = _ctx?.bus?['bus_number']?.toString() ?? 'Not assigned';
    final route = _ctx?.route?['route_name']?.toString() ?? 'Not assigned';
    final driver = _ctx?.driverName ?? 'Not assigned';
    final status = (_fee?['fee_status'] ?? 'unknown').toString();
    final paid = status == 'paid';

    Widget mini(IconData icon, Color color, String label, String value,
            {Widget? tag}) =>
        Expanded(
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
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Ym.h(14.5)),
                if (tag != null) ...[const SizedBox(height: 8), tag],
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
              mini(
                Icons.verified_rounded,
                paid ? Ym.green : Ym.amberDark,
                'Bus pass valid till',
                _validTill(),
                tag: YmChip(
                  paid
                      ? 'Fee paid'
                      : status == 'partial'
                          ? 'Partly paid'
                          : 'Fee due',
                  color: paid ? Ym.green : Ym.amberDark,
                ),
              ),
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

  Widget _quickAccess() {
    Widget row(List<Widget> items) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items,
        );

    return YmCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        children: [
          row([
            _action(const YmGradientTile(icon: Iconsax.bus, color: Ym.green),
                'Live Bus', _openLive),
            _action(
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const YmGradientTile(
                        icon: Iconsax.notification, color: Ym.red),
                    if (_alertCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Ym.navy,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 1.8),
                          ),
                          child: Text(_alertCount > 9 ? '9+' : '$_alertCount',
                              style: Ym.t(10.5,
                                  color: Colors.white, w: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
                'Alerts',
                _openAlerts),
            _action(
                const YmGradientTile(
                    icon: Icons.fact_check_rounded, color: Ym.blue),
                'Attendance',
                _openAttendance),
          ]),
          const SizedBox(height: 20),
          row([
            _action(
                const YmGradientTile(
                    icon: Icons.mail_outline_rounded, color: Ym.amberDark),
                'Complaints',
                _openComplaints),
            _action(
                const YmGradientTile(
                    icon: Icons.event_busy_rounded, color: Ym.purple),
                'Leave',
                _openLeave),
            _action(
                const YmGradientTile(
                    icon: Icons.alt_route_rounded, color: Color(0xFF0D9488)),
                'Route & Timings',
                _openRoute),
          ]),
          const SizedBox(height: 20),
          row([
            _action(
                const YmGradientTile(
                    icon: Icons.campaign_rounded, color: Color(0xFFE11D48)),
                'Announcements',
                _openAnnouncements),
            _action(
                const YmGradientTile(
                    icon: Icons.support_agent_rounded, color: Color(0xFF0EA5E9)),
                'Help & Contact',
                _openContact),
            _action(
                const YmGradientTile(
                    icon: Icons.call_rounded, color: Ym.green),
                'Call Driver',
                _callDriver),
          ]),
          const SizedBox(height: 20),
          row([
            _action(
                const YmGradientTile(
                    icon: Icons.account_balance_wallet_outlined,
                    color: Ym.amberDark),
                'Payments',
                _openPayments),
            _action(
                const YmGradientTile(
                    icon: Icons.badge_outlined, color: Ym.purple),
                'Bus Pass',
                _openBusPass),
            _action(
                const YmGradientTile(
                    icon: Icons.notifications_active_outlined, color: Ym.red),
                'Alert Distance',
                _openAlertDistance),
          ]),
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
              Expanded(
                child: Text((a['title'] ?? 'Announcement').toString(),
                    style: Ym.h(15)),
              ),
              if (at != null)
                Text(fmtClock(at), style: Ym.t(11.5, color: Ym.grey)),
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