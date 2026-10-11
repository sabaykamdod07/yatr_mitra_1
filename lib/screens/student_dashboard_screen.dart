import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'role_selection_screen.dart';
import 'bus_pass_screen.dart';
import 'complaints_screen.dart';
import 'emergency_sos_screen.dart';
import 'geofence_settings_screen.dart';
import 'live_bus_screen.dart';
import 'mark_absent_sheet.dart';
import 'other_buses_screen.dart';
import 'payments_screen.dart';
import 'student_history_screen.dart';
import 'student_notifications_screen.dart';
import 'student_profile_screen.dart';
import '../services/student_context.dart' show parseUtc, fmtClock, fmtDate;
import '../theme/ym_ui.dart';
import '../services/eta.dart';
import 'package:latlong2/latlong.dart';

/// Colours copied from the admin dashboard look.
/// If your admin screen uses AppTheme constants for these, swap them in here.
class _C {
  static const bg = Color(0xFFFFF8F1);
  static const navy = Color(0xFF0F1B4D);
  static const orange = Color(0xFFFF9800);
  static const orangeSoft = Color(0xFFFFEFD9);
  static const grey = Color(0xFF8E94A9);
  static const green = Color(0xFF0E9F6E);
  static const red = Color(0xFFE53935);
  static const blue = Color(0xFF3B6FF5);
  static const border = Color(0xFFF6E3C6);
}

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen>
    with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _student;
  Map<String, dynamic>? _bus;
  Map<String, dynamic>? _route;
  Map<String, dynamic>? _stop;
  Map<String, dynamic>? _institution;
  Map<String, dynamic>? _driverProfile;
  String? _driverPhone;
  String? _ownPhotoUrl;
  List<Map<String, dynamic>> _recentAlerts = [];
  Map<String, dynamic>? _latestAnnouncement;

  String? _busId;
  RealtimeChannel? _alertChannel;

  // live status of the bus on the student's route (driver trip or hardware)
  bool _tripLive = false;
  String? _busAt;
  String? _busNext;
  EtaResult? _eta; // bus -> this student's boarding stop
  bool _rescueActive = false; // a rescue bus has taken over after a breakdown

  int _currentTab = 0;
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  Timer? _videoTimer;
  Duration? _lastVideoPos;

  int get _alertCount => _recentAlerts.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboard();
    _initVideo();
    _listenForAlerts();
    // the hero video must never stay frozen: check it every 2 seconds
    _videoTimer = Timer.periodic(const Duration(seconds: 2), (_) => _videoWatchdog());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _videoController?.play();
  }

  /// Plays the video again if it was paused, and restarts it if the picture froze.
  void _videoWatchdog() {
    final c = _videoController;
    if (!mounted || c == null) return;
    if (c.value.hasError) {
      // the player broke: start a fresh one
      c.dispose();
      _videoController = null;
      _lastVideoPos = null;
      if (mounted) setState(() => _videoReady = false);
      _initVideo();
      return;
    }
    if (!c.value.isInitialized) return;
    final pos = c.value.position;
    if (!c.value.isPlaying) {
      c.play();
    } else if (_lastVideoPos != null && pos == _lastVideoPos) {
      // says playing, but the picture is not moving: jump to the start
      c.seekTo(Duration.zero).then((_) => c.play());
    }
    _lastVideoPos = pos;
  }

  void _initVideo() {
    final c = VideoPlayerController.asset(
        'assets/images/student_dashboard_video.mp4');
    _videoController = c;
    c.setLooping(true);
    c.setVolume(0);
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _videoReady = true);
      c.play();
    }).catchError((_) {
      // Video missing / unsupported -> we just show the image fallback.
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoTimer?.cancel();
    if (_alertChannel != null) _supabase.removeChannel(_alertChannel!);
    _videoController?.dispose();
    super.dispose();
  }

  // ───────────────────────── DATA ─────────────────────────

  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser?.email == null) throw Exception('Not logged in.');

      final studentRow = await _supabase
          .from('students')
          .select(
            '*, buses(bus_number,bus_name,status,driver_id), '
            'routes(id,route_name,start_point,end_point,timings,bus_id), '
            'stops(stop_name,timing)',
          )
          .eq('student_email', authUser!.email as Object)
          .maybeSingle();

      if (studentRow == null) {
        throw Exception(
          'No student record found for ${authUser.email}. '
          'Check that student_email matches exactly.',
        );
      }

      Map<String, dynamic>? institution;
      final instId = studentRow['institution_id'];
      if (instId != null) {
        institution = await _supabase
            .from('institutions')
            .select('name, city')
            .eq('id', instId)
            .maybeSingle();
      }

      // Bus: the student's own bus, else the bus attached to their route.
      Map<String, dynamic>? bus = studentRow['buses'] as Map<String, dynamic>?;
      final routeMap = studentRow['routes'] as Map<String, dynamic>?;
      var busId = (studentRow['bus_id'] ?? routeMap?['bus_id'])?.toString();

      // If this route's bus broke down and another bus accepted the rescue,
      // follow the rescue bus (its driver, position and ETA).
      var rescueActive = false;
      String? rescueDriverId;
      if (busId != null) {
        try {
          final ra = await _supabase
              .from('rescue_assignments')
              .select('rescue_bus_id, rescue_driver_id')
              .eq('broken_bus_id', busId)
              .eq('status', 'accepted')
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (ra != null && ra['rescue_bus_id'] != null) {
            rescueActive = true;
            busId = ra['rescue_bus_id'].toString();
            rescueDriverId = ra['rescue_driver_id']?.toString();
            bus = null; // load the rescue bus below
          }
        } catch (_) {}
      }

      if (bus == null && busId != null) {
        bus = await _supabase
            .from('buses')
            .select('bus_number,bus_name,status')
            .eq('id', busId)
            .maybeSingle();
      }

      // Driver: whoever is assigned to this bus or route in `drivers`.
      Map<String, dynamic>? driverProfile;
      String? driverPhone;
      final driverFilters = rescueDriverId != null
          ? <String>['id.eq.$rescueDriverId']
          : <String>[
              if (busId != null) 'bus_id.eq.$busId',
              if (routeMap?['id'] != null) 'route_id.eq.${routeMap!['id']}',
            ];
      if (driverFilters.isNotEmpty) {
        final d = await _supabase
            .from('drivers')
            .select('driver_name, driver_phone')
            .or(driverFilters.join(','))
            .eq('is_active', true)
            .limit(1)
            .maybeSingle();
        if (d != null) {
          driverProfile = {'full_name': d['driver_name'], 'photo': null};
          driverPhone = d['driver_phone']?.toString();
        }
      }

      final ownProfile = await _supabase
          .from('profiles')
          .select('photo')
          .eq('user_id', authUser.id)
          .maybeSingle();

      // Is the bus running right now? Reads the same trip data the driver app writes.
      var tripLive = false;
      String? busAt;
      String? busNext;
      String? nextStopId;
      EtaResult? eta;
      final routeIdForTrip = routeMap?['id'];
      if (routeIdForTrip != null) {
        final trip = await _supabase
            .from('trips')
            .select('id')
            .eq('route_id', routeIdForTrip)
            .eq('status', 'in_progress')
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (trip != null) {
          tripLive = true;
          final ts = await _supabase
              .from('trip_stops')
              .select('status, stop_order, stop_id, stops(stop_name)')
              .eq('trip_id', trip['id'])
              .order('stop_order', ascending: true);
          for (final r in ts) {
            final nm = (r['stops'] as Map?)?['stop_name']?.toString();
            if (r['status'] == 'reached') {
              busAt = nm;
            } else if (busNext == null) {
              busNext = nm;
              nextStopId = r['stop_id']?.toString();
            }
          }

          // estimated arrival of the bus at THIS student's boarding stop
          if (busId != null && nextStopId != null) {
            final loc = await _supabase
                .from('live_locations')
                .select('lat, lng')
                .eq('bus_id', busId)
                .order('timestamp', ascending: false)
                .limit(1);
            final stopRows = await _supabase
                .from('stops')
                .select('id, lat, lng, timing, stop_order')
                .eq('route_id', routeIdForTrip);
            final sorted = Eta.sortStops(stopRows);
            final mineId = studentRow['stop_id']?.toString();
            final nextIdx =
                sorted.indexWhere((x) => x['id'].toString() == nextStopId);
            final mineIdx =
                sorted.indexWhere((x) => x['id'].toString() == mineId);
            final la = loc.isEmpty ? null : double.tryParse('${loc.first['lat']}');
            final lo = loc.isEmpty ? null : double.tryParse('${loc.first['lng']}');
            if (la != null && lo != null && nextIdx >= 0 && mineIdx >= 0) {
              final avg = await Eta.recentSpeedKmh(_supabase, busId);
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

      // Alerts only live for 24 hours.
      final cutoff =
          DateTime.now().toUtc().subtract(const Duration(hours: 24));
      final notifRows = await _supabase
          .from('notifications')
          .select()
          .eq('recipient_id', authUser.id)
          .eq('type', 'geofence')
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at', ascending: false)
          .limit(3);

      // Dashboard shows only the single most recent announcement.
      // Includes announcements the admin sent to this student's route or bus.
      final annTargets = <String>[
        'all',
        'student',
        if (routeMap?['id'] != null) 'route_${routeMap!['id']}',
        if (busId != null) 'bus_$busId',
      ];
      var annQuery = _supabase
          .from('announcements')
          .select()
          .inFilter('target_role', annTargets);
      if (studentRow['institution_id'] != null) {
        annQuery = annQuery.eq('institution_id', studentRow['institution_id']);
      }
      final annRows =
          await annQuery.order('created_at', ascending: false).limit(1);

      if (!mounted) return;
      setState(() {
        _student = studentRow;
        _bus = bus;
        _busId = busId;
        _tripLive = tripLive;
        _busAt = busAt;
        _busNext = busNext;
        _eta = eta;
        _rescueActive = rescueActive;
        _route = studentRow['routes'] as Map<String, dynamic>?;
        _stop = studentRow['stops'] as Map<String, dynamic>?;
        _institution = institution;
        _driverProfile = driverProfile;
        _driverPhone = driverPhone;
        _ownPhotoUrl = ownProfile?['photo'] as String?;
        _recentAlerts = List<Map<String, dynamic>>.from(notifRows);
        _latestAnnouncement =
            annRows.isNotEmpty ? Map<String, dynamic>.from(annRows.first) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || silent) return; // a quiet refresh never replaces the screen with an error
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ───────────────────────── ACTIONS ─────────────────────────

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon.'),
        backgroundColor: _C.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _callDriver() async {
    if (_driverPhone == null || _driverPhone!.isEmpty) {
      _comingSoon('Driver phone number is not available yet,');
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: _driverPhone));
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again to continue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;

    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  void _push(Widget w) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  }

  void _openLiveBus() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LiveBusScreen()))
        .then((_) => _refreshAlerts());
  }

  void _openNotifications() {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => const StudentNotificationsScreen()))
        .then((_) => _refreshAlerts());
  }

  void _openGeofenceSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GeofenceSettingsScreen()),
    );
  }

  /// Reloads just the alerts card + badge (no full-screen spinner).
  Future<void> _refreshAlerts() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final cutoff =
          DateTime.now().toUtc().subtract(const Duration(hours: 24));
      final rows = await _supabase
          .from('notifications')
          .select()
          .eq('recipient_id', uid)
          .eq('type', 'geofence')
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at', ascending: false)
          .limit(3);
      if (!mounted) return;
      setState(() => _recentAlerts = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  /// Realtime: a new geofence notification pops up on screen straight away.
  /// The row is already saved in `notifications` (by the database trigger),
  /// so it also appears under Notifications for 24 hours.
  void _listenForAlerts() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    _alertChannel = _supabase
        .channel('student_alert_popup_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (payload) {
            if (!mounted) return;
            final n = payload.newRecord;
            _refreshAlerts();
            if (n['type']?.toString() == 'geofence') {
              _showGeofencePopup(n);
            } else {
              // rescue, announcements, updates: refresh the cards quietly
              _loadDashboard(silent: true);
            }
          },
        )
        .subscribe();
  }

  void _showGeofencePopup(Map<String, dynamic> n) {
    final at = parseUtc(n['created_at']) ?? DateTime.now();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close, size: 20, color: _C.grey),
                ),
              ),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                    color: _C.red.withOpacity(0.12), shape: BoxShape.circle),
                child: const Icon(Iconsax.location, color: _C.red, size: 28),
              ),
              const SizedBox(height: 12),
              Text(n['title']?.toString() ?? 'Geofence Alert',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _C.navy)),
              const SizedBox(height: 8),
              Text(n['message']?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _C.grey)),
              const SizedBox(height: 6),
              Text('Time: ${fmtClock(at)}',
                  style: const TextStyle(color: _C.grey, fontSize: 12)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openLiveBus();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.orange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('View on Map'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StudentProfileScreen()),
    );
  }

  String _fmtTime(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  // ───────────────────────── BUILD ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ym.creamTop,
      extendBody: true,
      body: YmBackground(
        child: SafeArea(
          bottom: false,
          child: _loading
              ? _buildSkeleton()
              : _error != null
                  ? _buildError()
                  : RefreshIndicator(
                      color: Ym.amber,
                      onRefresh: _loadDashboard,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
                        children: [
                          YmFadeSlide(index: 0, child: _buildTopBar()),
                          const SizedBox(height: 22),
                          YmFadeSlide(index: 1, child: _buildGreeting()),
                          const SizedBox(height: 18),
                          YmFadeSlide(index: 2, child: _buildHeroCard()),
                          const SizedBox(height: 26),
                          const YmFadeSlide(
                              index: 3, child: YmSectionTitle('My Bus')),
                          YmFadeSlide(index: 3, child: _buildMyBusCard()),
                          const SizedBox(height: 26),
                          const YmFadeSlide(
                              index: 4,
                              child: YmSectionTitle("Today's Journey")),
                          YmFadeSlide(index: 4, child: _buildJourneyCard()),
                          const SizedBox(height: 26),
                          const YmFadeSlide(
                              index: 5, child: YmSectionTitle('Quick Actions')),
                          YmFadeSlide(index: 5, child: _buildQuickActions()),
                          const SizedBox(height: 26),
                          YmFadeSlide(index: 6, child: _buildAlertsCard()),
                          const SizedBox(height: 16),
                          YmFadeSlide(index: 7, child: _buildAnnouncementCard()),
                        ],
                      ),
                    ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: (_loading || _error != null) ? null : _sosFab(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      children: const [
        YmSkeleton(height: 46, radius: 23),
        SizedBox(height: 22),
        YmSkeleton(height: 64),
        SizedBox(height: 18),
        YmSkeleton(height: 250, radius: 30),
        SizedBox(height: 26),
        YmSkeleton(height: 300),
        SizedBox(height: 18),
        YmSkeleton(height: 180),
      ],
    );
  }

  Widget _buildError() {
    return YmEmpty(
      icon: Iconsax.warning_2,
      color: Ym.red,
      title: 'Something went wrong',
      subtitle: _error,
      action: YmButton(
        label: 'Try again',
        icon: Icons.refresh_rounded,
        expanded: false,
        onPressed: _loadDashboard,
      ),
    );
  }

  // ── top bar ──

  Widget _buildTopBar() {
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
              backgroundImage:
                  _ownPhotoUrl != null ? NetworkImage(_ownPhotoUrl!) : null,
              child: _ownPhotoUrl == null
                  ? Text(
                      ((_student?['student_name'] ?? '?').toString().trim().isEmpty
                              ? '?'
                              : (_student!['student_name'] as String).trim()[0])
                          .toUpperCase(),
                      style: Ym.h(18, color: Ym.amberDark))
                  : null,
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
              Text((_student?['student_name'] ?? 'Student').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ym.t(11.5, color: Ym.grey, w: FontWeight.w600)),
            ],
          ),
        ),
        YmRoundButton(
            icon: Iconsax.notification,
            badge: _alertCount,
            onTap: _openNotifications),
        const SizedBox(width: 10),
        YmRoundButton(
            icon: Iconsax.logout, color: Ym.red, onTap: _handleLogout),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Widget _buildGreeting() {
    final name = _student?['student_name']?.toString() ?? 'Student';
    final firstName = name.trim().split(' ').first;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(), style: Ym.t(15, color: Ym.grey)),
              const SizedBox(height: 3),
              Text(firstName, style: Ym.h(32)),
            ],
          ),
        ),
      ],
    );
  }

  // ── hero ──

  Widget _buildHeroCard() {
    final instName = _institution?['name']?.toString() ?? 'Your Institution';
    final city = _institution?['city']?.toString();
    final dept = _student?['department']?.toString();
    final year = _student?['year']?.toString();
    final enrol = _student?['enrollment_no']?.toString();
    final chips = <String>[
      if (dept != null && dept.isNotEmpty) dept,
      if (year != null && year.isNotEmpty) year,
      if (enrol != null && enrol.isNotEmpty) enrol,
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Ym.amber.withOpacity(0.45), width: 1.2),
        boxShadow: Ym.shadow(Ym.amberDark, 0.28),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: -40,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Ym.amber.withOpacity(0.25)),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -60,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white.withOpacity(0.6)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(instName, style: Ym.h(20)),
                          if (city != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Row(
                                children: [
                                  const Icon(Iconsax.location,
                                      size: 14, color: Ym.amberDark),
                                  const SizedBox(width: 4),
                                  Text(city,
                                      style: Ym.t(13,
                                          color: Ym.grey, w: FontWeight.w600)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: Ym.shadow(Ym.amberDark, 0.12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          YmPulse(
                              color: _tripLive ? Ym.green : Ym.grey, size: 7),
                          Text(_tripLive ? 'Bus is live' : 'Bus not running',
                              style: Ym.t(11.5,
                                  color: _tripLive ? Ym.green : Ym.navy,
                                  w: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.78),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Ym.amber.withOpacity(0.5), width: 1),
                          ),
                          child: Text(c,
                              style: Ym.t(12,
                                  color: Ym.navy, w: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_videoReady && _videoController != null)
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _videoController!.value.size.width,
                              height: _videoController!.value.size.height,
                              child: VideoPlayer(_videoController!),
                            ),
                          )
                        else
                          Image.asset(
                            'assets/images/bus.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Ym.amber.withOpacity(0.18),
                              child: const Icon(Iconsax.bus,
                                  size: 44, color: Ym.amberDark),
                            ),
                          ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Ym.navy.withOpacity(0.55),
                                  Colors.transparent
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          bottom: 12,
                          child: Text('Safe journeys, every day',
                              style: Ym.h(13.5,
                                  color: Colors.white, w: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── my bus ──

  String _fmt12(dynamic raw) {
    final s = raw?.toString() ?? '';
    final p = s.split(':');
    if (p.length < 2) return '--';
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return '--';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
  }

  String? _pickupCountdown() {
    final p = (_stop?['timing']?.toString() ?? '').split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day, h, m).difference(now);
    if (diff.isNegative) return 'Time has passed';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
    return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  Widget _buildMyBusCard() {
    if (_bus == null) {
      return YmCard(
        child: Row(
          children: [
            const YmIconBadge(icon: Iconsax.bus, color: Ym.grey),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _route != null
                    ? 'Bus not assigned yet for ${_route!['route_name']}.'
                    : 'No route assigned yet. Please contact your institution.',
                style: Ym.t(13.5, color: Ym.grey),
              ),
            ),
          ],
        ),
      );
    }

    final maint = _bus!['status'] == 'maintenance' && !_rescueActive;
    final String label = maint ? 'Maintenance' : (_tripLive ? 'On Route' : 'Not running');
    final Color color = maint ? Ym.red : (_tripLive ? Ym.green : Ym.grey);
    final driverName = _driverProfile?['full_name']?.toString();
    final driverPhoto = _driverProfile?['photo'] as String?;
    final countdown = _pickupCountdown();

    return YmCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmIconBadge(icon: Iconsax.bus, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_bus!['bus_number']?.toString() ?? '',
                        style: Ym.h(18)),
                    if (_bus!['bus_name'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(_bus!['bus_name'].toString(),
                            style: Ym.t(12.5, color: Ym.grey)),
                      ),
                  ],
                ),
              ),
              YmChip(label, color: color, icon: Icons.circle),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Ym.amber.withOpacity(0.22), Ym.amber.withOpacity(0.07)],
              ),
              border: Border.all(color: Ym.amber.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PICKUP TIME',
                          style: Ym.t(10.5,
                              color: Ym.grey, w: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(_fmt12(_stop?['timing']), style: Ym.h(28)),
                    ],
                  ),
                ),
                if (_eta != null)
                  YmChip('Bus in ${_eta!.label}',
                      color: Ym.green, icon: Icons.directions_bus_rounded)
                else if (countdown != null)
                  YmChip(countdown, color: Ym.amberDark, icon: Iconsax.clock),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_eta != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Ym.green.withOpacity(0.09),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const YmPulse(color: Ym.green, size: 7),
                  Expanded(
                    child: Text(
                      'Your bus is on the way. Expected at your stop around '
                      '${fmtClock(_eta!.arrivesAt)}.',
                      style: Ym.t(12.5, color: Ym.green, w: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (_rescueActive)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Ym.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: const Border(left: BorderSide(color: Ym.red, width: 4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Ym.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your bus broke down. This rescue bus is taking over your pickup.',
                      style: Ym.t(12.5, color: Ym.red, w: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          _infoRow(Icons.alt_route_rounded, 'Route',
              _route?['route_name']?.toString() ?? '-'),
          _infoRow(Iconsax.location, 'Boarding stop',
              _stop?['stop_name']?.toString() ?? '-'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Ym.creamTop,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: Ym.amber.withOpacity(0.25),
                  backgroundImage:
                      driverPhoto != null ? NetworkImage(driverPhoto) : null,
                  child: driverPhoto == null
                      ? const Icon(Iconsax.user, color: Ym.amberDark, size: 19)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your driver',
                          style: Ym.t(11.5, color: Ym.grey)),
                      Text(driverName ?? 'Not assigned yet',
                          style: Ym.h(14.5)),
                    ],
                  ),
                ),
                YmPressable(
                  onTap: _callDriver,
                  child: const YmGradientTile(
                      icon: Icons.call_rounded, color: Ym.green, size: 44),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          YmButton(
            label: 'View Live Bus',
            icon: Iconsax.map_1,
            onPressed: _openLiveBus,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 17, color: Ym.amberDark),
            const SizedBox(width: 10),
            SizedBox(
                width: 104, child: Text(k, style: Ym.t(13, color: Ym.grey))),
            Expanded(child: Text(v, style: Ym.h(14, w: FontWeight.w700))),
          ],
        ),
      );

  // ── journey ──

  Widget _buildJourneyCard() {
    final stopName = _stop?['stop_name']?.toString();
    final endPoint = _route?['end_point']?.toString();

    if (stopName == null && endPoint == null) {
      return YmCard(
        child: Text('Your journey will appear here once a route is assigned.',
            style: Ym.t(13.5, color: Ym.grey)),
      );
    }

    final steps = <_JourneyStep>[
      if (stopName != null)
        _JourneyStep(
          color: Ym.green,
          title: 'Boarding stop',
          sub: stopName,
          trailing: _fmt12(_stop?['timing']),
        ),
      _JourneyStep(
        color: _tripLive ? Ym.blue : Ym.grey,
        title: _tripLive
            ? (_busAt != null ? 'Bus is at $_busAt' : 'Bus has started')
            : 'Bus has not started',
        sub: _tripLive
            ? (_busNext != null ? 'Next stop: $_busNext' : null)
            : 'Live tracking begins when the driver starts the trip',
        active: _tripLive,
      ),
      if (endPoint != null)
        _JourneyStep(color: Ym.amberDark, title: 'Drop point', sub: endPoint),
    ];

    return YmCard(
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _timelineRow(steps[i], isLast: i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _timelineRow(_JourneyStep s, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                const SizedBox(height: 3),
                s.active
                    ? YmPulse(color: s.color, size: 9)
                    : Container(
                        width: 15,
                        height: 15,
                        margin: const EdgeInsets.all(5.5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: s.color, width: 3.5),
                        ),
                      ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.5,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: s.color.withOpacity(0.3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            style: Ym.h(14.5,
                                color: s.active ? s.color : Ym.navy)),
                        if (s.sub != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(s.sub!,
                                style: Ym.t(12.5, color: Ym.grey)),
                          ),
                      ],
                    ),
                  ),
                  if (s.trailing != null) YmChip(s.trailing!, color: s.color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── quick actions ──

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

  Widget _buildQuickActions() {
    return YmCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _action(
                  const YmGradientTile(
                      icon: Icons.event_busy_rounded, color: Ym.purple),
                  'Mark Absent',
                  () => showMarkAbsentSheet(context)),
              _action(
                  const YmGradientTile(
                      icon: Iconsax.wallet_3, color: Ym.amberDark),
                  'Payments',
                  () => _push(const PaymentsScreen())),
              _action(
                  const YmGradientTile(
                      icon: Icons.badge_outlined, color: Ym.blue),
                  'Bus Pass',
                  () => _push(const BusPassScreen())),
              _action(
                  const YmGradientTile(icon: Iconsax.bus, color: Ym.green),
                  'Other Buses',
                  () => _push(const OtherBusesScreen())),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _action(
                  const YmGradientTile(
                      icon: Iconsax.location, color: Color(0xFF0EA5E9)),
                  'Geofence Radius',
                  _openGeofenceSettings),
              _action(
                  const YmGradientTile(icon: Iconsax.clock, color: Ym.navy),
                  'History',
                  () => _push(const StudentHistoryScreen())),
              _action(
                  const YmGradientTile(
                      icon: Iconsax.message_text, color: Color(0xFFEA580C)),
                  'Complaints',
                  () => _push(const ComplaintsScreen())),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  /// Round red SOS button, always bottom right above the navigation bar.
  Widget _sosFab() => YmPressable(
        onTap: () => _push(const EmergencySosScreen()),
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Ym.red, Color(0xFFB71C1C)],
            ),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: Ym.shadow(Ym.red, 0.45),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
              Text('SOS', style: Ym.h(11, color: Colors.white)),
            ],
          ),
        ),
      );

  // ── geofence alerts (last 24 h) ──

  Widget _buildAlertsCard() {
    return YmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmIconBadge(
                  icon: Iconsax.notification, color: Ym.red, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Geofence alerts', style: Ym.h(16)),
                    Text('Kept for 24 hours', style: Ym.t(11.5, color: Ym.grey)),
                  ],
                ),
              ),
              YmPressable(
                onTap: _openNotifications,
                child: Text('View all',
                    style: Ym.t(12.5, color: Ym.blue, w: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_recentAlerts.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Ym.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Ym.green, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('All clear. No alerts in the last 24 hours.',
                        style: Ym.t(12.5, color: Ym.green, w: FontWeight.w600)),
                  ),
                ],
              ),
            )
          else
            for (final n in _recentAlerts) _alertTile(n),
          const SizedBox(height: 10),
          YmButton(
            label: 'Set geofence radius',
            icon: Iconsax.location,
            outline: true,
            onPressed: _openGeofenceSettings,
          ),
        ],
      ),
    );
  }

  Widget _alertTile(Map<String, dynamic> n) {
    final msg = n['message']?.toString() ?? '';
    final exited = msg.contains('exited');
    final color = exited ? Ym.blue : Ym.green;
    final at = parseUtc(n['created_at']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(exited ? Icons.logout_rounded : Icons.login_rounded,
              color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Ym.t(12.5, w: FontWeight.w600)),
                if (at != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(fmtClock(at),
                        style: Ym.t(11, color: Ym.grey)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── latest announcement ──

  Widget _buildAnnouncementCard() {
    final a = _latestAnnouncement;
    final at = parseUtc(a?['created_at']);

    return YmCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEAF0FF), Colors.white],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmIconBadge(
                  icon: Icons.campaign_rounded, color: Ym.blue, size: 42),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Latest announcement', style: Ym.h(16))),
              if (at != null)
                Text(fmtDate(at), style: Ym.t(11.5, color: Ym.grey)),
            ],
          ),
          const SizedBox(height: 12),
          if (a == null)
            Text('No announcements yet.',
                style: Ym.t(13, color: Ym.grey))
          else ...[
            Text(a['title']?.toString() ?? '', style: Ym.h(15)),
            const SizedBox(height: 4),
            Text(a['body']?.toString() ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Ym.t(13, color: Ym.grey)),
          ],
        ],
      ),
    );
  }

  // ── floating bottom bar ──

  Widget _buildBottomNav() {
    final items = <(IconData, String)>[
      (Iconsax.home_2, 'Home'),
      (Iconsax.bus, 'Live Bus'),
      (Iconsax.notification, 'Alerts'),
      (Iconsax.clock, 'History'),
    ];

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
            for (int i = 0; i < items.length; i++)
              YmPressable(
                onTap: () {
                  if (i == 1) {
                    _openLiveBus();
                  } else if (i == 2) {
                    _openNotifications();
                  } else if (i == 3) {
                    _push(const StudentHistoryScreen());
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.symmetric(
                      horizontal: _currentTab == i ? 18 : 14, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: _currentTab == i
                        ? const LinearGradient(
                            colors: [Ym.amber, Ym.amberDark])
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(items[i].$1,
                          size: 22,
                          color: _currentTab == i ? Ym.navy : Ym.grey),
                      if (_currentTab == i) ...[
                        const SizedBox(width: 7),
                        Text(items[i].$2,
                            style: Ym.h(13, w: FontWeight.w800)),
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

class _JourneyStep {
  const _JourneyStep({
    required this.color,
    required this.title,
    this.sub,
    this.trailing,
    this.active = false,
  });

  final Color color;
  final String title;
  final String? sub;
  final String? trailing;
  final bool active;
}