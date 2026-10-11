import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iconsax/iconsax.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/eta.dart';
import '../services/student_context.dart' show parseUtc, fmtClock, fmtDate, dateKey;
import '../theme/ym_ui.dart';
import 'role_selection_screen.dart';
import 'change_password_screen.dart';
import 'scan_pass_screen.dart';

/// Driver dashboard.
///
/// Home   : trip control, SOS alerts, who is absent today, extra riders,
///          announcements and notifications for this driver.
/// Track  : live map, stop-by-stop progress, student check-in.
/// Reports: trips done and the driver's own issue reports with their status.
/// Profile: driver, bus and route details.
///
/// Everything is read from the database, so when GPS / RFID hardware is added
/// nothing in this file has to change.
/// What a stop looks like on the driver's map today.
enum _StopState { reached, next, skip, upcoming, empty }

/// Who boards at one stop today.
class _StopRiders {
  const _StopRiders(this.boarding, this.absent, this.faculty);
  final List<Map<String, dynamic>> boarding; // students boarding
  final List<Map<String, dynamic>> absent; // students who marked absent today
  final List<Map<String, dynamic>> faculty; // faculty boarding (always counted)
  int get boardingCount => boarding.length + faculty.length;
}

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final _supabase = Supabase.instance.client;
  DateTime? _lastBackPressTime;
  int _currentIndex = 0;

  bool _isLoading = true;
  Map<String, dynamic>? _driver;
  List<dynamic> _stops = [];
  Map<String, dynamic>? _activeTrip;
  List<Map<String, dynamic>> _tripStops = [];
  List<Map<String, dynamic>> _routeStudents = [];
  Set<String> _checkedInStudentIds = {};
  List<Map<String, dynamic>> _routeFaculty = []; // faculty riding this route
  String? _selectedStopId; // trip_stop tapped on the map (shows the pop-up)
  List<Map<String, dynamic>> _pastTrips = [];
  List<Map<String, dynamic>> _announcements = [];
  int _totalTripsCompleted = 0;

  // information for the driver
  Set<String> _absentTodayIds = {};
  Map<String, String?> _absentReasons = {};
  List<Map<String, dynamic>> _extraRiders = [];
  Map<String, Map<String, dynamic>> _feeByStudent = {};
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _myIssues = [];
  int get _unread => _notifications.where((n) => n['is_read'] == false).length;

  // breakdown rescue
  Map<String, dynamic>? _rescueOffer; // a request waiting for ME to accept / decline
  Map<String, dynamic>? _rescueActive; // a pickup I accepted
  Map<String, dynamic>? _myRescue; // the rescue being arranged for MY broken bus
  Map<String, String> _busNumbers = {};
  List<Map<String, dynamic>> _rescueStops = [];
  List<Map<String, dynamic>> _rescueStudents = [];
  Set<String> _rescueCheckedIn = {};
  dynamic _rescueLat;
  dynamic _rescueLng;

  bool _rescueDialogOpen = false;
  Timer? _feedTimer;

  RealtimeChannel? _channel;
  final MapController _mapController = MapController();
  Timer? _clockTimer;
  String _timeStr = '';
  VideoPlayerController? _video;
  bool _videoReady = false;

  // live location (phone -> `live_locations`, the same table the GPS hardware will use)
  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeat;
  Position? _lastPosition;
  DateTime? _lastSentAt;
  bool _sharingLocation = false;
  String? _locationStatus;
  LatLng? _myPos; // where the bus is (GPS device, or this phone if the bus has no device)

  // GPS hardware: when the bus has a registered device it is the ONLY source of location
  DateTime? _deviceLastFix;
  double? _avgKmh;
  DateTime? _avgAt;
  bool get _hasDevice =>
      ((_driver?['buses'] as Map?)?['gps_device_id'] ?? '').toString().isNotEmpty;

  String get _busNumber =>
      ((_driver?['buses'] as Map?)?['bus_number'] ?? '—').toString();
  String? get _busId => _driver?['bus_id']?.toString();
  String? get _routeId => _driver?['route_id']?.toString();
  String get _routeName =>
      ((_driver?['routes'] as Map?)?['route_name'] ?? 'Unassigned').toString();
  String get _today => dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _updateClock());
    _initVideo();
    _loadEverything();
    // backup for live messages: re-check the feed every 30 seconds
    _feedTimer = Timer.periodic(const Duration(seconds: 30), (_) => _feedTick());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _feedTimer?.cancel();
    _positionSub?.cancel();
    _heartbeat?.cancel();
    if (_channel != null) _supabase.removeChannel(_channel!);
    _video?.dispose();
    super.dispose();
  }

  void _initVideo() {
    final c = VideoPlayerController.asset('assets/images/driver_hero_bus.mp4');
    _video = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      setState(() => _videoReady = true);
    }).catchError((_) {});
  }

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final text =
        '$h:${now.minute.toString().padLeft(2, '0')} ${now.hour < 12 ? 'AM' : 'PM'}';
    if (mounted) {
      setState(() => _timeStr = text);
    } else {
      _timeStr = text;
    }
  }

  // ───────────────────────── DATA ─────────────────────────

  Future<void> _safe(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('Driver "$what" failed: $e');
    }
  }

  Future<void> _loadEverything({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final email = _supabase.auth.currentUser?.email?.toLowerCase();
      if (email == null) return;

      final driverData = await _supabase
          .from('drivers')
          .select(
              '*, buses(bus_number, bus_name, gps_device_id, gps_last_seen), routes(id, route_name, institution_id, stops(id, stop_name, timing, stop_order, lat, lng))')
          .eq('driver_email', email)
          .maybeSingle();

      if (driverData == null) {
        _driver = null;
        return;
      }
      _driver = driverData;

      final route = driverData['routes'];
      final rawStops = (route != null ? route['stops'] as List? : []) ?? [];
      // stop_order first; if two stops share an order, earlier pickup time first
      _stops = List.from(rawStops)
        ..sort((a, b) {
          final byOrder = ((a['stop_order'] ?? 0) as num)
              .compareTo((b['stop_order'] ?? 0) as num);
          if (byOrder != 0) return byOrder;
          return (a['timing'] ?? '').toString().compareTo((b['timing'] ?? '').toString());
        });

      if (route != null) {
        final students = await _supabase
            .from('students')
            .select('id, student_name, boarding_point, student_phone, stop_id')
            .eq('route_id', route['id']);
        _routeStudents = List<Map<String, dynamic>>.from(students);
        try {
          final fac = await _supabase
              .from('faculty')
              .select('id, faculty_name, boarding_point')
              .eq('route_id', route['id']);
          _routeFaculty = List<Map<String, dynamic>>.from(fac);
        } catch (_) {
          _routeFaculty = [];
        }
      } else {
        _routeStudents = [];
        _routeFaculty = [];
      }

      final tripData = await _supabase
          .from('trips')
          .select('*')
          .eq('driver_id', _driver!['id'])
          .eq('status', 'in_progress')
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
      _activeTrip = tripData;

      if (_activeTrip != null) {
        final stopProgress = await _supabase
            .from('trip_stops')
            .select('*, stops(stop_name, timing, lat, lng)')
            .eq('trip_id', _activeTrip!['id'])
            .order('stop_order', ascending: true);
        _tripStops = List<Map<String, dynamic>>.from(stopProgress);

        final checkins = await _supabase
            .from('trip_checkins')
            .select('student_id')
            .eq('trip_id', _activeTrip!['id']);
        _checkedInStudentIds =
            checkins.map<String>((c) => c['student_id'].toString()).toSet();
      } else {
        _tripStops = [];
        _checkedInStudentIds = {};
      }

      final completed = await _supabase
          .from('trips')
          .select('id')
          .eq('driver_id', _driver!['id'])
          .eq('status', 'completed');
      _totalTripsCompleted = (completed as List).length;

      final past = await _supabase
          .from('trips')
          .select('*, routes(route_name)')
          .eq('driver_id', _driver!['id'])
          .eq('status', 'completed')
          .order('started_at', ascending: false)
          .limit(20);
      _pastTrips = List<Map<String, dynamic>>.from(past);

      await _safe('announcements', _loadAnnouncements);
      await _safe('absent today', _loadAbsentToday);
      await _safe('extra riders', _loadExtraRiders);
      await _safe('fees', _loadFees);
      await _safe('notifications', _loadNotifications);
      await _safe('issues', _loadIssues);
      await _safe('rescue', _loadRescue);
    } catch (e) {
      debugPrint('Error loading driver dashboard: $e');
    } finally {
      _ensureRealtime();
      _syncLocationSharing();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Only announcements meant for this driver: everyone, drivers, this route, this bus.
  Future<void> _loadAnnouncements() async {
    final inst = _driver?['institution_id'];
    if (inst == null) return;
    final targets = <String>[
      'all',
      'driver',
      if (_routeId != null) 'route_$_routeId',
      if (_busId != null) 'bus_$_busId',
    ];
    final rows = await _supabase
        .from('announcements')
        .select('*')
        .eq('institution_id', inst)
        .inFilter('target_role', targets)
        .order('created_at', ascending: false)
        .limit(5);
    _announcements = List<Map<String, dynamic>>.from(rows);
  }

  /// Students on this route who marked themselves absent for today.
  Future<void> _loadAbsentToday() async {
    final routeId = _routeId;
    if (routeId == null) {
      _absentTodayIds = {};
      _absentReasons = {};
      return;
    }
    final rows = await _supabase
        .from('attendance_notifications')
        .select('student_id, reason')
        .eq('route_id', routeId)
        .eq('absent_date', _today)
        .eq('status', 'absent');
    _absentTodayIds = rows.map<String>((r) => r['student_id'].toString()).toSet();
    _absentReasons = {
      for (final r in rows) r['student_id'].toString(): r['reason']?.toString(),
    };
  }

  /// Students from other routes who asked to ride this route today
  /// (only requests the student sent to the driver).
  Future<void> _loadExtraRiders() async {
    final routeId = _routeId;
    if (routeId == null) {
      _extraRiders = [];
      return;
    }
    final reqs = await _supabase
        .from('one_day_requests')
        .select('student_id')
        .eq('route_id', routeId)
        .eq('ride_date', _today)
        .neq('status', 'rejected')
        .inFilter('target', ['driver', 'both']);
    final own = _routeStudents.map((s) => s['id'].toString()).toSet();
    final ids = reqs
        .map<String>((r) => r['student_id'].toString())
        .where((id) => !own.contains(id))
        .toSet()
        .toList();
    if (ids.isEmpty) {
      _extraRiders = [];
      return;
    }
    final students = await _supabase
        .from('students')
        .select('id, student_name, boarding_point, student_phone')
        .inFilter('id', ids);
    _extraRiders = List<Map<String, dynamic>>.from(students);
  }

  /// Fee status of everyone who may board (needs step 6; skipped if missing).
  Future<void> _loadFees() async {
    final ids = [
      ..._routeStudents.map((s) => s['id'].toString()),
      ..._extraRiders.map((s) => s['id'].toString()),
    ];
    if (ids.isEmpty) {
      _feeByStudent = {};
      return;
    }
    final rows = await _supabase
        .from('student_fee_status')
        .select('student_id, fee_status, valid_till')
        .inFilter('student_id', ids);
    _feeByStudent = {
      for (final r in rows) r['student_id'].toString(): Map<String, dynamic>.from(r),
    };
  }


  Future<void> _loadNotifications() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    final rows = await _supabase
        .from('notifications')
        .select('id, title, message, type, is_read, created_at')
        .eq('recipient_id', uid)
        .order('created_at', ascending: false)
        .limit(30);
    _notifications = List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _loadIssues() async {
    final id = _driver?['id'];
    if (id == null) return;
    final rows = await _supabase
        .from('driver_issues')
        .select()
        .eq('driver_id', id)
        .order('created_at', ascending: false)
        .limit(10);
    _myIssues = List<Map<String, dynamic>>.from(rows);
  }

  /// Every 30 seconds: refresh what the driver should see, and bring back a
  /// rescue request nobody has answered yet (it never expires).
  Future<void> _feedTick() async {
    if (!mounted || _driver == null || _isLoading) return;
    await _safe('absent today', _loadAbsentToday);
    await _safe('extra riders', () async {
      await _loadExtraRiders();
      await _loadFees();
    });
    await _safe('notifications', _loadNotifications);
    await _safe('rescue', _loadRescue);
    if (!mounted) return;
    setState(() {});
    if (_rescueOffer != null && !_rescueDialogOpen) _presentRescueOffer();
  }

  // live updates ---------------------------------------------------

  void _ensureRealtime() {
    if (_channel != null) return;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || _driver == null) return;
    final busId = _busId;
    final routeId = _routeId;

    void refresh(String what, Future<void> Function() f) {
      _safe(what, f).then((_) {
        if (mounted) setState(() {});
      });
    }

    var ch = _supabase.channel('driver_feed_$uid').onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: uid),
          callback: (p) {
            refresh('notifications', _loadNotifications);
            _showSnack(p.newRecord['title']?.toString() ?? 'New notification',
                isError: false);
          },
        );

    if (busId != null) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'live_locations',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'bus_id', value: busId),
        callback: (p) {
          if (!mounted) return;
          final la = double.tryParse('${p.newRecord['lat']}');
          final lo = double.tryParse('${p.newRecord['lng']}');
          if (la == null || lo == null) return;
          setState(() {
            _myPos = LatLng(la, lo);
            _deviceLastFix = DateTime.now();
          });
          if (_avgAt == null || DateTime.now().difference(_avgAt!).inSeconds > 30) {
            _avgAt = DateTime.now();
            Eta.recentSpeedKmh(_supabase, busId).then((v) {
              if (mounted) setState(() => _avgKmh = v);
            });
          }
        },
      );
    }

    if (routeId != null) {
      ch = ch
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'attendance_notifications',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'route_id',
                value: routeId),
            callback: (_) => refresh('absent today', _loadAbsentToday),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'one_day_requests',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'route_id',
                value: routeId),
            callback: (_) => refresh('extra riders', () async {
              await _loadExtraRiders();
              await _loadFees();
            }),
          );
    }

    // stops reached (by GPS or by hand): colours on the map change at once
    ch = ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'trip_stops',
      callback: (p) {
        final id = (p.newRecord['trip_id'] ?? p.oldRecord['trip_id'])?.toString();
        if (id != null && id == _activeTrip?['id']?.toString()) {
          refresh('trip stops', _reloadTripStops);
        }
      },
    );

    // breakdown rescue: requests for me, and progress of the rescue of my own bus
    final did = _driver?['id']?.toString();
    if (did != null) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rescue_assignments',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'rescue_driver_id',
            value: did),
        callback: (p) {
          if (p.eventType == PostgresChangeEvent.insert &&
              p.newRecord['status'] == 'offered') {
            _showRescueOffer();
          } else {
            refresh('rescue', _loadRescue);
          }
        },
      );
    }
    if (busId != null) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rescue_assignments',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'broken_bus_id',
            value: busId),
        callback: (_) => refresh('rescue', _loadRescue),
      );
    }

    _channel = ch.subscribe();
  }

  // ───────────────────────── TRIP ACTIONS ─────────────────────────

  Future<void> _startTrip() async {
    if (_driver == null || _driver!['route_id'] == null) {
      _showSnack('No route assigned, so a trip cannot be started.');
      return;
    }
    try {
      final newTrip = await _supabase.from('trips').insert({
        'driver_id': _driver!['id'],
        'route_id': _driver!['route_id'],
        'institution_id': _driver!['institution_id'],
        'status': 'in_progress',
      }).select().single();

      final stopRows = _stops.asMap().entries.map((entry) {
        return {
          'trip_id': newTrip['id'],
          'stop_id': entry.value['id'],
          'stop_order': entry.key,
          'status': 'pending',
        };
      }).toList();
      if (stopRows.isNotEmpty) {
        await _supabase.from('trip_stops').insert(stopRows);
      }

      _showSnack(
          _hasDevice
              ? 'Trip started. The bus GPS device will start sending in a few seconds.'
              : 'Trip started',
          isError: false);
      await _loadEverything(silent: true);
      if (mounted) setState(() => _currentIndex = 1);
    } catch (e) {
      _showSnack('Failed to start trip: $e');
    }
  }

  Future<void> _markStopReached(String tripStopId) async {
    try {
      await _supabase.from('trip_stops').update({
        'status': 'reached',
        'reached_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', tripStopId);
      await _loadEverything(silent: true);
    } catch (e) {
      _showSnack('Failed to update stop: $e');
    }
  }

  Future<void> _endTrip() async {
    if (_activeTrip == null) return;
    final ok = await _confirm('End trip?',
        'Mark this trip as completed. This cannot be undone.', 'End trip');
    if (!ok) return;
    try {
      await _supabase.from('trips').update({
        'status': 'completed',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _activeTrip!['id']);
      _showSnack('Trip completed', isError: false);
      await _loadEverything(silent: true);
    } catch (e) {
      _showSnack('Failed to end trip: $e');
    }
  }

  Future<void> _checkInStudent(String studentId, String name) async {
    if (_activeTrip == null) {
      _showSnack('Start a trip first to check in students.');
      return;
    }
    if (_absentTodayIds.contains(studentId)) {
      final ok = await _confirm('Marked absent today',
          '$name told you they would not board today. Check in anyway?', 'Check in');
      if (!ok) return;
    }
    final fee = _feeByStudent[studentId]?['fee_status']?.toString();
    if (fee != null && fee != 'paid') {
      final ok = await _confirm('Bus pass not valid',
          "$name's fee for this academic year is not fully paid. Check in anyway?",
          'Check in');
      if (!ok) return;
    }
    try {
      await _supabase.from('trip_checkins').insert({
        'trip_id': _activeTrip!['id'],
        'student_id': studentId,
      });
      if (mounted) setState(() => _checkedInStudentIds.add(studentId));
    } catch (e) {
      _showSnack('Failed to check in: $e');
    }
  }

  // ───────────────────────── BREAKDOWN RESCUE ─────────────────────────

  String _cleanError(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }

  Future<void> _loadRescue() async {
    final did = _driver?['id'];
    final busId = _busId;
    _rescueOffer = null;
    _rescueActive = null;
    _myRescue = null;

    if (did != null) {
      final rows = await _supabase
          .from('rescue_assignments')
          .select()
          .eq('rescue_driver_id', did)
          .inFilter('status', ['offered', 'accepted'])
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final r = Map<String, dynamic>.from(rows.first);
        if (r['status'] == 'offered') {
          _rescueOffer = r;
        } else {
          _rescueActive = r;
        }
      }
    }

    if (busId != null) {
      final since =
          DateTime.now().toUtc().subtract(const Duration(hours: 12)).toIso8601String();
      final rows = await _supabase
          .from('rescue_assignments')
          .select()
          .eq('broken_bus_id', busId)
          .inFilter('status', ['offered', 'accepted', 'declined', 'no_bus'])
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) _myRescue = Map<String, dynamic>.from(rows.first);
    }

    // bus numbers for the cards
    final ids = <String>{};
    for (final r in [_rescueOffer, _rescueActive, _myRescue]) {
      if (r == null) continue;
      for (final k in ['broken_bus_id', 'rescue_bus_id']) {
        if (r[k] != null) ids.add(r[k].toString());
      }
    }
    if (ids.isNotEmpty) {
      final b = await _supabase
          .from('buses')
          .select('id, bus_number')
          .inFilter('id', ids.toList());
      _busNumbers = {
        for (final x in b) x['id'].toString(): x['bus_number']?.toString() ?? '',
      };
    }

    // what the rescue bus has to pick up
    final cur = _rescueActive ?? _rescueOffer;
    _rescueStops = [];
    _rescueStudents = [];
    _rescueCheckedIn = {};
    _rescueLat = null;
    _rescueLng = null;
    if (cur != null && cur['broken_trip_id'] != null) {
      final tripId = cur['broken_trip_id'];
      final stops = await _supabase
          .from('trip_stops')
          .select('id, stop_order, status, stops(stop_name, timing, lat, lng)')
          .eq('trip_id', tripId)
          .eq('status', 'pending')
          .order('stop_order', ascending: true);
      _rescueStops = List<Map<String, dynamic>>.from(stops);

      final trip = await _supabase
          .from('trips')
          .select('route_id')
          .eq('id', tripId)
          .maybeSingle();
      if (trip?['route_id'] != null) {
        final st = await _supabase
            .from('students')
            .select('id, student_name, boarding_point, student_phone')
            .eq('route_id', trip!['route_id']);
        _rescueStudents = List<Map<String, dynamic>>.from(st);
      }
      final ck = await _supabase
          .from('trip_checkins')
          .select('student_id')
          .eq('trip_id', tripId);
      _rescueCheckedIn = ck.map<String>((c) => c['student_id'].toString()).toSet();

      if (cur['issue_id'] != null) {
        final iss = await _supabase
            .from('driver_issues')
            .select('lat, lng')
            .eq('id', cur['issue_id'])
            .maybeSingle();
        _rescueLat = iss?['lat'];
        _rescueLng = iss?['lng'];
      }
    }
  }

  Future<void> _respondRescue(String id, bool accept) async {
    try {
      await _supabase.rpc('respond_rescue', params: {'p_id': id, 'p_accept': accept});
      await _loadEverything(silent: true);
      _showSnack(
          accept
              ? 'Rescue accepted. Head to the pickup.'
              : 'Declined. The next nearest bus will be asked.',
          isError: false);
      if (accept && mounted) setState(() => _currentIndex = 1);
    } catch (e) {
      _showSnack(_cleanError(e));
      await _safe('rescue', _loadRescue);
      if (mounted) setState(() {});
    }
  }

  Future<void> _completeRescue(String id) async {
    final ok = await _confirm('Finish the rescue?',
        'Tell everyone the pickup is done.', 'Finish rescue');
    if (!ok) return;
    try {
      await _supabase.rpc('complete_rescue', params: {'p_id': id});
      await _loadEverything(silent: true);
      _showSnack('Rescue completed. Thank you.', isError: false);
    } catch (e) {
      _showSnack(_cleanError(e));
    }
  }

  Future<void> _checkInRescueStudent(String studentId) async {
    final tripId = _rescueActive?['broken_trip_id'];
    if (tripId == null) return;
    try {
      await _supabase
          .from('trip_checkins')
          .insert({'trip_id': tripId, 'student_id': studentId});
      if (mounted) setState(() => _rescueCheckedIn.add(studentId));
    } catch (e) {
      _showSnack('Failed to check in: $e');
    }
  }

  /// Pop-up the moment a rescue request arrives.
  Future<void> _showRescueOffer() async {
    await _safe('rescue', _loadRescue);
    if (!mounted) return;
    setState(() {});
    if (_rescueOffer != null && !_rescueDialogOpen) _presentRescueOffer();
  }

  void _presentRescueOffer() {
    final o = _rescueOffer;
    if (o == null || !mounted) return;
    _rescueDialogOpen = true;
    final broken = _busNumbers[o['broken_bus_id']?.toString()] ?? 'a bus';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const YmGradientTile(
                  icon: Icons.support_rounded, color: Ym.red, size: 68),
              const SizedBox(height: 16),
              Text('Rescue request', style: Ym.h(21, color: Ym.red)),
              const SizedBox(height: 8),
              Text(
                'Bus $broken broke down about ${o['distance_km'] ?? '?'} km from you.\n'
                '${_rescueStops.length} stops and '
                '${_rescueStudents.where((s) => !_rescueCheckedIn.contains(s['id'].toString())).length} students are waiting.',
                textAlign: TextAlign.center,
                style: Ym.t(13.5, color: Ym.grey),
              ),
              const SizedBox(height: 20),
              YmButton(
                label: 'Accept the pickup',
                icon: Icons.check_rounded,
                color: Ym.green,
                onPressed: () {
                  Navigator.pop(ctx);
                  _respondRescue(o['id'].toString(), true);
                },
              ),
              const SizedBox(height: 10),
              YmButton(
                label: 'Decline',
                outline: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _respondRescue(o['id'].toString(), false);
                },
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _rescueDialogOpen = false);
  }

  // ───────────────────────── OTHER ACTIONS ─────────────────────────

  Future<void> _reportIssue() async {
    final text = TextEditingController();
    var type = 'breakdown';
    var saving = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  decoration: BoxDecoration(
                      color: Ym.line, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const YmIconBadge(
                      icon: Icons.warning_amber_rounded, color: Ym.red, size: 44),
                  const SizedBox(width: 12),
                  Text('Report an issue', style: Ym.h(19)),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in ['breakdown', 'delay', 'accident', 'other'])
                    ChoiceChip(
                      label: Text(t[0].toUpperCase() + t.substring(1)),
                      selected: type == t,
                      selectedColor: Ym.amber.withOpacity(0.3),
                      onSelected: (_) => setSheet(() => type = t),
                    ),
                ],
              ),
              if (type == 'breakdown')
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Ym.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Ym.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your bus location will be shared. The nearest running bus will be asked to take over your remaining stops, and the admin and your students will be told.',
                          style: Ym.t(12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: text,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe the issue…',
                  filled: true,
                  fillColor: const Color(0xFFF8F9FB),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: Ym.t(12.5, color: Ym.red)),
                ),
              const SizedBox(height: 14),
              YmButton(
                label: 'Send to admin',
                icon: Icons.send_rounded,
                loading: saving,
                onPressed: () async {
                  if (text.text.trim().isEmpty) {
                    setSheet(() => error = 'Please describe the issue.');
                    return;
                  }
                  setSheet(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    await _supabase.from('driver_issues').insert({
                      'driver_id': _driver!['id'],
                      'institution_id': _driver!['institution_id'],
                      'type': type,
                      'description': text.text.trim(),
                      'bus_id': _busId,
                      'trip_id': _activeTrip?['id'],
                      'lat': _myPos?.latitude,
                      'lng': _myPos?.longitude,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showSnack(
                        type == 'breakdown'
                            ? 'Breakdown reported. The nearest bus is being asked to help.'
                            : 'Issue sent to admin.',
                        isError: false);
                    await _safe('issues', _loadIssues);
                    await _safe('rescue', _loadRescue);
                    if (mounted) setState(() {});
                  } catch (e) {
                    setSheet(() {
                      error = 'Could not send: $e';
                      saving = false;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    text.dispose();
  }

  Future<void> _callNumber(String? phone) async {
    if (phone == null || phone.isEmpty) {
      _showSnack('No phone number available.');
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _openMap(dynamic lat, dynamic lng) async {
    final la = double.tryParse('$lat');
    final lo = double.tryParse('$lng');
    if (la == null || lo == null) {
      _showSnack('No location was shared with this alert.');
      return;
    }
    await launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$la,$lo'),
        mode: LaunchMode.externalApplication);
  }

  // ───────────────────────── DRIVER SOS ─────────────────────────

  /// Round red SOS button, always in the same place (bottom right, above the
  /// navigation bar) on every driver tab.
  Widget _sosFab() => YmPressable(
        onTap: _openSos,
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

  /// Saves the driver's emergency with the bus position. `type` is one of the
  /// `emergency_type` values: accident, breakdown, health, security, traffic, other.
  Future<bool> _raiseSos(String type, String description) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;

    double? lat = _myPos?.latitude;
    double? lng = _myPos?.longitude;
    if (lat == null || lng == null) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 6)),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        // no position: the alert is still sent
      }
    }

    try {
      await _supabase.from('emergencies').insert({
        'bus_id': _busId,
        'trip_id': _activeTrip?['id'],
        'raised_by': uid,
        'type': type,
        'description': description,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
      return true;
    } catch (e) {
      _showSnack('Could not send the alert: $e');
      return false;
    }
  }

  Future<void> _openSos() async {
    var sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> send(String type, String description, String label) async {
            final ok = await showDialog<bool>(
              context: ctx,
              builder: (d) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Text('Send emergency alert?', style: Ym.h(18, color: Ym.red)),
                content: Text(
                    '$label\nThe admin will be alerted at once with your bus location.',
                    style: Ym.t(13.5)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: Text('Send alert',
                          style: Ym.t(14, color: Ym.red, w: FontWeight.w800))),
                ],
              ),
            );
            if (ok != true) return;
            setSheet(() => sending = true);
            final sent = await _raiseSos(type, description);
            if (!mounted) return;
            if (sent) {
              if (ctx.mounted) Navigator.pop(ctx);
              _showSnack('Alert sent. The admin has been told. Stay safe.',
                  isError: false);
            } else {
              setSheet(() => sending = false);
            }
          }

          Widget tile(IconData icon, String title, String sub, Color color,
                  VoidCallback onTap) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: YmCard(
                  onTap: sending ? null : onTap,
                  padding: const EdgeInsets.all(14),
                  radius: 20,
                  child: Row(
                    children: [
                      YmIconBadge(icon: icon, color: color, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: Ym.h(14.5)),
                            Text(sub, style: Ym.t(11.5, color: Ym.grey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Ym.grey),
                    ],
                  ),
                ),
              );

          return Container(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4.5,
                      decoration: BoxDecoration(
                          color: Ym.line, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Emergency', style: Ym.h(22, color: Ym.red)),
                  const SizedBox(height: 3),
                  Text('Alerts your admin with your bus location.',
                      style: Ym.t(12.5, color: Ym.grey)),
                  const SizedBox(height: 18),
                  Center(
                    child: YmPressable(
                      onTap: sending
                          ? null
                          : () => send('other', 'Driver pressed SOS',
                              'This sends an SOS.'),
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Ym.red, Color(0xFFB71C1C)],
                          ),
                          boxShadow: Ym.shadow(Ym.red, 0.45),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.6), width: 5),
                        ),
                        child: Center(
                          child: sending
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.warning_rounded,
                                        color: Colors.white, size: 40),
                                    const SizedBox(height: 4),
                                    Text('SOS',
                                        style: Ym.h(30, color: Colors.white)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text('Tap, then confirm',
                        style: Ym.t(12, color: Ym.grey)),
                  ),
                  const SizedBox(height: 20),
                  Text('What happened?', style: Ym.h(15)),
                  const SizedBox(height: 10),
                  tile(Icons.car_crash_rounded, 'Accident', 'The bus has been in an accident', Ym.red,
                      () => send('accident', 'Accident involving the bus', 'Accident.')),
                  tile(Icons.medical_services_rounded, 'Medical emergency',
                      'Someone on the bus needs medical help', Ym.red,
                      () => send('health', 'Medical emergency on the bus', 'Medical emergency.')),
                  tile(Icons.shield_outlined, 'Security threat', 'I or the passengers are in danger',
                      Ym.purple,
                      () => send('security', 'Security threat on the bus', 'Security threat.')),
                  tile(Icons.more_horiz_rounded, 'Something else', 'Another emergency',
                      Ym.amberDark,
                      () => send('other', 'Driver reported an emergency', 'Emergency.')),
                  const SizedBox(height: 6),
                  Text('Call for help', style: Ym.h(15)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: YmButton(
                          label: 'Ambulance 108',
                          icon: Icons.call_rounded,
                          color: Ym.red,
                          onPressed: () => _callNumber('108'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: YmButton(
                          label: 'Police 100',
                          icon: Icons.call_rounded,
                          outline: true,
                          onPressed: () => _callNumber('100'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openNotifications() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid != null) {
      _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_id', uid)
          .eq('is_read', false)
          .then((_) {})
          .catchError((_) {});
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                    color: Ym.line, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Notifications', style: Ym.h(20)),
            const SizedBox(height: 12),
            Flexible(
              child: _notifications.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: YmEmpty(
                          icon: Iconsax.notification,
                          title: 'Nothing new',
                          subtitle: 'Absences, extra riders and alerts appear here.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final n = _notifications[i];
                        final isSos = n['type'] == 'emergency';
                        final c = isSos ? Ym.red : Ym.blue;
                        final at = parseUtc(n['created_at']);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(16),
                            border: Border(left: BorderSide(color: c, width: 4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n['title']?.toString() ?? '', style: Ym.h(14)),
                              const SizedBox(height: 3),
                              Text(n['message']?.toString() ?? '',
                                  style: Ym.t(12.5, color: Ym.grey)),
                              if (at != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('${fmtDate(at)}  •  ${fmtClock(at)}',
                                      style: Ym.t(11, color: Ym.grey)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    await _safe('notifications', _loadNotifications);
    if (mounted) setState(() {});
  }

  Future<void> _callEmergencyContact() async {
    final uri = Uri(scheme: 'tel', path: '112');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _logout() async {
    final ok = await _confirm('Log out?', 'Are you sure you want to log out?', 'Log out');
    if (!ok) return;
    try {
      _stopLocationSharing();
    } catch (_) {
      // never let this block the log out
    }
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }

  void _showSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        backgroundColor: isError ? Ym.red : Ym.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title, style: Ym.h(18)),
        content: Text(body, style: Ym.t(13.5, color: Ym.grey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Ym.amber,
              foregroundColor: Ym.navy,
              elevation: 0,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return r == true;
  }

  // ───────────────────────── LIVE LOCATION ─────────────────────────
  // While a trip is in progress the phone sends the bus position to
  // `live_locations`. Students read that table (Live Bus + geofence alerts).
  // On Android a foreground notification keeps it running with the screen off.

  void _syncLocationSharing() {
    if (_activeTrip != null && _driver != null) {
      _startLocationSharing();
    } else {
      _stopLocationSharing();
    }
  }

  LocationSettings _locationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 10);
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Yatra Mitra: trip in progress',
            notificationText: 'Sharing the bus location with students',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 10);
    }
  }

  /// Last position the GPS device reported for this bus.
  Future<void> _loadDeviceFix() async {
    final busId = _busId;
    if (busId == null) return;
    final rows = await _supabase
        .from('live_locations')
        .select('lat, lng, timestamp')
        .eq('bus_id', busId)
        .eq('source', 'device')
        .order('timestamp', ascending: false)
        .limit(1);
    if (rows.isEmpty) return;
    final la = double.tryParse('${rows.first['lat']}');
    final lo = double.tryParse('${rows.first['lng']}');
    if (la == null || lo == null) return;
    _myPos = LatLng(la, lo);
    _deviceLastFix = parseUtc(rows.first['timestamp']);
    _avgKmh = await Eta.recentSpeedKmh(_supabase, busId);
  }

  Future<void> _startLocationSharing() async {
    if (_hasDevice) {
      // The GPS device on the bus is the only source of location. Pressing
      // "Start trip" is what tells it (through `device-ingest`) to start sending.
      await _safe('device fix', _loadDeviceFix);
      if (mounted) {
        setState(() {
          _sharingLocation = false;
          _locationStatus = null;
        });
      }
      return;
    }
    if (_positionSub != null) return;
    if (_busId == null) {
      if (mounted) {
        setState(() => _locationStatus =
            'No bus is linked to your account, so the location is not being shared.');
      }
      return;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() =>
              _locationStatus = 'Turn on location (GPS) to share the bus position.');
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _locationStatus =
              'Location permission is off. Allow it to share the bus position.');
        }
        return;
      }

      _positionSub = Geolocator.getPositionStream(locationSettings: _locationSettings())
          .listen(_onPosition,
              onError: (e) => debugPrint('Location stream error: $e'));

      // keeps the bus "fresh" for students while it stands still
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        final p = _lastPosition;
        if (p != null) _sendPosition(p);
      });

      if (mounted) {
        setState(() {
          _sharingLocation = true;
          _locationStatus = null;
        });
      }
    } catch (e) {
      debugPrint('Could not start location sharing: $e');
      if (mounted) {
        setState(() => _locationStatus = 'Could not start location sharing.');
      }
    }
  }

  void _onPosition(Position p) {
    _lastPosition = p;
    if (mounted) setState(() => _myPos = LatLng(p.latitude, p.longitude));
    _sendPosition(p);
  }

  Future<void> _sendPosition(Position p) async {
    final busId = _busId;
    if (busId == null) return;
    final now = DateTime.now();
    if (_lastSentAt != null &&
        now.difference(_lastSentAt!) < const Duration(seconds: 4)) {
      return;
    }
    _lastSentAt = now;
    try {
      await _supabase.from('live_locations').insert({
        'bus_id': busId,
        'trip_id': _activeTrip?['id'],
        'lat': p.latitude,
        'lng': p.longitude,
        'source': 'phone',
        'speed': (p.speed.isNaN || p.speed < 0) ? 0 : p.speed,
        'heading': (p.heading.isNaN || p.heading < 0) ? 0 : p.heading,
      });
    } catch (e) {
      debugPrint('Location send failed: $e');
    }
  }

  void _stopLocationSharing() {
    _positionSub?.cancel();
    _positionSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _lastPosition = null;
    _lastSentAt = null;
    _deviceLastFix = null;
    if (_sharingLocation || _myPos != null || _locationStatus != null) {
      if (mounted) {
        setState(() {
          _sharingLocation = false;
          _myPos = null;
          _locationStatus = null;
        });
      }
    }
  }

  // ───────────────────────── STOPS ON THE MAP ─────────────────────────

  Future<void> _reloadTripStops() async {
    final t = _activeTrip;
    if (t == null) return;
    final rows = await _supabase
        .from('trip_stops')
        .select('*, stops(stop_name, timing, lat, lng)')
        .eq('trip_id', t['id'])
        .order('stop_order', ascending: true);
    _tripStops = List<Map<String, dynamic>>.from(rows);
  }

  /// Who boards at a stop today: students (minus the ones who marked absent)
  /// and faculty. A student is placed by `stop_id`, or by boarding point name.
  _StopRiders _ridersAt(Map<String, dynamic> ts) {
    final stopId = ts['stop_id']?.toString();
    final name =
        ((ts['stops'] as Map?)?['stop_name'] ?? '').toString().trim().toLowerCase();

    bool here(Map<String, dynamic> p) {
      final sid = p['stop_id']?.toString();
      if (sid != null && sid.isNotEmpty) return sid == stopId;
      final bp = (p['boarding_point'] ?? '').toString().trim().toLowerCase();
      return bp.isNotEmpty && bp == name;
    }

    final students = _routeStudents.where(here).toList();
    final absent = students
        .where((s) => _absentTodayIds.contains(s['id'].toString()))
        .toList();
    final boarding = students
        .where((s) => !_absentTodayIds.contains(s['id'].toString()))
        .toList();
    final faculty = name.isEmpty
        ? <Map<String, dynamic>>[]
        : _routeFaculty
            .where((f) =>
                (f['boarding_point'] ?? '').toString().trim().toLowerCase() == name)
            .toList();
    return _StopRiders(boarding, absent, faculty);
  }

  _StopState _stopState(int idx, int nextIdx) {
    final ts = _tripStops[idx];
    if (ts['status'] == 'reached') return _StopState.reached;
    final r = _ridersAt(ts);
    // everyone registered at this stop is absent today
    if (r.boardingCount == 0 && r.absent.isNotEmpty) return _StopState.skip;
    if (idx == nextIdx) return _StopState.next;
    if (r.boardingCount == 0 && r.absent.isEmpty) return _StopState.empty;
    return _StopState.upcoming;
  }

  Color _stopColor(_StopState st) => switch (st) {
        _StopState.reached => Ym.green,
        _StopState.next => Ym.blue,
        _StopState.skip => Ym.purple,
        _StopState.upcoming => Ym.amber,
        _StopState.empty => Ym.grey,
      };

  EtaResult? _etaFor(int index, int nextIdx) {
    if (_myPos == null ||
        nextIdx < 0 ||
        _tripStops[index]['status'] == 'reached') {
      return null;
    }
    final stopMaps = [
      for (final t in _tripStops)
        Map<String, dynamic>.from((t['stops'] ?? <String, dynamic>{}) as Map),
    ];
    return Eta.estimate(
        bus: _myPos!,
        stops: stopMaps,
        nextIndex: nextIdx,
        targetIndex: index,
        avgKmh: _avgKmh);
  }

  /// Green for the part already driven, blue for what is left.
  List<Polyline> _routeLines() {
    final pts = <(int, LatLng)>[];
    var lastReached = -1;
    for (var i = 0; i < _tripStops.length; i++) {
      if (_tripStops[i]['status'] == 'reached') lastReached = i;
      final s = _tripStops[i]['stops'];
      final lat = (s?['lat'] as num?)?.toDouble();
      final lng = (s?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) pts.add((i, LatLng(lat, lng)));
    }
    final done = [for (final p in pts) if (p.$1 <= lastReached) p.$2];
    final rest = [for (final p in pts) if (p.$1 > lastReached) p.$2];
    final lines = <Polyline>[];
    if (done.length > 1) {
      lines.add(Polyline(
        points: done,
        color: Ym.green,
        strokeWidth: 5,
        borderColor: Colors.white,
        borderStrokeWidth: 2,
      ));
    }
    final remaining = [if (done.isNotEmpty) done.last, ...rest];
    if (remaining.length > 1) {
      lines.add(Polyline(
        points: remaining,
        color: Ym.blue.withOpacity(0.7),
        strokeWidth: 5,
        borderColor: Colors.white,
        borderStrokeWidth: 2,
      ));
    }
    return lines;
  }

  Marker _stopMarker(int idx, int nextIdx) {
    final ts = _tripStops[idx];
    final stop = ts['stops'];
    final lat = (stop?['lat'] as num).toDouble();
    final lng = (stop?['lng'] as num).toDouble();
    final st = _stopState(idx, nextIdx);
    final color = _stopColor(st);
    final riders = _ridersAt(ts);
    final selected = _selectedStopId == ts['id'].toString();
    final big = st == _StopState.next || selected;
    final size = big ? 46.0 : 38.0;
    final name = (stop?['stop_name'] ?? '').toString();
    final showLabel = st == _StopState.next || selected;
    final showBadge = st != _StopState.reached &&
        (st == _StopState.skip || riders.boardingCount > 0);

    return Marker(
      point: LatLng(lat, lng),
      width: 150,
      height: 100,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(
            () => _selectedStopId = selected ? null : ts['id'].toString()),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (showLabel)
              Positioned(
                top: 2,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 148),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: Ym.shadow(color, 0.3),
                  ),
                  child: Text(
                    st == _StopState.skip ? '$name • skip' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ym.t(11,
                        color: st == _StopState.skip ? Ym.purple : Ym.navy,
                        w: FontWeight.w800),
                  ),
                ),
              ),
            SizedBox(
              width: size + 16,
              height: size + 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)
                        ],
                      ),
                      child: Center(
                        child: switch (st) {
                          _StopState.reached => const Icon(Icons.check_rounded,
                              color: Colors.white, size: 20),
                          _StopState.skip => const Icon(Icons.fast_forward_rounded,
                              color: Colors.white, size: 21),
                          _ => Text('${idx + 1}',
                              style: Ym.t(13, color: Colors.white, w: FontWeight.w800)),
                        },
                      ),
                    ),
                  ),
                  if (showBadge)
                    Positioned(
                      top: 0,
                      right: 0,
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
                        child: Text('${riders.boardingCount}',
                            style: Ym.t(10.5, color: Colors.white, w: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Strip at the top of the map: what to do at the next stop.
  Widget _mapBanner(int nextIdx) {
    if (nextIdx < 0) {
      return _bannerBox(Ym.green, Icons.flag_rounded, 'All stops completed',
          'You can end the trip.', true);
    }
    final ts = _tripStops[nextIdx];
    final name = (ts['stops']?['stop_name'] ?? '').toString();
    final r = _ridersAt(ts);
    final st = _stopState(nextIdx, nextIdx);

    if (st == _StopState.skip) {
      // find the stop after it that is not a skip
      String? then;
      for (var i = nextIdx + 1; i < _tripStops.length; i++) {
        if (_stopState(i, nextIdx) != _StopState.skip) {
          then = (_tripStops[i]['stops']?['stop_name'] ?? '').toString();
          break;
        }
      }
      return _bannerBox(
        Ym.purple,
        Icons.fast_forward_rounded,
        'Skip $name',
        then == null
            ? 'Nobody is boarding here today.'
            : 'Nobody is boarding here today. Go on to $then.',
        true,
      );
    }
    final absentText = r.absent.isEmpty ? '' : '  •  ${r.absent.length} absent';
    return _bannerBox(
      Ym.blue,
      Icons.near_me_rounded,
      'Next: $name',
      r.boardingCount == 0 && r.absent.isEmpty
          ? 'No registered riders at this stop'
          : '${r.boardingCount} boarding$absentText',
      false,
    );
  }

  Widget _bannerBox(Color color, IconData icon, String title, String sub, bool solid) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: solid ? color : Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: Ym.shadow(color, 0.25),
        ),
        child: Row(
          children: [
            Icon(icon, color: solid ? Colors.white : color, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ym.h(13,
                          color: solid ? Colors.white : Ym.navy)),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Ym.t(11.5,
                          color: solid ? Colors.white.withOpacity(0.92) : Ym.grey)),
                ],
              ),
            ),
          ],
        ),
      );

  /// Pop-up on the map for the tapped stop.
  Widget _stopPopup(int nextIdx) {
    final idx = _tripStops.indexWhere((t) => t['id'].toString() == _selectedStopId);
    if (idx < 0) return const SizedBox.shrink();
    final ts = _tripStops[idx];
    final stop = ts['stops'];
    final name = (stop?['stop_name'] ?? '').toString();
    final st = _stopState(idx, nextIdx);
    final color = _stopColor(st);
    final r = _ridersAt(ts);
    final time = _hhmm(stop?['timing']);
    final eta = _etaFor(idx, nextIdx);
    final reachedAt = parseUtc(ts['reached_at']);

    final label = switch (st) {
      _StopState.reached => 'Reached${reachedAt != null ? ' at ${fmtClock(reachedAt)}' : ''}',
      _StopState.next => 'Next stop',
      _StopState.skip => 'Skip: nobody boarding',
      _StopState.upcoming => 'Upcoming',
      _StopState.empty => 'No registered riders',
    };

    Widget names(List<Map<String, dynamic>> list, Color c, IconData icon) {
      final shown = list.take(6).toList();
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in shown)
            YmChip((p['student_name'] ?? p['faculty_name'] ?? '').toString(),
                color: c, icon: icon),
          if (list.length > shown.length)
            YmChip('+${list.length - shown.length} more', color: Ym.grey),
        ],
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: Ym.shadow(Ym.navy, 0.22),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    st == _StopState.reached
                        ? Icons.check_rounded
                        : (st == _StopState.skip
                            ? Icons.fast_forward_rounded
                            : Icons.location_on_rounded),
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${idx + 1}. $name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ym.h(15)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          YmChip(label, color: color),
                          if (time.isNotEmpty)
                            YmChip(time, color: Ym.navy, icon: Icons.access_time_rounded),
                          if (eta != null)
                            YmChip('ETA ${eta.label}',
                                color: Ym.blue, icon: Icons.timelapse_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, color: Ym.grey),
                  onPressed: () => setState(() => _selectedStopId = null),
                ),
              ],
            ),
            if (st == _StopState.skip)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10, right: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Ym.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                    'Everyone at this stop is absent today. You can skip it.',
                    style: Ym.t(12.5, color: Ym.purple, w: FontWeight.w700)),
              ),
            if (r.boardingCount > 0 || r.absent.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${r.boardingCount} boarding  •  ${r.absent.length} absent',
                style: Ym.t(12.5, w: FontWeight.w700),
              ),
            ],
            if (r.boarding.isNotEmpty || r.faculty.isNotEmpty) ...[
              const SizedBox(height: 8),
              names([...r.boarding, ...r.faculty], Ym.green, Icons.person_rounded),
            ],
            if (r.absent.isNotEmpty) ...[
              const SizedBox(height: 8),
              names(r.absent, Ym.purple, Icons.event_busy_rounded),
            ],
            if (st != _StopState.reached) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: YmButton(
                  label: st == _StopState.skip ? 'Skip this stop' : 'Mark reached',
                  icon: st == _StopState.skip
                      ? Icons.fast_forward_rounded
                      : Icons.check_rounded,
                  color: st == _StopState.skip ? Ym.purple : Ym.green,
                  onPressed: () async {
                    await _markStopReached(ts['id']);
                    if (mounted) setState(() => _selectedStopId = null);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ───────────────────────── MAP HELPERS ─────────────────────────

  List<LatLng> _getStopLatLngs() {
    final points = <LatLng>[];
    for (final ts in _tripStops) {
      final stop = ts['stops'];
      final lat = (stop?['lat'] as num?)?.toDouble();
      final lng = (stop?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) points.add(LatLng(lat, lng));
    }
    return points;
  }

  LatLng _mapCenter() {
    final points = _getStopLatLngs();
    if (points.isEmpty) return const LatLng(12.9716, 77.5946);
    double lat = 0, lng = 0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  int _nextStopIndex() {
    for (int i = 0; i < _tripStops.length; i++) {
      if (_tripStops[i]['status'] != 'reached') return i;
    }
    return -1;
  }

  String _hhmm(dynamic raw) {
    final s = raw?.toString() ?? '';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  // ───────────────────────── BUILD ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Ym.creamTop,
        extendBody: true,
        body: YmBackground(
          child: _isLoading
              ? SafeArea(child: _skeleton())
              : _driver == null
                  ? SafeArea(child: _noDriver())
                  : IndexedStack(
                      index: _currentIndex,
                      children: [
                        _buildHomeTab(),
                        _buildTrackTab(),
                        _buildReportsTab(),
                        _buildProfileTab(),
                      ],
                    ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        // hidden only while a stop pop-up is open on the map, so it never covers its buttons
        floatingActionButton: (_isLoading ||
                _driver == null ||
                (_currentIndex == 1 && _selectedStopId != null))
            ? null
            : _sosFab(),
        bottomNavigationBar:
            (_isLoading || _driver == null) ? null : _buildBottomNav(),
      ),
    );
  }

  Widget _skeleton() => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        children: const [
          YmSkeleton(height: 46, radius: 23),
          SizedBox(height: 22),
          YmSkeleton(height: 64),
          SizedBox(height: 18),
          YmSkeleton(height: 300, radius: 30),
          SizedBox(height: 16),
          YmSkeleton(height: 90),
          SizedBox(height: 22),
          YmSkeleton(height: 180),
        ],
      );

  Widget _noDriver() => YmEmpty(
        icon: Icons.directions_bus_outlined,
        title: 'Driver profile not found',
        subtitle: 'Contact your admin to set up your driver account.',
        action: YmButton(
            label: 'Log out',
            icon: Icons.logout_rounded,
            expanded: false,
            color: Ym.red,
            onPressed: _logout),
      );

  // ───────────────────────── SMALL PIECES ─────────────────────────

  Widget _topBar() {
    return Row(
      children: [
        YmPressable(
          onTap: () => setState(() => _currentIndex = 3),
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
              child: Text(
                  (_driver?['driver_name'] ?? '?').toString().trim().isEmpty
                      ? '?'
                      : (_driver!['driver_name'] as String).trim()[0].toUpperCase(),
                  style: Ym.h(18, color: Ym.amberDark)),
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
              Text((_driver?['driver_name'] ?? 'Driver').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ym.t(11.5, color: Ym.grey, w: FontWeight.w600)),
            ],
          ),
        ),
        YmRoundButton(
            icon: Iconsax.notification, badge: _unread, onTap: _openNotifications),
        const SizedBox(width: 10),
        YmRoundButton(icon: Iconsax.logout, color: Ym.red, onTap: _logout),
      ],
    );
  }

  Widget _pill(String text, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Ym.amber.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: Ym.amberDark),
              const SizedBox(width: 5),
            ],
            Text(text, style: Ym.t(12, w: FontWeight.w700)),
          ],
        ),
      );

  Widget _miniBtn(String label, IconData icon, Color color, VoidCallback onTap) =>
      YmPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(label, style: Ym.t(12, color: color, w: FontWeight.w800)),
            ],
          ),
        ),
      );

  // ───────────────────────── HOME TAB ─────────────────────────

  Widget _buildHomeTab() {
    final h = DateTime.now().hour;
    final greeting =
        h < 12 ? 'Good morning,' : (h < 17 ? 'Good afternoon,' : 'Good evening,');
    final name = (_driver!['driver_name'] ?? 'Driver').toString();
    final first = name.trim().split(' ').first;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Ym.amber,
        onRefresh: () => _loadEverything(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
          children: [
            YmFadeSlide(index: 0, child: _topBar()),
            const SizedBox(height: 22),
            YmFadeSlide(
              index: 1,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greeting, style: Ym.t(15, color: Ym.grey)),
                        const SizedBox(height: 3),
                        Text(first, style: Ym.h(30)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            YmFadeSlide(index: 2, child: _heroCard()),
            const SizedBox(height: 16),
            YmFadeSlide(index: 3, child: _statsRow()),
            if (_rescueOffer != null || _rescueActive != null || _myRescue != null) ...[
              const SizedBox(height: 26),
              YmFadeSlide(index: 4, child: _rescueSection()),
            ],
            const SizedBox(height: 26),
            YmFadeSlide(
              index: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const YmSectionTitle('Quick Actions'),
                  _quickActions(),
                ],
              ),
            ),
            const SizedBox(height: 26),
            YmFadeSlide(index: 6, child: _todaySection()),
            const SizedBox(height: 26),
            YmFadeSlide(index: 7, child: _announcementsSection()),
          ],
        ),
      ),
    );
  }

  Widget _heroCard() {
    final onTrip = _activeTrip != null;
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
            bottom: 60,
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
                          Text(_routeName, style: Ym.h(22)),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(Iconsax.bus,
                                  size: 15, color: Ym.amberDark),
                              const SizedBox(width: 5),
                              Text('Bus $_busNumber',
                                  style: Ym.t(13,
                                      color: Ym.grey, w: FontWeight.w600)),
                            ],
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
                          YmPulse(color: onTrip ? Ym.green : Ym.grey, size: 7),
                          Text(onTrip ? 'On trip' : 'Off duty',
                              style: Ym.t(11.5,
                                  color: onTrip ? Ym.green : Ym.navy,
                                  w: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill('${_stops.length} stops', icon: Iconsax.location),
                    _pill('${_routeStudents.length} students',
                        icon: Icons.groups_rounded),
                    _pill(_timeStr, icon: Iconsax.clock),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_videoReady && _video != null)
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _video!.value.size.width,
                              height: _video!.value.size.height,
                              child: VideoPlayer(_video!),
                            ),
                          )
                        else
                          const _DriveScene(),
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
                          child: Text('Drive safe. Reach every student safely.',
                              style: Ym.h(13,
                                  color: Colors.white, w: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                YmButton(
                  label: onTrip ? 'View trip' : 'Start trip',
                  icon: onTrip ? Iconsax.map_1 : Icons.play_arrow_rounded,
                  color: onTrip ? null : Ym.green,
                  onPressed: onTrip
                      ? () => setState(() => _currentIndex = 1)
                      : _startTrip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    Widget stat(IconData icon, Color color, String value, String label) =>
        Expanded(
          child: YmCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            radius: 22,
            child: Column(
              children: [
                YmIconBadge(icon: icon, color: color, size: 40),
                const SizedBox(height: 10),
                Text(value, style: Ym.h(22)),
                const SizedBox(height: 2),
                Text(label,
                    textAlign: TextAlign.center,
                    style: Ym.t(11, color: Ym.grey)),
              ],
            ),
          ),
        );

    final absentCount = _routeStudents
        .where((s) => _absentTodayIds.contains(s['id'].toString()))
        .length;
    return Row(
      children: [
        stat(Iconsax.location, Ym.blue, '${_stops.length}', 'Stops'),
        const SizedBox(width: 12),
        stat(Icons.groups_rounded, Ym.green, '${_routeStudents.length}', 'Students'),
        const SizedBox(width: 12),
        stat(Icons.event_busy_rounded, absentCount > 0 ? Ym.purple : Ym.grey,
            '$absentCount', 'Absent today'),
      ],
    );
  }

  // ── breakdown rescue ──

  Widget _rescueSection() {
    final cards = <Widget>[];

    final o = _rescueOffer;
    if (o != null) {
      final broken = _busNumbers[o['broken_bus_id']?.toString()] ?? 'a bus';
      cards.add(Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Ym.red.withOpacity(0.07),
          borderRadius: BorderRadius.circular(22),
          border: const Border(left: BorderSide(color: Ym.red, width: 5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const YmGradientTile(
                    icon: Icons.support_rounded, color: Ym.red, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rescue request', style: Ym.h(16, color: Ym.red)),
                      Text('Bus $broken  •  ${o['distance_km'] ?? '?'} km away',
                          style: Ym.t(12.5, color: Ym.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
                '${_rescueStops.length} stops and '
                '${_rescueStudents.where((s) => !_rescueCheckedIn.contains(s['id'].toString())).length} students are waiting for a bus.',
                style: Ym.t(13)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: YmButton(
                    label: 'Accept',
                    icon: Icons.check_rounded,
                    color: Ym.green,
                    onPressed: () => _respondRescue(o['id'].toString(), true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: YmButton(
                    label: 'Decline',
                    outline: true,
                    onPressed: () => _respondRescue(o['id'].toString(), false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ));
    }

    final a = _rescueActive;
    if (a != null) {
      final broken = _busNumbers[a['broken_bus_id']?.toString()] ?? 'a bus';
      cards.add(YmCard(
        margin: const EdgeInsets.only(bottom: 12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFEDEA), Colors.white],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const YmGradientTile(
                    icon: Icons.support_rounded, color: Ym.green, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Rescue pickup in progress', style: Ym.h(16)),
                ),
                YmChip('Bus $broken', color: Ym.red),
              ],
            ),
            const SizedBox(height: 10),
            Text(
                '${_rescueStops.length} stops left  •  '
                '${_rescueStudents.where((s) => !_rescueCheckedIn.contains(s['id'].toString())).length} students waiting',
                style: Ym.t(13, color: Ym.grey)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: YmButton(
                    label: 'Open pickup',
                    icon: Iconsax.map_1,
                    onPressed: () => setState(() => _currentIndex = 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: YmButton(
                    label: 'Finish',
                    outline: true,
                    onPressed: () => _completeRescue(a['id'].toString()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ));
    }

    final m = _myRescue;
    if (m != null) {
      final status = m['status']?.toString();
      final other = _busNumbers[m['rescue_bus_id']?.toString()] ?? 'another bus';
      final (text, color) = switch (status) {
        'accepted' => ('Bus $other accepted. Help is on the way to you.', Ym.green),
        'declined' => ('Bus $other could not help. Asking the next nearest bus…', Ym.amberDark),
        'no_bus' => ('No bus is close enough. The admin has been told and will arrange one.', Ym.red),
        _ => ('Asking Bus $other (${m['distance_km'] ?? '?'} km away) to take over…', Ym.amberDark),
      };
      cards.add(YmCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            YmIconBadge(icon: Icons.build_circle_outlined, color: color, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your breakdown', style: Ym.h(15)),
                  const SizedBox(height: 3),
                  Text(text, style: Ym.t(12.5, color: color, w: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const YmSectionTitle('Breakdown rescue'), ...cards],
    );
  }

  // ── SOS alerts ──

  Widget _quickActions() {
    Widget action(Widget tile, String label, VoidCallback onTap) => Expanded(
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

    final onTrip = _activeTrip != null;
    return YmCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          action(
              YmGradientTile(
                  icon: onTrip ? Iconsax.bus : Icons.play_arrow_rounded,
                  color: Ym.green),
              onTrip ? 'View trip' : 'Start trip',
              onTrip ? () => setState(() => _currentIndex = 1) : _startTrip),
          action(
              const YmGradientTile(icon: Icons.how_to_reg_rounded, color: Ym.blue),
              'Student check-in',
              () => setState(() => _currentIndex = 1)),
          action(
              const YmGradientTile(
                  icon: Icons.warning_amber_rounded, color: Ym.amberDark),
              'Report issue',
              _reportIssue),
          action(
              const YmGradientTile(icon: Icons.call_rounded, color: Ym.red),
              'Emergency call',
              _callEmergencyContact),
        ],
      ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              action(
                  const YmGradientTile(
                      icon: Icons.qr_code_scanner_rounded, color: Ym.purple),
                  'Scan bus pass',
                  () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ScanPassScreen()))),
              const Expanded(child: SizedBox()),
              const Expanded(child: SizedBox()),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  // ── today on my route: absences + extra riders ──

  Widget _todaySection() {
    final absent = _routeStudents
        .where((s) => _absentTodayIds.contains(s['id'].toString()))
        .toList();

    Widget block(IconData icon, Color color, String title, int count,
            String empty, List<Widget> rows) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                YmIconBadge(icon: icon, color: color, size: 38),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: Ym.h(15))),
                YmChip('$count', color: color),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Text(empty, style: Ym.t(12.5, color: Ym.grey))
            else
              ...rows,
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const YmSectionTitle('Today on my route'),
        YmCard(
          child: Column(
            children: [
              block(
                Icons.event_busy_rounded,
                Ym.purple,
                'Absent today',
                absent.length,
                'Everyone is expected today.',
                [
                  for (final s in absent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['student_name']?.toString() ?? '',
                                    style: Ym.h(14)),
                                if ((_absentReasons[s['id'].toString()] ?? '')
                                    .isNotEmpty)
                                  Text(_absentReasons[s['id'].toString()]!,
                                      style: Ym.t(12, color: Ym.grey)),
                              ],
                            ),
                          ),
                          Text(s['boarding_point']?.toString() ?? '',
                              style: Ym.t(11.5, color: Ym.grey)),
                        ],
                      ),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: Ym.line),
              ),
              block(
                Icons.person_add_alt_1_rounded,
                Ym.green,
                'Extra riders today',
                _extraRiders.length,
                'No extra riders requested.',
                [
                  for (final s in _extraRiders)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['student_name']?.toString() ?? '',
                                    style: Ym.h(14)),
                                Text(s['boarding_point']?.toString() ?? 'Stop not set',
                                    style: Ym.t(12, color: Ym.grey)),
                              ],
                            ),
                          ),
                          if ((s['student_phone'] ?? '').toString().isNotEmpty)
                            _miniBtn('Call', Icons.call_rounded, Ym.green,
                                () => _callNumber(s['student_phone']?.toString())),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── announcements ──

  Widget _announcementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        YmSectionTitle('Announcements',
            trailing: _announcements.isEmpty
                ? null
                : YmChip('${_announcements.length}', color: Ym.blue)),
        if (_announcements.isEmpty)
          YmCard(
              child: Text('No announcements right now.',
                  style: Ym.t(13.5, color: Ym.grey)))
        else
          for (final a in _announcements)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: YmCard(
                padding: const EdgeInsets.all(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF8E8), Colors.white],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const YmIconBadge(
                        icon: Icons.campaign_rounded, color: Ym.amberDark, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a['title']?.toString() ?? '', style: Ym.h(14.5)),
                          const SizedBox(height: 3),
                          Text(a['body']?.toString() ?? '',
                              style: Ym.t(12.5, color: Ym.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // ───────────────────────── TRACK TAB ─────────────────────────

  Widget _pageHeader(String title, {String? subtitle}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Ym.h(26)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(subtitle, style: Ym.t(12.5, color: Ym.grey)),
                    ),
                ],
              ),
            ),
            YmRoundButton(
                icon: Iconsax.notification,
                badge: _unread,
                onTap: _openNotifications),
          ],
        ),
      );

  Widget _buildTrackTab() {
    if (_activeTrip == null) {
      return SafeArea(
        child: Column(
          children: [
            _pageHeader('Route Tracking'),
            Expanded(
              child: YmEmpty(
                icon: Iconsax.bus,
                title: 'No active trip',
                subtitle:
                    'Start a trip to begin tracking stops and checking in students.',
                action: YmButton(
                  label: 'Start trip',
                  icon: Icons.play_arrow_rounded,
                  color: Ym.green,
                  expanded: false,
                  onPressed: _startTrip,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final stopLatLngs = _getStopLatLngs();
    final reached = _tripStops.where((s) => s['status'] == 'reached').length;
    final nextIdx = _nextStopIndex();
    final riders = <(Map<String, dynamic>, bool)>[
      for (final s in _routeStudents) (s, false),
      for (final s in _extraRiders) (s, true),
    ];

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Ym.amber,
        onRefresh: () => _loadEverything(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
          children: [
            _pageHeader('Route Tracking', subtitle: _routeName),
            const SizedBox(height: 6),
            YmCard(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF6E3), Color(0xFFFFE9BD)],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const YmIconBadge(icon: Iconsax.bus, size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bus $_busNumber', style: Ym.h(16)),
                            Text('Driver: ${_driver!['driver_name'] ?? '—'}',
                                style: Ym.t(12, color: Ym.grey)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$reached/${_tripStops.length}',
                              style: Ym.h(20, color: Ym.green)),
                          Text('stops done', style: Ym.t(11, color: Ym.grey)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _tripStops.isEmpty ? 0 : reached / _tripStops.length,
                      minHeight: 10,
                      backgroundColor: Colors.white.withOpacity(0.8),
                      valueColor: const AlwaysStoppedAnimation<Color>(Ym.green),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_hasDevice)
              _deviceStatus()
            else if (_locationStatus != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Ym.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_off_rounded,
                        color: Ym.amberDark, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_locationStatus!, style: Ym.t(12.5))),
                  ],
                ),
              )
            else
              Row(
                children: [
                  YmChip(
                      _sharingLocation
                          ? 'Sharing live location'
                          : 'Starting location…',
                      color: _sharingLocation ? Ym.green : Ym.grey,
                      icon: Icons.circle),
                ],
              ),
            const SizedBox(height: 14),
            _trackMap(stopLatLngs, nextIdx),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              children: [
                _legend(Ym.green, 'Reached'),
                _legend(Ym.blue, 'Next stop'),
                _legend(Ym.amber, 'Upcoming'),
                _legend(Ym.purple, 'Skip: nobody boarding'),
                _legend(Ym.grey, 'No riders registered'),
              ],
            ),
            if (_rescueActive != null) ..._rescuePickupWidgets(),
            const SizedBox(height: 22),
            const YmSectionTitle('Route progress'),
            for (var i = 0; i < _tripStops.length; i++) _stopRow(i, nextIdx),
            const SizedBox(height: 14),
            YmSectionTitle('Student check-in',
                trailing: YmChip('${_checkedInStudentIds.length}/${riders.length}',
                    color: Ym.blue)),
            if (riders.isEmpty)
              YmCard(
                  child: Text('No students on this route.',
                      style: Ym.t(13.5, color: Ym.grey)))
            else
              for (final r in riders) _riderTile(r.$1, r.$2),
            const SizedBox(height: 22),
            YmButton(
              label: 'End trip',
              icon: Icons.stop_circle_outlined,
              color: Ym.red,
              onPressed: _endTrip,
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceStatus() {
    final fix = _deviceLastFix;
    final live = fix != null && DateTime.now().difference(fix).inSeconds < 120;
    if (live) {
      return const Row(
        children: [
          YmChip('GPS device live', color: Ym.green, icon: Icons.satellite_alt_rounded),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Ym.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.satellite_alt_rounded, color: Ym.amberDark, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Waiting for the GPS device on this bus. It starts sending a few seconds '
              'after the trip begins. If this stays for more than a minute, check that '
              'the device is switched on.',
              style: Ym.t(12.5),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rescuePickupWidgets() {
    final r = _rescueActive!;
    final broken = _busNumbers[r['broken_bus_id']?.toString()] ?? 'the broken bus';
    final waiting = _rescueStudents
        .where((s) => !_rescueCheckedIn.contains(s['id'].toString()))
        .toList();

    return [
      const SizedBox(height: 22),
      YmSectionTitle('Rescue pickup', trailing: YmChip('Bus $broken', color: Ym.red)),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Ym.red.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: const Border(left: BorderSide(color: Ym.red, width: 5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Take over the remaining stops of bus $broken. '
                'Mark each stop as you reach it and check the students in.',
                style: Ym.t(13)),
            if (_rescueLat != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _miniBtn('Breakdown location', Icons.location_on_rounded,
                    Ym.blue, () => _openMap(_rescueLat, _rescueLng)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      for (final ts in _rescueStops)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: YmCard(
            padding: const EdgeInsets.all(14),
            radius: 20,
            child: Row(
              children: [
                const YmIconBadge(icon: Iconsax.location, color: Ym.red, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((ts['stops'] as Map?)?['stop_name']?.toString() ?? '',
                          style: Ym.h(14.5)),
                      Text(_hhmm((ts['stops'] as Map?)?['timing']),
                          style: Ym.t(12, color: Ym.grey)),
                    ],
                  ),
                ),
                _miniBtn('Reached', Icons.check_rounded, Ym.green,
                    () => _markStopReached(ts['id'].toString())),
              ],
            ),
          ),
        ),
      if (waiting.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('Students waiting (${waiting.length})', style: Ym.h(15)),
        const SizedBox(height: 10),
        for (final s in waiting)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: YmCard(
              padding: const EdgeInsets.all(14),
              radius: 20,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Ym.blue.withOpacity(0.1),
                    child: Text(
                        (s['student_name']?.toString() ?? '?').isEmpty
                            ? '?'
                            : s['student_name'].toString()[0].toUpperCase(),
                        style: Ym.h(14, color: Ym.blue)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['student_name']?.toString() ?? '', style: Ym.h(14)),
                        Text(s['boarding_point']?.toString() ?? '—',
                            style: Ym.t(12, color: Ym.grey)),
                      ],
                    ),
                  ),
                  if ((s['student_phone'] ?? '').toString().isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.call_rounded, color: Ym.green, size: 20),
                      onPressed: () => _callNumber(s['student_phone']?.toString()),
                    ),
                  _miniBtn('Check in', Icons.how_to_reg_rounded, Ym.blue,
                      () => _checkInRescueStudent(s['id'].toString())),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: 8),
      YmButton(
        label: 'Finish rescue',
        icon: Icons.verified_rounded,
        color: Ym.green,
        onPressed: () => _completeRescue(r['id'].toString()),
      ),
    ];
  }

  Widget _legend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Ym.t(11, color: Ym.grey)),
        ],
      );

  Widget _trackMap(List<LatLng> stopLatLngs, int nextIdx) {
    return Container(
      height: 400,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: Ym.shadow(Ym.navy, 0.14),
      ),
      child: stopLatLngs.isEmpty
          ? Container(
              color: Colors.white,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(20),
              child: Text(
                'Map unavailable.\nThe stops of this route have no coordinates yet.',
                textAlign: TextAlign.center,
                style: Ym.t(12.5, color: Ym.grey),
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _mapCenter(),
                    initialZoom: 13,
                    onTap: (_, __) {
                      if (_selectedStopId != null) {
                        setState(() => _selectedStopId = null);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.yatramitra.app',
                    ),
                    PolylineLayer(polylines: _routeLines()),
                    MarkerLayer(
                      markers: [
                        for (var i = 0; i < _tripStops.length; i++)
                          if (_tripStops[i]['stops']?['lat'] is num &&
                              _tripStops[i]['stops']?['lng'] is num)
                            _stopMarker(i, nextIdx),
                        if (_myPos != null)
                          Marker(
                            point: _myPos!,
                            width: 80,
                            height: 80,
                            child: IgnorePointer(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const YmPulse(color: Ym.navy, size: 16),
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Ym.navy,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                      boxShadow: Ym.shadow(Ym.navy, 0.4),
                                    ),
                                    child: const Icon(Iconsax.bus,
                                        color: Colors.white, size: 21),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: _mapBanner(nextIdx),
                ),
                if (_selectedStopId != null)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: _stopPopup(nextIdx),
                  ),
              ],
            ),
    );
  }

  Widget _stopRow(int index, int nextIdx) {
    final ts = _tripStops[index];
    final stop = ts['stops'];
    final isReached = ts['status'] == 'reached';
    final isNext = index == nextIdx;
    final isLast = index == _tripStops.length - 1;
    final st = _stopState(index, nextIdx);
    final isSkip = st == _StopState.skip;
    final color = _stopColor(st);
    final time = _hhmm(stop?['timing']);

    // estimated arrival of the bus at this stop
    EtaResult? eta;
    if (!isReached && _myPos != null && nextIdx >= 0) {
      final stopMaps = [
        for (final t in _tripStops)
          Map<String, dynamic>.from((t['stops'] ?? <String, dynamic>{}) as Map),
      ];
      eta = Eta.estimate(
          bus: _myPos!,
          stops: stopMaps,
          nextIndex: nextIdx,
          targetIndex: index,
          avgKmh: _avgKmh);
    }
    final etaText = eta == null ? '' : '  •  ETA ${eta.label}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)
                    ],
                  ),
                  child: isReached
                      ? const Icon(Icons.check, color: Colors.white, size: 12)
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.5,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: color.withOpacity(0.3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isNext
                      ? Ym.blue.withOpacity(0.07)
                      : (isReached ? Ym.green.withOpacity(0.06) : Colors.white),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: isNext ? Ym.blue.withOpacity(0.35) : Ym.line,
                      width: 0.9),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stop?['stop_name']?.toString() ?? '',
                              style: Ym.h(14.5)),
                          const SizedBox(height: 3),
                          Text(
                            isReached
                                ? 'Completed${time.isNotEmpty ? '  •  $time' : ''}'
                                : isSkip
                                    ? 'Skip: nobody boarding${time.isNotEmpty ? '  •  $time' : ''}'
                                    : (isNext
                                    ? 'Next stop${time.isNotEmpty ? '  •  $time' : ''}$etaText'
                                    : 'Upcoming${time.isNotEmpty ? '  •  $time' : ''}$etaText'),
                            style: Ym.t(11.5,
                                color: isReached
                                    ? Ym.green
                                    : (isSkip ? Ym.purple : (isNext ? Ym.blue : Ym.grey)),
                                w: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (!isReached)
                      YmPressable(
                        onTap: () => _markStopReached(ts['id']),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isSkip
                                  ? [Ym.purple.withOpacity(0.85), Ym.purple]
                                  : (isNext
                                      ? [Ym.amber, Ym.amberDark]
                                      : [Ym.blue.withOpacity(0.85), Ym.blue]),
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(isSkip ? 'Skip stop' : 'Mark reached',
                              style: Ym.t(11.5,
                                  color: (isNext && !isSkip) ? Ym.navy : Colors.white,
                                  w: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _riderTile(Map<String, dynamic> s, bool extra) {
    final id = s['id'].toString();
    final name = s['student_name']?.toString() ?? '';
    final checked = _checkedInStudentIds.contains(id);
    final absent = _absentTodayIds.contains(id);
    final fee = _feeByStudent[id]?['fee_status']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        color: checked ? Ym.green.withOpacity(0.05) : Colors.white,
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  checked ? Ym.green.withOpacity(0.15) : Ym.blue.withOpacity(0.1),
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: Ym.h(15, color: checked ? Ym.green : Ym.blue)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Ym.h(14.5)),
                  Text(s['boarding_point']?.toString() ?? '—',
                      style: Ym.t(12, color: Ym.grey)),
                  if (absent || extra || (fee != null && fee != 'paid'))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (extra) const YmChip('Extra rider', color: Ym.green),
                          if (absent)
                            const YmChip('Absent today', color: Ym.purple),
                          if (fee != null && fee != 'paid')
                            YmChip(fee == 'partial' ? 'Fee partial' : 'Fee unpaid',
                                color: Ym.red),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (checked)
              const Icon(Icons.check_circle_rounded, color: Ym.green, size: 28)
            else
              YmPressable(
                onTap: () => _checkInStudent(id, name),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Ym.blue, Color(0xFF2B45D8)]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text('Check in',
                      style: Ym.t(12, color: Colors.white, w: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── REPORTS TAB ─────────────────────────

  Widget _buildReportsTab() {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Ym.amber,
        onRefresh: () => _loadEverything(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
          children: [
            _pageHeader('Trip Reports', subtitle: 'Your completed trips'),
            const SizedBox(height: 6),
            YmCard(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total trips',
                            style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w700)),
                        Text('$_totalTripsCompleted', style: Ym.h(44)),
                        Text('completed', style: Ym.t(12, color: Ym.grey)),
                      ],
                    ),
                  ),
                  const YmGradientTile(
                      icon: Iconsax.bus, color: Ym.amberDark, size: 64),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const YmSectionTitle('Recent trips'),
            if (_pastTrips.isEmpty)
              YmCard(
                  child: Text('No completed trips yet.',
                      style: Ym.t(13.5, color: Ym.grey)))
            else
              for (final t in _pastTrips) _tripTile(t),
            const SizedBox(height: 24),
            const YmSectionTitle('My issue reports'),
            if (_myIssues.isEmpty)
              YmCard(
                  child: Text('You have not reported any issues.',
                      style: Ym.t(13.5, color: Ym.grey)))
            else
              for (final i in _myIssues) _issueTile(i),
          ],
        ),
      ),
    );
  }

  Widget _tripTile(Map<String, dynamic> t) {
    final started = parseUtc(t['started_at']);
    final ended = parseUtc(t['ended_at']);
    final mins =
        (started != null && ended != null) ? ended.difference(started).inMinutes : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const YmIconBadge(
                icon: Icons.check_circle_rounded, color: Ym.green, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((t['routes'] as Map?)?['route_name']?.toString() ?? '',
                      style: Ym.h(14.5)),
                  if (started != null)
                    Text(
                        '${fmtDate(started)}  •  ${fmtClock(started)}'
                        '${ended != null ? ' – ${fmtClock(ended)}' : ''}',
                        style: Ym.t(11.5, color: Ym.grey)),
                ],
              ),
            ),
            if (mins != null) YmChip('$mins min', color: Ym.blue),
          ],
        ),
      ),
    );
  }

  Widget _issueTile(Map<String, dynamic> i) {
    final status = i['status']?.toString() ?? 'open';
    final resolved = status == 'resolved';
    final at = parseUtc(i['created_at']);
    final type = i['type']?.toString();
    final response = i['response']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      type == null || type.isEmpty
                          ? 'Issue'
                          : type[0].toUpperCase() + type.substring(1),
                      style: Ym.h(14.5)),
                ),
                YmChip(resolved ? 'Resolved' : 'Open',
                    color: resolved ? Ym.green : Ym.red),
              ],
            ),
            const SizedBox(height: 4),
            Text(i['description']?.toString() ?? '',
                style: Ym.t(12.5, color: Ym.grey)),
            if (at != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(fmtDate(at), style: Ym.t(11, color: Ym.grey)),
              ),
            if (response != null && response.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Ym.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Admin: $response', style: Ym.t(12.5)),
              ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── PROFILE TAB ─────────────────────────

  Widget _buildProfileTab() {
    final name = (_driver!['driver_name'] ?? '').toString();
    Widget tile(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              YmIconBadge(icon: icon, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Ym.t(11, color: Ym.grey)),
                    Text(value, style: Ym.h(14.5)),
                  ],
                ),
              ),
            ],
          ),
        );

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
        children: [
          _pageHeader('Profile'),
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Ym.amber, Ym.amberDark]),
                  ),
                  child: CircleAvatar(
                    radius: 46,
                    backgroundColor: Colors.white,
                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: Ym.h(38, color: Ym.amberDark)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(name, style: Ym.h(22)),
                const SizedBox(height: 3),
                Text((_driver!['driver_email'] ?? '').toString(),
                    style: Ym.t(13, color: Ym.grey)),
                const SizedBox(height: 10),
                const YmChip('Driver  •  Active', color: Ym.green),
              ],
            ),
          ),
          const SizedBox(height: 24),
          YmCard(
            child: Column(
              children: [
                tile(Icons.phone_outlined, 'Phone',
                    (_driver!['driver_phone'] ?? '—').toString()),
                tile(Icons.badge_outlined, 'Licence number',
                    (_driver!['license_number'] ?? '—').toString()),
                tile(Iconsax.bus, 'Bus', _busNumber),
                tile(Icons.alt_route_rounded, 'Assigned route', _routeName),
                tile(Icons.check_circle_outline_rounded, 'Trips completed',
                    '$_totalTripsCompleted'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          YmButton(
            label: 'Change password',
            icon: Icons.lock_reset_rounded,
            outline: true,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          const SizedBox(height: 10),
          YmButton(
            label: 'Log out',
            icon: Icons.logout_rounded,
            color: Ym.red,
            onPressed: _logout,
          ),
        ],
      ),
    );
  }

  // ───────────────────────── BOTTOM BAR ─────────────────────────

  Widget _buildBottomNav() {
    final items = <(IconData, String)>[
      (Iconsax.home_2, 'Home'),
      (Iconsax.bus, 'Track'),
      (Icons.bar_chart_rounded, 'Reports'),
      (Iconsax.user, 'Profile'),
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
            for (var i = 0; i < items.length; i++)
              YmPressable(
                onTap: () => setState(() => _currentIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.symmetric(
                      horizontal: _currentIndex == i ? 18 : 14, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: _currentIndex == i
                        ? const LinearGradient(colors: [Ym.amber, Ym.amberDark])
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(items[i].$1,
                          size: 22,
                          color: _currentIndex == i ? Ym.navy : Ym.grey),
                      if (_currentIndex == i) ...[
                        const SizedBox(width: 7),
                        Text(items[i].$2, style: Ym.h(13)),
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


// ══════════════════════════════════════════════════════════════
// MOVING SCENE for the Home card: a bus driving through the town.
// Plays when there is no video file (or while the video is loading).
// ══════════════════════════════════════════════════════════════
class _DriveScene extends StatefulWidget {
  const _DriveScene();

  @override
  State<_DriveScene> createState() => _DriveSceneState();
}

class _DriveSceneState extends State<_DriveScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 10))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _DriveScenePainter(_c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DriveScenePainter extends CustomPainter {
  _DriveScenePainter(this.t);

  /// 0..1, one full loop. Every moving layer shifts by a whole number of its
  /// own period per loop, so the loop is seamless.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final roadTop = h - 40;

    // sky
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFBFE3FF), Color(0xFFFFF1CF)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // sun
    canvas.drawCircle(Offset(w * 0.84, h * 0.27), 27, Paint()..color = const Color(0x55FFE082));
    canvas.drawCircle(Offset(w * 0.84, h * 0.27), 15, Paint()..color = const Color(0xFFFFC94A));

    // repeats an element across the width, drifting left
    void repeatAcross(double period, int loops, void Function(double x) draw) {
      final shift = (t * loops * period) % period;
      for (var x = -period - shift; x < w + period; x += period) {
        draw(x);
      }
    }

    // clouds (slow)
    final cloud = Paint()..color = Colors.white.withOpacity(0.92);
    repeatAcross(150, 1, (x) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 30, h * 0.22), width: 46, height: 15), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 44, h * 0.22 - 6), width: 28, height: 17), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 18, h * 0.22 - 3), width: 24, height: 13), cloud);
    });
    repeatAcross(210, 1, (x) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 120, h * 0.38), width: 36, height: 12), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 130, h * 0.38 - 5), width: 22, height: 13), cloud);
    });

    // far hills
    final hill = Paint()..color = const Color(0xFFF3D9A4);
    repeatAcross(130, 2, (x) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 65, roadTop), width: 150, height: 56), hill);
    });

    // houses
    final wall = Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.85);
    final roof = Paint()..color = const Color(0xFFE9A25A);
    repeatAcross(95, 3, (x) {
      canvas.drawRect(Rect.fromLTWH(x + 30, roadTop - 22, 26, 22), wall);
      final path = Path()
        ..moveTo(x + 27, roadTop - 22)
        ..lineTo(x + 43, roadTop - 34)
        ..lineTo(x + 59, roadTop - 22)
        ..close();
      canvas.drawPath(path, roof);
      canvas.drawRect(Rect.fromLTWH(x + 39, roadTop - 13, 8, 13), Paint()..color = const Color(0xFFB9C7DE));
    });

    // trees close to the road
    final trunk = Paint()..color = const Color(0xFF8B5E3C);
    final leaves = Paint()..color = const Color(0xFF7BC96F);
    repeatAcross(70, 5, (x) {
      canvas.drawRect(Rect.fromLTWH(x + 8, roadTop - 14, 4, 14), trunk);
      canvas.drawCircle(Offset(x + 10, roadTop - 20), 11, leaves);
      canvas.drawCircle(Offset(x + 16, roadTop - 15), 7, leaves);
    });

    // road
    canvas.drawRect(Rect.fromLTWH(0, roadTop, w, h - roadTop), Paint()..color = const Color(0xFF3C4466));
    canvas.drawRect(Rect.fromLTWH(0, roadTop, w, 3), Paint()..color = const Color(0xFF59638A));
    final dash = Paint()..color = Colors.white.withOpacity(0.85);
    repeatAcross(44, 14, (x) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, roadTop + 24, 24, 3.2), const Radius.circular(2)),
          dash);
    });

    // the bus
    final bx = w * 0.46;
    final dy = math.sin(t * 2 * math.pi * 18) * 1.3; // gentle bounce
    final top = roadTop - 44 + dy;

    // dust behind the bus
    for (var k = 0; k < 3; k++) {
      final ph = (t * 8 + k / 3) % 1;
      canvas.drawCircle(
        Offset(bx - 60 - ph * 34, roadTop - 3 - ph * 9),
        3 + ph * 5,
        Paint()..color = Colors.white.withOpacity((1 - ph) * 0.4),
      );
    }

    // headlight beam
    final beam = Path()
      ..moveTo(bx + 55, top + 30)
      ..lineTo(bx + 100, top + 40)
      ..lineTo(bx + 100, top + 20)
      ..close();
    canvas.drawPath(beam, Paint()..color = const Color(0x33FFF3B0));

    // body
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx - 55, top, 110, 44), const Radius.circular(9));
    canvas.drawRRect(body, Paint()..color = const Color(0xFFFFC21E));
    canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(bx - 55, top + 35, 110, 9),
            bottomLeft: const Radius.circular(9), bottomRight: const Radius.circular(9)),
        Paint()..color = const Color(0xFFE59A00));
    canvas.drawRect(Rect.fromLTWH(bx - 55, top + 24, 110, 3), Paint()..color = const Color(0xFF3C4466));

    // windows
    final glass = Paint()..color = const Color(0xFFD5ECFF);
    for (var i = 0; i < 4; i++) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(bx - 48 + i * 21.0, top + 7, 16, 14), const Radius.circular(3)),
          glass);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(bx + 38, top + 7, 13, 20), const Radius.circular(3)),
        glass);

    // lights
    canvas.drawCircle(Offset(bx + 52, top + 33), 3, Paint()..color = const Color(0xFFFFF3B0));
    canvas.drawCircle(Offset(bx - 52, top + 31), 2.4, Paint()..color = const Color(0xFFE24B4A));

    // wheels
    for (final wx in [bx - 32, bx + 32]) {
      final c = Offset(wx, roadTop + 1 + dy * 0.4);
      canvas.drawCircle(c, 9.5, Paint()..color = const Color(0xFF2B3050));
      canvas.drawCircle(c, 4.5, Paint()..color = const Color(0xFFB9C0D6));
      final spin = t * 2 * math.pi * 30;
      final spoke = Paint()
        ..color = const Color(0xFF2B3050)
        ..strokeWidth = 1.6;
      for (var k = 0; k < 3; k++) {
        final a = spin + k * 2 * math.pi / 3;
        canvas.drawLine(c, c + Offset(math.cos(a) * 4.3, math.sin(a) * 4.3), spoke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DriveScenePainter old) => old.t != t;
}